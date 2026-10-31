import StackbarProtocol

/// What every surface does with every node: the parity ledger.
///
/// Each renderer (panel, window, menu bar, widget, palette, agent) makes its
/// own choices, and those choices drift unless they are written down in one
/// place. This is that place. The switches have no `default`, so adding a node
/// to `ViewNode` will not compile until each surface's treatment is decided
/// here; `docs/surface-parity.md` is generated from it and a test fails when
/// the two disagree.
public enum SurfaceParity {
    /// The surfaces the ledger covers: the plugin surfaces plus the two the
    /// host derives (the palette from panel rows, the agent from text).
    public enum Column: String, CaseIterable, Sendable {
        case panel, window, settings, menuBar, widget, palette, agent

        var title: String {
            switch self {
            case .panel: return "Panel"
            case .window: return "Window"
            case .settings: return "Settings"
            case .menuBar: return "Menu bar"
            case .widget: return "Widget"
            case .palette: return "Palette"
            case .agent: return "Agent (text)"
            }
        }
    }

    /// One name per `ViewNode` case.
    public enum Kind: String, CaseIterable, Sendable {
        case text, label, stack, list, section, row, badge, button, toggle, progress, divider
        case labeled, chart, textField, picker, slider, link, empty

        public init(_ node: ViewNode) {
            switch node {
            case .text: self = .text
            case .label: self = .label
            case .stack: self = .stack
            case .list: self = .list
            case .section: self = .section
            case .row: self = .row
            case .badge: self = .badge
            case .button: self = .button
            case .toggle: self = .toggle
            case .progress: self = .progress
            case .divider: self = .divider
            case .labeled: self = .labeled
            case .chart: self = .chart
            case .textField: self = .textField
            case .picker: self = .picker
            case .slider: self = .slider
            case .link: self = .link
            case .empty: self = .empty
            }
        }
    }

    public static func treatment(_ kind: Kind, on column: Column) -> String {
        switch column {
        case .panel, .window, .settings: return panel(kind)
        case .menuBar: return menuBar(kind)
        case .widget: return widget(kind)
        case .palette: return palette(kind)
        case .agent: return agent(kind)
        }
    }

    private static func panel(_ kind: Kind) -> String {
        switch kind {
        case .text: return "Text with style and role"
        case .label: return "Label with SF Symbol"
        case .stack: return "VStack / HStack"
        case .list: return "List; filter field when searchable"
        case .section: return "Captioned group"
        case .row: return "Row; click = first action, context menu = all"
        case .badge: return "Capsule"
        case .button: return "Button"
        case .toggle: return "Toggle"
        case .progress: return "ProgressView"
        case .divider: return "Divider"
        case .labeled: return "LabeledContent"
        case .chart: return "Swift Charts line or bar"
        case .textField: return "TextField; return submits"
        case .picker: return "Picker"
        case .slider: return "Slider; sends on release"
        case .link: return "Link; host opens it"
        case .empty: return "ContentUnavailableView"
        }
    }

    private static func menuBar(_ kind: Kind) -> String {
        switch kind {
        case .text: return "Inline text"
        case .label: return "Symbol and title"
        case .stack: return "Children on one line"
        case .list, .section, .row: return "Hidden (panel only)"
        case .badge: return "Small capsule"
        case .button, .toggle, .textField, .picker, .slider, .link: return "Hidden (click opens the panel)"
        case .progress: return "12 pt ring"
        case .divider: return "Hidden"
        case .labeled: return "Label and value"
        case .chart: return "32 pt sparkline"
        case .empty: return "Symbol and title"
        }
    }

    private static func widget(_ kind: Kind) -> String {
        switch kind {
        case .list: return "First 4 rows, no filter"
        case .row: return "Row, not clickable"
        case .button, .toggle, .textField, .picker, .slider: return "Drawn disabled"
        case .link: return "Link (opens Stackbar's URL)"
        case .text, .label, .stack, .section, .badge, .progress, .divider, .labeled, .chart, .empty: return "As panel"
        }
    }

    private static func palette(_ kind: Kind) -> String {
        switch kind {
        case .row: return "Entry per action, searchable by title and subtitle"
        case .button: return "Entry, runs the button"
        case .toggle: return "Entry, flips the toggle"
        case .link: return "Entry, opens the URL"
        case .list, .section, .stack: return "Searched through"
        case .text, .label, .badge, .progress, .divider, .labeled, .chart, .textField, .picker, .slider, .empty: return "Not listed"
        }
    }

    private static func agent(_ kind: Kind) -> String {
        switch kind {
        case .text: return "Line (`# ` for titles)"
        case .label: return "`[symbol] title`"
        case .stack: return "Lines, or one line when horizontal"
        case .list: return "`List` then indented rows"
        case .section: return "`-- title --`"
        case .row: return "`* title - subtitle <actions {ids}>`"
        case .badge: return "`[text]`"
        case .button: return "`(title) {id}`"
        case .toggle: return "`[x] title {id}`"
        case .progress: return "`[####......] 40%`"
        case .divider: return "`----`"
        case .labeled: return "`label: value`"
        case .chart: return "Block sparkline"
        case .textField: return "`[text____] {id}`"
        case .picker: return "`title: a | *b* {id}`"
        case .slider: return "`title: v (min...max) {id}`"
        case .link: return "`<title> url`"
        case .empty: return "`[symbol] title - message`"
        }
    }

    /// The Markdown table in `docs/surface-parity.md`.
    public static func ledger() -> String {
        let columns = Column.allCases
        var lines = [
            "| Node | " + columns.map(\.title).joined(separator: " | ") + " |",
            "| --- | " + columns.map { _ in "---" }.joined(separator: " | ") + " |",
        ]
        for kind in Kind.allCases {
            lines.append("| `\(kind.rawValue)` | " + columns.map { treatment(kind, on: $0) }.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}
