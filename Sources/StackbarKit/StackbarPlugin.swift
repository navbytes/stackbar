import Foundation

/// A Stackbar plugin: a class whose properties are its state and whose view
/// properties describe what each surface shows.
///
/// ```swift
/// @main
/// final class Clock: StackbarPlugin {
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
public protocol StackbarPlugin: AnyObject {
    static var manifest: Manifest { get }
    init()
    /// Fetch or recompute state. Thrown errors are logged to the host, and the
    /// previous render stays on screen.
    func refresh() async throws
    /// The status item. Drawing nothing at all takes the item out of the
    /// menu bar until it draws something again.
    @ViewBuilder var menuBar: ViewContent { get }
    @ViewBuilder var panel: ViewContent { get }
    /// The window surface. Defaults to the panel's content.
    @ViewBuilder var window: ViewContent { get }
    /// The widget surface. Buttons, toggles, tappables and rows act through
    /// the app while Stackbar runs; fields, pickers and sliders are drawn
    /// disabled. Defaults to the panel's content.
    @ViewBuilder var widget: ViewContent { get }
    /// The plugin's page in Stackbar's Settings window. List `.settings` in the
    /// manifest's surfaces to get one; the panel's footer then shows a gear
    /// that opens it. Put preferences here and keep the panel for actions.
    @ViewBuilder var settings: ViewContent { get }
    /// What a left click on the menu-bar item does. `nil` (the default)
    /// opens the panel; an action runs instead, and a right click still
    /// opens the panel. Recomputed on every render, so it can follow a
    /// setting.
    var menuBarClick: MenuBarAction? { get }
    /// What agents can call through the host's MCP gateway.
    @ToolBuilder var tools: [AgentTool] { get }
    /// What people can find and run by name: in the palette, from a hotkey,
    /// a `stackbar://` link, Spotlight or Shortcuts. Recomputed on every
    /// render, so user-defined items (one command per quicklink) can be
    /// commands too.
    @CommandBuilder var commands: [Command] { get }
    /// Another plugin published to a topic this plugin's manifest listens to
    /// with `.topic(name:)`. The plugin re-renders afterwards.
    func receive(topic: String, payload: String, from sender: String) async throws
    /// Scenes with sample data for screenshots (see `PreviewScene`). The store
    /// and the website show these instead of the first-run screen.
    static var previews: [PreviewScene<Self>] { get }
}

extension StackbarPlugin {
    public func refresh() async throws {}
    public var menuBar: ViewContent { [Label(Self.manifest.name, symbol: "puzzlepiece.extension")] }
    public var panel: ViewContent { [] }
    public var window: ViewContent { panel }
    public var widget: ViewContent { panel }
    public var settings: ViewContent { [] }
    public var menuBarClick: MenuBarAction? { nil }
    public var tools: [AgentTool] { [] }
    public var commands: [Command] { [] }
    public func receive(topic: String, payload: String, from sender: String) async throws {}
    public static var previews: [PreviewScene<Self>] { [] }

    /// The entry point `@main` uses. `--manifest` prints the manifest as JSON
    /// and `--previews` the previews' names and titles, and both exit;
    /// anything else starts the protocol loop on stdin/stdout, as the
    /// preview named by `STACKBAR_PREVIEW` when that is set.
    public static func main() async {
        if CommandLine.arguments.contains("--manifest") {
            StdioTransport.printManifest(manifest)
            return
        }
        if CommandLine.arguments.contains("--previews") {
            StdioTransport.printPreviews(previewSpecs)
            return
        }
        let transport = StdioTransport()
        HostClient.shared.configure(send: transport.send)
        let preview = ProcessInfo.processInfo.environment[stackbarPreviewEnvironmentKey].flatMap { $0.isEmpty ? nil : $0 }
        let runtime = PluginRuntime(plugin: Self(), preview: preview, send: transport.send)
        let mailbox = transport.incoming()
        while let entry = await mailbox.next() {
            if await !runtime.handle(entry.message, absorbed: entry.absorbed) { break }
        }
    }
}

/// A left-click action for the menu-bar item, like starting or stopping a
/// keep-awake session. `title` is the item's tooltip ("Start keeping awake").
public struct MenuBarAction {
    public var title: String
    public var perform: @MainActor () async throws -> Void

    public init(_ title: String, perform: @escaping @MainActor () async throws -> Void) {
        self.title = title
        self.perform = perform
    }
}
