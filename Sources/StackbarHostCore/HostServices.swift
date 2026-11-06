import Foundation
import StackbarProtocol

/// What the host does for plugins, and the one place their capabilities are
/// enforced.
///
/// Every `HostCall` arrives here with the capabilities the user granted the
/// plugin (normally its manifest's, after the install or update sheet). A call
/// outside them fails with a message naming the capability to add, so an agent
/// writing the plugin can fix it from the error alone.
/// A notification as the host posts it, after checking its buttons.
public struct HostNotification: Equatable, Sendable {
    public var pluginID: String
    public var pluginName: String
    public var title: String
    public var body: String?
    /// At most three, each opening an allowed URL.
    public var actions: [NotificationAction]

    public init(pluginID: String, pluginName: String, title: String, body: String? = nil, actions: [NotificationAction] = []) {
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.title = title
        self.body = body
        self.actions = actions
    }
}

public final class HostServices: Sendable {
    /// The host's side effects that need a UI or the OS.
    public struct Platform: Sendable {
        public var notify: @Sendable (HostNotification) -> Void
        /// A full-screen alert; `actions` are already checked.
        public var alert: @Sendable (HostNotification) -> Void
        /// Plays a system sound.
        public var playSound: @Sendable (SystemSound) -> Void
        /// A short message in the HUD over the screen.
        public var hud: @Sendable (_ message: String, _ isError: Bool) -> Void
        public var open: @Sendable (URL) -> Void
        /// Opens with a specific app by bundle id; throws when it isn't installed.
        public var openWith: @Sendable (URL, String) async throws -> Void
        public var copy: @Sendable (String) -> Void
        /// A plugin asked for a declared secret the user hasn't entered.
        public var secretMissing: @Sendable (_ pluginID: String, _ name: String) -> Void
        /// The clipboard, power and calendar.
        public var system: any SystemServices
        /// A declared command now resolves to another program: the plugin's
        /// approval should be shown again.
        public var approvalNeeded: @Sendable (_ pluginID: String) -> Void

        public init(
            notify: @escaping @Sendable (HostNotification) -> Void = { _ in },
            alert: @escaping @Sendable (HostNotification) -> Void = { _ in },
            playSound: @escaping @Sendable (SystemSound) -> Void = { _ in },
            hud: @escaping @Sendable (String, Bool) -> Void = { _, _ in },
            open: @escaping @Sendable (URL) -> Void = { _ in },
            openWith: @escaping @Sendable (URL, String) async throws -> Void = { _, _ in throw SystemServiceError("opening with a chosen app is not available here") },
            copy: @escaping @Sendable (String) -> Void = { _ in },
            secretMissing: @escaping @Sendable (String, String) -> Void = { _, _ in },
            system: any SystemServices = UnsupportedSystem(),
            approvalNeeded: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.approvalNeeded = approvalNeeded
            self.notify = notify
            self.alert = alert
            self.playSound = playSound
            self.hud = hud
            self.open = open
            self.openWith = openWith
            self.copy = copy
            self.secretMissing = secretMissing
            self.system = system
        }
    }

    public let storage: StorageStore
    public let secrets: any SecretStore
    public let audit: NetworkAudit
    public let http: HTTPService
    /// The remote images plugins draw, fetched through `http`.
    public let images: RemoteImageStore
    public let oauth: OAuthBroker
    public let bus: PluginBus
    public let platform: Platform
    /// Runs declared commands, and keeps the audit of what ran.
    public let runs: CommandRunGate
    /// The programs the user approved each plugin to run, by declared name
    /// (the capability ledger's). `nil`: every granted name runs what it
    /// resolves to now, as in `stackbarctl` and tests.
    private let approvedCommands: (@Sendable (String) -> [String: String])?
    private let notifications = RateLimiter(limit: 10, per: 60)
    private let alerts = RateLimiter(limit: 1, per: 60)
    private let sounds = RateLimiter(limit: 10, per: 60)
    private let panels = RateLimiter(limit: 10, per: 60)
    private let arrangements = RateLimiter(limit: 10, per: 60)
    private let appSwitches = RateLimiter(limit: 120, per: 60)
    private let huds = RateLimiter(limit: 30, per: 60)
    private let systemActions = RateLimiter(limit: 10, per: 60)
    private let calendarWrites = RateLimiter(limit: 30, per: 60)
    private let terminals = RateLimiter(limit: 5, per: 60)
    private let textReads = RateLimiter(limit: 30, per: 60)
    /// Every call a plugin makes, so a loop that hammers the host is cut off
    /// instead of starving the others.
    private let calls = RateLimiter(limit: 1200, per: 60)
    private let requests = RateLimiter(limit: 300, per: 60)

