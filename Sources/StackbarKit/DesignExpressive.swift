import Foundation

// The bolder half of the design system (Stackbar 0.14.0, protocol 12): glows,
// sweeps and vivid fills from a theme, a backdrop made from a picture, glass
// control bars, avatars, ring clusters, sparklines, tiles and time-of-day
// skies. Like the rest of the kit these are built from the vocabulary, so a
// plugin stays one file; plugins that use them set `minimumStackbar: "0.14.0"`.
//
// ```swift
// Backdrop(imageURL: track.artworkURL, theme: .pink, height: 168) {
//     Spacer()
//     Text(track.title).typography(.title)
//     GlassBar {
//         IconButton("backward.fill", label: "Previous", prominence: .onMedia) { ... }
//         IconButton("pause.fill", label: "Pause", prominence: .onMedia, size: 36) { ... }
//         IconButton("forward.fill", label: "Next", prominence: .onMedia) { ... }
//     }
// }
// ```

// MARK: - Paints

extension Paint {
    /// Text and symbols over a picture, a `Backdrop` or a `Sky`: white.
    public static let onMedia = Paint.hex("#FFFFFF")
    /// The veil a `Backdrop` lays over its picture, darker toward the
    /// bottom, so white text reads whatever the picture is.
    public static let scrim = Paint.linearGradient(colors: [HexColor("#00000080"), HexColor("#000000B8")], angle: 90)
    /// A see-through wash for a hover highlight.
    public static let hoverWash = Paint.hex("#0000000A", dark: "#FFFFFF12")
}

extension Theme {
    /// The hue swept around a ring, from a lighter tone at the top to the
    /// full hue: a ring that warms as it fills.
    public var sweep: Paint {
        .angularGradient(colors: [HexColor(Self.lighten(solid.light, 0.25), dark: solid.dark.map { Self.lighten($0, 0.3) }), solid], angle: -90)
    }

    /// A soft light of the hue from the top-left corner, laid over its tint
    /// behind a hero: the panel's one glowing spot.
    public var glow: Paint {
        .radialGradient(colors: [HexColor(solid.light + "40", dark: solid.dark.map { $0 + "4D" }), HexColor(solid.light + "00", dark: solid.dark.map { $0 + "00" })], x: 0.1, y: 0, radius: 260)
    }

    /// The hue deepening on a diagonal, for a filled hero or tile; text on it
    /// is `onSolid`.
    public var vivid: Paint {
        .linearGradient(colors: [solid, HexColor(Self.deepen(Self.deepen(solid.light)), dark: solid.dark.map { Self.deepen(Self.deepen($0)) })], angle: 45)
    }

    /// The hue's track for a ring: the hue, faint.
    public var track: Paint {
        .color(HexColor(solid.light + "2E", dark: solid.dark.map { $0 + "38" }))
    }

    /// `hex` mixed `amount` (0 to 1) of the way to white.
    static func lighten(_ hex: String, _ amount: Double) -> String {
        guard let rgb = HexColor.components(hex) else { return hex }
        func channel(_ value: Double) -> String { String(format: "%02X", Int(((value + (1 - value) * amount) * 255).rounded())) }
        return "#" + channel(rgb.red) + channel(rgb.green) + channel(rgb.blue)
    }
}

// MARK: - Sky

/// The sky at an hour of the day, for clocks and calendars: deep night,
/// rose dawn, blue day, violet dusk. Every one is dark enough for white text
/// (`Paint.onMedia`) at 4.5:1, in both modes.
public enum Sky: String, CaseIterable, Sendable {
    case night, dawn, day, dusk

    /// The phase of `hour` (0 to 24, fractions allowed): dawn from 5 to 8,
    /// day to 17, dusk to 20, night otherwise.
    public init(hour: Double) {
        let hour = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        switch hour {
        case 5..<8: self = .dawn
        case 8..<17: self = .day
        case 17..<20: self = .dusk
        default: self = .night
        }
    }

    /// The two colors of the gradient, top then bottom.
    public var colors: (top: String, bottom: String) {
        switch self {
        case .night: return ("#0B1026", "#26346A")
        case .dawn: return ("#7A3E7A", "#B5523F")
        case .day: return ("#0B56A8", "#1F6FC4")
        case .dusk: return ("#4B2A86", "#A63A5C")
        }
    }

    public var paint: Paint { .gradient([colors.top, colors.bottom], angle: 90) }

    /// The sun or moon for the phase.
    public var symbol: String {
        switch self {
        case .night: return "moon.stars.fill"
        case .dawn: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .dusk: return "sunset.fill"
        }
    }
}

// MARK: - Components

