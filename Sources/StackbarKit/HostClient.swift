import Foundation

/// The plugin's line to the host for everything it can't or shouldn't do
/// itself: secrets, HTTP to declared domains, OAuth tokens, notifications,
/// topics, and saved values.
///
/// Calls are `request` messages answered by `response` messages. Responses are
/// routed here straight from the reader thread, not through the runtime's
/// one-message-at-a-time loop, so a `refresh()` that awaits the host never
/// waits on itself.
public final class HostClient: @unchecked Sendable {
    public static let shared = HostClient()

    private let lock = NSLock()
    private var nextID = 1
    private var pending: [Int: @Sendable (HostResult) -> Void] = [:]
    /// The timeout of each waiting call that has one (`HostCall.replyTimeout`).
    private var deadlines: [Int: DispatchWorkItem] = [:]
    /// Streamed runs still going, by the id of the request that started them.
    private var streams: [Int: AsyncThrowingStream<RunEvent, any Error>.Continuation] = [:]
    private var sendMessage: (@Sendable (PluginMessage) -> Void)?

    init() {}

    /// Points the client at a transport. The runtime does this; tests can too.
    public func configure(send: @escaping @Sendable (PluginMessage) -> Void) {
        lock.lock()
        sendMessage = send
        lock.unlock()
    }

    /// Sends a call and waits for its answer, or fails it after
    /// `HostCall.replyTimeout`.
    public func call(_ call: HostCall) async -> HostResult {
        await self.call(call, timeout: call.replyTimeout)
    }

    /// Sends a call and waits at most `timeout` seconds (`nil`: for good).
    func call(_ call: HostCall, timeout: Double?) async -> HostResult {
        await withCheckedContinuation { continuation in
            send(call, timeout: timeout) { continuation.resume(returning: $0) }
        }
    }

    /// Sends a call without waiting. A failure is reported to the host's log.
    public func fire(_ call: HostCall) {
        let label = call.label
        send(call, timeout: call.replyTimeout) { [weak self] result in
            if case .failure(let message) = result {
                self?.deliver(.log(level: .warning, message: "\(label) failed: \(message)"))
            }
        }
    }

    /// Delivers a response. Returns `false` for an id nobody is waiting on.
    @discardableResult
    public func resolve(id: Int, result: HostResult) -> Bool {
        lock.lock()
        let handler = pending.removeValue(forKey: id)
        let deadline = deadlines.removeValue(forKey: id)
        lock.unlock()
        deadline?.cancel()
        handler?(result)
        return handler != nil
    }

    /// Answers every waiting call with a failure.
    public func failAll(_ reason: String) {
        lock.lock()
        let handlers = pending
        let running = streams
        let timers = deadlines.values
        pending.removeAll()
        streams.removeAll()
        deadlines.removeAll()
        sendMessage = nil
        lock.unlock()
        for timer in timers { timer.cancel() }
        for handler in handlers.values { handler(.failure(reason)) }
        for stream in running.values { stream.finish(throwing: HostError(reason)) }
    }

