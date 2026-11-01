/// Styling and custom controls (protocol 11), named after SwiftUI so an AI
/// already knows them:
///
/// ```swift
/// ZStack {
///     Circle().stroke(.hex("#00000014"), lineWidth: 6)
///     ProgressBar(timing: session, style: .ring(lineWidth: 6)).foreground(orange)
///     Button(key: "start") { running.toggle() } label: {
///         Image(systemName: running ? "pause.fill" : "play.fill")
///             .font(size: 26)
///             .frame(width: 72, height: 72)
///             .background(orange, in: .circle)
///     }
/// }
/// .frame(width: 128, height: 128)
/// TimerText(session).font(size: 64, weight: .heavy, design: .rounded, monospacedDigit: true)
/// ```
///
/// Modifiers apply outside what they follow, in the order written, as in
/// SwiftUI. Each resolves to a `styled` node; consecutive modifiers fold into
/// one node when that keeps the meaning (`Style.folding`).

/// A view with a `Style` applied outside it.
public struct Modified: StackbarView {
    var content: any StackbarView
    var style: Style

    public func resolve(in context: RenderContext) -> [ViewNode] {
        content.resolve(in: context).map { $0.styled(style) }
    }
}

extension StackbarView {
    public func style(_ style: Style) -> Modified { Modified(content: self, style: style) }

    /// Overrides the text style's font. `nil` fields keep the text style's.
    public func font(size: Double? = nil, weight: FontSpec.Weight? = nil, design: FontSpec.Design? = nil, monospacedDigit: Bool? = nil) -> Modified {
        style(Style(font: FontSpec(size: size, weight: weight, design: design, monospacedDigit: monospacedDigit)))
    }

    /// Colors text, symbols, progress and unfilled shapes inside.
    public func foreground(_ paint: Paint) -> Modified { style(Style(foreground: paint)) }

    public func padding(_ length: Double = 8) -> Modified { style(Style(padding: EdgeInsets(length))) }
    public func padding(horizontal: Double = 0, vertical: Double = 0) -> Modified { style(Style(padding: EdgeInsets(horizontal: horizontal, vertical: vertical))) }
    public func padding(_ insets: EdgeInsets) -> Modified { style(Style(padding: insets)) }

    /// A fixed width or height, or all the width or height offered (`fill`).
    public func frame(width: Double? = nil, height: Double? = nil, fillWidth: Bool = false, fillHeight: Bool = false, alignment: FrameAlignment? = nil) -> Modified {
        style(Style(frame: Frame(width: width, height: height, fillWidth: fillWidth ? true : nil, fillHeight: fillHeight ? true : nil, alignment: alignment)))
    }

    public func background(_ paint: Paint, in shape: ShapeKind = .rectangle) -> Modified { style(Style(background: Fill(paint, in: shape))) }
    public func border(_ paint: Paint, width: Double = 1, in shape: ShapeKind = .rectangle) -> Modified { style(Style(border: Border(paint, width: width, in: shape))) }
    public func clipShape(_ shape: ShapeKind) -> Modified { style(Style(clip: shape)) }
    public func cornerRadius(_ radius: Double) -> Modified { clipShape(.roundedRectangle(cornerRadius: radius)) }
    public func shadow(radius: Double, x: Double = 0, y: Double = 0, color: HexColor? = nil) -> Modified { style(Style(shadow: Shadow(color: color, radius: radius, x: x, y: y))) }
    public func opacity(_ value: Double) -> Modified { style(Style(opacity: min(max(value, 0), 1))) }
    /// What VoiceOver and the agent read in place of this view. Give one to
    /// every shape and image that means something.
    public func accessibilityLabel(_ label: String) -> Modified { style(Style(accessibilityLabel: label)) }
    /// Animates changes inside this view; off under Reduce Motion.
    public func animation(_ motion: Motion = .default) -> Modified { style(Style(animation: motion)) }
}

/// Flexible space along the enclosing stack's axis.
public struct Spacer: StackbarView {
    var minLength: Double?

    public init(minLength: Double? = nil) { self.minLength = minLength }

    public func resolve(in context: RenderContext) -> [ViewNode] { [.spacer(minLength: minLength)] }
}

/// An SF Symbol, sized by `.font(size:)` and colored by `.foreground(_:)`.
public struct Image: StackbarView {
    var source: ImageSource

    public init(systemName: String) { self.source = .symbol(systemName) }

    public func resolve(in context: RenderContext) -> [ViewNode] { [.image(source)] }
}

/// Clock text the host counts on its own: down to `0:00` at `range.end`, or
/// up from `range.start`. Render once when the timer starts, not every second.
public struct TimerText: StackbarView {
    var range: TimeRange
    var countsDown: Bool

    public init(_ range: TimeRange, countsDown: Bool = true) {
        self.range = range
        self.countsDown = countsDown
    }

    public func resolve(in context: RenderContext) -> [ViewNode] { [.timer(range, countsDown: countsDown)] }
}

/// What the four shapes share: a fill and a stroke over one `ShapeNode`.
@MainActor
public protocol ShapeView: StackbarView {
    var node: ShapeNode { get set }
}

extension ShapeView {
    public func fill(_ paint: Paint) -> Self {
        var copy = self
        copy.node.fill = paint
        return copy
    }

    public func stroke(_ paint: Paint, lineWidth: Double = 1) -> Self {
        var copy = self
        copy.node.stroke = paint
        copy.node.lineWidth = lineWidth
        return copy
    }

    public func resolve(in context: RenderContext) -> [ViewNode] { [.shape(node)] }
}

public struct Circle: ShapeView {
    public var node = ShapeNode(.circle)
    public init() {}
}

public struct Capsule: ShapeView {
    public var node = ShapeNode(.capsule)
    public init() {}
}

public struct Rectangle: ShapeView {
    public var node = ShapeNode(.rectangle)
    public init() {}
}

public struct RoundedRectangle: ShapeView {
    public var node: ShapeNode
    public init(cornerRadius: Double) { node = ShapeNode(.roundedRectangle(cornerRadius: cornerRadius)) }
}
