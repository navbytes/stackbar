#if canImport(SwiftUI)
#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import StackbarProtocol

/// An SF Symbol drawn with a `SymbolStyle`: its rendering mode, palette and
/// effect. Effects stop under Reduce Motion.
struct SymbolView: View {
    let name: String
    let style: SymbolStyle?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        colored
            .modifier(SymbolEffectModifier(effect: reduceMotion ? nil : style?.effect, repeats: style?.repeats ?? true))
    }

    @ViewBuilder private var colored: some View {
        let image = Image(systemName: name).symbolRenderingMode(style?.rendering?.mode)
        if style?.rendering == .palette, let palette = style?.palette, let first = palette.first {
            let second = palette.count > 1 ? palette[1] : first
            let third = palette.count > 2 ? palette[2] : second
            image.foregroundStyle(first.color, second.color, third.color)
        } else {
            image
        }
    }
}

extension SymbolStyle.Rendering {
    var mode: SymbolRenderingMode {
        switch self {
        case .monochrome: return .monochrome
        case .hierarchical: return .hierarchical
        case .multicolor: return .multicolor
        case .palette: return .palette
        }
    }
}

/// Plays one `SymbolStyle.Effect`, looping or once. Each effect is its own
/// SwiftUI type, hence the switch.
struct SymbolEffectModifier: ViewModifier {
    let effect: SymbolStyle.Effect?
    let repeats: Bool

    func body(content: Content) -> some View {
        let options: SymbolEffectOptions = repeats ? .repeat(.continuous) : .nonRepeating
        switch effect {
        case nil: content
        case .pulse?: content.symbolEffect(.pulse, options: options, isActive: true)
        case .breathe?: content.symbolEffect(.breathe, options: options, isActive: true)
        case .bounce?: content.symbolEffect(.bounce, options: repeats ? .repeat(.periodic(delay: 1.2)) : .nonRepeating, isActive: true)
        case .rotate?: content.symbolEffect(.rotate, options: options, isActive: true)
        case .variableColor?: content.symbolEffect(.variableColor.iterative, options: options, isActive: true)
        case .wiggle?: content.symbolEffect(.wiggle, options: repeats ? .repeat(.periodic(delay: 1.5)) : .nonRepeating, isActive: true)
        }
    }
}

/// A remote picture the host fetched, filling the space offered and cropped
/// to keep its aspect; until then the placeholder symbol on a quiet fill, or
/// nothing, so what is behind (initials, a tint) shows.
struct RemoteImageView: View {
    let url: String
    let placeholder: String?
    @Environment(\.stackbarRemoteImage) private var remoteImage

    var body: some View {
        Color.clear
            .overlay {
                if let data = remoteImage?(url), let image = Self.image(data) {
                    image.resizable().scaledToFill()
                } else if let placeholder {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: placeholder).foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private static func image(_ data: Data) -> Image? {
        #if canImport(AppKit)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }
}

/// Children in rows of equal-width columns. A plain `Grid`, not a lazy one,
/// so snapshots draw every cell.
struct GridNodeView: View {
    let columns: Int
    let spacing: Double?
    let children: [ViewNode]
    let send: SendAction

    var body: some View {
        let count = max(1, min(columns, 12))
        let gap = CGFloat(spacing ?? 8)
        let rows = stride(from: 0, to: children.count, by: count).map { Array(children[$0..<min($0 + count, children.count)]) }
        Grid(alignment: .topLeading, horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, child in
                        NodeView(node: child, send: send).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    // Empty cells keep the last row's columns as wide as the rest.
                    ForEach(row.count..<count, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
    }
}

/// Grows, tints and lifts its content while the pointer is over it.
struct HoverModifier: ViewModifier {
    let hover: Hover
    let shape: ShapeKind
    let enabled: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = enabled && hovering
        content
            // Over the content, so it shows on an opaque background too: give
            // it a see-through paint.
            .overlay {
                if active, let highlight = hover.highlight {
                    shape.anyShape.fill(highlight.shapeStyle).allowsHitTesting(false)
                }
            }
            .shadow(color: active ? (hover.shadow?.color?.color ?? .black.opacity(0.18)) : .clear, radius: active ? (hover.shadow?.radius ?? 0) : 0, x: hover.shadow?.x ?? 0, y: active ? (hover.shadow?.y ?? 0) : 0)
            .scaleEffect(active && !reduceMotion ? (hover.scale ?? 1) : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: active)
            .onHover { inside in if enabled { hovering = inside } }
    }
}
#endif