    /// Starts a streamed run. Ending the loop over it early cancels the run.
    func stream(_ request: RunRequest) -> AsyncThrowingStream<RunEvent, any Error> {
        var request = request
        request.stream = true
        let (events, continuation) = AsyncThrowingStream.makeStream(of: RunEvent.self)
        lock.lock()
        guard let sendMessage else {
            lock.unlock()
            continuation.finish(throwing: HostError("not running inside Stackbar"))
            return events
        }
        let id = nextID
        nextID += 1
        streams[id] = continuation
        pending[id] = { [weak self] result in
            // `.ok` means it started; output follows as `runOutput`.
            guard case .failure(let message) = result else { return }
            self?.endStream(id)?.finish(throwing: HostError(message))
        }
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            // Still registered: the consumer left before the exit.
            guard let self, self.endStream(id) != nil else { return }
            self.fire(.cancelRun(id: id))
        }
        sendMessage(.request(id: id, call: .run(request)))
        return events
    }

    /// Delivers a streamed run's output or exit. Returns `false` for a run
    /// nobody is reading.
    @discardableResult
    public func deliver(run message: HostMessage) -> Bool {
        switch message {
        case .runOutput(let id, let channel, let data):
            guard let stream = lock.withLock({ streams[id] }) else { return false }
            stream.yield(channel == .stdout ? .stdout(data) : .stderr(data))
            return true
        case .runExit(let id, let exit):
            guard let stream = endStream(id) else { return false }
            stream.yield(.exit(exit))
            stream.finish()
            return true
        default:
            return false
        }
    }

    private func endStream(_ id: Int) -> AsyncThrowingStream<RunEvent, any Error>.Continuation? {
        lock.withLock { streams.removeValue(forKey: id) }
    }

    /// How many calls are waiting on the host (for tests).
    public var openRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    private func send(_ call: HostCall, timeout: Double?, onResult: @escaping @Sendable (HostResult) -> Void) {
        lock.lock()
        guard let sendMessage else {
            lock.unlock()
            onResult(.failure("not running inside Stackbar"))
            return
        }
        let id = nextID
        nextID += 1
        pending[id] = onResult
        if let timeout {
            let label = call.label
            let deadline = DispatchWorkItem { [weak self] in
                self?.resolve(id: id, result: .failure("\(label) got no answer from Stackbar within \(Int(timeout)) seconds"))
            }
            deadlines[id] = deadline
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        }
        lock.unlock()
        sendMessage(.request(id: id, call: call))
    }

    private func deliver(_ message: PluginMessage) {
        lock.lock()
        let sendMessage = sendMessage
        lock.unlock()
        sendMessage?(message)
    }
}

/// What a streamed run hands over.
public enum RunEvent: Equatable, Sendable {
    case stdout(Data)
    case stderr(Data)
    /// The last event: how it ended.
    case exit(RunExit)
}

extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

/// A host call that failed: a missing capability, a network error, a sign-in
/// the user cancelled. `message` says what happened in words.
public struct HostError: Error, CustomStringConvertible, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Host services, for use in `refresh()` and action closures.
///
/// ```swift
/// let prs: [PR] = try await Stackbar.getJSON("https://api.github.com/...", auth: .bearer(secret: "GITHUB_TOKEN"))
/// ```
///
/// Every call is checked against the manifest's capabilities as approved by
/// the user, and the error says which capability is missing.
public enum Stackbar {
    /// Saved values, also available as `@Stored` properties.
    @MainActor public static let storage = PluginStorage()

    /// Why the running `refresh()` was called: `.wake`, `.displays`, an
    /// interval and so on. `nil` outside a refresh, and with hosts older than
    /// Stackbar 0.15.0 for reasons they don't send.
    @MainActor public internal(set) static var refreshReason: TriggerReason?

    /// A secret the manifest declares with `.secret(name:)`, or `nil` when the
    /// user hasn't entered it yet (the host asks them for it).
    public static func secret(_ name: String) async throws -> String? {
        switch await HostClient.shared.call(.secret(name: name)) {
        case .value(let value): return value
        case .failure(let message): throw HostError(message)
        default: throw HostError("unexpected answer to secret(\(name))")
        }
    }

    /// An HTTP request made by the host to a domain the manifest declares.
    /// `auth` adds a header built from a secret; while the user hasn't
    /// entered it, this throws `StackbarError.missingSecret` instead of
    /// sending a request that can only fail.
    public static func http(_ request: HTTPRequest, auth: Auth? = nil) async throws -> HTTPResponse {
        var request = request
        if let auth {
            let header = try await auth.header()
            request.headers[header.name] = header.value
        }
        switch await HostClient.shared.call(.http(request)) {
        case .http(let response): return response
        case .failure(let message): throw HostError(message)
        default: throw HostError("unexpected answer to \(request.method) \(request.url)")
        }
    }