/// A stage made from a picture: the image blurred to fill the card, a veil
/// over it, and the content in white on top. Album art behind a track, a
/// cover behind a title. Without an image, or until it loads, the theme's
/// vivid fill shows. `height` is fixed, since the picture fills it.
public struct Backdrop: StackbarView {
    var imageURL: String?
    var paint: Paint?
    var theme: Theme
    var height: Double
    var blur: Double
    var alignment: StackAlignment?
    var content: ViewContent

    /// `paint` replaces the theme's vivid fill as the base (a `Sky`, say).
    public init(imageURL: String? = nil, paint: Paint? = nil, theme: Theme, height: Double = 160, blur: Double = 30, alignment: StackAlignment? = nil, @ViewBuilder content: () -> ViewContent) {
        self.imageURL = imageURL
        self.paint = paint
        self.theme = theme
        self.height = height
        self.blur = blur
        self.alignment = alignment
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        ZStack(alignment: .start) {
            Rectangle().fill(paint ?? theme.vivid)
            if let imageURL {
                Image(url: imageURL).blur(blur).opacity(0.9)
            }
            VStack(alignment: alignment, spacing: Space.s) { content }
                .foreground(.onMedia)
                .padding(Space.l)
                .frame(fillWidth: true, fillHeight: true, alignment: alignment == .center ? .bottom : .bottomLeading)
                .background(.scrim)
        }
        .frame(height: height, fillWidth: true)
        .clipShape(.roundedRectangle(cornerRadius: Radius.large + 2))
        .resolve(in: context)
    }
}

/// A capsule of frosted glass holding controls: transport buttons over a
/// backdrop, a toolbar over a gradient.
public struct GlassBar: StackbarView {
    var spacing: Double
    var content: ViewContent

    public init(spacing: Double = Space.xs, @ViewBuilder content: () -> ViewContent) {
        self.spacing = spacing
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        HStack(spacing: spacing) { content }
            .padding(horizontal: Space.s, vertical: Space.xs + 1)
            .background(.material(.glass), in: .capsule)
            .resolve(in: context)
    }
}

/// A person as a circle: their picture when there is one, their initials on
/// the theme's tint until it loads or when there isn't.
public struct Avatar: StackbarView {
    var name: String
    var imageURL: String?
    var theme: Theme
    var size: Double

    public init(_ name: String, imageURL: String? = nil, theme: Theme = .neutral, size: Double = 24) {
        self.name = name
        self.imageURL = imageURL
        self.theme = theme
        self.size = size
    }

    /// Up to two capitals from the first two words: "Ada Lovelace" is "AL".
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        ZStack {
            Circle().fill(theme.tintPaint)
            Text(Self.initials(name)).font(size: (size * 0.38).rounded(), weight: .semibold, design: .rounded).foreground(theme.textPaint)
            if let imageURL { Image(url: imageURL) }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityLabel(name)
        .resolve(in: context)
    }
}

/// Overlapping avatars, at most `limit`, then "+n".
public struct AvatarStack: StackbarView {
    var people: [(name: String, imageURL: String?)]
    var theme: Theme
    var size: Double
    var limit: Int

    public init(_ people: [(name: String, imageURL: String?)], theme: Theme = .neutral, size: Double = 22, limit: Int = 4) {
        self.people = people
        self.theme = theme
        self.size = size
        self.limit = max(1, limit)
    }

    /// What VoiceOver reads: "Ada, Grace and 2 more".
    static func summary(_ names: [String], limit: Int) -> String {
        let shown = names.prefix(limit)
        let extra = names.count - shown.count
        if extra > 0 { return shown.joined(separator: ", ") + " and \(extra) more" }
        if shown.count <= 1 { return shown.first ?? "" }
        return shown.dropLast().joined(separator: ", ") + " and " + (shown.last ?? "")
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let shown = people.prefix(limit)
        let extra = people.count - shown.count
        let ring = Paint.hex("#FFFFFF", dark: "#2B2B2B")
        return HStack(spacing: -(size * 0.32).rounded()) {
            for person in shown {
                Avatar(person.name, imageURL: person.imageURL, theme: theme, size: size)
                    .border(ring, width: 1.5, in: .circle)
            }
            if extra > 0 {
                Text("+\(extra)").typography(Typography(size: (size * 0.42).rounded(), weight: .semibold, design: .rounded, monospacedDigit: true))
                    .frame(width: size, height: size)
                    .background(.raised, in: .circle)
                    .border(ring, width: 1.5, in: .circle)
            }
        }
        .accessibilityLabel(Self.summary(people.map(\.name), limit: limit))
        .resolve(in: context)
    }
}

/// Up to three concentric rings, each in its own theme's sweep, around a
/// center: CPU, memory and disk at a glance, like activity rings.
public struct RingCluster: StackbarView {
    public struct Ring: Sendable {
        public var label: String
        public var value: Double
        public var total: Double
        public var theme: Theme

