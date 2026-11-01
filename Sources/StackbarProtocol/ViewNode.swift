/// The declarative UI a plugin hands the host.
///
/// A plugin never draws. It describes what it wants as a tree of `ViewNode`s and
/// the host renders that tree natively on each surface — the menu bar, the
/// panel, and later windows, widgets and the agent gateway. The vocabulary is
/// deliberately small (under twenty nodes): small enough to keep every surface
/// in parity (see `SurfaceParity` in StackbarHostCore and docs/surface-parity.md),
/// and named after SwiftUI so an AI already knows it.
///
/// Nodes carry *meaning* (a `Role`, a `TextStyle`) by default, so the host
/// picks colors, fonts and spacing for light and dark mode on every surface.
/// Since protocol 11 a plugin can also take over the look: `styled` sets
/// fonts, colors, padding, frames, backgrounds and more; `shape`, `image`,
/// `timer` and `tappable` build custom controls.
public indirect enum ViewNode: Codable, Equatable, Sendable {
    case text(String, style: TextStyle = .body, role: Role = .primary)
    case label(String, symbol: String, role: Role = .primary)
    /// `alignment` lines children up across the axis (protocol 11); `nil`
    /// keeps leading for vertical stacks and center otherwise.
    case stack(axis: StackAxis, spacing: Double? = nil, alignment: StackAlignment? = nil, children: [ViewNode])
    /// A scrolling list of rows. `searchable` asks the host for a filter field
    /// that narrows rows by title and subtitle.
    case list(searchable: Bool = false, children: [ViewNode])
    case section(title: String?, children: [ViewNode])
    case row(RowNode)
    case badge(String, role: Role = .secondary)
    case button(title: String, symbol: String? = nil, role: Role = .primary, action: ActionID)
    case toggle(title: String, isOn: Bool, action: ActionID)
    /// A determinate gauge; `value` is clamped to `0...total` by renderers.
    /// With `timing` (protocol 11) the host computes the value from the clock
    /// and animates it; `style` draws a ring in place of a bar.
    case progress(value: Double, total: Double = 1, label: String? = nil, role: Role = .accent, style: ProgressStyle? = nil, timing: TimeRange? = nil)
    case divider
    /// A label and its value on one line, like SwiftUI's `LabeledContent`.
    case labeled(label: String, value: String, role: Role = .primary)
    /// A chart of a series: a sparkline in the menu bar, a chart in panels.
    /// `options` names the points, gives a unit and a goal line.
    case chart(values: [Double], kind: ChartKind = .line, label: String? = nil, role: Role = .accent, options: ChartOptions? = nil)
    /// A one-line text input. Submitting sends `.text` with the field's contents.
    case textField(placeholder: String, text: String, action: ActionID)
    /// A choice among a few options. Choosing sends `.text` with the option.
    case picker(title: String, options: [String], selection: String?, style: ChoiceStyle? = nil, action: ActionID)
    /// A continuous value. Releasing sends `.number`.
    case slider(title: String, value: Double, min: Double, max: Double, step: Double? = nil, action: ActionID)
    /// Opens a URL. The host opens it; the plugin never hears about the click.
    case link(title: String, url: String)
    /// What to show when there is nothing to show, like `ContentUnavailableView`.
    case empty(title: String, symbol: String? = nil, message: String? = nil)
    /// Several fields submitted together. Submitting sends `.fields` with
    /// every field's value by name.
    case form(FormNode)
    /// The child drawn with a `Style`: fonts, colors, padding, frame,
    /// background, border, clip, shadow, opacity. Protocol 11.
    case styled(ViewNode, style: Style)
    /// A filled or stroked shape. Protocol 11.
    case shape(ShapeNode)
    /// An image, sized by the font and colored by the foreground. Protocol 11.
    case image(ImageSource)
    /// Live clock text the host counts through `range` on its own: down to
    /// `0:00`, or up from it. Protocol 11.
    case timer(TimeRange, countsDown: Bool = true)
    /// Flexible space along the enclosing stack's axis. Protocol 11.
    case spacer(minLength: Double? = nil)
    /// Any content as a button: a click sends `action`. Protocol 11.
    case tappable(ViewNode, action: ActionID)
}