    public static func get(_ url: String, headers: [String: String] = [:], auth: Auth? = nil) async throws -> HTTPResponse {
        try await http(HTTPRequest(url: url, headers: headers), auth: auth)
    }

    /// GETs a URL and decodes its JSON body; a non-2xx status throws.
    public static func getJSON<T: Decodable>(_ url: String, as type: T.Type = T.self, headers: [String: String] = [:], auth: Auth? = nil, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        try await json(HTTPRequest(url: url, headers: headers), auth: auth, decoder: decoder)
    }

    /// Sends `body` encoded as JSON (POST unless `method` says otherwise) and
    /// decodes the JSON answer, as a GraphQL query or a create call needs; a
    /// non-2xx status throws.
    public static func postJSON<T: Decodable>(_ url: String, body: some Encodable, as type: T.Type = T.self, method: String = "POST", headers: [String: String] = [:], auth: Auth? = nil, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var headers = headers
        if headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        return try await json(HTTPRequest(url: url, method: method, headers: headers, body: try encoder.encode(body)), auth: auth, decoder: decoder)
    }

    private static func json<T: Decodable>(_ request: HTTPRequest, auth: Auth?, decoder: JSONDecoder) async throws -> T {
        var request = request
        if request.headers["Accept"] == nil { request.headers["Accept"] = "application/json" }
        let response = try await http(request, auth: auth)
        guard (200..<300).contains(response.status) else {
            throw HostError("\(request.url) answered \(response.status): \(String(decoding: response.body.prefix(300), as: UTF8.self))")
        }
        return try decoder.decode(T.self, from: response.body)
    }

    /// An access token for a provider declared with `.oauth(...)`. The first
    /// call opens the browser to sign in; later calls reuse or refresh it.
    public static func oauthToken(_ provider: String, forceRefresh: Bool = false) async throws -> String {
        switch await HostClient.shared.call(.oauthToken(provider: provider, forceRefresh: forceRefresh)) {
        case .value(let token?): return token
        case .failure(let message): throw HostError(message)
        default: throw HostError("no token for \(provider)")
        }
    }

    /// Sends a payload to every plugin listening on the topic with a
    /// `.topic(name:)` trigger.
    public static func publish(_ topic: String, _ payload: String) {
        HostClient.shared.fire(.publish(topic: topic, payload: payload))
    }

