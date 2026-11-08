import Foundation
import StackbarProtocol

/// One plugin, built and running headless, with a log and a way to wait until
/// it has finished handling what it was sent. `stackbarctl` and both MCP servers
/// drive plugins through this.
public actor PluginSession {
    public let source: URL
    private let loader: PluginLoader
    private let services: HostServices?
    private var supervisor: PluginSupervisor?
    /// Applies the supervisor's updates one at a time, in the order they came.
    private var updates: Task<Void, Never>?
    private var binary: URL?
    private var expected = 0
    private var logLines: [String] = []
    private let maxLogLines = 500
    /// Each open command view, kept by the same rules as the palette's.
    private var commandViews: [Int: CommandView] = [:]
    private var nextSession = 1

    public init(source: URL, loader: PluginLoader, services: HostServices?) {
        self.source = source
        self.loader = loader
        self.services = services
    }

    public var manifest: Manifest? { supervisor?.manifest }
    public var isRunning: Bool { supervisor != nil }

    /// Builds the plugin (when it is a `.swift` file) and starts it, or
    /// restarts it when the build produced a different helper. Throws
    /// `PluginBuilder.Failure` with diagnostics when it doesn't compile.
    @discardableResult
    public func ensureRunning() async throws -> Bool {
        let loader = loader
        let source = source
        let built = try await PluginLoader.inBackground { try loader.helper(for: source).binary }
        if let supervisor, built == binary, await supervisor.state != .stopped {
            if case .failed = await supervisor.state {} else { return false }
        }
        await supervisor?.stop()
        // Loading the built helper rather than the source skips a second
        // build and still reads, checks and signs it like any other load.
        let loaded = try await loader.loadInBackground(built)
        // The old consumer ends on its own once the old supervisor is gone.
        let (stream, continuation) = AsyncStream.makeStream(of: PluginSupervisor.Update.self)
        let next = PluginSupervisor(executable: loaded.binary, manifest: loaded.manifest, policy: BackoffPolicy(initialDelay: 0.2, multiplier: 2, maxDelay: 2, maxConsecutiveFailures: 2), services: services) { continuation.yield($0) }
        updates = Task { [weak self] in
            for await update in stream { await self?.record(update) }
        }
        supervisor = next
        binary = built
        expected = next.startupMessageCount
        await next.start()
        try await settle()
        return true
    }

    public func view(_ surface: Surface) async -> ViewNode? {
        await supervisor?.views[surface]
    }

    public func views() async -> [Surface: ViewNode] {
        await supervisor?.views ?? [:]
    }

    public func tools() async -> [ToolSpec] {
        await supervisor?.tools ?? []
    }

    public func commands() async -> [CommandSpec] {
        await supervisor?.commands ?? []
    }

    /// Runs a run command and waits for its result.
    public func runCommand(_ command: String, arguments: [String: String] = [:], context: InvocationContext? = nil) async throws -> CommandResult {
        guard let supervisor else { throw SessionError.notRunning }
        let result = await supervisor.runCommand(command, arguments: arguments, source: .cli, context: context)
        expected += 1
        try? await settle()
        return result
    }

    /// Opens a view command with a query and returns its session and tree.
    public func openView(_ command: String, query: CommandQuery = CommandQuery(), context: InvocationContext? = nil) async throws -> (session: Int, root: ViewNode?) {
        guard let supervisor else { throw SessionError.notRunning }
        let session = nextSession
        nextSession += 1
        var view = CommandView(session: session, pluginName: supervisor.manifest.name, query: query)
        let sends = view.open()
        commandViews[session] = view
        await deliver(sends, session: session, command: command, context: context)
        try await settle()
        return (session, commandViews[session]?.root)
    }

    /// Changes an open view's query and returns its new tree.
    public func updateView(_ session: Int, query: CommandQuery) async throws -> ViewNode? {
        guard supervisor != nil else { throw SessionError.notRunning }
        guard let sends = commandViews[session]?.change(query) else { return nil }
        await deliver(sends, session: session)
        try await settle()
        return commandViews[session]?.root
    }

    public func commandView(_ session: Int) -> ViewNode? {
        commandViews[session]?.root
    }

    /// An open view as the palette would see it: its tree, its problem
    /// (a restart, a stop), and whether a submitted form finished.
    public func commandViewState(_ session: Int) -> CommandView? {
        commandViews[session]
    }

    /// Whether the last form submitted in the view came back without
    /// errors, which closes the palette.
    public func formFinished(_ session: Int) -> Bool {
        finishedForms.contains(session)
    }

    public func closeView(_ session: Int) async {
        let sends = commandViews[session]?.close() ?? []
        commandViews[session] = nil
        finishedForms.remove(session)
        await deliver(sends, session: session)
        try? await settle()
    }

    /// Views whose submitted form came back without errors.
    private var finishedForms: Set<Int> = []
    /// Each view's command and context, to open it again after a restart.
    private var openedAs: [Int: (command: String, context: InvocationContext?)] = [:]

    /// Sends a view's messages in order; each one the plugin answers counts
    /// toward `settle`.
    private func deliver(_ sends: [CommandView.Send], session: Int, command: String? = nil, context: InvocationContext? = nil) async {
        guard let supervisor else { return }
        if let command { openedAs[session] = (command, context) }
        for send in sends {
            switch send {
            case .open(let seq, let query):
                guard let opened = openedAs[session] else { continue }
                await supervisor.openView(session: session, command: opened.command, query: query, seq: seq, context: opened.context)
            case .update(let seq, let query):
                await supervisor.updateView(session: session, query: query, seq: seq)
            case .event(let action, let value):
                await supervisor.event(action, value: value)
            case .close:
                await supervisor.closeView(session: session)
                openedAs[session] = nil
            }
            expected += 1
        }
    }

    /// The plugin's left-click action on its menu-bar item, if any.
    public func menuBarClick() async -> MenuBarClick? {
        await supervisor?.menuBarClick
    }

    public func state() async -> PluginSupervisor.State {
        await supervisor?.state ?? .stopped
    }

    /// Sends an event and waits until the plugin has handled it.
    ///
    /// An action that carries `confirm` is held on its first press, as the
    /// app does: the arm comes back and nothing is sent. The same event
    /// again within `ActionConfirmer.window` sends it; `confirmed` sends it
    /// at once, for tests and scripts that mean it.
    @discardableResult
    public func event(_ action: ActionID, value: EventValue? = nil, confirmed: Bool = false) async throws -> ActionConfirmer.Arm? {
        guard let supervisor else { throw SessionError.notRunning }
        let views = await supervisor.views
        let actions = Surface.allCases.compactMap { views[$0] }.flatMap(\.actions) + commandViews.values.flatMap { $0.root?.actions ?? [] }
        guard actions.contains(action) else {
            throw SessionError.unknownAction(action, available: actions)
        }
        // An action inside a command view goes through the view, as in the
        // palette: a stopped view takes none, and a submitted form is
        // watched for whether it finished.
        if let session = commandViews.first(where: { $0.value.root?.actions.contains(action) == true })?.key {
            if confirmed {
                commandViews[session]?.cancelConfirmation()
            } else if case .armed(let arm) = commandViews[session]?.confirm(action) {
                return arm
            }
            finishedForms.remove(session)
            let sends = commandViews[session]?.perform(action, value) ?? []
            guard !sends.isEmpty else { throw SessionError.viewCannotAct(commandViews[session]?.problem) }
            await deliver(sends, session: session)
        } else {
            let surface = Surface.allCases.first { views[$0]?.actions.contains(action) == true }
            if confirmed {
                confirmer.cancel()
            } else if case .armed(let arm) = confirmer.press(action, surface: surface, in: surface.flatMap { views[$0] }) {
                return arm
            }
            await supervisor.event(action, value: value)
            expected += 1
        }
        try await settle()
        return nil
    }

    /// The panel's, window's and settings' "press again", as the app keeps it.
    private var confirmer = ActionConfirmer()

    public func refresh() async throws {
        guard let supervisor else { throw SessionError.notRunning }
        await supervisor.refresh()
        expected += 1
        try await settle()
    }

    /// Fires a trigger (a simulated copy, say) and waits until it is handled.
    public func trigger(_ reason: TriggerReason) async throws {
        guard let supervisor else { throw SessionError.notRunning }
        await supervisor.send(.trigger(reason: reason))
        expected += 1
        try await settle()
    }

    public func callTool(_ name: String, arguments: [String: EventValue]) async throws -> (text: String, isError: Bool) {
        guard let supervisor else { throw SessionError.notRunning }
        let result = await supervisor.callTool(name, arguments: arguments)
        expected += 1
        try? await settle()
        return result
    }

    public func logs(last count: Int = 50) -> [String] {
        Array(logLines.suffix(count))
    }

    public func stop() async {
        await supervisor?.stop()
        supervisor = nil
        binary = nil
    }

    private func record(_ update: PluginSupervisor.Update) {
        switch update {
        case .log(let level, let message): logLines.append("[\(level.rawValue)] \(message)")
        case .state(let state):
            logLines.append("[state] \(state)")
            for session in commandViews.keys {
                let sends = commandViews[session]?.pluginState(state) ?? []
                if !sends.isEmpty { Task { await self.deliver(sends, session: session) } }
            }
        case .view(let session, let seq, let root):
            guard let result = commandViews[session]?.received(seq: seq, root: root) else { return }
            if result.finished { finishedForms.insert(session) }
            if !result.sends.isEmpty { Task { await self.deliver(result.sends, session: session) } }
            return
        case .render(let surface, let root):
            confirmer.rendered(root, surface: surface)
            return
        case .tools, .menuBarClick, .commands: return
        }
        if logLines.count > maxLogLines { logLines.removeFirst(logLines.count - maxLogLines) }
    }

    private func settle(timeout: Double = 30) async throws {
        guard let supervisor else { throw SessionError.notRunning }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = await supervisor.state
            if case .failed(let reason) = state { throw SessionError.failed(reason, logs: logs(last: 20)) }
            if await supervisor.settledCount >= expected { return }
            if case .restarting = state {
                // A crash reset the count; wait for the fresh helper instead.
                expected = supervisor.startupMessageCount
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw SessionError.timedOut(logs: logs(last: 20))
    }

    public enum SessionError: Error, CustomStringConvertible {
        case notRunning
        case unknownAction(ActionID, available: [ActionID])
        case viewCannotAct(String?)
        case failed(String, logs: [String])
        case timedOut(logs: [String])

        public var description: String {
            switch self {
            case .notRunning: return "the plugin is not running"
            case .unknownAction(let action, let available):
                return "no control has the action id \(action). Available: " + (available.isEmpty ? "none" : available.map(\.rawValue).joined(separator: ", "))
            case .viewCannotAct(let problem): return "the command view can't take actions now" + (problem.map { ": \($0)" } ?? "")
            case .failed(let reason, let logs): return "the plugin failed (\(reason)). Recent log:\n" + logs.joined(separator: "\n")
            case .timedOut(let logs): return "the plugin did not finish in time. Recent log:\n" + logs.joined(separator: "\n")
            }
        }
    }
}
