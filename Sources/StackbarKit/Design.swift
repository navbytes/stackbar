import Foundation

// The Stackbar design system: one look shared by every plugin, so a panel from
// the store feels like part of the Mac and like its neighbours, without each
// plugin carrying its own copy of a palette and a dozen helper views.
//
// ```swift
// let theme = Theme.teal
//
// var panel: ViewContent {
//     PanelHeader("3 running", subtitle: "Docker · updated just now", symbol: "shippingbox.fill", theme: theme) {
//         IconButton("arrow.clockwise", label: "Refresh", theme: theme) { await self.load() }
//     }
//     HStack(spacing: Space.s) {
//         StatTile("Running", value: "3", symbol: "play.fill", theme: theme)
//         StatTile("Stopped", value: "5", symbol: "stop.fill", theme: .neutral)
//     }
//     Card("Containers") { ... }
// }
// ```
//
// Everything here is built from the protocol 11 vocabulary (stacks, shapes,
// paints, fonts); plugins that use it set `minimumStackbar: "0.13.0"`.
// Text keeps the system's primary and secondary colors, which follow the
// panel's material in light and dark mode; color comes from the theme.

// MARK: - Tokens

/// The spacing scale, in points. Stacks, padding and gaps use these.
public enum Space {
    /// 2: hairline gaps, a title and its subtitle.
    public static let xxs = 2.0
    /// 4: inside a chip, between a symbol and its text.
    public static let xs = 4.0
    /// 8: between related items, the default stack spacing.
    public static let s = 8.0
    /// 12: inside a card, between cards.
    public static let m = 12.0
    /// 16: between groups.
    public static let l = 16.0
    /// 24: around an empty state.
    public static let xl = 24.0
}

/// Corner radii, in points.
public enum Radius {
    /// 6: badges and small tiles inside a card.
    public static let small = 6.0
    /// 8: buttons, icon tiles and inner tiles.
    public static let medium = 8.0
    /// 12: cards. The panel itself is 12 inside the popover.
    public static let large = 12.0
}

/// A size, weight and design for one job, so the same kind of text looks the
/// same in every plugin. Apply with `.typography(_:)`.
public struct Typography: Equatable, Sendable {
    public var size: Double
    public var weight: FontSpec.Weight
    public var design: FontSpec.Design
    public var monospacedDigit: Bool

    public init(size: Double, weight: FontSpec.Weight = .regular, design: FontSpec.Design = .default, monospacedDigit: Bool = false) {
        self.size = size
        self.weight = weight
        self.design = design
        self.monospacedDigit = monospacedDigit
    }

    /// 44 heavy rounded: the one number a panel is about (a countdown, a total).
    public static let hero = Typography(size: 44, weight: .heavy, design: .rounded, monospacedDigit: true)
    /// 28 bold rounded: a large reading beside other content.
    public static let metric = Typography(size: 28, weight: .bold, design: .rounded, monospacedDigit: true)
    /// 20 semibold rounded: the value in a stat tile.
    public static let stat = Typography(size: 20, weight: .semibold, design: .rounded, monospacedDigit: true)
    /// 15 semibold: a panel header's title.
    public static let title = Typography(size: 15, weight: .semibold)
    /// 13 semibold: a card's lead line, a track or event name.
    public static let headline = Typography(size: 13, weight: .semibold)
    /// 13 regular: body text.
    public static let body = Typography(size: 13)
    /// 11 regular: captions and subtitles.
    public static let caption = Typography(size: 11)
    /// 11 medium, digits even: times and counts in captions.
    public static let captionNumber = Typography(size: 11, weight: .medium, monospacedDigit: true)
    /// 10 semibold: card titles and overlines, written in capitals.
    public static let overline = Typography(size: 10, weight: .semibold)
}

extension StackbarView {
    /// Sets the font from the shared type ramp.
    public func typography(_ type: Typography) -> Modified {
        font(size: type.size, weight: type.weight, design: type.design, monospacedDigit: type.monospacedDigit ? true : nil)
    }
}

