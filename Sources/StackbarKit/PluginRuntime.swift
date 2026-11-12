/// Runs one plugin against the host's messages.
///
/// Messages are handled in order, one at a time, with one exception: a
/// refresh the host asks for (`trigger`) runs in the background, so a click
/// or a palette search that arrives while it waits on the network is handled
/// at once instead of after it. Everything runs on the main actor, so plugin
/// code still needs no locking; it only has to expect that state can change
/// at an `await` inside `refresh()`. At most one refresh runs: triggers that
/// arrive during one fold into a single follow-up, and `Stackbar.refresh()`
/// replaces a running one (cancelling it) rather than racing it. A trigger is
/// `settled` when its refresh has finished, so the host's count of handled
/// messages stays honest. Previews keep the old order: they never refresh.
/// Host call responses bypass this queue (see `HostClient`).
@MainActor
public final class PluginRuntime {
    public typealias Send = @Sendable (PluginMessage) -> Void

    private let plugin: any StackbarPlugin
    private let send: Send
    private var surfaces: [Surface] = []
    private var lastSent: [Surface: ViewNode] = [:]
    private var lastTools: [ToolSpec]?
    private var lastClick: MenuBarClick?
    private var lastCommands: [CommandSpec]?
    private var handlers: [ActionID: RenderContext.Handler] = [:]
    /// Open command views, by session.
    private var views: [Int: OpenView] = [:]
    /// The preview this runtime shows (see `PreviewScene`): set up after hello,
    /// and triggers then re-render without refreshing.
    private let preview: String?

    /// The refresh running now, if any.
    private var refreshing: Refresh?
    /// Triggers that arrived during `refreshing`, folded into one follow-up:
    /// the newest reason and how many messages it answers.
    private var followUp: (reason: TriggerReason, settles: Int)?
    private var nextRefreshID = 0

    private typealias RefreshTask = Task<Result<Void, any Error>, Never>

    private struct Refresh {
        var id: Int
        var task: RefreshTask
        /// The `settled` messages owed once it finishes.
        var settles: Int
    }

    private struct OpenView {
        var command: String
        var invocation: CommandInvocation
        var seq: Int
        var lastRoot: ViewNode?
        var handlers: [ActionID: RenderContext.Handler] = [:]
    }

    public init(plugin: any StackbarPlugin, preview: String? = nil, send: @escaping Send) {
        self.plugin = plugin
        self.preview = preview
        self.send = send
        Stackbar.redrawHandler = { [weak self] in self?.redraw() }
        Stackbar.refreshState = { [weak self] in self?.refreshing != nil }
        Stackbar.refreshNow = { [weak self] in try await self?.refreshNow() }
    }

    /// Whether `hello` has come: before it there is nothing to draw on.
    private var greeted = false

    /// `Stackbar.redraw()`: draws again outside a message, for state a
    /// plugin's own task changed. Only what changed is sent, as after a message.
    private func redraw() {
        guard greeted else { return }
        render()
    }

    /// Handles one message; returns `false` once the plugin should exit.
    /// `absorbed` counts the messages the mailbox folded into this one, each
    /// still owed a `settled`.
    @discardableResult
    public func handle(_ message: HostMessage, absorbed: Int = 0) async -> Bool {
        if case .trigger(let reason) = message, preview == nil || reason == .clipboard {
            startRefresh(reason: reason, settles: 1 + absorbed)
            return true
        }
        let goOn = await handleInOrder(message)
        for _ in 0..<absorbed { send(.settled) }
        return goOn
    }

    /// Waits until no refresh is running or waiting (tests, and a clean exit).
    public func waitForRefreshes() async {
        while let running = refreshing { _ = await running.task.value }
    }

    // MARK: Refreshes

    /// A trigger: starts a refresh, or folds into the follow-up of the one
    /// running.
    private func startRefresh(reason: TriggerReason, settles: Int) {
        if refreshing != nil {
            followUp = (reason, (followUp?.settles ?? 0) + settles)
            return
        }
        launch(reason: reason, settles: settles, after: nil)
    }

    /// `Stackbar.refresh()`: replaces whatever runs or waits with a refresh
    /// that starts now, and waits for it to finish.
    private func refreshNow() async throws {
        // Called from inside a refresh: that refresh is the fresh one, and
        // waiting on a replacement that waits on it would never end.
        if Stackbar.insideRefresh { return }
        var settles = followUp?.settles ?? 0
        followUp = nil
        let previous = refreshing
        if let previous {
            previous.task.cancel()
            settles += previous.settles
        }
        var task = launch(reason: nil, settles: settles, after: previous?.task)
        // Another `Stackbar.refresh()` may replace this one in turn; the
        // caller wants fresh data, so it waits for the one that replaced it.
        while true {
            let result = await task.value
            if case .failure(let error) = result, error is CancellationError, let newer = refreshing?.task, newer != task {
                task = newer
                continue
            }
            try result.get()
            return
        }
    }

