#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftUI
import StackbarProtocol

/// Renders a surface to PNG with the real renderers, headless. This is what
/// `stackbarctl render --png` and the authoring MCP server's `stackbar_render` use,
/// so an agent can look at what a plugin draws without a screen.
@MainActor
public enum Snapshot {
    /// `images` gives the bytes of remote images the tree names, fetched
    /// beforehand: a snapshot is drawn at once and can't wait for them.
    public static func png(_ node: ViewNode, surface: Surface, dark: Bool = false, scale: CGFloat = 2, images: (@Sendable (String) -> Data?)? = nil) -> Data? {
        let content: AnyView
        switch surface {
        case .menuBar:
            content = AnyView(MenuBarView(node: node, fallbackTitle: "").padding(4).frame(height: 24))
        case .panel, .window, .settings:
            // The panel is 380 points wide with 12 points of padding, as in PanelView.
            content = AnyView(NodeView(node: node, send: { _, _ in }).padding(12).frame(width: surface == .panel ? 380 : 520, alignment: .leading))
        case .widget:
            content = AnyView(WidgetContentView(node: node).frame(width: 330, height: 155))
        }
        let view = content
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.stackbarSnapshot, true)
            .environment(\.stackbarRemoteImage, images)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