    public init(storage: StorageStore, secrets: any SecretStore, platform: Platform = Platform(), audit: NetworkAudit = NetworkAudit(), bus: PluginBus = PluginBus(), oauthTimeout: Double = 300, runs: CommandRunGate? = nil, approvedCommands: (@Sendable (String) -> [String: String])? = nil) {
        self.runs = runs ?? CommandRunGate(root: FileManager.default.temporaryDirectory.appendingPathComponent("stackbar-run", isDirectory: true))
        self.approvedCommands = approvedCommands
        self.storage = storage
        self.secrets = secrets
        self.audit = audit
        self.http = HTTPService(audit: audit)
        self.images = RemoteImageStore(http: http)
        self.oauth = OAuthBroker(secrets: secrets, timeout: oauthTimeout, openURL: platform.open)
        self.bus = bus
        self.platform = platform
    }

    /// Services rooted in one directory, with the given secret store. For
    /// `stackbarctl` and tests; the app builds its own with the Keychain.
    public static func local(directory: URL, secrets: (any SecretStore)? = nil, platform: Platform = Platform()) -> HostServices {
        let store = secrets ?? ChainedSecretStore([FileSecretStore(file: directory.appendingPathComponent("secrets.json")), EnvironmentSecretStore()])
        return HostServices(storage: StorageStore(directory: directory.appendingPathComponent("storage", isDirectory: true)), secrets: store, platform: platform)
    }