    /// Runs `plugin.refresh()` in its own task, after `previous` has wound
    /// down so two refreshes never interleave. The task ends after
    /// `finished`, so awaiting it means the refresh is drawn and settled.
    @discardableResult
    private func launch(reason: TriggerReason?, settles: Int, after previous: RefreshTask?) -> RefreshTask {
        nextRefreshID += 1
        let id = nextRefreshID
        let task = Task { [weak self, plugin] () -> Result<Void, any Error> in
            if let previous { _ = await previous.value }
            var result: Result<Void, any Error> = .failure(CancellationError())
            if !Task.isCancelled {
                result = await Stackbar.$insideRefresh.withValue(true) {
                    await Stackbar.$currentRefreshReason.withValue(reason) {
                        do {
                            try await plugin.refresh()
                            return .success(())
                        } catch {
                            return .failure(error)
                        }
                    }
                }
            }
            self?.finished(id: id, result: result)
            return result
        }
        refreshing = Refresh(id: id, task: task, settles: settles)
        // A replacement draws when it ends; drawing now would show the
        // cancelled one's half-way state.
        if previous == nil { render() }
        return task
    }

    private func finished(id: Int, result: Result<Void, any Error>) {
        guard let done = refreshing, done.id == id else { return } // replaced
        refreshing = nil
        if case .failure(let error) = result, !(error is CancellationError) {
            send(.log(level: .error, message: "refresh failed: \(error)"))
        }
        render()
        for _ in 0..<done.settles { send(.settled) }
        if let next = followUp {
            followUp = nil
            launch(reason: next.reason, settles: next.settles, after: nil)
        }
    }

    // MARK: Messages

    private func handleInOrder(_ message: HostMessage) async -> Bool {
        switch message {
        case .hello(let hostProtocol, let offered, let storage):
            Stackbar.hostProtocol = hostProtocol
            Stackbar.storage.isScratch = preview != nil
            Stackbar.storage.load(preview == nil ? storage : [:])
            let declared = type(of: plugin).manifest.surfaces
            surfaces = declared.filter(offered.contains)
            greeted = true
            send(.ready(protocolVersion: StackbarProtocolVersion.current))
            if let preview {
                await run("preview \(preview)") { try await self.plugin.applyPreview(named: preview) }
            }
            render()
        // A preview's scene stays put: timers, wakes and the like only
        // re-render. A copy is something the user did, like an event, so
        // it still reaches the plugin (`stackbarctl render --copy`).
        case .trigger:
            render() // a preview's trigger; the rest refresh in the background
        case .event(let action, let value):
            guard let handler = handler(for: action) else {
                send(.log(level: .warning, message: "no handler for action \(action)"))
                send(.settled)
                return true
            }
            await run("action \(action)") { try await handler(value) }
            // An action inside a command view always answers with its view,
            // so the host knows the action finished and what it left behind
            // (a form with errors, or not).
            render(forcing: Self.viewSession(of: action))
        case .visibility(let surface, let isVisible):
            if isVisible {
                // Re-send on open, so a host that dropped the tree recovers.
                lastSent[surface] = nil
                render()
            }
        case .shutdown:
            return false
        case .response(let id, let result):
            HostClient.shared.resolve(id: id, result: result)
            return true
        case .topic(let name, let payload, let sender):
            await run("topic \(name)") { try await self.plugin.receive(topic: name, payload: payload, from: sender) }
            render()
        case .callTool(let id, let name, let arguments):
            await callTool(id: id, name: name, arguments: arguments)
            render()
        case .runCommand(let id, let command, let arguments, let source, let context):
            await runCommand(id: id, command: command, invocation: CommandInvocation(arguments: arguments, source: source, context: context))
            render()
        case .openView(let session, let command, let query, let seq, let context):
            let invocation = CommandInvocation(text: query.text, arguments: query.arguments, source: .palette, context: context)
            views[session] = OpenView(command: command, invocation: invocation, seq: seq)
            await searchView(session)
            render(forcing: session)
        case .updateView(let session, let query, let seq):
            if var view = views[session] {
                view.invocation.text = query.text
                view.invocation.arguments = query.arguments
                view.seq = seq
                views[session] = view
                await searchView(session)
                render(forcing: session)
            }
        case .closeView(let session):
            views[session] = nil
        case .runOutput, .runExit:
            // The transport hands these to `HostClient` directly; a test
            // driving the runtime by hand lands here.
            HostClient.shared.deliver(run: message)
            return true
        }
        send(.settled)
        return true
    }

