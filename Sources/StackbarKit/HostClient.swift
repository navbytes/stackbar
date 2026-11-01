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

    /// Sends a call and waits for its answer.
    public func call(_ call: HostCall) async -> HostResult {
        await withCheckedContinuation { continuation in
            send(call) { continuation.resume(returning: $0) }
        }
    }

    /// Sends a call without waiting. A failure is reported to the host's log.
    public func fire(_ call: HostCall) {
        let label = Self.label(call)
        send(call) { [weak self] result in
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
        lock.unlock()
        handler?(result)
        return handler != nil
    }

    /// Answers every waiting call with a failure.
    public func failAll(_ reason: String) {
        lock.lock()
        let handlers = pending
        let running = streams
        pending.removeAll()
        streams.removeAll()
        sendMessage = nil
        lock.unlock()
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

    private func send(_ call: HostCall, onResult: @escaping @Sendable (HostResult) -> Void) {
        lock.lock()
        guard let sendMessage else {
            lock.unlock()
            onResult(.failure("not running inside Stackbar"))
            return
        }
        let id = nextID
        nextID += 1
        pending[id] = onResult
        lock.unlock()
        sendMessage(.request(id: id, call: call))
    }

    private func deliver(_ message: PluginMessage) {
        lock.lock()
        let sendMessage = sendMessage
        lock.unlock()
        sendMessage?(message)
    }

    static func label(_ call: HostCall) -> String {
        switch call {
        case .storageSet(let key, _): return "saving \(key)"
        case .secret(let name): return "reading secret \(name)"
        case .http(let request): return "\(request.method) \(request.url)"
        case .oauthToken(let provider, _): return "signing in to \(provider)"
        case .publish(let topic, _): return "publishing to \(topic)"
        case .notify: return "notification"
        case .alert: return "alert"
        case .playSound(let sound): return "playing \(sound.rawValue)"
        case .openURL(let url): return "opening \(url)"
        case .open(let url, _): return "opening \(url)"
        case .copy: return "copying"
        case .clipboardRead: return "reading the clipboard"
        case .clipboardWrite: return "writing the clipboard"
        case .paste: return "pasting"
        case .keepAwake(let request): return request == nil ? "letting the Mac sleep" : "keeping the Mac awake"
        case .systemStatus: return "reading system status"
        case .calendarEvents: return "reading calendar events"
        case .run(let request): return "running \(request.command)"
        case .cancelRun: return "stopping a run"
        case .context: return "reading the selection"
        case .finderSelection: return "reading Finder's selection"
        case .chooseFile: return "choosing a file"
        case .saveFile(let name, _): return "saving \(name)"
        case .resolveApplication(let name): return "finding the app \(name)"
        }
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
/// let token = try await Stackbar.secret("GITHUB_TOKEN")
/// let prs: [PR] = try await Stackbar.getJSON("https://api.github.com/...", headers: ["Authorization": "Bearer \(token ?? "")"])
/// ```
///
/// Every call is checked against the manifest's capabilities as approved by
/// the user, and the error says which capability is missing.
public enum Stackbar {
    /// Saved values, also available as `@Stored` properties.
    @MainActor public static let storage = PluginStorage()

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
    public static func http(_ request: HTTPRequest) async throws -> HTTPResponse {
        switch await HostClient.shared.call(.http(request)) {
        case .http(let response): return response
        case .failure(let message): throw HostError(message)
        default: throw HostError("unexpected answer to \(request.method) \(request.url)")
        }
    }

    public static func get(_ url: String, headers: [String: String] = [:]) async throws -> HTTPResponse {
        try await http(HTTPRequest(url: url, headers: headers))
    }

    /// GETs a URL and decodes its JSON body; a non-2xx status throws.
    public static func getJSON<T: Decodable>(_ url: String, as type: T.Type = T.self, headers: [String: String] = [:], decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var headers = headers
        if headers["Accept"] == nil { headers["Accept"] = "application/json" }
        let response = try await get(url, headers: headers)
        guard (200..<300).contains(response.status) else {
            throw HostError("\(url) answered \(response.status): \(String(decoding: response.body.prefix(300), as: UTF8.self))")
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
        guard let json = try await value(.clipboardRead) else { return nil }
        return try SystemCodec.decode(ClipboardItem.self, from: json)
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
        guard let json = try await value(.systemStatus) else { throw HostError("no system status") }
        return try SystemCodec.decode(SystemStatus.self, from: json)
    }

    /// Events overlapping `from..<to` (at most 31 days), sorted by start.
    /// Needs `.calendar`; the first call asks the user for calendar access.
    public static func calendarEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        guard let json = try await value(.calendarEvents(from: from, to: to)) else { return [] }
        return try SystemCodec.decode([CalendarEvent].self, from: json)
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
        guard let json = try await value(.run(request)) else { throw HostError("no result from \(command)") }
        return try SystemCodec.decode(RunResult.self, from: json)
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
        guard let json = try await value(.context) else { return InvocationContext() }
        return try SystemCodec.decode(InvocationContext.self, from: json)
    }

    /// The paths selected in Finder. Needs `.context`; macOS asks the user
    /// once to let Stackbar read Finder's selection.
    public static func finderSelection() async throws -> [String] {
        guard let json = try await value(.finderSelection) else { return [] }
        return try SystemCodec.decode([String].self, from: json)
    }

    // MARK: Files and apps

    /// Asks the user to pick a file (of these extensions, or any) and
    /// returns its name and contents, at most 5 MB; `nil` when they cancel.
    /// Needs no capability: the user chooses.
    public static func chooseFile(types: [String] = []) async throws -> ChosenFile? {
        guard let json = try await value(.chooseFile(types: types)) else { return nil }
        return try SystemCodec.decode(ChosenFile.self, from: json)
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
        default: throw HostError("unexpected answer to \(HostClient.label(call))")
        }
    }

    private static func ok(_ call: HostCall) async throws {
        switch await HostClient.shared.call(call) {
        case .ok, .value: return
        case .failure(let message): throw HostError(message)
        default: throw HostError("unexpected answer to \(HostClient.label(call))")
        }
    }
}
