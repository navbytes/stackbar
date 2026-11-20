import Foundation

/// How a widget tree is laid on a desktop widget. Pure, so Linux tests cover
/// what the widget extension draws.
///
/// Like a Scriptable widget's `backgroundColor`, `backgroundGradient` and
/// `backgroundImage`, a widget's background fills the whole widget, edge to
/// edge, rather than sitting as a card inside the widget's margins. A tree
/// says it has a background in one of two ways, both of which draw the same
/// on the panel:
///
/// - Its root is a depth stack (`ZStack`) whose first children are shapes
///   or remote images (a `Backdrop`): those are the background, and the rest
///   is the content, which keeps its own padding. Size, clip, border, shadow
///   and outer padding around such a stack are the panel's card; the widget
///   is the card, so they are dropped.
/// - Its root is `styled` with a `background`: that paint fills the widget
///   and the content keeps the style's padding inside the widget's margins.
public struct WidgetLayers: Equatable, Sendable {
    /// Drawn behind everything, filling the widget, first child at the back.
    /// Empty: the widget's standard background.
    public var background: [ViewNode]
    public var content: ViewNode
    /// The content draws to the widget's edges and pads itself (a depth
    /// stack's content); otherwise it sits inside the system margins.
    public var edgeToEdge: Bool

    public init(background: [ViewNode], content: ViewNode, edgeToEdge: Bool) {
        self.background = background
        self.content = content
        self.edgeToEdge = edgeToEdge
    }
}

/// The desktop widget sizes, as WidgetKit's families.
public enum WidgetSize: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    case small, medium, large

    /// How many rows a list shows at this size: a row is about 30 points
    /// and a small or medium widget about 155 tall, a large one about 345.
    public var maxRows: Int {
        switch self {
        case .small: return 3
        case .medium: return 4
        case .large: return 9
        }
    }

    /// The size in points the previews (`stackbarctl render`) draw at: a
    /// widget's size on a 14-inch MacBook Pro.
    public var points: (width: Double, height: Double) {
        switch self {
        case .small: return (170, 170)
        case .medium: return (364, 170)
        case .large: return (364, 382)
        }
    }
}

extension ViewNode {
    /// The tree split into the background that fills the widget and the
    /// content laid over it (see `WidgetLayers`).
    public var widgetLayers: WidgetLayers {
        if let layers = backdropLayers(inherited: nil) { return layers }
        if case .styled(let child, let style) = self, let background = style.background {
            var inner = style
            inner.background = nil
            inner.border = nil
            inner.clip = nil
            inner.shadow = nil
            inner.frame = nil
            let fill = ViewNode.shape(ShapeNode(.rectangle, fill: background.paint))
            return WidgetLayers(background: [fill], content: inner == Style() ? child : .styled(child, style: inner), edgeToEdge: false)
        }
        return WidgetLayers(background: [], content: self, edgeToEdge: false)
    }

    /// A depth stack opening with background layers, under styles that only
    /// size, pad or frame it (and text styling, which the layers inherit).
    private func backdropLayers(inherited: Style?) -> WidgetLayers? {
        switch self {
        case .styled(let child, let style):
            guard style.background == nil, style.blur == nil, style.opacity == nil, style.hover == nil, style.animation == nil else { return nil }
            // Text styling and labels pass to the layers; the box goes.
            var carried = inherited ?? Style()
            carried.font = carried.font ?? style.font
            carried.foreground = carried.foreground ?? style.foreground
            carried.symbol = carried.symbol ?? style.symbol
            carried.numericTransition = carried.numericTransition ?? style.numericTransition
            carried.accessibilityLabel = carried.accessibilityLabel ?? style.accessibilityLabel
            return child.backdropLayers(inherited: carried)
        case .stack(.depth, let spacing, let alignment, let children):
            let background = Array(children.prefix { $0.isBackdropLayer })
            guard !background.isEmpty, background.count < children.count else { return nil }
            let rest = Array(children.dropFirst(background.count))
            let content = rest.count == 1 ? rest[0] : .stack(axis: .depth, spacing: spacing, alignment: alignment, children: rest)
            guard let inherited, inherited != Style() else {
                return WidgetLayers(background: background, content: content, edgeToEdge: true)
            }
            return WidgetLayers(background: background.map { .styled($0, style: inherited) }, content: .styled(content, style: inherited), edgeToEdge: true)
        default:
            return nil
        }
    }

    /// A shape or a remote image, possibly blurred or faded: something a
    /// backdrop is made of.
    private var isBackdropLayer: Bool {
        switch self {
        case .shape, .image(.url):
            return true
        case .styled(let child, _):
            return child.isBackdropLayer
        default:
            return false
        }
    }

    /// Whether the tree shows something that changes with time on its own:
    /// a clock, or progress that fills over a time range. A widget then
    /// draws ahead for each coming minute, since it can't redraw itself.
    /// (A `timer` counts by itself in a widget too.)
    public var changesWithTime: Bool {
        switch self {
        case .clock:
            return true
        case .progress(_, _, _, _, _, let timing):
            return timing != nil
        case .row(let row):
            return row.accessories.contains(where: \.changesWithTime)
        default:
            return children.contains(where: \.changesWithTime)
        }
    }
}
