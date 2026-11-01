import Foundation

/// How a `styled` node draws its child: SwiftUI's common modifiers as one
/// value, so every renderer handles styling in one place.
///
/// Fields apply in a fixed order, the order a SwiftUI author usually writes
/// them: font and foreground, then padding, frame, background, border, clip,
/// shadow and opacity. `font`, `foreground`, `accessibilityLabel` and
/// `animation` act like SwiftUI environment values, so the innermost one wins.
/// Protocol 11.
public struct Style: Codable, Equatable, Sendable {
    public var font: FontSpec?
    /// Overrides the role color of text, labels, images, progress and shapes
    /// without a paint of their own.
    public var foreground: Paint?
    public var padding: EdgeInsets?
    public var frame: Frame?
    public var background: Fill?
    public var border: Border?
    /// Clips the child (and everything before it) to a shape.
    public var clip: ShapeKind?
    public var shadow: Shadow?
    /// 0 to 1.
    public var opacity: Double?
    /// What VoiceOver and the agent read in place of the child.
    public var accessibilityLabel: String?
    /// Animates changes inside the child.
    public var animation: Motion?

    public init(font: FontSpec? = nil, foreground: Paint? = nil, padding: EdgeInsets? = nil, frame: Frame? = nil, background: Fill? = nil, border: Border? = nil, clip: ShapeKind? = nil, shadow: Shadow? = nil, opacity: Double? = nil, accessibilityLabel: String? = nil, animation: Motion? = nil) {
        self.font = font
        self.foreground = foreground
        self.padding = padding
        self.frame = frame
        self.background = background
        self.border = border
        self.clip = clip
        self.shadow = shadow
        self.opacity = opacity
        self.accessibilityLabel = accessibilityLabel
        self.animation = animation
    }

    /// The positions of the order-sensitive fields that are set, in drawing order.
    private var orderedSlots: [Int] {
        [padding != nil, frame != nil, background != nil, border != nil, clip != nil, shadow != nil, opacity != nil]
            .enumerated().filter(\.element).map(\.offset)
    }

    /// This style with `outer` applied after it, when one `Style` can say the
    /// same as wrapping a second `styled` node around this one; `nil` when it
    /// can't (a padding outside a background).
    ///
    /// Environment-like fields keep the inner value, as in SwiftUI.
    public func folding(_ outer: Style) -> Style? {
        if let last = orderedSlots.last, let first = outer.orderedSlots.first, first <= last { return nil }
        var result = self
        result.font = font ?? outer.font
        result.foreground = foreground ?? outer.foreground
        result.accessibilityLabel = accessibilityLabel ?? outer.accessibilityLabel
        result.animation = animation ?? outer.animation
        result.padding = padding ?? outer.padding
        result.frame = frame ?? outer.frame
        result.background = background ?? outer.background
        result.border = border ?? outer.border
        result.clip = clip ?? outer.clip
        result.shadow = shadow ?? outer.shadow
        result.opacity = opacity ?? outer.opacity
        return result
    }
}

extension ViewNode {
    /// This node with `style` applied outside it, folded into an existing
    /// `styled` node when that keeps the meaning.
    public func styled(_ style: Style) -> ViewNode {
        if case .styled(let child, let inner) = self, let folded = inner.folding(style) {
            return .styled(child, style: folded)
        }
        return .styled(self, style: style)
    }
}

/// A color or gradient. A role follows the system as before; hex colors are
/// the plugin's own, each with an optional dark-mode variant.
public enum Paint: Codable, Equatable, Sendable {
    case role(Role)
    case color(HexColor)
    /// A linear gradient; `angle` is in degrees, 0 running left to right and
    /// 90 top to bottom.
    case linearGradient(colors: [HexColor], angle: Double)

    /// `Paint.hex("#F28C38")`, or with a dark-mode variant.
    public static func hex(_ light: String, dark: String? = nil) -> Paint {
        .color(HexColor(light, dark: dark))
    }

    /// A linear gradient through hex colors, top to bottom unless `angle` says otherwise.
    public static func gradient(_ colors: [String], angle: Double = 90) -> Paint {
        .linearGradient(colors: colors.map { HexColor($0) }, angle: angle)
    }
}

/// A color as `#RRGGBB` or `#RRGGBBAA`, with an optional dark-mode variant.
public struct HexColor: Codable, Equatable, Sendable {
    public var light: String
    public var dark: String?

    public init(_ light: String, dark: String? = nil) {
        self.light = light
        self.dark = dark
    }

    /// The hex string for a mode: the dark variant falls back to the light one.
    public func hex(dark isDark: Bool) -> String { isDark ? (dark ?? light) : light }

    /// Red, green, blue and alpha from 0 to 1, or `nil` when `hex` is not
    /// `#RRGGBB` or `#RRGGBBAA`.
    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let full = digits.count == 6 ? value << 8 | 0xFF : value
        func channel(_ shift: UInt64) -> Double { Double(full >> shift & 0xFF) / 255 }
        return (channel(24), channel(16), channel(8), channel(0))
    }

    /// WCAG 2 relative luminance of an opaque color, from 0 (black) to 1.
    public static func luminance(_ hex: String) -> Double? {
        guard let rgb = components(hex) else { return nil }
        func linear(_ channel: Double) -> Double {
            channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    /// WCAG 2 contrast ratio between two colors, from 1 to 21.
    public static func contrast(_ first: String, _ second: String) -> Double? {
        guard let one = luminance(first), let two = luminance(second) else { return nil }
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }
}

public struct FontSpec: Codable, Equatable, Sendable {
    public enum Weight: String, Codable, Sendable, CaseIterable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
    }

    public enum Design: String, Codable, Sendable, CaseIterable {
        case `default`, rounded, monospaced, serif
    }

    /// Points; `nil` keeps the size of the child's text style.
    public var size: Double?
    public var weight: Weight?
    public var design: Design?
    /// Digits of equal width, so a ticking number doesn't jiggle.
    public var monospacedDigit: Bool?

    public init(size: Double? = nil, weight: Weight? = nil, design: Design? = nil, monospacedDigit: Bool? = nil) {
        self.size = size
        self.weight = weight
        self.design = design
        self.monospacedDigit = monospacedDigit
    }
}