/// A form: fields, a submit button and the action it sends.
public struct FormNode: Codable, Equatable, Sendable {
    public var fields: [FormField]
    public var submitTitle: String
    public var action: ActionID

    public init(fields: [FormField], submitTitle: String = "Save", action: ActionID) {
        self.fields = fields
        self.submitTitle = submitTitle
        self.action = action
    }
}

/// One field of a form.
public struct FormField: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        /// One line of text.
        case text(placeholder: String?)
        /// Several lines of text, like a snippet's body.
        case multiline(placeholder: String?)
        /// An installed app, picked by the host; the value is its bundle id.
        case application
        /// One of a few options.
        case picker(options: [String])
        case toggle
    }

    /// The key of the field's value in the submitted `.fields`.
    public var name: String
    public var label: String
    public var kind: Kind
    /// The value the field starts with: `.text` for text, app and picker
    /// fields, `.bool` for a toggle.
    public var value: EventValue?
    /// A problem the plugin found on the last submit, shown under the field.
    public var error: String?

    public init(name: String, label: String, kind: Kind, value: EventValue? = nil, error: String? = nil) {
        self.name = name
        self.label = label
        self.kind = kind
        self.value = value
        self.error = error
    }
}

public enum ChartKind: String, Codable, Sendable, CaseIterable {
    case line, bar
    /// A line with the area under it filled.
    case area
    /// Shares of a whole, one slice per value, named by `ChartOptions.labels`.
    case donut
    /// One square per day, oldest first, in week columns like a contribution
    /// graph; darker is more. `labels` name the days ("2026-10-31") and the
    /// last value is today. Stackbar 0.11.0 and later.
    case heatmap
}

/// What a chart's points mean, so the host can label them.
public struct ChartOptions: Codable, Equatable, Sendable {
    /// One per value: x-axis labels ("Mon"), or slice names for a donut.
    public var labels: [String]?
    /// Appended to values on the axis and in the summary ("h", "%").
    public var unit: String?
    /// A dashed rule at this value, like a daily target.
    public var goal: Double?
    /// Index of the point to emphasize, like today in a week.
    public var highlight: Int?

    public init(labels: [String]? = nil, unit: String? = nil, goal: Double? = nil, highlight: Int? = nil) {
        self.labels = labels
        self.unit = unit
        self.goal = goal
        self.highlight = highlight
    }
}

/// One entry in a list: the workhorse of most plugin panels.
public struct RowNode: Codable, Equatable, Sendable {
    /// Stable identity across renders. Action ids are derived from it, so an
    /// event that arrives after a re-render still reaches the right row.
    public var key: String
    public var title: String
    public var subtitle: String?
    public var symbol: String?
    /// An app's bundle id: the host draws that app's icon in place of the
    /// symbol, and the symbol where it can't (the app isn't installed).
    public var appIcon: String?
    /// Small trailing graphics: badges and progress gauges.
    public var accessories: [ViewNode]
    /// The first action is the row's primary action (a click); the rest are
    /// secondary (a context menu).
    public var actions: [ActionRef]
    /// What the host shows for the selected row in a searchable list: the
    /// full text, an image the host keeps, or both.
    public var preview: RowPreview?

    public init(key: String, title: String, subtitle: String? = nil, symbol: String? = nil, appIcon: String? = nil, accessories: [ViewNode] = [], actions: [ActionRef] = [], preview: RowPreview? = nil) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.appIcon = appIcon
        self.accessories = accessories
        self.actions = actions
        self.preview = preview
    }
}

/// A row's preview. `text` is cut to 10,000 characters by the plugin kit;
/// `imageID` is a `ClipboardItem.imageID` the host still keeps.
public struct RowPreview: Codable, Equatable, Sendable {
    public var text: String?
    public var imageID: String?
    /// Lines under the preview, like "1,204 characters · copied 3 times".
    public var caption: String?

    public init(text: String? = nil, imageID: String? = nil, caption: String? = nil) {
        self.text = text
        self.imageID = imageID
        self.caption = caption
    }
}

/// A user-facing action attached to a row.
public struct ActionRef: Codable, Equatable, Sendable {
    public var id: ActionID
    public var title: String
    /// A key-equivalent spelled like Vee's `key=`: `cmd+return`, `cmd+shift+k`.
    public var shortcut: String?
    public var role: Role
    /// When set, the host opens this command itself instead of sending the
    /// action: the palette pushes it as a new view.
    public var navigate: CommandTarget?

