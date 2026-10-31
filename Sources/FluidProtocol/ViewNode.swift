/// The declarative UI a plugin hands the host.
///
/// A plugin never draws. It describes what it wants as a tree of `ViewNode`s and
/// the host renders that tree natively on each surface — the menu bar, the
/// panel, and later windows, widgets and the agent gateway. The vocabulary is
/// deliberately small (under twenty nodes): small enough to keep every surface
/// in parity (see `SurfaceParity` in FluidHostCore and docs/surface-parity.md),
/// and named after SwiftUI so an AI already knows it.
///
/// Every node carries *meaning* (a `Role`, a `TextStyle`), never pixels, so the
/// host decides colors, fonts and spacing for light and dark mode on every
/// surface.
public indirect enum ViewNode: Codable, Equatable, Sendable {
    case text(String, style: TextStyle = .body, role: Role = .primary)
    case label(String, symbol: String, role: Role = .primary)
    case stack(axis: StackAxis, spacing: Double? = nil, children: [ViewNode])
    /// A scrolling list of rows. `searchable` asks the host for a filter field
    /// that narrows rows by title and subtitle.
    case list(searchable: Bool = false, children: [ViewNode])
    case section(title: String?, children: [ViewNode])
    case row(RowNode)
    case badge(String, role: Role = .secondary)
    case button(title: String, symbol: String? = nil, role: Role = .primary, action: ActionID)
    case toggle(title: String, isOn: Bool, action: ActionID)
    /// A determinate gauge; `value` is clamped to `0...total` by renderers.
    case progress(value: Double, total: Double = 1, label: String? = nil, role: Role = .accent)
    case divider
    /// A label and its value on one line, like SwiftUI's `LabeledContent`.
    case labeled(label: String, value: String, role: Role = .primary)
    /// A small chart of a series: a sparkline in the menu bar, a chart in panels.
    case chart(values: [Double], kind: ChartKind = .line, label: String? = nil, role: Role = .accent)
    /// A one-line text input. Submitting sends `.text` with the field's contents.
    case textField(placeholder: String, text: String, action: ActionID)
    /// A choice among a few options. Choosing sends `.text` with the option.
    case picker(title: String, options: [String], selection: String?, action: ActionID)
    /// A continuous value. Releasing sends `.number`.
    case slider(title: String, value: Double, min: Double, max: Double, step: Double? = nil, action: ActionID)
    /// Opens a URL. The host opens it; the plugin never hears about the click.
    case link(title: String, url: String)
    /// What to show when there is nothing to show, like `ContentUnavailableView`.
    case empty(title: String, symbol: String? = nil, message: String? = nil)
}

public enum ChartKind: String, Codable, Sendable, CaseIterable {
    case line, bar
}

/// One entry in a list: the workhorse of most plugin panels.
public struct RowNode: Codable, Equatable, Sendable {
    /// Stable identity across renders. Action ids are derived from it, so an
    /// event that arrives after a re-render still reaches the right row.
    public var key: String
    public var title: String
    public var subtitle: String?
    public var symbol: String?
    /// Small trailing graphics: badges and progress gauges.
    public var accessories: [ViewNode]
    /// The first action is the row's primary action (a click); the rest are
    /// secondary (a context menu).
    public var actions: [ActionRef]

    public init(key: String, title: String, subtitle: String? = nil, symbol: String? = nil, accessories: [ViewNode] = [], actions: [ActionRef] = []) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accessories = accessories
        self.actions = actions
    }
}

/// A user-facing action attached to a row.
public struct ActionRef: Codable, Equatable, Sendable {
    public var id: ActionID
    public var title: String
    /// A key-equivalent spelled like Vee's `key=`: `cmd+return`, `cmd+shift+k`.
    public var shortcut: String?
    public var role: Role

    public init(id: ActionID, title: String, shortcut: String? = nil, role: Role = .primary) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.role = role
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
}

extension ViewNode {
    /// Rows anywhere below this node, in order. Hosts use it for list filtering;
    /// tests use it to find things without spelling out the whole tree.
    public var rows: [RowNode] {
        switch self {
        case .row(let row):
            return [row]
        case .stack(_, _, let children), .list(_, let children), .section(_, let children):
            return children.flatMap(\.rows)
        default:
            return []
        }
    }
}

extension ViewNode {
    /// Every action id this tree can send, in order. The palette and the agent
    /// gateway use it to list what can be pressed.
    public var actions: [ActionID] {
        switch self {
        case .row(let row):
            return row.actions.map(\.id)
        case .button(_, _, _, let action), .toggle(_, _, let action), .textField(_, _, let action), .picker(_, _, _, let action), .slider(_, _, _, _, _, let action):
            return [action]
        case .stack(_, _, let children), .list(_, let children), .section(_, let children):
            return children.flatMap(\.actions)
        case .text, .label, .badge, .progress, .divider, .labeled, .chart, .link, .empty:
            return []
        }
    }
}
