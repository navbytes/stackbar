#if canImport(SwiftUI)
import SwiftUI
import StackbarProtocol

/// The widget surface's content: the tree drawn in one frame, the way the
/// desktop widget draws it, with lists cut to what the size fits. Shared by
/// the widget extension and `Snapshot`, so `stackbarctl render --surface
/// widget --png` shows what the desktop shows.
///
/// A widget draws once per timeline entry and can't run tasks, timers or
/// AppKit controls, so everything here draws as a snapshot does: fields,
/// pickers and sliders as look-alikes, icons looked up at once, clocks and
/// timed progress as of `now`, and remote images from `images`. The
/// extension sets `stackbarWidgetButton`, which makes buttons, toggles,
/// tappables and rows act.
public struct WidgetContentView: View {
    let layers: WidgetLayers
    let size: WidgetSize
    let margins: SwiftUI.EdgeInsets

    /// `margins`: the widget's content margins, kept around content that
    /// doesn't draw to the edges itself.
    public init(layers: WidgetLayers, size: WidgetSize = .medium, margins: SwiftUI.EdgeInsets) {
        self.layers = layers
        self.size = size
        self.margins = margins
    }

    public var body: some View {
        NodeView(node: layers.content.trimmed(maxRows: size.maxRows), send: { _, _ in })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(layers.edgeToEdge ? SwiftUI.EdgeInsets() : margins)
            .environment(\.stackbarReadOnly, true)
            .environment(\.stackbarSnapshot, true)
    }
}

/// What fills the widget behind its content: the tree's own background
/// (`WidgetLayers.background`), edge to edge, or nil for the standard one.
public struct WidgetBackgroundView: View {
    let layers: WidgetLayers

    public init(layers: WidgetLayers) { self.layers = layers }

    public var body: some View {
        ZStack {
            ForEach(Array(layers.background.enumerated()), id: \.offset) { _, layer in
                NodeView(node: layer, send: { _, _ in })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.stackbarReadOnly, true)
        .environment(\.stackbarSnapshot, true)
    }
}

/// A whole widget as the desktop shows it, for previews: the background,
/// the content over it, the rounded corners. The extension builds the same
/// from WidgetKit's container background instead.
public struct WidgetPreview: View {
    let node: ViewNode
    let size: WidgetSize

    /// macOS's content margins for desktop widgets.
    public static var margins: SwiftUI.EdgeInsets { SwiftUI.EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16) }

    public init(node: ViewNode, size: WidgetSize) {
        self.node = node
        self.size = size
    }

    public var body: some View {
        let layers = node.widgetLayers
        let points = size.points
        WidgetContentView(layers: layers, size: size, margins: Self.margins)
            .frame(width: points.width, height: points.height)
            .background {
                if layers.background.isEmpty {
                    Rectangle().fill(.background.secondary)
                } else {
                    WidgetBackgroundView(layers: layers)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}
#endif
