#if canImport(SwiftUI)
#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import StackbarProtocol

/// Applies a `Style` in its fixed order: font and foreground, padding,
/// frame, background, border, clip, shadow, opacity, then the accessibility
/// label and animation. Font and foreground also go into the environment,
/// where `NodeView` uses them in place of text styles and role colors.
struct StyleModifier: ViewModifier {
    let style: Style
    /// What the animation watches: the styled child.
    let animationValue: ViewNode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.stackbarFont) { if let font = style.font { $0 = font } }
            .transformEnvironment(\.font) { if let font = style.font { $0 = font.font(for: .body) } }
            .transformEnvironment(\.stackbarForeground) { if let paint = style.foreground { $0 = paint } }
            .ifLet(style.foreground) { $0.foregroundStyle($1.shapeStyle) }
            .ifLet(style.padding) { $0.padding(SwiftUI.EdgeInsets(top: $1.top, leading: $1.leading, bottom: $1.bottom, trailing: $1.trailing)) }
            .ifLet(style.frame) { view, frame in
                view
                    .frame(width: frame.width.map { CGFloat($0) }, height: frame.height.map { CGFloat($0) }, alignment: frame.alignment?.alignment ?? .center)
                    .frame(maxWidth: frame.fillWidth == true ? .infinity : nil, maxHeight: frame.fillHeight == true ? .infinity : nil, alignment: frame.alignment?.alignment ?? .center)
            }
            .ifLet(style.background) { view, fill in view.background { fill.shape.view(fill: fill.paint.shapeStyle, stroke: nil, lineWidth: 0) } }
            .ifLet(style.border) { view, border in view.overlay { border.shape.view(fill: nil, stroke: border.paint.shapeStyle, lineWidth: border.width) } }
            .ifLet(style.clip) { $0.clipShape($1.anyShape) }
            .ifLet(style.shadow) { view, shadow in
                view.shadow(color: shadow.color?.color ?? .black.opacity(0.25), radius: shadow.radius, x: shadow.x, y: shadow.y)
            }
            .ifLet(style.opacity) { $0.opacity($1) }
            .ifLet(style.accessibilityLabel) { $0.accessibilityElement(children: .combine).accessibilityLabel($1) }
            .ifLet(style.animation) { view, motion in view.animation(reduceMotion ? nil : motion.animation, value: animationValue) }
    }
}

extension View {
    /// Applies `transform` when `value` is set.
    @ViewBuilder func ifLet<Value, Result: View>(_ value: Value?, _ transform: (Self, Value) -> Result) -> some View {
        if let value { transform(self, value) } else { self }
    }
}

/// A fraction from a fixed value, or from the clock through a `TimeRange`,
/// redrawn every frame until the range ends.
struct TimedFraction<Content: View>: View {
    let value: Double
    let total: Double
    let timing: TimeRange?
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        if let timing {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: Date() >= timing.end)) { context in
                content(timing.fraction(at: context.date))
            }
        } else {
            content(total > 0 ? min(max(value, 0), total) / total : 0)
        }
    }
}

/// A circle that fills clockwise from the top, inside its frame.
struct RingView: View {
    var fraction: Double
    var paint: AnyShapeStyle
    var lineWidth: Double
    var track: Color = .secondary.opacity(0.2)

    var body: some View {
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        ZStack {
            Circle().strokeBorder(track, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: clamped)
                .stroke(paint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((clamped * 100).rounded())) percent"))
    }
}

/// Shrinks a little while pressed: the feedback a custom-drawn button needs.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Paint {
    var shapeStyle: AnyShapeStyle {
        switch self {
        case .role(let role):
            return AnyShapeStyle(role.color)
        case .color(let color):
            return AnyShapeStyle(color.color)
        case .linearGradient(let colors, let angle):
            let radians = angle * .pi / 180
            let dx = cos(radians) / 2, dy = sin(radians) / 2
            return AnyShapeStyle(LinearGradient(colors: colors.map(\.color), startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
        }
    }
}

extension HexColor {
    /// The color, switching to the dark variant with the appearance.
    var color: Color {
        #if canImport(AppKit)
        let light = light, dark = dark
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return Self.nsColor(isDark ? (dark ?? light) : light)
        })
        #else
        return Self.swiftUIColor(light)
        #endif
    }

    #if canImport(AppKit)
    private static func nsColor(_ hex: String) -> NSColor {
        guard let rgb = components(hex) else { return .clear }
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
    }
    #else
    private static func swiftUIColor(_ hex: String) -> Color {
        guard let rgb = components(hex) else { return .clear }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
    }
    #endif
}

extension FontSpec {
    /// The font, keeping what this spec leaves unset from `style`.
    func font(for style: TextStyle) -> Font {
        let design = design?.font ?? style.design
        let weight = weight?.font ?? style.weight
        var font = size.map { Font.system(size: $0, weight: weight ?? .regular, design: design) }
            ?? Font.system(style.textStyle, design: design, weight: weight)
        if monospacedDigit == true { font = font.monospacedDigit() }
        return font
    }
}

extension FontSpec.Weight {
    var font: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

extension FontSpec.Design {
    var font: Font.Design {
        switch self {
        case .default: return .default
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        case .serif: return .serif
        }
    }
}

extension ShapeKind {
    var anyShape: AnyShape {
        switch self {
        case .rectangle: return AnyShape(Rectangle())
        case .roundedRectangle(let radius): return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule: return AnyShape(Capsule())
        case .circle: return AnyShape(Circle())
        }
    }

    /// The shape filled and stroked, the stroke inside its frame.
    @ViewBuilder func view(fill: AnyShapeStyle?, stroke: AnyShapeStyle?, lineWidth: Double) -> some View {
        switch self {
        case .rectangle: Self.draw(Rectangle(), fill, stroke, lineWidth)
        case .roundedRectangle(let radius): Self.draw(RoundedRectangle(cornerRadius: radius, style: .continuous), fill, stroke, lineWidth)
        case .capsule: Self.draw(Capsule(), fill, stroke, lineWidth)
        case .circle: Self.draw(Circle(), fill, stroke, lineWidth)
        }
    }

    private static func draw(_ shape: some InsettableShape, _ fill: AnyShapeStyle?, _ stroke: AnyShapeStyle?, _ lineWidth: Double) -> some View {
        ZStack {
            if let fill { shape.fill(fill) }
            if let stroke { shape.strokeBorder(stroke, lineWidth: lineWidth) }
        }
    }
}

extension FrameAlignment {
    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

extension StackAlignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .start: return .leading
        case .center: return .center
        case .end: return .trailing
        }
    }

    var vertical: VerticalAlignment {
        switch self {
        case .start: return .top
        case .center: return .center
        case .end: return .bottom
        }
    }
}

extension Motion {
    var animation: Animation {
        switch self {
        case .default: return .default
        case .spring: return .spring
        case .easeInOut(let duration): return .easeInOut(duration: duration)
        }
    }
}
#endif