    /// Handles one call for a plugin whose granted capabilities are those of
    /// `granted` (its manifest with the approved capability list). `declared`
    /// is the manifest as written: a call it covers but `granted` does not is
    /// refused as waiting for approval, not as undeclared.
    ///
    /// `id` is the plugin's request id, which names a streamed run; `emit`
    /// sends a streamed run's output to the plugin.
    public func handle(_ call: HostCall, for granted: Manifest, declared: Manifest? = nil, id: Int = 0, emit: (@Sendable (HostMessage) -> Void)? = nil) async -> HostResult {
        let declared = declared ?? granted
        if let refused = calls.refusal(granted.id, "host calls") { return refused }
        // Capabilities a call needs whatever its arguments; the cases below
        // check what depends on the manifest's details.
        if let need = call.requirement, !granted.capabilities.contains(need.capability) {
            return declared.capabilities.contains(need.capability)
                ? Self.awaitingApproval(granted, "to \(need.purpose)")
                : Self.missing(need.capability, need.purpose)
        }
        switch call {
        case .storageSet(let key, let value):
            return await perform { try await self.storage.set(key, value, for: granted.id, quota: granted.storageQuotaBytes) }

        case .secret(let name):
            guard Manifest.isValidSecretName(name) else {
                return .failure("secret names are 1 to 100 letters, digits, _, - or .")
            }
            guard granted.secretNames.contains(name) else {
                if declared.secretNames.contains(name) { return Self.awaitingApproval(granted, "to read secret \(name)") }
                return .failure("secret \(name) is not declared; add .secret(name: \"\(name)\") to the manifest's capabilities")
            }
            do {
                if let value = try secrets.secret(name), !value.isEmpty { return .value(value) }
                platform.secretMissing(granted.id, name)
                return .value(nil)
            } catch {
                return .failure("could not read secret \(name): \(error)")
            }

        case .http(let request):
            if let refused = requests.refusal(granted.id, "HTTP requests") { return refused }
            let allowed = granted.networkHosts + userServerHosts(granted)
            let result = await http.perform(request, pluginID: granted.id, allowedHosts: allowed)
            if case .failure = result, let host = URLParts.host(of: request.url),
               !URLParts.host(host, matches: allowed), URLParts.host(host, matches: declared.networkHosts + userServerHosts(declared)) {
                return Self.awaitingApproval(granted, "to reach \(host)")
            }
            return result

        case .oauthToken(let name, let forceRefresh):
            guard let provider = granted.oauthProviders.first(where: { $0.name == name }) else {
                if declared.oauthProviders.contains(where: { $0.name == name }) { return Self.awaitingApproval(granted, "to sign in with \(name)") }
                return .failure("OAuth provider \(name) is not declared; add .oauth(OAuthProvider(name: \"\(name)\", ...)) to the manifest's capabilities")
            }
            do {
                return .value(try await oauth.token(pluginID: granted.id, provider: provider, forceRefresh: forceRefresh))
            } catch {
                return .failure("\(error)")
            }

        case .publish(let topic, let payload):
            return await perform { try await self.bus.publish(topic, payload: payload, from: granted.id) }

        case .notify(let title, let body, let actions):
            if let refused = notifications.refusal(granted.id, "notifications") { return refused }
            switch Self.checked(actions ?? []) {
            case .failure(let message): return .failure(message)
            case .success(let buttons):
                platform.notify(HostNotification(pluginID: granted.id, pluginName: granted.name, title: String(title.prefix(200)), body: body.map { String($0.prefix(1000)) }, actions: buttons))
                return .ok
            }

        case .hud(let message, let isError):
            if let refused = huds.refusal(granted.id, "HUD messages") { return refused }
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .failure("a HUD message needs text") }
            platform.hud(String(text.prefix(200)), isError)
            return .ok

        case .system(let action):
            if let refused = systemActions.refusal(granted.id, "system actions") { return refused }
            return await perform { try await self.platform.system.perform(action) }

        case .playSound(let sound):
            if let refused = sounds.refusal(granted.id, "sounds") { return refused }
            platform.playSound(sound)
            return .ok

        case .alert(let title, let body, let actions):
            if let refused = alerts.refusal(granted.id, "alerts") { return refused }
            switch Self.checked(actions) {
            case .failure(let message): return .failure(message)
            case .success(let buttons):
                platform.alert(HostNotification(pluginID: granted.id, pluginName: granted.name, title: String(title.prefix(200)), body: body.map { String($0.prefix(1000)) }, actions: buttons))
                return .ok
            }

        case .openURL(let string):
            guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), Self.openableSchemes.contains(scheme) else {
                return .failure("only https, http, mailto, tel and meeting app (zoommtg, msteams) URLs can be opened")
            }
            platform.open(url)
            return .ok

        case .open(let string, let app):
            let url: URL
            switch Self.openTarget(string, granted: granted) {
            case .success(let target): url = target
            case .failure(let message): return .failure(message.description)
            }
            if url.isFileURL, app == nil, Self.isProgram(url) {
                return .failure("\(url.path) is a program; open it with an app chosen explicitly")
            }
            if let app { return await perform { try await self.platform.openWith(url, app) } }
            platform.open(url)
            return .ok

        case .copy(let text):
            guard text.utf8.count <= 1024 * 1024 else { return .failure("text is too large to copy") }
            platform.copy(text)
            return .ok

        case .clipboardRead:
            return HostReplies.clipboardRead.result(ifAny: platform.system.readClipboard())

        case .clipboardWrite(let content), .paste(let content, _):
            if case .text(let text) = content, text.utf8.count > 1024 * 1024 { return .failure("text is too large to copy") }
            if case .paste(_, let options) = call {
                var options = options ?? PasteOptions()
                options.cursorFromEnd = min(options.cursorFromEnd, PasteOptions.maxCursorFromEnd)
                return await perform { try await self.platform.system.paste(content, options: options) }
            }
            return await perform { try self.platform.system.writeClipboard(content) }

        case .keepAwake(let request):
            return await perform { try self.platform.system.keepAwake(request.map { KeepAwakeRequest(display: $0.display, reason: "\(granted.name): \($0.reason.prefix(120))") }, pluginID: granted.id) }

