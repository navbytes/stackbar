/// A Fluid plugin: a class whose properties are its state and whose view
/// properties describe what each surface shows.
///
/// ```swift
/// @main
/// final class Clock: FluidPlugin {
///     static let manifest = Manifest(id: "dev.example.clock", name: "Clock", triggers: [.launch, .every(.seconds(1))])
///     var now = Date()
///     func refresh() async throws { now = Date() }
///     var menuBar: ViewContent { Label(now.formatted(date: .omitted, time: .shortened), symbol: "clock") }
/// }
/// ```
///
/// The runtime calls `refresh()` when a trigger fires, runs action closures
/// when the user acts, and re-renders after each. A render that comes out the
/// same as the last one is not sent.
@MainActor
public protocol FluidPlugin: AnyObject {
    static var manifest: Manifest { get }
    init()
    /// Fetch or recompute state. Thrown errors are logged to the host, and the
    /// previous render stays on screen.
    func refresh() async throws
    @ViewBuilder var menuBar: ViewContent { get }
    @ViewBuilder var panel: ViewContent { get }
    /// The window surface. Defaults to the panel's content.
    @ViewBuilder var window: ViewContent { get }
    /// The widget surface: read-only, so controls in it do nothing. Defaults
    /// to the panel's content.
    @ViewBuilder var widget: ViewContent { get }
    /// The plugin's page in Fluid's Settings window. List `.settings` in the
    /// manifest's surfaces to get one; the panel's footer then shows a gear
    /// that opens it. Put preferences here and keep the panel for actions.
    @ViewBuilder var settings: ViewContent { get }
    /// What agents can call through the host's MCP gateway.
    @ToolBuilder var tools: [AgentTool] { get }
    /// Another plugin published to a topic this plugin's manifest listens to
    /// with `.topic(name:)`. The plugin re-renders afterwards.
    func receive(topic: String, payload: String, from sender: String) async throws
}

extension FluidPlugin {
    public func refresh() async throws {}
    public var menuBar: ViewContent { [Label(Self.manifest.name, symbol: "puzzlepiece.extension")] }
    public var panel: ViewContent { [] }
    public var window: ViewContent { panel }
    public var widget: ViewContent { panel }
    public var settings: ViewContent { [] }
    public var tools: [AgentTool] { [] }
    public func receive(topic: String, payload: String, from sender: String) async throws {}

    /// The entry point `@main` uses. `--manifest` prints the manifest as JSON
    /// and exits; anything else starts the protocol loop on stdin/stdout.
    public static func main() async {
        if CommandLine.arguments.contains("--manifest") {
            StdioTransport.printManifest(manifest)
            return
        }
        let transport = StdioTransport()
        HostClient.shared.configure(send: transport.send)
        let runtime = PluginRuntime(plugin: Self(), send: transport.send)
        for await message in transport.incoming() {
            if await !runtime.handle(message) { break }
        }
    }
}
