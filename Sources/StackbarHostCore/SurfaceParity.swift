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
    /// The surfaces the ledger covers: the plugin surfaces, a command's view
    /// in the palette, plus the two the host derives (the palette from panel
    /// rows, the agent from text).
    public enum Column: String, CaseIterable, Sendable {
        case panel, window, settings, menuBar, widget, command, palette, agent

        var title: String {
            switch self {
            case .panel: return "Panel"
            case .window: return "Window"
            case .settings: return "Settings"
            case .menuBar: return "Menu bar"
            case .widget: return "Widget"
            case .command: return "Command view"
            case .palette: return "Palette"
            case .agent: return "Agent (text)"
            }
        }
    }

    /// One name per `ViewNode` case.
    public enum Kind: String, CaseIterable, Sendable {
        case text, label, stack, list, section, row, badge, button, toggle, progress, divider
        case labeled, chart, textField, picker, slider, link, empty, form
        case styled, shape, image, timer, spacer, tappable, grid

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
            case .form: self = .form
            case .styled: self = .styled
            case .shape: self = .shape
            case .image: self = .image
            case .timer: self = .timer
            case .spacer: self = .spacer
            case .tappable: self = .tappable
            case .grid: self = .grid
            }
        }
    }

    public static func treatment(_ kind: Kind, on column: Column) -> String {
        switch column {
        case .panel, .window, .settings: return panel(kind)
        case .menuBar: return menuBar(kind)
        case .widget: return widget(kind)
        case .command: return command(kind)
        case .palette: return palette(kind)
        case .agent: return agent(kind)
        }
    }

    private static func panel(_ kind: Kind) -> String {
        switch kind {
        case .text: return "Text with style and role"
        case .label: return "Label with SF Symbol"
        case .stack: return "VStack / HStack / ZStack, aligned"
        case .list: return "List; filter field when searchable"
        case .section: return "Captioned group"
        case .row: return "Row with app icon or symbol; click = first action, context menu = all"
        case .badge: return "Capsule"
        case .button: return "Button"
        case .toggle: return "Toggle"
        case .progress: return "Bar or ring; a timed range animates on its own"
        case .divider: return "Divider"
        case .labeled: return "LabeledContent"
        case .chart: return "Swift Charts line, bar, area or donut, with labels, unit and goal; a day heatmap"
        case .textField: return "TextField; return submits"
        case .picker: return "Picker; segmented when asked"
        case .slider: return "Slider; sends on release"
        case .link: return "Link; host opens it"
        case .empty: return "ContentUnavailableView"
        case .form: return "Form; submit sends every field"
        case .styled: return "Child with font, colors, gradients and glass, padding, frame, background, border, clip, shadow, blur, opacity, symbol effects, rolling numbers, hover, animation"
        case .shape: return "Filled or stroked shape"
        case .image: return "SF Symbol sized by the font; a remote image fills its frame"
        case .timer: return "Live timer text the host counts"
        case .spacer: return "Spacer"
        case .tappable: return "Content as a plain button; click sends the action"
        case .grid: return "Equal-width columns, filled left to right"
        }
    }

    private static func command(_ kind: Kind) -> String {
        switch kind {
        case .list: return "List filtered by the plugin as the user types"
        case .row: return "Row; Return = first action, ⌘K = all, navigate pushes"
        case .text, .label, .stack, .section, .badge, .button, .toggle, .progress, .divider, .labeled, .chart, .textField, .picker, .slider, .link, .empty, .form,
             .styled, .shape, .image, .timer, .spacer, .tappable, .grid:
            return "As panel"
        }
    }

    private static func menuBar(_ kind: Kind) -> String {
        switch kind {
        case .text: return "Inline text"
        case .label: return "Symbol and title"
        case .stack: return "Children on one line; layered when depth"
        case .list, .section, .row, .grid: return "Hidden (panel only)"
        case .badge: return "Small capsule"
        case .button, .toggle, .textField, .picker, .slider, .link, .form, .tappable: return "Hidden (click opens the panel)"
        case .progress: return "12 pt ring, timed ones animate"
        case .divider, .shape, .spacer: return "Hidden"
        case .styled: return "Child; colors and decoration ignored so the bar stays legible"
        case .image: return "Symbol; a remote image is hidden"
        case .timer: return "Live timer text"
        case .labeled: return "Label and value"
        case .chart: return "32 pt sparkline"
        case .empty: return "Symbol and title"
        }
    }

    private static func widget(_ kind: Kind) -> String {
        switch kind {
        case .list: return "First 4 rows, no filter"
        case .row: return "Row, not clickable"
        case .button, .toggle, .textField, .picker, .slider, .form: return "Drawn disabled"
        case .tappable: return "Drawn, not clickable"
        case .link: return "Link (opens Stackbar's URL)"
        case .text, .label, .stack, .section, .badge, .progress, .divider, .labeled, .chart, .empty, .shape, .timer, .spacer, .grid: return "As panel"
        case .styled: return "As panel, without hover"
        case .image: return "Symbol; a remote image shows its placeholder"
        }
    }

    private static func palette(_ kind: Kind) -> String {
        switch kind {
        case .row: return "Entry per action, searchable by title and subtitle"
        case .button: return "Entry, runs the button"
        case .toggle: return "Entry, flips the toggle"
        case .link: return "Entry, opens the URL"
        case .tappable: return "Entry named by its text"
        case .list, .section, .stack, .styled, .grid: return "Searched through"
        case .text, .label, .badge, .progress, .divider, .labeled, .chart, .textField, .picker, .slider, .empty, .form, .shape, .image, .timer, .spacer: return "Not listed"
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
        case .chart: return "Block sparkline; donut as named values"
        case .textField: return "`[text____] {id}`"
        case .picker: return "`title: a | *b* {id}`"
        case .slider: return "`title: v (min...max) {id}`"
        case .link: return "`<title> url`"
        case .empty: return "`[symbol] title - message`"
        case .form: return "`Form` then `label: [value____]` lines and `(submit) {id}`"
        case .styled: return "Child, or its accessibility label with the child's action ids"
        case .shape, .spacer: return "Nothing"
        case .image: return "`[symbol]`, or `[image]` for a remote one"
        case .timer: return "`12:34` as of now"
        case .tappable: return "`(text) {id}`"
        case .grid: return "Lines, one per cell"
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