    public init(id: ActionID, title: String, shortcut: String? = nil, role: Role = .primary, navigate: CommandTarget? = nil) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.role = role
        self.navigate = navigate
    }
}

/// Names a closure inside the plugin process. The host sends it back in an
/// `event` message; it means nothing to the host itself.
public struct ActionID: Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// What a piece of content *means*; the host maps it to a color per surface.
public enum Role: String, Codable, Sendable, CaseIterable {
    case primary, secondary, accent, success, warning, critical
}

public enum TextStyle: String, Codable, Sendable, CaseIterable {
    case title, headline, body, caption, monospaced
}

public enum StackAxis: String, Codable, Sendable {
    case vertical, horizontal
    /// Children layered front to back, like SwiftUI's `ZStack`. Protocol 11.
    case depth
}

/// Where a plugin can appear.
///
/// The command palette and the agent gateway are not surfaces a plugin draws
/// for: they reuse the panel's rows and the plugin's tools.
public enum Surface: String, Codable, Sendable, CaseIterable {
    /// The status item: compact, one line.
    case menuBar
    /// The popover under the status item.
    case panel
    /// A resizable window, for plugins that need room.
    case window
    /// A desktop or Notification Center widget: read-only, refreshed by the host.
    case widget
    /// The plugin's page in Stackbar's Settings window: preferences people set
    /// once, kept out of the panel so it stays about doing things. The host
    /// draws it as a grouped form and puts a gear in the panel's footer.
    case settings
}

extension ViewNode {
    /// The nodes this one contains, in order: a container's children, or the
    /// child of a `styled` or `tappable` node. A row's accessories are part
    /// of the row, not children.
    public var children: [ViewNode] {
        switch self {
        case .stack(_, _, _, let children), .list(_, let children), .section(_, let children):
            return children
        case .styled(let child, _), .tappable(let child, _):
            return [child]
        case .text, .label, .row, .badge, .button, .toggle, .progress, .divider, .labeled, .chart, .textField, .picker, .slider, .link, .empty, .form, .shape, .image, .timer, .spacer:
            return []
        }
    }

    /// Rows anywhere below this node, in order. Hosts use it for list filtering;
    /// tests use it to find things without spelling out the whole tree.
    public var rows: [RowNode] {
        if case .row(let row) = self { return [row] }
        return children.flatMap(\.rows)
    }

    /// Every action id this tree can send, in order: its `affordances`
    /// without links. The agent gateway checks events against it.
    public var actions: [ActionID] {
        affordances.compactMap(\.action)
    }

    /// The words this tree shows, joined by spaces: what names a `tappable`
    /// in the palette and the agent text. An accessibility label stands in
    /// for its child.
    public var plainText: String {
        switch self {
        case .text(let string, _, _), .badge(let string, _):
            return string
        case .label(let title, _, _), .button(let title, _, _, _):
            return title
        case .styled(_, let style) where style.accessibilityLabel != nil:
            return style.accessibilityLabel ?? ""
        default:
            return children.map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    /// How many nodes the tree has and how deep it goes, counting row
    /// accessories. The host refuses renders past `RenderLimits`.
    public var size: (count: Int, depth: Int) {
        let inner = (children + accessories).map(\.size)
        return (1 + inner.reduce(0) { $0 + $1.count }, 1 + (inner.map(\.depth).max() ?? 0))
    }

    private var accessories: [ViewNode] {
        if case .row(let row) = self { return row.accessories }
        return []
    }
}

/// The largest tree a plugin may render, so a runaway render can't stall the
/// host's UI.
public enum RenderLimits {
    public static let maxNodes = 5_000
    public static let maxDepth = 64

    /// Why `node` is over the limits, or `nil` when it is within them.
    public static func violation(_ node: ViewNode) -> String? {
        let size = node.size
        if size.count > maxNodes { return "the view has \(size.count) nodes; at most \(maxNodes) are allowed" }
        if size.depth > maxDepth { return "the view is \(size.depth) levels deep; at most \(maxDepth) are allowed" }
        return nil
    }
}