public struct EdgeInsets: Codable, Equatable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(_ all: Double) { self.init(top: all, leading: all, bottom: all, trailing: all) }
    public init(horizontal: Double, vertical: Double) { self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal) }
}

/// A fixed size, or the width or height of the space offered (`fill`).
public struct Frame: Codable, Equatable, Sendable {
    public var width: Double?
    public var height: Double?
    public var fillWidth: Bool?
    public var fillHeight: Bool?
    public var alignment: FrameAlignment?

    public init(width: Double? = nil, height: Double? = nil, fillWidth: Bool? = nil, fillHeight: Bool? = nil, alignment: FrameAlignment? = nil) {
        self.width = width
        self.height = height
        self.fillWidth = fillWidth
        self.fillHeight = fillHeight
        self.alignment = alignment
    }
}

public enum FrameAlignment: String, Codable, Sendable, CaseIterable {
    case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing
}

/// Where a stack lines up its children across its axis: for a vertical stack
/// leading, center or trailing; for a horizontal one top, center or bottom.
public enum StackAlignment: String, Codable, Sendable, CaseIterable {
    case start, center, end
}

public enum ShapeKind: Codable, Equatable, Sendable {
    case rectangle
    case roundedRectangle(cornerRadius: Double)
    case capsule
    case circle
}

/// A paint behind the child, in a shape.
public struct Fill: Codable, Equatable, Sendable {
    public var paint: Paint
    public var shape: ShapeKind

    public init(_ paint: Paint, in shape: ShapeKind = .rectangle) {
        self.paint = paint
        self.shape = shape
    }
}

/// A stroke around the child, in a shape.
public struct Border: Codable, Equatable, Sendable {
    public var paint: Paint
    public var width: Double
    public var shape: ShapeKind

    public init(_ paint: Paint, width: Double = 1, in shape: ShapeKind = .rectangle) {
        self.paint = paint
        self.width = width
        self.shape = shape
    }
}

public struct Shadow: Codable, Equatable, Sendable {
    /// Black at 25% when `nil`.
    public var color: HexColor?
    public var radius: Double
    public var x: Double
    public var y: Double

    public init(color: HexColor? = nil, radius: Double, x: Double = 0, y: Double = 0) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

/// How changes animate. The host turns animation off under Reduce Motion.
public enum Motion: Codable, Equatable, Sendable {
    case `default`
    case spring
    case easeInOut(duration: Double)
}

/// A shape drawn by the host: a fill, a stroke, or both. Size it with a
/// frame; without one it takes the space offered.
public struct ShapeNode: Codable, Equatable, Sendable {
    public var kind: ShapeKind
    /// The foreground (or the primary color) when neither fill nor stroke is set.
    public var fill: Paint?
    public var stroke: Paint?
    public var lineWidth: Double?

    public init(_ kind: ShapeKind, fill: Paint? = nil, stroke: Paint? = nil, lineWidth: Double? = nil) {
        self.kind = kind
        self.fill = fill
        self.stroke = stroke
        self.lineWidth = lineWidth
    }
}

/// Where an image comes from. SF Symbols for now; bundled assets later.
public enum ImageSource: Codable, Equatable, Sendable {
    case symbol(String)
}

/// A span of time the host counts through on its own, so a countdown or a
/// timed ring moves every frame without the plugin rendering again.
public struct TimeRange: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    /// How far through the range `now` is, from 0 to 1.
    public func fraction(at now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    /// Seconds left (counting down) or gone (counting up) at `now`, as
    /// `m:ss`, or `h:mm:ss` from an hour.
    public func clock(at now: Date, countsDown: Bool) -> String {
        let elapsed = min(max(now.timeIntervalSince(start), 0), end.timeIntervalSince(start))
        let seconds = Int((countsDown ? end.timeIntervalSince(start) - elapsed : elapsed).rounded(countsDown ? .up : .down))
        let hours = seconds / 3600, minutes = seconds / 60 % 60, rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

/// How a `progress` node draws.
public enum ProgressStyle: Codable, Equatable, Sendable {
    case bar
    /// A circle that fills clockwise from the top; `lineWidth` in points.
    case ring(lineWidth: Double?)
}

/// How a `picker` draws.
public enum ChoiceStyle: String, Codable, Sendable, CaseIterable {
    /// A pop-up menu, the default.
    case menu
    /// Side-by-side segments, for two to five short options.
    case segmented
}

/// The macOS system sounds a plugin may play. No audio files, so a plugin
/// can't play arbitrary sound.
public enum SystemSound: String, Codable, Sendable, CaseIterable {
    case basso = "Basso", blow = "Blow", bottle = "Bottle", frog = "Frog", funk = "Funk", glass = "Glass"
    case hero = "Hero", morse = "Morse", ping = "Ping", pop = "Pop", purr = "Purr", sosumi = "Sosumi"
    case submarine = "Submarine", tink = "Tink"
}