        case .systemStatus:
            return HostReplies.systemStatus.result(platform.system.systemStatus())

        case .calendarEvents(let from, let to):
            guard to > from else { return .failure("calendarEvents needs to > from") }
            guard to.timeIntervalSince(from) <= 31 * 86400 + 3600 else { return .failure("calendarEvents covers at most 31 days at a time") }
            return await answer(HostReplies.calendarEvents) {
                try await self.platform.system.calendarEvents(from: from, to: to).prefix(500).map { event -> CalendarEvent in
                    var event = event
                    event.notes = event.notes.map { String($0.prefix(4000)) }
                    return event
                }
            }

        case .reminderAccess(let ask):
            return HostReplies.reminderAccess.result(await platform.system.reminderAccess(ask: ask))

        case .reminderLists:
            return await answer(HostReplies.reminderLists) { try await self.platform.system.reminderLists() }

        case .createReminderList(let title, let color):
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return .failure("a Reminders list needs a title") }
            return await answer(HostReplies.createReminderList) { try await self.platform.system.createReminderList(title: String(title.prefix(200)), color: color) }

        case .reminders(let query):
            return await answer(HostReplies.reminders) {
                try await self.platform.system.reminders(query).prefix(ReminderQuery.limit).map { reminder -> Reminder in
                    var reminder = reminder
                    reminder.notes = reminder.notes.map { String($0.prefix(4000)) }
                    return reminder
                }
            }

        case .saveReminder(let reminder, let fields):
            guard !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (fields.map { !$0.contains(.title) } ?? false) else {
                return .failure("a reminder needs a title")
            }
            var reminder = reminder
            reminder.notes = reminder.notes.map { String($0.prefix(4000)) }
            return await answer(HostReplies.saveReminder) { try await self.platform.system.saveReminder(reminder, fields: fields) }

        case .deleteReminder(let reminderID):
            return await perform { try await self.platform.system.deleteReminder(id: reminderID) }

        case .run(let request):
            return await run(request, id: id, granted: granted, declared: declared, emit: emit)

        case .cancelRun(let runID):
            runs.cancel(pluginID: granted.id, id: runID)
            return .ok

        case .context:
            return HostReplies.context.result(await platform.system.context())

        case .finderSelection:
            return await answer(HostReplies.finderSelection) { try await self.platform.system.finderSelection() }

        case .chooseFile(let types):
            if let refused = panels.refusal(granted.id, "file panels") { return refused }
            do {
                guard let file = try await platform.system.chooseFile(types: types, for: granted.name) else { return .value(nil) }
                guard file.data.count <= ChosenFile.maxBytes else { return .failure("\(file.name) is larger than 5 MB") }
                return HostReplies.chooseFile.result(file)
            } catch {
                return .failure("\(error)")
            }

        case .saveFile(let name, let data):
            if let refused = panels.refusal(granted.id, "file panels") { return refused }
            guard data.count <= ChosenFile.maxBytes else { return .failure("files saved this way are at most 5 MB") }
            let safe = (name as NSString).lastPathComponent
            do {
                return .value(try await platform.system.saveFile(name: safe.isEmpty ? "Untitled" : safe, data: data, for: granted.name))
            } catch {
                return .failure("\(error)")
            }

        case .resolveApplication(let nameOrPath):
            return .value(await platform.system.resolveApplication(nameOrPath))

        case .windows:
            return await answer(HostReplies.windows) { try await self.platform.system.windows() }

        case .installedApps:
            return await answer(HostReplies.installedApps) { try await self.platform.system.installedApps() }

        case .findFiles(let query):
            let query = FileQuery(text: query.text, limit: query.limit)
            guard !query.text.trimmingCharacters(in: .whitespaces).isEmpty else { return HostReplies.findFiles.result([]) }
            return await answer(HostReplies.findFiles) { try await self.platform.system.findFiles(query) }

        case .runningApps:
            return await answer(HostReplies.runningApps) { try await self.platform.system.runningApps() }

        case .activateApp(let id, let launch):
            if let refused = appSwitches.refusal(granted.id, "app switches") { return refused }
            return await perform { try await self.platform.system.activateApp(id, launch: launch) }

        case .hideApp(let id):
            if let refused = appSwitches.refusal(granted.id, "app switches") { return refused }
            return await perform { try await self.platform.system.hideApp(id) }

        case .setKeyLayer(let layer):
            return await answer(HostReplies.keyLayer) { try self.platform.system.setKeyLayer(layer, pluginID: granted.id, pluginName: granted.name) }

        case .keyLayerStatus:
            return HostReplies.keyLayer.result(platform.system.keyLayerStatus(pluginID: granted.id))

        case .setExpansions(let expansions):
            return await answer(HostReplies.expansions) { try self.platform.system.setExpansions(expansions, pluginID: granted.id, pluginName: granted.name) }

        case .expansionStatus:
            return HostReplies.expansions.result(platform.system.expansionStatus(pluginID: granted.id))

        case .saveCalendarEvent(let draft):
            if let problem = draft.problem { return .failure(problem) }
            if let refused = calendarWrites.refusal(granted.id, "calendar changes") { return refused }
            return await answer(HostReplies.saveCalendarEvent) { try await self.platform.system.saveCalendarEvent(draft) }

        case .writableCalendars:
            return await answer(HostReplies.writableCalendars) { try await self.platform.system.writableCalendars() }

        case .openInTerminal(let command, let title):
            if let problem = Self.terminalProblem(command) { return .failure(problem) }
            if let refused = terminals.refusal(granted.id, "terminals") { return refused }
            return await perform { try await self.platform.system.openInTerminal(command, title: title.map { String($0.prefix(80)) }) }

        case .recognizeText(let imageID, let languages):
            if let refused = textReads.refusal(granted.id, "text reads") { return refused }
            return await answer(HostReplies.recognizedText) { try await self.platform.system.recognizeText(imageID: imageID, languages: languages.map { Array($0.prefix(8)) }) }

        case .captureScreenText(let languages):
            if let refused = textReads.refusal(granted.id, "text reads") { return refused }
            return await answer(HostReplies.recognizedText) { try await self.platform.system.captureScreenText(languages: languages.map { Array($0.prefix(8)) }) }

        case .sensors:
            return await answer(HostReplies.sensors) { try await self.platform.system.sensors() }

        case .focusWindow(let target):
            if let refused = appSwitches.refusal(granted.id, "app switches") { return refused }
            return await perform { try await self.platform.system.focusWindow(target) }

        case .menuItems:
            return await answer(HostReplies.menuItems) { try await self.platform.system.menuItems() }

        case .pressMenuItem(let appID, let path):
            guard !path.isEmpty, path.count <= MenuSnapshot.maxDepth + 1 else { return .failure("a menu path has 1 to \(MenuSnapshot.maxDepth + 1) titles") }
            if let refused = appSwitches.refusal(granted.id, "menu presses") { return refused }
            return await perform { try await self.platform.system.pressMenuItem(appID: appID, path: path) }

        case .pickColor:
            if let refused = panels.refusal(granted.id, "color pickers") { return refused }
            return await answer(HostReplies.pickColor) { try await self.platform.system.pickColor() }

        case .define(let word):
            let query = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, query.count <= Definition.maxQuery else { return .failure("look up 1 to \(Definition.maxQuery) characters") }
            return HostReplies.define.result(ifAny: await platform.system.define(query))

        case .arrangeWindows(let placements, let launch):
            guard placements.count <= WindowPlacement.maxPerCall else { return .failure("at most \(WindowPlacement.maxPerCall) windows at a time") }
            if let refused = arrangements.refusal(granted.id, "window arrangements") { return refused }
            return await answer(HostReplies.arrangeWindows) { try await self.platform.system.arrangeWindows(placements, launch: launch) }
        }
    }

    /// The value as its call's reply, or the error in words.
    private func answer<Value>(_ reply: HostReply<Value>, _ body: () async throws -> Value) async -> HostResult {
        do {
            return reply.result(try await body())
        } catch {
            return .failure("\(error)")
        }
    }

    /// A value that may be nothing (a picker the user closed) as its call's
    /// reply, or the error in words.
    private func answer<Value>(_ reply: HostReply<Value>, _ body: () async throws -> Value?) async -> HostResult {
        do {
            return reply.result(ifAny: try await body())
        } catch {
            return .failure("\(error)")
        }
    }

    /// `.ok` once the work is done, or the error in words.
    private func perform(_ body: () async throws -> Void) async -> HostResult {
        do {
            try await body()
            return .ok
        } catch {
            return .failure("\(error)")
        }
    }

    private func run(_ request: RunRequest, id: Int, granted: Manifest, declared: Manifest, emit: (@Sendable (HostMessage) -> Void)?) async -> HostResult {
        let name = request.command
        guard granted.runCommands.contains(name) else {
            if declared.runCommands.contains(name) { return Self.awaitingApproval(granted, "to run \(name)") }
            return .failure("\(name) is not declared; add .run(commands: [\"\(name)\"]) to the manifest's capabilities")
        }
        let folders = granted.capabilities.flatMap { capability -> [String] in
            if case .files(let paths) = capability { return paths }
            return []
        }
        let grant = CommandRunGate.Grant(pluginID: granted.id, approvedPaths: approvedCommands?(granted.id), folders: folders)
        func refused(_ refusal: CommandRunGate.Refusal) -> HostResult {
            if refusal.kind == .moved { platform.approvalNeeded(granted.id) }
            return .failure(refusal.description)
        }
        if request.stream {
            guard let emit else { return .failure("streaming runs are not available here") }
            if let refusal = runs.stream(request, id: id, grant: grant, emit: emit) { return refused(refusal) }
            return .ok
        }
        switch await runs.run(request, id: id, grant: grant) {
        case .success(let result): return HostReplies.run.result(result)
        case .failure(let refusal): return refused(refusal)
        }
    }

    /// Lets go of anything the plugin holds in the OS (its power assertion)
    /// and stops the commands it is running. The supervisor calls it
    /// whenever the helper stops or exits.
    public func release(pluginID: String) {
        try? platform.system.keepAwake(nil, pluginID: pluginID)
        _ = try? platform.system.setKeyLayer(nil, pluginID: pluginID, pluginName: "")
        _ = try? platform.system.setExpansions([], pluginID: pluginID, pluginName: "")
        runs.cancelAll(pluginID: pluginID)
    }

    /// URL schemes a plugin may open: the web, mail, and the meeting apps
    /// that can't be reached through an https link without a browser tab.
    public static let openableSchemes: Set<String> = ["https", "http", "mailto", "tel", "zoommtg", "msteams"]

    /// What `open` may open for this plugin: a URL whose scheme is a safe
    /// default or declared in `.openURLs`, or (with `"*"`) an absolute or `~/`
    /// path that exists.
    static func openTarget(_ text: String, granted: Manifest) -> Result<URL, SystemServiceError> {
        let extra = granted.capabilities.flatMap { capability -> [String] in
            if case .openURLs(let schemes) = capability { return schemes.map { $0.lowercased() } }
            return []
        }
        let anything = extra.contains("*")
        if text.hasPrefix("/") || text.hasPrefix("~/") || text == "~" {
            guard anything else { return .failure(SystemServiceError("opening files and folders needs .openURLs(schemes: [\"*\"])")) }
            let path = NSString(string: text).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return .failure(SystemServiceError("\(text) does not exist")) }
            return .success(URL(fileURLWithPath: path))
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return .failure(SystemServiceError("\(text) is not a URL or an absolute path"))
        }
        if scheme == "file" {
            guard anything else { return .failure(SystemServiceError("opening files and folders needs .openURLs(schemes: [\"*\"])")) }
            guard FileManager.default.fileExists(atPath: url.path) else { return .failure(SystemServiceError("\(url.path) does not exist")) }
            return .success(url)
        }
        // Stackbar's own Settings and Store pages only show something; a
        // command link (`stackbar://commands/...`) still needs the scheme.
        if scheme == "stackbar", AppLink(url) != nil || StoreLink(url) != nil {
            return .success(url)
        }
        guard openableSchemes.contains(scheme) || anything || extra.contains(scheme) else {
            return .failure(SystemServiceError("\(scheme): links need .openURLs(schemes: [\"\(scheme)\"]); https, http, mailto, tel and meeting links need nothing"))
        }
        return .success(url)
    }

    /// An app bundle or an executable file: opening one launches a program.
    static func isProgram(_ url: URL) -> Bool {
        let path = url.path
        if url.pathExtension.lowercased() == "app" { return true }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// At most three buttons, each opening an allowed URL, titles cut to 40.
    static func checked(_ actions: [NotificationAction]) -> CheckedButtons {
        var buttons: [NotificationAction] = []
        for action in actions.prefix(3) {
            // A button that runs one of the plugin's own commands; the host
            // looks the command up when it is clicked.
            if let command = action.command {
                guard CommandSpec.isValidID(command) else { return .failure("button \"\(action.title)\" runs \(command), which is not a command id") }
                let arguments = action.arguments ?? [:]
                guard arguments.count <= 3, arguments.allSatisfy({ $0.key.count <= 40 && $0.value.count <= 500 }) else {
                    return .failure("button \"\(action.title)\" passes at most 3 arguments of up to 500 characters")
                }
                buttons.append(NotificationAction(String(action.title.prefix(40)), command: command, arguments: arguments))
                continue
            }
            guard let url = URL(string: action.url), let scheme = url.scheme?.lowercased(), openableSchemes.contains(scheme) else {
                return .failure("button \"\(action.title)\" opens \(action.url); only https, http, mailto, tel and meeting app URLs can be opened")
            }
            buttons.append(NotificationAction(String(action.title.prefix(40)), url: action.url))
        }
        return .success(buttons)
    }

    /// A terminal command is a program and its arguments, never a shell line
    /// the plugin wrote: the host quotes every word itself.
    static func terminalProblem(_ command: [String]) -> String? {
        guard let program = command.first, !program.trimmingCharacters(in: .whitespaces).isEmpty else { return "openInTerminal needs a program to run" }
        if command.count > 64 { return "openInTerminal takes at most 64 words" }
        if command.contains(where: { $0.count > 4096 || $0.contains("\0") || $0.contains("\n") || $0.contains("\r") }) {
            return "a terminal command's words are at most 4096 characters, without newlines"
        }
        return nil
    }

    enum CheckedButtons {
        case success([NotificationAction])
        case failure(String)
    }

    /// The hosts of the servers the user entered for `.userServer` secrets.
    /// Only the host counts: a URL's scheme, port and path don't widen it.
    func userServerHosts(_ manifest: Manifest) -> [String] {
        manifest.userServerSecrets.compactMap { name in
            guard let value = try? secrets.secret(name) else { return nil }
            return URLParts.host(of: value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func awaitingApproval(_ granted: Manifest, _ what: String) -> HostResult {
        .failure("\(granted.name) needs your approval \(what); open its panel in Stackbar and click Allow")
    }

    private static func missing(_ capability: Capability, _ what: String) -> HostResult {
        .failure("to \(what), add .\(capability.kind.rawValue) to the manifest's capabilities")
    }
}

/// At most `limit` events per key in a sliding window of `per` seconds.
final class RateLimiter: @unchecked Sendable {
    private let limit: Int
    private let window: Double
    private let lock = NSLock()
    private var events: [String: [Date]] = [:]

    init(limit: Int, per window: Double) {
        self.limit = limit
        self.window = window
    }

    /// The refusal once `key` has used up its calls: "too many sounds; at
    /// most 10 a minute". `what` names the calls in the plural.
    func refusal(_ key: String, _ what: String, now: Date = Date()) -> HostResult? {
        guard !allow(key, now: now) else { return nil }
        let count = limit == 1 ? "one" : "\(limit)"
        let span = window == 60 ? "a minute" : "every \(Int(window)) seconds"
        return .failure("too many \(what); at most \(count) \(span)")
    }

    func allow(_ key: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var recent = (events[key] ?? []).filter { now.timeIntervalSince($0) < window }
        guard recent.count < limit else {
            events[key] = recent
            return false
        }
        recent.append(now)
        events[key] = recent
        return true
    }
}