    /// Resolves every surface and sends the ones that changed, then the tool
    /// and command lists if they changed, then every open command view that
    /// changed (and `forcing`'s view always, since the host waits on its seq).
    public func render(forcing forced: Int? = nil) {
        let context = RenderContext()
        for surface in surfaces {
            let root = Self.root(for: surface, content(for: surface).resolve(in: context))
            if lastSent[surface] != root {
                lastSent[surface] = root
                send(.render(surface: surface, root: root))
            }
        }
        var click: MenuBarClick?
        if surfaces.contains(.menuBar), let action = plugin.menuBarClick {
            let perform = action.perform
            click = MenuBarClick(title: action.title, action: context.register("menubar/click", { _ in try await perform() }))
        }
        if click != lastClick {
            lastClick = click
            send(.menuBarClick(click))
        }
        handlers = context.handlers
        for warning in context.warnings { send(.log(level: .warning, message: warning)) }
        let tools = plugin.tools.map(\.spec)
        if tools != lastTools, !(lastTools == nil && tools.isEmpty) {
            lastTools = tools
            send(.tools(tools))
        }
        let commands = plugin.commands.map(\.spec)
        if commands != lastCommands, !(lastCommands == nil && commands.isEmpty) {
            lastCommands = commands
            send(.commands(commands))
        }
        renderViews(forcing: forced)
    }

    static func viewSession(of action: ActionID) -> Int? {
        guard action.rawValue.hasPrefix("view/") else { return nil }
        let parts = action.rawValue.split(separator: "/", maxSplits: 2)
        return parts.count == 3 ? Int(parts[1]) : nil
    }

    private func handler(for action: ActionID) -> RenderContext.Handler? {
        if action.rawValue.hasPrefix("view/") {
            let parts = action.rawValue.split(separator: "/", maxSplits: 2)
            guard parts.count == 3, let session = Int(parts[1]) else { return nil }
            return views[session]?.handlers[action]
        }
        return handlers[action]
    }

    private func command(_ id: String) -> Command? {
        plugin.commands.first { $0.spec.id == id }
    }

    private func renderViews(forcing forced: Int?) {
        for session in views.keys.sorted() {
            guard var view = views[session] else { continue }
            let context = RenderContext(prefix: "view/\(session)/")
            let root: ViewNode
            if let body = command(view.command)?.body {
                root = Self.root(for: .panel, body(view.invocation).resolve(in: context))
            } else {
                root = .empty(title: "\(view.command) is not a view command", symbol: "exclamationmark.triangle", message: nil)
            }
            view.handlers = context.handlers
            for warning in context.warnings { send(.log(level: .warning, message: warning)) }
            if root != view.lastRoot || session == forced {
                view.lastRoot = root
                send(.view(session: session, seq: view.seq, root: root))
            }
            views[session] = view
        }
    }

    private func searchView(_ session: Int) async {
        guard let view = views[session], let search = command(view.command)?.search else { return }
        await run("search \(view.command)") { try await search(view.invocation) }
    }

    private func runCommand(id: Int, command name: String, invocation: CommandInvocation) async {
        guard let command = command(name) else {
            send(.commandResult(id: id, result: .failure("no command named \(name)")))
            return
        }
        guard let perform = command.run else {
            send(.commandResult(id: id, result: .failure("\(command.spec.title) opens a view; it can't be run")))
            return
        }
        var invocation = invocation
        for argument in command.spec.arguments where invocation[argument.name] == nil {
            if let defaultValue = argument.defaultValue {
                invocation.arguments[argument.name] = defaultValue
            } else if argument.required {
                send(.commandResult(id: id, result: .failure("\(command.spec.title) needs \(argument.placeholder)")))
                return
            }
        }
        do {
            send(.commandResult(id: id, result: try await perform(invocation)))
        } catch {
            send(.commandResult(id: id, result: .failure("\(error)")))
        }
    }

    private func content(for surface: Surface) -> ViewContent {
        switch surface {
        case .menuBar: return plugin.menuBar
        case .panel: return plugin.panel
        case .window: return plugin.window
        case .widget: return plugin.widget
        case .settings: return plugin.settings
        }
    }

    private func callTool(id: Int, name: String, arguments: [String: EventValue]) async {
        guard let tool = plugin.tools.first(where: { $0.spec.name == name }) else {
            send(.toolResult(id: id, text: "no tool named \(name)", isError: true))
            return
        }
        for parameter in tool.spec.parameters where parameter.required && arguments[parameter.name] == nil {
            send(.toolResult(id: id, text: "missing required argument \(parameter.name)", isError: true))
            return
        }
        do {
            send(.toolResult(id: id, text: try await tool.perform(arguments), isError: false))
        } catch {
            send(.toolResult(id: id, text: "\(error)", isError: true))
        }
    }

    private func run(_ what: String, _ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            send(.log(level: .error, message: "\(what) failed: \(error)"))
        }
    }

    static func root(for surface: Surface, _ nodes: [ViewNode]) -> ViewNode {
        if nodes.count == 1 { return nodes[0] }
        return .stack(axis: surface == .menuBar ? .horizontal : .vertical, spacing: nil, children: nodes)
    }
}