extension Paint {
    /// A card on the panel: a faint layer that lets the material show through.
    public static let surface = Paint.hex("#0000000A", dark: "#FFFFFF0F")
    /// A tile or control inside a card, one step above `surface`.
    public static let raised = Paint.hex("#00000010", dark: "#FFFFFF17")
    /// Dividers, tracks and outlines.
    public static let hairline = Paint.hex("#0000001A", dark: "#FFFFFF1F")
    /// Nothing, for a background that only some states fill.
    public static let clear = Paint.hex("#00000000")
}

// MARK: - Theme

/// A plugin's color: one hue in the four forms the components need, each with
/// a dark-mode variant and checked for 4.5:1 text contrast. Text on the fill is
/// white in light mode and ink in dark mode, for every hue.
///
/// Pick one hue that says what the plugin is about and use it sparingly: the
/// header tile, the main action, rings and progress. Status colors
/// (`.success`, `.warning`, `.critical`, `.neutral`) are themes too, so a
/// pill or a dot says "failing" the same way everywhere.
public struct Theme: Equatable, Sendable {
    /// Fills: the header tile, prominent buttons, rings, progress, chart marks.
    public var solid: HexColor
    /// Text and symbols on `solid`.
    public var onSolid: HexColor
    /// The hue as text or a symbol on the panel, a card or `tint` (the
    /// same as `solid` for the built-in hues).
    public var text: HexColor
    /// A wash of the hue behind a pill, a chip, a banner or a hero card.
    public var tint: HexColor

    public init(solid: HexColor, onSolid: HexColor, text: HexColor, tint: HexColor) {
        self.solid = solid
        self.onSolid = onSolid
        self.text = text
        self.tint = tint
    }

    /// A theme from one hue: deep enough in light mode for white text on it
    /// and as text on the panel, bright enough in dark mode for ink on it and
    /// as text on the panel. `soft` is the hue washed into the background,
    /// opaque so chips stay crisp and contrast is exact.
    public init(_ light: String, dark: String, soft: String, darkSoft: String) {
        self.solid = HexColor(light, dark: dark)
        self.onSolid = HexColor("#FFFFFF", dark: "#141414")
        self.text = HexColor(light, dark: dark)
        self.tint = HexColor(soft, dark: darkSoft)
    }

    public static let blue = Theme("#0A60C8", dark: "#5AA9FF", soft: "#E6EFFA", darkSoft: "#263342")
    public static let indigo = Theme("#4F46E5", dark: "#A5A0FF", soft: "#EDECFC", darkSoft: "#323142")
    public static let violet = Theme("#7537E0", dark: "#C4A3FF", soft: "#F1EBFC", darkSoft: "#373242")
    public static let pink = Theme("#BA2163", dark: "#FF8AB8", soft: "#F8E9EF", darkSoft: "#402E37")
    public static let red = Theme("#C0122E", dark: "#FF8A80", soft: "#F9E7EA", darkSoft: "#402E2E")
    public static let orange = Theme("#A64200", dark: "#FF9F4F", soft: "#F6ECE6", darkSoft: "#403126")
    public static let amber = Theme("#835500", dark: "#FFC24D", soft: "#F3EEE6", darkSoft: "#403726")
    public static let green = Theme("#17743A", dark: "#5BD27A", soft: "#E8F1EB", darkSoft: "#26392D")
    public static let teal = Theme("#00716F", dark: "#4FD6CF", soft: "#E6F1F1", darkSoft: "#243A3A")
    public static let cyan = Theme("#00699A", dark: "#5CC8F5", soft: "#E6F0F5", darkSoft: "#263840")
    public static let graphite = Theme("#4A5361", dark: "#B4BCC8", soft: "#EDEEEF", darkSoft: "#343639")