    /// Encodes `value` as JSON and publishes it.
    public static func publish(_ topic: String, json value: some Encodable) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        publish(topic, String(decoding: data, as: UTF8.self))
    }

    /// Posts a notification. `actions` become its buttons (up to three); each
    /// opens its URL, so `NotificationAction("Join", url: link)` joins a call.
    /// Clicking the notification itself opens your panel.
    public static func notify(_ title: String, body: String? = nil, actions: [NotificationAction] = []) {
        HostClient.shared.fire(.notify(title: title, body: body, actions: actions.isEmpty ? nil : actions))
    }

    /// A full-screen alert that stays until dismissed, for what must not be
    /// missed. Buttons open their URLs. At most one a minute.
    public static func alert(_ title: String, body: String? = nil, actions: [NotificationAction] = []) {
        HostClient.shared.fire(.alert(title: title, body: body, actions: actions))
    }

    /// Plays a macOS system sound, like `Stackbar.play(.glass)` when a timer
    /// ends. At most 10 a minute.
    public static func play(_ sound: SystemSound) {
        HostClient.shared.fire(.playSound(sound))
    }

    /// A short message in the HUD over the screen, the one a command
    /// result's message shows: `Stackbar.hud("Copied")` after a panel button
    /// or a row acts. Needs nothing; at most 30 a minute. Stackbar 0.22.0.
    public static func hud(_ message: String, isError: Bool = false) {
        HostClient.shared.fire(.hud(message, isError: isError))
    }

    public static func open(_ url: String) {
        HostClient.shared.fire(.openURL(url))
    }

    /// Opens a URL or an absolute (or `~/`) path, with the app whose bundle
    /// id is `app` when given, and waits for the host to say it worked.
    /// Schemes beyond https, http, mailto, tel and meeting links need
    /// `.openURLs(schemes:)`; files and folders need `"*"`.
    public static func open(_ url: String, with app: String?) async throws {
        if case .failure(let message) = await HostClient.shared.call(.open(url: url, app: app)) { throw HostError(message) }
    }

    public static func copy(_ text: String) {
        HostClient.shared.fire(.copy(text))
    }

    // MARK: System (clipboard, power, calendar)

    /// What is on the clipboard now, or `nil` when it is empty. Needs
    /// `.clipboard`. Pair it with the `.clipboard` trigger to hear every copy.
    public static func clipboard() async throws -> ClipboardItem? {
        try await HostReplies.clipboardRead.decode(value(.clipboardRead))
    }

    /// Puts text, files or a kept image on the clipboard. Needs `.clipboard`
    /// (plain text alone can use `Stackbar.copy` without it).
    public static func setClipboard(_ content: ClipboardContent) async throws {
        try await ok(.clipboardWrite(content))
    }

    /// Puts the content on the clipboard and pastes it into the app the user
    /// was in before Stackbar's panel opened. Needs `.clipboard`. Throws (after
    /// copying) when Stackbar lacks Accessibility access.
    ///
    /// `restoringClipboard` puts back what the user had copied about half a
    /// second later (unless they copied something else meanwhile), and marks
    /// the pasted content transient so clipboard managers skip it.
    /// `cursorFromEnd` moves the caret that many characters left afterwards.
    public static func paste(_ content: ClipboardContent, restoringClipboard: Bool = false, cursorFromEnd: Int = 0) async throws {
        let options = restoringClipboard || cursorFromEnd > 0 ? PasteOptions(restoreClipboard: restoringClipboard, cursorFromEnd: cursorFromEnd) : nil
        try await ok(.paste(content, options: options))
    }

    /// Keeps the Mac (and with `display`, the screen) awake until
    /// `allowSleep()`, or until the plugin stops. Needs `.power`.
    public static func keepAwake(display: Bool = true, reason: String) async throws {
        try await ok(.keepAwake(KeepAwakeRequest(display: display, reason: reason)))
    }

    /// Releases `keepAwake`.
    public static func allowSleep() async throws {
        try await ok(.keepAwake(nil))
    }

    /// Battery, power and running apps. Needs `.power`.
    public static func systemStatus() async throws -> SystemStatus {
        guard let reply = try await HostReplies.systemStatus.decode(value(.systemStatus)) else { throw HostError("no system status") }
        return reply
    }

    /// Events overlapping `from..<to` (at most 31 days), sorted by start.
    /// Needs `.calendar`; the first call asks the user for calendar access.
    public static func calendarEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        try await HostReplies.calendarEvents.decode(value(.calendarEvents(from: from, to: to))) ?? []
    }

    /// Adds an event to a calendar, or changes the one `draft.id` names (an
    /// id this call returned), and answers it as saved. `calendarID` comes
    /// from `writableCalendars()`; nil is the user's default calendar.
    /// Needs `.calendarWrite`; the host asks for calendar access the first
    /// time. Stackbar 0.26.0.
    @discardableResult
    public static func saveCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent {
        guard let reply = try await HostReplies.saveCalendarEvent.decode(value(.saveCalendarEvent(draft))) else { throw HostError("the event wasn't saved") }
        return reply
    }

    /// The calendars events can be added to, the default one marked. Needs
    /// `.calendarWrite`. Stackbar 0.26.0.
    public static func writableCalendars() async throws -> [CalendarInfo] {
        try await HostReplies.writableCalendars.decode(value(.writableCalendars)) ?? []
    }

    // MARK: Terminal, text and sensors

    /// Opens the user's terminal app (whatever opens `.command` files:
    /// Terminal, iTerm, Ghostty…) running `command`, a program and its
    /// arguments: `["docker", "exec", "-it", "web", "sh"]`. The host quotes
    /// every word, so nothing is read as shell. Needs `.terminal`; at most
    /// 5 a minute. Stackbar 0.26.0.
    public static func openInTerminal(_ command: [String], title: String? = nil) async throws {
        try await ok(.openInTerminal(command: command, title: title))
    }

    /// The text in a kept clipboard image (a `ClipboardItem.imageID`), read
    /// on the Mac with Vision. `languages` are BCP 47 codes to prefer
    /// (`["ja", "en"]`); nil lets Vision pick. Needs `.clipboard`.
    /// Stackbar 0.26.0.
    public static func recognizeText(imageID: String, languages: [String]? = nil) async throws -> RecognizedText {
        try await HostReplies.recognizedText.decode(value(.recognizeText(imageID: imageID, languages: languages))) ?? RecognizedText(lines: [])
    }

    /// Lets the user drag over part of the screen, like ⇧⌘4, and answers the
    /// text in it; nil when they press Esc. Needs `.screenText`; the host
    /// asks for Screen Recording access the first time. Stackbar 0.26.0.
    public static func captureScreenText(languages: [String]? = nil) async throws -> RecognizedText? {
        try await HostReplies.recognizedText.decode(value(.captureScreenText(languages: languages)))
    }

    /// The Mac's temperatures (°C: CPU, GPU, battery, SSD as it reports
    /// them) and fan speeds (rpm). A Mac without fans has none, and a
    /// sensor the Mac doesn't expose is left out. Needs `.sensors`.
    /// Stackbar 0.26.0.
    public static func sensors() async throws -> [SensorReading] {
        try await HostReplies.sensors.decode(value(.sensors)) ?? []
    }

    // MARK: Reminders

    /// Whether Stackbar may use the user's reminders. With `ask`, macOS asks
    /// the user if it hasn't yet. Needs `.reminders`. Stackbar 0.18.0.
    public static func reminderAccess(ask: Bool = false) async throws -> ReminderAccess {
        try await HostReplies.reminderAccess.decode(value(.reminderAccess(ask: ask))) ?? .unavailable
    }

    /// The user's Reminders lists. Needs `.reminders`; the first call asks
    /// for access.
    public static func reminderLists() async throws -> [ReminderList] {
        try await HostReplies.reminderLists.decode(value(.reminderLists)) ?? []
    }

    /// Makes a Reminders list (`color` as `#RRGGBB`). Needs `.reminders`.
    public static func createReminderList(_ title: String, color: String? = nil) async throws -> ReminderList {
        guard let reply = try await HostReplies.createReminderList.decode(value(.createReminderList(title: title, color: color))) else { throw HostError("no list") }
        return reply
    }

    /// Open reminders in `lists` (nil for all), plus those completed since
    /// `completedSince`. Needs `.reminders`.
    public static func reminders(in lists: [String]? = nil, completedSince: Date? = nil) async throws -> [Reminder] {
        try await HostReplies.reminders.decode(value(.reminders(ReminderQuery(lists: lists, completedSince: completedSince)))) ?? []
    }

    /// Adds a reminder (empty `id`) or saves one. Pass the `fields` you
    /// changed, and only those are written over what is there now, so an
    /// edit made on another device a moment ago survives. Returns the saved
    /// reminder with its id. Needs `.reminders`.
    @discardableResult
    public static func saveReminder(_ reminder: Reminder, fields: [Reminder.Field]? = nil) async throws -> Reminder {
        guard let reply = try await HostReplies.saveReminder.decode(value(.saveReminder(reminder, fields: fields))) else { throw HostError("no reminder") }
        return reply
    }

    /// Deletes a reminder. Needs `.reminders`.
    public static func deleteReminder(id: String) async throws {
        try await ok(.deleteReminder(id: id))
    }

    // MARK: Apps and the key layer

    /// The regular apps that are running, in launch order, with the one in
    /// front marked `isActive`. Needs `.apps`. Stackbar 0.16.0.
    public static func runningApps() async throws -> [RunningApp] {
        guard let reply = try await HostReplies.runningApps.decode(value(.runningApps)) else { throw HostError("no running apps") }
        return reply
    }

    /// Brings the app with this bundle id to the front, unhiding it; with
    /// `launch`, opens it when it isn't running. Needs `.apps`; at most 120
    /// switches a minute. Stackbar 0.16.0.
    public static func activateApp(_ id: String, launch: Bool = false) async throws {
        try await ok(.activateApp(id, launch: launch))
    }

    /// Hides the app with this bundle id. Needs `.apps`. Stackbar 0.16.0.
    public static func hideApp(_ id: String) async throws {
        try await ok(.hideApp(id))
    }

    /// The installed apps (in /Applications, ~/Applications and the system's
    /// own) and System Settings panes, by name. Open an app with
    /// `activateApp(id, launch: true)` and a pane with `open(pane.url)`.
    /// Needs `.apps`. Stackbar 0.20.0.
    public static func installedApps() async throws -> [InstalledApp] {
        guard let reply = try await HostReplies.installedApps.decode(value(.installedApps)) else { throw HostError("no apps") }
        return reply
    }

    /// Files and folders in the user's home whose names hold every word of
    /// `text`, from Spotlight's index, most recently used first. App bundles,
    /// hidden files and Library internals are left out. Needs `.fileSearch`.
    /// Stackbar 0.20.0.
    public static func findFiles(_ text: String, limit: Int = 8) async throws -> [FoundFile] {
        try await HostReplies.findFiles.decode(value(.findFiles(FileQuery(text: text, limit: limit)))) ?? []
    }

    /// Locks, sleeps, restarts the Mac and the like (`SystemAction`). Ask
    /// before a destructive one (`action.isDestructive`). Needs
    /// `.systemActions`; macOS asks once to let Stackbar control Finder or
    /// System Events for some. Stackbar 0.22.0.
    public static func system(_ action: SystemAction) async throws {
        try await ok(.system(action))
    }

    /// Registers this plugin's key layer, replacing the last one, or removes
    /// it with `nil`. While the layer's trigger (Right ⌘) is held, its keys
    /// switch apps: the host decides each press itself, so set the whole map
    /// up front and set it again when it changes (the `.apps` trigger says
    /// when an app opened or quit). Answers whether it is listening. Needs
    /// `.keyLayer`; the host asks for Accessibility access. Stackbar 0.16.0.
    @discardableResult
    public static func setKeyLayer(_ layer: KeyLayer?) async throws -> KeyLayerStatus {
        guard let reply = try await HostReplies.keyLayer.decode(value(.setKeyLayer(layer))) else { throw HostError("no key layer status") }
        return reply
    }

    /// Registers this plugin's keywords, replacing the last set, or removes
    /// them with `[]`. Typing a keyword in any app deletes it and runs its
    /// command, which usually pastes (return `.paste(text)`). The plugin
    /// never sees what is typed: set every keyword up front and set them
    /// again when they change. Answers whether they expand. Needs
    /// `.textExpansion`; the host asks for Accessibility access. Stackbar
    /// 0.24.0.
    @discardableResult
    public static func setExpansions(_ expansions: [TextExpansion]) async throws -> ExpansionStatus {
        guard let reply = try await HostReplies.expansions.decode(value(.setExpansions(expansions))) else { throw HostError("no expansion status") }
        return reply
    }

    /// Whether this plugin's keywords expand, and if not, why: expansion
    /// switched off in Settings, missing Accessibility access, an app holding
    /// Secure Input, or keywords another plugin registered first. Needs
    /// `.textExpansion`. Stackbar 0.24.0.
    public static func expansionStatus() async throws -> ExpansionStatus {
        guard let reply = try await HostReplies.expansions.decode(value(.expansionStatus)) else { throw HostError("no expansion status") }
        return reply
    }

    /// Whether this plugin's key layer is listening, and if not, why: missing
    /// Accessibility access, an app holding Secure Input, or another plugin
    /// on the same trigger. Needs `.keyLayer`. Stackbar 0.16.0.
    public static func keyLayerStatus() async throws -> KeyLayerStatus {
        guard let reply = try await HostReplies.keyLayer.decode(value(.keyLayerStatus)) else { throw HostError("no key layer status") }
        return reply
    }

    // MARK: Windows

    /// The displays and the regular apps' windows, front to back, with the
    /// monitor setup's id (`WindowSnapshot.setupID`). Needs `.windows`; the
    /// host asks for Accessibility access the first time. Stackbar 0.15.0.
    public static func windows() async throws -> WindowSnapshot {
        guard let reply = try await HostReplies.windows.decode(value(.windows)) else { throw HostError("no windows") }
        return reply
    }

    /// Moves and resizes windows to `placements` (take them from
    /// `WindowPlacement.capture(snapshot)`), matching by app, then title,
    /// then order. With `launch`, apps that aren't running are opened first.
    /// At most 200 placements and 10 calls a minute. Needs `.windows`.
    @discardableResult
    public static func arrangeWindows(_ placements: [WindowPlacement], launch: Bool = false) async throws -> ArrangeResult {
        guard let reply = try await HostReplies.arrangeWindows.decode(value(.arrangeWindows(placements, launch: launch))) else { throw HostError("no result from arranging windows") }
        return reply
    }

    /// Brings one window to the front: unminimizes and raises it, and makes
    /// its app active. Point at a window from `windows()` with
    /// `WindowTarget(window, in: snapshot)`. Needs `.windows`. Stackbar 0.25.0.
    public static func focusWindow(_ target: WindowTarget) async throws {
        try await ok(.focusWindow(target))
    }

    // MARK: Menus

    /// The menu bar of the app the user was in before Stackbar (the Apple
    /// menu left out): every item that does something, with its path of
    /// titles and shortcut. Needs `.menus`; the host asks for Accessibility
    /// access the first time. Stackbar 0.25.0.
    public static func menuItems() async throws -> MenuSnapshot {
        guard let reply = try await HostReplies.menuItems.decode(value(.menuItems)) else { throw HostError("no menus") }
        return reply
    }

    /// Brings the app forward and chooses its menu item at `path`, as
    /// `menuItems()` gave it. Fails when the item is gone or dimmed. Needs
    /// `.menus`. Stackbar 0.25.0.
    public static func pressMenuItem(appID: String, path: [String]) async throws {
        try await ok(.pressMenuItem(appID: appID, path: path))
    }

    // MARK: Colors and the dictionary

    /// Shows the system's magnifier so the user can pick a color anywhere on
    /// screen. Nil when they press Escape. Needs no capability: nothing is
    /// read until the user clicks. Stackbar 0.26.0 and later.
    ///
    /// ```swift
    /// if let color = try await Stackbar.pickColor() { Stackbar.copy(color.hex) }
    /// ```
    public static func pickColor() async throws -> PickedColor? {
        try await HostReplies.pickColor.decode(value(.pickColor))
    }

    /// The definition the Mac's own Dictionary has for a word or phrase, as
    /// plain text, or nil when it has none. Needs no capability; the lookup
    /// stays on the Mac. Stackbar 0.26.0 and later.
    public static func define(_ word: String) async throws -> Definition? {
        try await HostReplies.define.decode(value(.define(word)))
    }

    // MARK: Commands and context

    /// Runs a command the manifest declares with `.run(commands:)` and
    /// waits for it to finish. Arguments go to it exactly as given (there is
    /// no shell). A non-zero exit is not an error; check `result.status`.
    ///
    /// ```swift
    /// let result = try await Stackbar.run("brew", ["outdated", "--json=v2"], timeout: .seconds(120))
    /// let outdated = try JSONDecoder().decode(Outdated.self, from: result.stdout)
    /// ```
    ///
    /// It runs in the plugin's own folder unless `workingDirectory` names
    /// one inside a granted `.files` path, with PATH, HOME, LANG and TMPDIR
    /// set by the host plus `environment`. Output past 8 MB a channel is
    /// cut (`result.truncated`); the timeout is at most 10 minutes.
    public static func run(_ command: String, _ arguments: [String] = [], input: Data? = nil, workingDirectory: String? = nil, environment: [String: String] = [:], timeout: Duration = .seconds(60)) async throws -> RunResult {
        let request = RunRequest(command: command, arguments: arguments, input: input, workingDirectory: workingDirectory, environment: environment, timeout: timeout.seconds)
        guard let reply = try await HostReplies.run.decode(value(.run(request))) else { throw HostError("no result from \(command)") }
        return reply
    }

    /// Runs a declared command and hands over its output as it is written,
    /// ending with `.exit`. Leaving the loop early stops the command.
    ///
    /// ```swift
    /// for try await event in Stackbar.stream("docker", ["logs", "-f", id]) {
    ///     switch event {
    ///     case .stdout(let data): lines.append(String(decoding: data, as: UTF8.self))
    ///     case .stderr: break
    ///     case .exit(let exit): status = exit.status
    ///     }
    /// }
    /// ```
    public static func stream(_ command: String, _ arguments: [String] = [], input: Data? = nil, workingDirectory: String? = nil, environment: [String: String] = [:], timeout: Duration = .seconds(60)) -> AsyncThrowingStream<RunEvent, any Error> {
        HostClient.shared.stream(RunRequest(command: command, arguments: arguments, input: input, workingDirectory: workingDirectory, environment: environment, timeout: timeout.seconds, stream: true))
    }

    /// The app the user is in, its window title and the selected text (when
    /// the app shares it through Accessibility). Needs `.context`. In a
    /// command, prefer `invocation.context`: it was read when the command
    /// started, before Stackbar's palette took focus.
    public static func context() async throws -> InvocationContext {
        try await HostReplies.context.decode(value(.context)) ?? InvocationContext()
    }

    /// The paths selected in Finder. Needs `.context`; macOS asks the user
    /// once to let Stackbar read Finder's selection.
    public static func finderSelection() async throws -> [String] {
        try await HostReplies.finderSelection.decode(value(.finderSelection)) ?? []
    }

    // MARK: Files and apps

    /// Asks the user to pick a file (of these extensions, or any) and
    /// returns its name and contents, at most 5 MB; `nil` when they cancel.
    /// Needs no capability: the user chooses.
    public static func chooseFile(types: [String] = []) async throws -> ChosenFile? {
        try await HostReplies.chooseFile.decode(value(.chooseFile(types: types)))
    }

    /// Asks the user where to save `data`, suggesting `name`; returns the
    /// path written, or `nil` when they cancel. At most 5 MB.
    @discardableResult
    public static func saveFile(_ name: String, data: Data) async throws -> String? {
        try await value(.saveFile(name: name, data: data))
    }

    /// An installed app's bundle id from its name ("Safari"), path or
    /// bundle id; `nil` when it isn't installed.
    public static func resolveApplication(_ nameOrPath: String) async throws -> String? {
        try await value(.resolveApplication(nameOrPath))
    }

    private static func value(_ call: HostCall) async throws -> String? {
        switch await HostClient.shared.call(call) {
        case .value(let value): return value
        case .failure(let message): throw HostError(message)
        default: throw HostError("unexpected answer to \(call.label)")
        }
    }

    private static func ok(_ call: HostCall) async throws {
        switch await HostClient.shared.call(call) {
        case .ok, .value: return
        case .failure(let message): throw HostError(message)
        default: throw HostError("unexpected answer to \(call.label)")
        }
    }
}
