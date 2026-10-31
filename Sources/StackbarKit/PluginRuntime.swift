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
    private var handlers: [ActionID: RenderContext.Handler] = [:]

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
            guard let handler = handlers[action] else {
                send(.log(level: .warning, message: "no handler for action \(action)"))
                send(.settled)
                return true
            }
            await run("action \(action)") { try await handler(value) }
            render()
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
        }
        send(.settled)
        return true
    }

    /// Resolves every surface and sends the ones that changed, then the tool
    /// list if it changed.
    public func render() {
        let context = RenderContext()
        for surface in surfaces {
            let root = Self.root(for: surface, content(for: surface).resolve(in: context))
            if lastSent[surface] != root {
                lastSent[surface] = root
                send(.render(surface: surface, root: root))
            }
        }
        handlers = context.handlers
        let tools = plugin.tools.map(\.spec)
        if tools != lastTools, !(lastTools == nil && tools.isEmpty) {
            lastTools = tools
            send(.tools(tools))
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