    /// Done, healthy, passing.
    public static let success = green
    /// Needs a look soon: running out, waiting, behind.
    public static let warning = amber
    /// Broken, failing, about to be lost.
    public static let critical = red
    /// No particular state.
    public static let neutral = graphite
    /// Something to know, nothing to do.
    public static let info = blue

    /// Every named hue, for tests and pickers.
    public static let all: [(name: String, theme: Theme)] = [
        ("blue", .blue), ("indigo", .indigo), ("violet", .violet), ("pink", .pink), ("red", .red), ("orange", .orange),
        ("amber", .amber), ("green", .green), ("teal", .teal), ("cyan", .cyan), ("graphite", .graphite),
    ]

    public var solidPaint: Paint { .color(solid) }
    public var onSolidPaint: Paint { .color(onSolid) }
    public var textPaint: Paint { .color(text) }
    public var tintPaint: Paint { .color(tint) }
    /// The fill, deepening toward the bottom, for tiles and prominent buttons.
    public var gradient: Paint {
        .linearGradient(colors: [solid, HexColor(Self.deepen(solid.light), dark: solid.dark.map(Self.deepen))], angle: 90)
    }

    /// `hex` 12% of the way to black.
    static func deepen(_ hex: String) -> String {
        guard let rgb = HexColor.components(hex) else { return hex }
        func channel(_ value: Double) -> String { String(format: "%02X", Int((value * 0.88 * 255).rounded())) }
        return "#" + channel(rgb.red) + channel(rgb.green) + channel(rgb.blue)
    }
}

// MARK: - Building blocks

/// A rounded square of the theme's color with a symbol on it: a plugin's
/// mark in its header, or a category beside a row of content.
public struct IconTile: StackbarView {
    var symbol: String
    var theme: Theme
    var size: Double

    public init(_ symbol: String, theme: Theme, size: Double = 28) {
        self.symbol = symbol
        self.theme = theme
        self.size = size
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        Image(systemName: symbol)
            .font(size: (size * 0.5).rounded(), weight: .semibold)
            .foreground(theme.onSolidPaint)
            .frame(width: size, height: size)
            .background(theme.gradient, in: .roundedRectangle(cornerRadius: (size * 0.27).rounded()))
            .resolve(in: context)
    }
}

/// The top of a panel: the plugin's tile, what is going on in a few words,
/// a line of detail, and room for a button or two on the right.
///
/// The host already names the plugin in the panel's footer, so the title is
/// best spent on the state: "3 running", "Staying awake", "All caught up".
public struct PanelHeader: StackbarView {
    var title: String
    var subtitle: String?
    var symbol: String
    var theme: Theme
    var trailing: ViewContent

    public init(_ title: String, subtitle: String? = nil, symbol: String, theme: Theme, @ViewBuilder trailing: () -> ViewContent = { [] }) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.theme = theme
        self.trailing = trailing()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        HStack(spacing: Space.s + 2) {
            IconTile(symbol, theme: theme, size: 32)
            VStack(spacing: Space.xxs) {
                Text(title).typography(.title)
                if let subtitle { Text(subtitle).role(.secondary).typography(.caption) }
            }
            Spacer(minLength: Space.s)
            trailing
        }
        .frame(fillWidth: true)
        .resolve(in: context)
    }
}

/// A group of content on a faint rounded layer, with an optional title in
/// small capitals and a trailing note (a count, "updated 2m ago").
public struct Card: StackbarView {
    var title: String?
    var detail: String?
    var spacing: Double
    var padding: Double
    var content: ViewContent

    public init(_ title: String? = nil, detail: String? = nil, spacing: Double = Space.s, padding: Double = Space.m, @ViewBuilder content: () -> ViewContent) {
        self.title = title
        self.detail = detail
        self.spacing = spacing
        self.padding = padding
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        VStack(spacing: spacing) {
            if title != nil || detail != nil {
                CardTitle(title ?? "", detail: detail)
            }
            content
        }
        .padding(padding)
        .frame(fillWidth: true, alignment: .leading)
        .background(.surface, in: .roundedRectangle(cornerRadius: Radius.large))
        .resolve(in: context)
    }
}

