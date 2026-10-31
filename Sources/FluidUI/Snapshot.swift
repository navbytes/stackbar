#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftUI
import FluidProtocol

/// Renders a surface to PNG with the real renderers, headless. This is what
/// `fluidctl render --png` and the authoring MCP server's `fluid_render` use,
/// so an agent can look at what a plugin draws without a screen.
@MainActor
public enum Snapshot {
    public static func png(_ node: ViewNode, surface: Surface, dark: Bool = false, scale: CGFloat = 2) -> Data? {
        let content: AnyView
        switch surface {
        case .menuBar:
            content = AnyView(MenuBarView(node: node, fallbackTitle: "").padding(4).frame(height: 24))
        case .panel, .window:
            content = AnyView(NodeView(node: node, send: { _, _ in }).padding(12).frame(width: surface == .panel ? 360 : 520, alignment: .leading))
        case .widget:
            content = AnyView(WidgetContentView(node: node).frame(width: 330, height: 155))
        }
        let view = content
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