        public init(_ label: String, value: Double, total: Double = 1, theme: Theme) {
            self.label = label
            self.value = value
            self.total = total
            self.theme = theme
        }

        var fraction: Double { total > 0 ? min(max(value / total, 0), 1) : 0 }
    }

    var rings: [Ring]
    var size: Double
    var lineWidth: Double
    var gap: Double
    var center: ViewContent

    public init(_ rings: [Ring], size: Double = 104, lineWidth: Double = 10, gap: Double = 3, @ViewBuilder center: () -> ViewContent = { [] }) {
        self.rings = Array(rings.prefix(3))
        self.size = size
        self.lineWidth = lineWidth
        self.gap = gap
        self.center = center()
    }

    /// The diameter of ring `index`, outermost first.
    func diameter(_ index: Int) -> Double { size - Double(index) * 2 * (lineWidth + gap) }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let label = rings.map { "\($0.label) \(Int(($0.fraction * 100).rounded()))%" }.joined(separator: ", ")
        return ZStack {
            for (index, ring) in rings.enumerated() {
                // The ring draws its own track in the sweep's hue.
                ProgressBar(value: ring.fraction, style: .ring(lineWidth: lineWidth)).foreground(ring.theme.sweep)
                    .frame(width: diameter(index), height: diameter(index))
            }
            center
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
        .resolve(in: context)
    }
}

/// A series as a small filled line, no axes, with the latest value dotted.
public struct Sparkline: StackbarView {
    var values: [Double]
    var theme: Theme
    var height: Double
    var kind: ChartKind
    var label: String?

    public init(_ values: [Double], theme: Theme, height: Double = 28, kind: ChartKind = .area, label: String? = nil) {
        self.values = values
        self.theme = theme
        self.height = height
        self.kind = kind
        self.label = label
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        Chart(label, values: values, kind: kind, compact: true)
            .foreground(theme.solidPaint)
            .frame(height: height, fillWidth: true)
            .resolve(in: context)
    }
}

/// A square-ish tile for a grid: an icon (or a picture, like a favicon), a
/// title and a line of detail, lifting under the pointer. With an action it
/// is a button.
public struct Tile: StackbarView {
    var title: String
    var subtitle: String?
    var symbol: String
    var imageURL: String?
    var theme: Theme
    var trailing: ViewContent
    var key: String?
    var action: (@MainActor () async throws -> Void)?

    public init(_ title: String, subtitle: String? = nil, symbol: String, imageURL: String? = nil, theme: Theme, key: String? = nil, action: (@MainActor () async throws -> Void)? = nil, @ViewBuilder trailing: () -> ViewContent = { [] }) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.imageURL = imageURL
        self.theme = theme
        self.key = key
        self.action = action
        self.trailing = trailing()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let face = VStack(spacing: Space.s) {
            HStack(spacing: Space.xs) {
                ZStack {
                    IconTile(symbol, theme: theme, size: 30)
                    if let imageURL {
                        Image(url: imageURL).frame(width: 30, height: 30).clipShape(.roundedRectangle(cornerRadius: 8))
                    }
                }
                Spacer(minLength: Space.xs)
                trailing
            }
            .frame(fillWidth: true)
            VStack(spacing: 1) {
                Text(title).typography(.headline)
                if let subtitle { Text(subtitle).role(.secondary).typography(.caption) }
            }
        }
        .padding(Space.m - 2)
        .frame(fillWidth: true, alignment: .leading)
        .background(.surface, in: .roundedRectangle(cornerRadius: Radius.large))
        .hover(scale: 1.03, highlight: .hoverWash)
        guard let action else { return face.resolve(in: context) }
        return Button(key: key ?? title, action: action) { face }.resolve(in: context)
    }
}

/// A big rolling number with a small-capitals label, for a row of two to
/// four across a `HeroCard(look: .glow)`: the counts a developer panel is
/// about. `live` puts a pulsing dot of the theme's color before the label.
public struct HeroStat: StackbarView {
    var label: String
    var value: String
    var theme: Theme
    var live: Bool
    var symbol: String?

    public init(_ label: String, value: String, theme: Theme, live: Bool = false, symbol: String? = nil) {
        self.label = label
        self.value = value
        self.theme = theme
        self.live = live
        self.symbol = symbol
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        VStack(spacing: 0) {
            HStack(spacing: Space.xs) {
                if live {
                    Image(systemName: "circle.fill").font(size: 7).foreground(theme.textPaint).symbolEffect(.pulse)
                } else if let symbol {
                    Image(systemName: symbol).font(size: 9, weight: .semibold).foreground(theme.textPaint)
                }
                Text(label.uppercased()).role(.secondary).typography(.overline)
            }
            Text(value).typography(.metric).numericTransition()
        }
        .accessibilityLabel("\(value) \(label)")
        .resolve(in: context)
    }
}