/// The stage at the top of an instrument's panel (the track playing, the
/// awake state, the next meeting): the theme's wash, rounded, padded. One per
/// panel, right under the header.
public struct HeroCard: StackbarView {
    var theme: Theme
    var alignment: StackAlignment?
    var spacing: Double
    var content: ViewContent

    public init(theme: Theme, alignment: StackAlignment? = nil, spacing: Double = Space.m, @ViewBuilder content: () -> ViewContent) {
        self.theme = theme
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        VStack(alignment: alignment, spacing: spacing) { content }
            .padding(Space.l)
            .frame(fillWidth: true, alignment: alignment == .center ? .center : .leading)
            .background(theme.tintPaint, in: .roundedRectangle(cornerRadius: Radius.large + 2))
            .resolve(in: context)
    }
}

/// A title in small capitals with a note on the right, for the top of a card
/// or above a list.
public struct CardTitle: StackbarView {
    var title: String
    var detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        HStack(spacing: Space.s) {
            Text(title.uppercased()).role(.secondary).typography(.overline)
            Spacer(minLength: Space.s)
            if let detail { Text(detail).role(.secondary).typography(.captionNumber) }
        }
        .frame(fillWidth: true)
        .resolve(in: context)
    }
}

/// One number with what it counts: a row of two to four of these sums up a
/// panel. The theme colors the symbol, and when `emphasized` the value, on
/// the theme's tint.
public struct StatTile: StackbarView {
    var label: String
    var value: String
    var caption: String?
    var symbol: String?
    var theme: Theme
    var emphasized: Bool

    public init(_ label: String, value: String, caption: String? = nil, symbol: String? = nil, theme: Theme = .neutral, emphasized: Bool = false) {
        self.label = label
        self.value = value
        self.caption = caption
        self.symbol = symbol
        self.theme = theme
        self.emphasized = emphasized
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        VStack(spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                if let symbol { Image(systemName: symbol).font(size: 10, weight: .semibold).foreground(theme.textPaint) }
                Text(label).role(.secondary).typography(.caption)
            }
            if emphasized {
                Text(value).typography(.stat).foreground(theme.textPaint)
            } else {
                Text(value).typography(.stat)
            }
            if let caption { Text(caption).role(.secondary).typography(.caption) }
        }
        .padding(horizontal: Space.m - 2, vertical: Space.s + 1)
        .frame(fillWidth: true, alignment: .leading)
        // The theme's color reads on its own tint, not on a see-through surface.
        .background(emphasized ? theme.tintPaint : .surface, in: .roundedRectangle(cornerRadius: Radius.medium + 2))
        .resolve(in: context)
    }
}

/// The panel's headline number, large: a value, its unit and a caption.
public struct Metric: StackbarView {
    var value: String
    var unit: String?
    var caption: String?
    var type: Typography

    public init(_ value: String, unit: String? = nil, caption: String? = nil, type: Typography = .hero) {
        self.value = value
        self.unit = unit
        self.caption = caption
        self.type = type
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        VStack(spacing: 0) {
            HStack(alignment: .end, spacing: Space.xs) {
                Text(value).typography(type)
                if let unit { Text(unit).role(.secondary).typography(Typography(size: (type.size * 0.4).rounded(), weight: .semibold, design: type.design)).padding(EdgeInsets(top: 0, leading: 0, bottom: (type.size * 0.16).rounded(), trailing: 0)) }
            }
            if let caption { Text(caption).role(.secondary).typography(.caption) }
        }
        .resolve(in: context)
    }
}

/// A ring with something in the middle: how full, how far, how long left.
/// Pass `timing` for a ring the host fills with the clock.
public struct Gauge: StackbarView {
    var value: Double
    var total: Double
    var timing: TimeRange?
    var theme: Theme
    var size: Double
    var lineWidth: Double
    var label: String?
    var center: ViewContent

