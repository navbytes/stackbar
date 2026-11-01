/// Runs one plugin against the host's messages.
///
/// Messages are handled strictly in order, one at a time, so plugin code never
/// runs concurrently with itself and needs no locking: a refresh finishes
/// before the click that arrived during it is handled. The cost is that a slow
/// `refresh()` delays events; plugins should keep refreshes short. Host call
/// responses bypass this queue (see `HostClient`), so awaiting the host inside
/// a refresh is fine.
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

    private struct OpenView {
        var command: String
        var invocation: CommandInvocation
        var seq: Int
        var lastRoot: ViewNode?
        var handlers: [ActionID: RenderContext.Handler] = [:]
    }

    public init(plugin: any StackbarPlugin, send: @escaping Send) {
        self.plugin = plugin
        self.send = send
    }

    /// Handles one message; returns `false` once the plugin should exit.
    @discardableResult
    public func handle(_ message: HostMessage) async -> Bool {
        switch message {
        case .hello(_, let offered, let storage):
            Stackbar.storage.load(storage)
            let declared = type(of: plugin).manifest.surfaces
            surfaces = declared.filter(offered.contains)
            send(.ready(protocolVersion: StackbarProtocolVersion.current))
            render()
        case .trigger:
            await run("refresh") { try await self.plugin.refresh() }
            render()
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