    public init(value: Double, total: Double = 1, theme: Theme, size: Double = 64, lineWidth: Double = 6, label: String? = nil, @ViewBuilder center: () -> ViewContent = { [] }) {
        self.value = value
        self.total = total
        self.theme = theme
        self.size = size
        self.lineWidth = lineWidth
        self.label = label
        self.center = center()
    }

    public init(timing: TimeRange, theme: Theme, size: Double = 64, lineWidth: Double = 6, label: String? = nil, @ViewBuilder center: () -> ViewContent = { [] }) {
        self.init(value: 0, theme: theme, size: size, lineWidth: lineWidth, label: label, center: center)
        self.timing = timing
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let ring: any StackbarView = timing.map { ProgressBar(label, timing: $0, style: .ring(lineWidth: lineWidth)) }
            ?? ProgressBar(label, value: min(max(value, 0), total), total: total, style: .ring(lineWidth: lineWidth))
        return ZStack {
            Circle().stroke(.hairline, lineWidth: lineWidth)
            ring.foreground(theme.solidPaint)
            center
        }
        .frame(width: size, height: size)
        .resolve(in: context)
    }
}

/// A labeled bar: what it measures on the left, the reading on the right, and
/// how full underneath.
public struct Meter: StackbarView {
    var label: String
    var reading: String?
    var value: Double
    var total: Double
    var theme: Theme

    public init(_ label: String, reading: String? = nil, value: Double, total: Double = 1, theme: Theme) {
        self.label = label
        self.reading = reading
        self.value = value
        self.total = total
        self.theme = theme
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        VStack(spacing: Space.xs + 1) {
            HStack(spacing: Space.s) {
                Text(label).typography(.caption)
                Spacer(minLength: Space.s)
                if let reading { Text(reading).role(.secondary).typography(.captionNumber) }
            }
            ProgressBar(value: min(max(value, 0), total), total: total).foreground(theme.solidPaint)
        }
        .frame(fillWidth: true)
        .resolve(in: context)
    }
}

/// A span of time as a bar, with stretches of it filled: a day's meetings,
/// or a city's working hours. `segments` and `now` are fractions of the
/// span, 0 to 1. The bar is `width` points wide: 332 fills a panel card.
public struct DayBar: StackbarView {
    var segments: [ClosedRange<Double>]
    var now: Double?
    var theme: Theme
    var width: Double
    var height: Double

    public init(_ segments: [ClosedRange<Double>], now: Double? = nil, theme: Theme, width: Double = 332, height: Double = 8) {
        self.segments = segments
        self.now = now
        self.theme = theme
        self.width = width
        self.height = height
    }

    /// The bar as runs of filled and empty, merged and clamped to 0...1.
    static func runs(_ segments: [ClosedRange<Double>]) -> [(span: ClosedRange<Double>, filled: Bool)] {
        var merged: [ClosedRange<Double>] = []
        for segment in segments.map({ min(1, max(0, $0.lowerBound))...min(1, max(0, $0.upperBound)) }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, segment.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, segment.upperBound)
            } else {
                merged.append(segment)
            }
        }
        var runs: [(span: ClosedRange<Double>, filled: Bool)] = []
        var at = 0.0
        for segment in merged {
            if segment.lowerBound > at { runs.append((at...segment.lowerBound, false)) }
            if segment.upperBound > segment.lowerBound { runs.append((segment, true)) }
            at = segment.upperBound
        }
        if at < 1 { runs.append((at...1, false)) }
        return runs
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let marker = 2.0
        // The now marker takes its width out of whichever run it lands in.
        let cut = now.map { min(max($0, 0), 1) * (width - marker) }
        var pieces: [(width: Double, paint: Paint)] = []
        var x = 0.0
        for run in Self.runs(segments) {
            let runWidth = (run.span.upperBound - run.span.lowerBound) * (width - (cut == nil ? 0 : marker))
            let paint: Paint = run.filled ? theme.solidPaint : .hairline
            if let cut, cut >= x, cut < x + runWidth || (cut == x + runWidth && run.span.upperBound >= 1) {
                pieces.append((cut - x, paint))
                pieces.append((marker, .role(.primary)))
                pieces.append((x + runWidth - cut, paint))
            } else {
                pieces.append((runWidth, paint))
            }
            x += runWidth
        }
        return HStack(spacing: 0) {
            ForEach(Array(pieces.enumerated()).filter { $0.element.width > 0.25 }) { _, piece in
                Rectangle().fill(piece.paint).frame(width: piece.width, height: height)
            }
        }
        .clipShape(.capsule)
        .resolve(in: context)
    }
}

/// A small colored state: "Running", "Checks fail", "Today". Not a button.
public struct Pill: StackbarView {
    var text: String
    var symbol: String?
    var theme: Theme

    public init(_ text: String, symbol: String? = nil, theme: Theme) {
        self.text = text
        self.symbol = symbol
        self.theme = theme
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(size: 9, weight: .bold) }
            Text(text)
        }
        .font(size: 11, weight: .semibold)
        .foreground(theme.textPaint)
        .padding(horizontal: 7, vertical: 2)
        .background(theme.tintPaint, in: .capsule)
        .resolve(in: context)
    }
}

/// A dot of color for a state, beside a title or in a legend.
public struct StatusDot: StackbarView {
    var theme: Theme
    var size: Double

    public init(_ theme: Theme, size: Double = 8) {
        self.theme = theme
        self.size = size
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        Circle().fill(theme.solidPaint).frame(width: size, height: size).resolve(in: context)
    }
}

/// A one-line note on a tinted strip: a problem, a pause, stale numbers.
public struct Banner: StackbarView {
    var message: String
    var symbol: String
    var theme: Theme
    var trailing: ViewContent

    public init(_ message: String, symbol: String = "exclamationmark.triangle.fill", theme: Theme = .warning, @ViewBuilder trailing: () -> ViewContent = { [] }) {
        self.message = message
        self.symbol = symbol
        self.theme = theme
        self.trailing = trailing()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).font(size: 12, weight: .semibold).foreground(theme.textPaint)
            Text(message).typography(.caption).foreground(theme.textPaint)
            Spacer(minLength: 0)
            trailing
        }
        .padding(horizontal: Space.m - 2, vertical: Space.s)
        .frame(fillWidth: true)
        .background(theme.tintPaint, in: .roundedRectangle(cornerRadius: Radius.medium + 2))
        .resolve(in: context)
    }
}

/// What a panel shows when there is nothing to show, or something stands in
/// the way: a tinted symbol, a title, a sentence, and the action that fixes it.
public struct EmptyState: StackbarView {
    var title: String
    var symbol: String
    var message: String?
    var theme: Theme
    var actions: ViewContent

    public init(_ title: String, symbol: String, message: String? = nil, theme: Theme, @ViewBuilder actions: () -> ViewContent = { [] }) {
        self.title = title
        self.symbol = symbol
        self.message = message
        self.theme = theme
        self.actions = actions()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        VStack(alignment: .center, spacing: Space.s) {
            Image(systemName: symbol)
                .font(size: 22, weight: .semibold)
                .foreground(theme.textPaint)
                .frame(width: 52, height: 52)
                .background(theme.tintPaint, in: .circle)
            Text(title).typography(.headline)
            if let message { Text(message).role(.secondary).typography(.caption) }
            if !actions.isEmpty {
                HStack(spacing: Space.s) { actions }.padding(EdgeInsets(top: Space.xs, leading: 0, bottom: 0, trailing: 0))
            }
        }
        .padding(horizontal: Space.l, vertical: Space.xl)
        .frame(fillWidth: true)
        .resolve(in: context)
    }
}

// MARK: - Controls

/// A round button with a symbol. Every one needs a `label` for VoiceOver and
/// the agent.
public struct IconButton: StackbarView {
    public enum Prominence: Sendable {
        /// Just the symbol on a faint circle: secondary actions, toolbars.
        case plain
        /// The hue's wash: a switch that is on.
        case tinted
        /// The hue's fill: the main action.
        case filled
    }

    var symbol: String
    var label: String
    var theme: Theme
    var prominence: Prominence
    var size: Double
    var key: String?
    var action: @MainActor () async throws -> Void

    public init(_ symbol: String, label: String, theme: Theme = .neutral, prominence: Prominence = .plain, size: Double = 28, key: String? = nil, action: @escaping @MainActor () async throws -> Void) {
        self.symbol = symbol
        self.label = label
        self.theme = theme
        self.prominence = prominence
        self.size = size
        self.key = key
        self.action = action
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let fill: Paint, ink: Paint
        switch prominence {
        case .plain: (fill, ink) = (.raised, .role(.primary))
        case .tinted: (fill, ink) = (theme.tintPaint, theme.textPaint)
        case .filled: (fill, ink) = (theme.gradient, theme.onSolidPaint)
        }
        return Button(key: key ?? label, action: action) {
            Image(systemName: symbol)
                .font(size: (size * 0.43).rounded(), weight: .semibold)
                .foreground(ink)
                .frame(width: size, height: size)
                .background(fill, in: .circle)
        }
        .accessibilityLabel(label)
        .resolve(in: context)
    }
}

/// A rounded button with a title: `prominent` fills it with the theme for the
/// one main action, otherwise it sits on a faint layer.
public struct ActionButton: StackbarView {
    var title: String
    var symbol: String?
    var theme: Theme
    var prominent: Bool
    var fillWidth: Bool
    var key: String?
    var action: @MainActor () async throws -> Void

    public init(_ title: String, symbol: String? = nil, theme: Theme = .neutral, prominent: Bool = false, fillWidth: Bool = false, key: String? = nil, action: @escaping @MainActor () async throws -> Void) {
        self.title = title
        self.symbol = symbol
        self.theme = theme
        self.prominent = prominent
        self.fillWidth = fillWidth
        self.key = key
        self.action = action
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        Button(key: key ?? title, action: action) {
            HStack(spacing: Space.xs + 1) {
                if let symbol { Image(systemName: symbol).font(size: 11, weight: .bold) }
                Text(title)
            }
            .font(size: 12, weight: .semibold)
            .foreground(prominent ? theme.onSolidPaint : .role(.primary))
            .padding(horizontal: Space.m, vertical: 6)
            .frame(fillWidth: fillWidth)
            .background(prominent ? theme.gradient : .raised, in: .roundedRectangle(cornerRadius: Radius.medium))
        }
        .resolve(in: context)
    }
}

/// A capsule you click to choose: a filter, a preset, a tag. The selected one
/// fills with the theme.
public struct Chip: StackbarView {
    var title: String
    var symbol: String?
    var theme: Theme
    var selected: Bool
    var key: String?
    var action: @MainActor () async throws -> Void

    public init(_ title: String, symbol: String? = nil, theme: Theme, selected: Bool = false, key: String? = nil, action: @escaping @MainActor () async throws -> Void) {
        self.title = title
        self.symbol = symbol
        self.theme = theme
        self.selected = selected
        self.key = key
        self.action = action
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        Button(key: key ?? title, action: action) {
            HStack(spacing: Space.xs) {
                if let symbol { Image(systemName: symbol).font(size: 10, weight: .bold) }
                Text(title)
            }
            .font(size: 12, weight: selected ? .semibold : .medium)
            .foreground(selected ? theme.onSolidPaint : .role(.primary))
            .padding(horizontal: Space.s + 2, vertical: Space.xs + 1)
            .background(selected ? theme.solidPaint : theme.tintPaint, in: .capsule)
        }
        .resolve(in: context)
    }
}
