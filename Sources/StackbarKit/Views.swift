// The StackbarKit view vocabulary. Each view maps one-to-one onto a `ViewNode`;
// the names and modifiers follow SwiftUI wherever the meaning is the same.

public struct Text: StackbarView {
    var string: String
    var textStyle: TextStyle = .body
    var textRole: Role = .primary

    public init(_ string: String) { self.string = string }

    public func style(_ style: TextStyle) -> Text { var copy = self; copy.textStyle = style; return copy }
    public func role(_ role: Role) -> Text { var copy = self; copy.textRole = role; return copy }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.text(string, style: textStyle, role: textRole)]
    }
}

/// A title with an SF Symbol — the usual menu-bar content.
public struct Label: StackbarView {
    var title: String
    var symbol: String
    var labelRole: Role = .primary

    public init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    public func role(_ role: Role) -> Label { var copy = self; copy.labelRole = role; return copy }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.label(title, symbol: symbol, role: labelRole)]
    }
}

/// What VStack, HStack and ZStack share: they differ only in their axis.
@MainActor
protocol AxisStack: StackbarView {
    static var axis: StackAxis { get }
    var alignment: StackAlignment? { get }
    var spacing: Double? { get }
    var content: ViewContent { get }
}

extension AxisStack {
    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.stack(axis: Self.axis, spacing: spacing, alignment: alignment, children: content.resolve(in: context))]
    }
}

/// Children top to bottom, leading-aligned unless `alignment` says otherwise.
public struct VStack: AxisStack {
    static let axis = StackAxis.vertical
    var alignment: StackAlignment?
    var spacing: Double?
    var content: ViewContent

    public init(alignment: StackAlignment? = nil, spacing: Double? = nil, @ViewBuilder content: () -> ViewContent) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
}

/// Children left to right, vertically centered unless `alignment` says otherwise.
public struct HStack: AxisStack {
    static let axis = StackAxis.horizontal
    var alignment: StackAlignment?
    var spacing: Double?
    var content: ViewContent

    public init(alignment: StackAlignment? = nil, spacing: Double? = nil, @ViewBuilder content: () -> ViewContent) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
}

/// Children layered back to front, centered: a ring behind a button.
public struct ZStack: AxisStack {
    static let axis = StackAxis.depth
    var alignment: StackAlignment?
    let spacing: Double? = nil
    var content: ViewContent

    public init(alignment: StackAlignment? = nil, @ViewBuilder content: () -> ViewContent) {
        self.alignment = alignment
        self.content = content()
    }
}

public struct List: StackbarView {
    var searchable: Bool
    var content: ViewContent

    public init(searchable: Bool = false, @ViewBuilder content: () -> ViewContent) {
        self.searchable = searchable
        self.content = content()
    }

    /// One row per element: `List(prs, searchable: true) { pr in Row(pr.title) }`.
    public init<Data: Sequence>(_ data: Data, searchable: Bool = false, @ViewBuilder row: (Data.Element) -> ViewContent) {
        self.searchable = searchable
        self.content = data.flatMap(row)
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.list(searchable: searchable, children: content.resolve(in: context))]
    }
}

public struct Section: StackbarView {
    var title: String?
    var content: ViewContent

    public init(_ title: String? = nil, @ViewBuilder content: () -> ViewContent) {
        self.title = title
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.section(title: title, children: content.resolve(in: context))]
    }
}

/// Repeats content for each element, inside a stack or section.
public struct ForEach: StackbarView {
    var content: ViewContent

    public init<Data: Sequence>(_ data: Data, @ViewBuilder content: (Data.Element) -> ViewContent) {
        self.content = data.flatMap(content)
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        content.resolve(in: context)
    }
}

/// A list entry with trailing accessories and actions.
public struct Row: StackbarView {
    var key: String
    var title: String
    var subtitle: String?
    var symbol: String?
    var appIcon: String?
    var fileIcon: String?
    var accessories: [ViewNode] = []
    var actions: [(title: String, shortcut: String?, role: Role, handler: RenderContext.Handler?, navigate: CommandTarget?, confirm: String?)] = []
    var preview: RowPreview?
    var previewView: ViewContent?
    var hiddenFromPalette: Bool?

    /// `key` defaults to the title; give one explicitly when titles can repeat
    /// or change (an id from your data is ideal).
    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil, key: String? = nil) {
        self.key = key ?? title
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    /// Shows the icon of the app with this bundle id instead of the symbol
    /// (the symbol stays as the fallback when the app isn't installed).
    public func appIcon(_ bundleID: String?) -> Row {
        var copy = self
        copy.appIcon = bundleID
        return copy
    }

    /// Shows a file or folder's Finder icon instead of the symbol: a path
    /// from `Stackbar.findFiles`. Protocol 16.
    public func fileIcon(_ path: String?) -> Row {
        var copy = self
        copy.fileIcon = path
        return copy
    }

    /// Keeps this row out of the command palette's own results. It still
    /// shows and acts in your panel. For rows of your data (history, items)
    /// that would flood the palette; a root-search command is the way to
    /// offer them there. Protocol 22.
    public func hiddenFromPalette(_ hidden: Bool = true) -> Row {
        var copy = self
        copy.hiddenFromPalette = hidden ? true : nil
        return copy
    }

    public func badge(_ text: String, role: Role = .secondary) -> Row {
        var copy = self
        copy.accessories.append(.badge(text, role: role))
        return copy
    }

    public func progress(_ value: Double, total: Double = 1, role: Role = .accent) -> Row {
        var copy = self
        copy.accessories.append(.progress(value: value, total: total, label: nil, role: role))
        return copy
    }

    /// What the host shows under a searchable list while this row is
    /// selected: the full text (cut to 10,000 characters), a kept clipboard
    /// image, and a caption. Search also looks through the text.
    public func preview(text: String? = nil, imageID: String? = nil, caption: String? = nil) -> Row {
        var copy = self
        copy.preview = RowPreview(text: text.map { String($0.prefix(10_000)) }, imageID: imageID, caption: caption)
        return copy
    }

    /// A view in the preview pane while this row is selected (protocol 29):
    /// a check list, a release chain, a color swatch. Start from
    /// `PreviewDetail`. The host draws it display-only, so it shows things
    /// and the row's actions and ⌘K do things: controls in it are drawn
    /// disabled. Keep it under `RowPreview.maxViewNodes` (150) nodes, since
    /// every row sends its preview with each render; a larger one is dropped
    /// with a warning. `text` is still what search matches and what hosts
    /// older than 0.38 show, so give it the same facts in words.
    public func preview(text: String?, caption: String? = nil, @ViewBuilder view: () -> ViewContent) -> Row {
        var copy = preview(text: text, caption: caption)
        copy.previewView = view()
        return copy
    }

    /// Adds an action. The first one is what a click on the row does.
    ///
    /// `confirm` makes the host ask for a second press first, and says what
    /// the action does as the end of "Press again within 10 s to …":
    /// `confirm: "stop \(name) (pid \(pid))"`. Give it to anything that
    /// loses work or data. Protocol 25; on older hosts the kit asks itself.
    public func action(_ title: String, shortcut: String? = nil, role: Role = .primary, confirm: Confirm = .none, perform: @escaping @MainActor () async throws -> Void) -> Row {
        var copy = self
        copy.actions.append((title, shortcut, role, { _ in try await perform() }, nil, confirm.text))
        return copy
    }

    /// Adds an action that opens another of this plugin's commands, with
    /// arguments. The host opens it without calling the plugin: in the
    /// palette it is pushed as a new view (Esc comes back).
    public func navigate(_ title: String, to command: String, arguments: [String: String] = [:], shortcut: String? = nil) -> Row {
        var copy = self
        copy.actions.append((title, shortcut, .primary, nil, CommandTarget(command: command, arguments: arguments), nil))
        return copy
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let refs = actions.map { action in
            let base = "row/\(key)/\(action.title)"
            let id = action.handler.map { context.register(base, confirm: action.confirm, $0) } ?? ActionID(context.prefix + base)
            return ActionRef(id: id, title: action.title, shortcut: action.shortcut, role: action.role, navigate: action.navigate, confirm: action.confirm)
        }
        return [.row(RowNode(key: key, title: title, subtitle: subtitle, symbol: symbol, appIcon: appIcon, fileIcon: fileIcon, accessories: accessories, actions: refs, preview: resolvedPreview(in: context), hiddenFromPalette: hiddenFromPalette))]
    }

    /// The preview with its view resolved, on hosts that draw one and while
    /// it fits the budget.
    private func resolvedPreview(in context: RenderContext) -> RowPreview? {
        guard var preview, let previewView, (Stackbar.hostProtocol ?? StackbarProtocolVersion.current) >= RowPreview.firstViewProtocol else { return preview }
        let nodes = previewView.resolve(in: context)
        let node: ViewNode? = nodes.count > 1 ? .stack(axis: .vertical, spacing: 8, children: nodes) : nodes.first
        if let node, node.nodeCount > RowPreview.maxViewNodes {
            context.warnOnce("row \(key)'s preview view has \(node.nodeCount) nodes, over the \(RowPreview.maxViewNodes) a preview may have, so its text shows instead")
            return preview
        }
        preview.view = node
        return preview
    }
}

public struct Badge: StackbarView {
    var text: String
    var role: Role

    public init(_ text: String, role: Role = .secondary) {
        self.text = text
        self.role = role
    }

    public func resolve(in context: RenderContext) -> [ViewNode] { [.badge(text, role: role)] }
}

public struct Button: StackbarView {
    var title: String
    var symbol: String?
    var role: Role
    var key: String?
    var confirm: Confirm
    var label: ViewContent?
    var handler: RenderContext.Handler

    /// `confirm` as on `Row.action`: the host asks for a second press first.
    public init(_ title: String, symbol: String? = nil, role: Role = .primary, key: String? = nil, confirm: Confirm = .none, action: @escaping @MainActor () async throws -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.key = key
        self.confirm = confirm
        self.handler = { _ in try await action() }
    }

    /// A button drawn as any content: a round icon, a tile, a chip. Give it a
    /// `key` when the content has no text, so its action id stays stable.
    public init(key: String? = nil, confirm: Confirm = .none, action: @escaping @MainActor () async throws -> Void, @ViewBuilder label: () -> ViewContent) {
        self.init("", key: key, confirm: confirm, action: action)
        self.label = label()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        guard let label else {
            let id = context.register("button/\(key ?? title)", confirm: confirm.text, handler)
            return [.button(title: title, symbol: symbol, role: role, action: id, confirm: confirm.text)]
        }
        let nodes = label.resolve(in: context)
        let content = nodes.count == 1 ? nodes[0] : .stack(axis: .horizontal, children: nodes)
        let id = context.register("button/\(key ?? content.plainText)", confirm: confirm.text, handler)
        return [.tappable(content, action: id, confirm: confirm.text)]
    }
}

/// Whether an action asks for a second press, and what it does: the end of
/// "Press again within 10 s to …". Write it as a string,
/// `confirm: "remove \(count) containers"`, or `.none` to say on purpose that
/// a `.critical` action needs no confirmation (the store's check looks for
/// one or the other).
public struct Confirm: ExpressibleByStringInterpolation, Equatable, Sendable {
    /// The longest text the host shows; longer is cut.
    public static let maxLength = 120
    /// No second press.
    public static let none = Confirm(text: nil)

    public let text: String?

    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxLength))
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    private init(text: String?) {
        self.text = text
    }
}

public struct Toggle: StackbarView {
    var title: String
    var isOn: Bool
    var key: String?
    var onChange: @MainActor (Bool) async throws -> Void

    /// The host sends the new state; update your own property in `onChange`
    /// and the next render shows it.
    public init(_ title: String, isOn: Bool, key: String? = nil, onChange: @escaping @MainActor (Bool) async throws -> Void) {
        self.title = title
        self.isOn = isOn
        self.key = key
        self.onChange = onChange
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let current = isOn
        let change = onChange
        let id = context.register("toggle/\(key ?? title)") { value in
            if case .bool(let newValue) = value {
                try await change(newValue)
            } else {
                try await change(!current)
            }
        }
        return [.toggle(title: title, isOn: isOn, action: id)]
    }
}

public struct ProgressBar: StackbarView {
    var value: Double
    var total: Double
    var label: String?
    var role: Role
    var style: ProgressStyle?
    var timing: TimeRange?

    /// `style: .ring(lineWidth:)` draws a ring in place of a bar.
    public init(_ label: String? = nil, value: Double, total: Double = 1, role: Role = .accent, style: ProgressStyle? = nil) {
        self.label = label
        self.value = value
        self.total = total
        self.role = role
        self.style = style
    }

    /// Progress through `timing` that the host animates from the clock, so
    /// it moves smoothly without the plugin rendering again.
    public init(_ label: String? = nil, timing: TimeRange, role: Role = .accent, style: ProgressStyle? = nil) {
        self.init(label, value: 0, role: role, style: style)
        self.timing = timing
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.progress(value: value, total: total, label: label, role: role, style: style, timing: timing)]
    }
}

public struct Divider: StackbarView {
    public init() {}
    public func resolve(in context: RenderContext) -> [ViewNode] { [.divider] }
}

/// A label and its value on one line.
public struct LabeledContent: StackbarView {
    var label: String
    var value: String
    var valueRole: Role = .primary

    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    public func role(_ role: Role) -> LabeledContent { var copy = self; copy.valueRole = role; return copy }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.labeled(label: label, value: value, role: valueRole)]
    }
}

/// A small chart of a series of numbers: a sparkline in the menu bar.
public struct Chart: StackbarView {
    var values: [Double]
    var kind: ChartKind
    var label: String?
    var role: Role
    var options: ChartOptions?

    /// `labels` name the points (x-axis labels, or donut slices), `unit`
    /// follows the values ("h"), `goal` draws a target line, and
    /// `highlight` emphasizes one point (today, say). `compact` draws the
    /// marks alone, filling the frame you give it: a sparkline (protocol 12).
    public init(_ label: String? = nil, values: [Double], kind: ChartKind = .line, role: Role = .accent, labels: [String]? = nil, unit: String? = nil, goal: Double? = nil, highlight: Int? = nil, compact: Bool = false) {
        self.label = label
        self.values = values
        self.kind = kind
        self.role = role
        if labels != nil || unit != nil || goal != nil || highlight != nil || compact {
            options = ChartOptions(labels: labels, unit: unit, goal: goal, highlight: highlight, compact: compact ? true : nil)
        }
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        // Non-finite values would not survive JSON; the host draws gaps as 0.
        [.chart(values: values.map { $0.isFinite ? $0 : 0 }, kind: kind, label: label, role: role, options: options)]
    }
}

/// Several lines of text edited in place, like a note. The host keeps what
/// the user types and calls `onChange` with the whole text after a pause in
/// typing and when the editor loses focus or closes, so save it there.
///
/// ```swift
/// TextEditor(text: note.body, document: note.id, placeholder: "Start writing…", markdown: true) { text in
///     try self.save(note.id, text)
/// }
/// ```
///
/// `document` names what is edited: render a different one (another note)
/// and the editor shows its text; render the same one and the user's
/// typing stays, while a changed `text` (the file changed elsewhere) shows
/// once nothing is waiting to be sent. `markdown` styles headings, emphasis,
/// code, quotes, lists and task boxes as they are typed and adds the keys
/// ⌘B, ⌘I, ⇧⌘X, ⌘E, ⌘K, ⌘Return (tick a task), Return (continue a list)
/// and Tab. In a window the editor fills the window; in the panel it is
/// `minHeight` tall. Stackbar 0.38.0; older hosts show nothing.
public struct TextEditor: StackbarView {
    var text: String
    var document: String
    var placeholder: String?
    var markdown: Bool
    var minHeight: Double?
    var focus: Bool
    var key: String?
    var onChange: @MainActor (String) async throws -> Void

    public init(text: String, document: String = "", placeholder: String? = nil, markdown: Bool = false, minHeight: Double? = nil, focus: Bool = false, key: String? = nil, onChange: @escaping @MainActor (String) async throws -> Void) {
        self.text = text
        self.document = document
        self.placeholder = placeholder
        self.markdown = markdown
        self.minHeight = minHeight
        self.focus = focus
        self.key = key
        self.onChange = onChange
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let change = onChange
        let id = context.register("editor/\(key ?? placeholder ?? "text")") { value in
            if case .text(let text) = value { try await change(text) }
        }
        return [.editor(EditorNode(text: text, document: document, placeholder: placeholder, markdown: markdown ? true : nil,
                                   minHeight: minHeight, focus: focus ? true : nil, action: id))]
    }
}

/// A one-line text input. `onSubmit` gets the text when the user presses return,
/// and the field then goes back to `text`: an add field (`text: ""`) clears for
/// the next entry, and an edit field shows whatever the plugin renders next.
public struct TextField: StackbarView {
    var placeholder: String
    var text: String
    var key: String?
    var onSubmit: @MainActor (String) async throws -> Void

    public init(_ placeholder: String, text: String = "", key: String? = nil, onSubmit: @escaping @MainActor (String) async throws -> Void) {
        self.placeholder = placeholder
        self.text = text
        self.key = key
        self.onSubmit = onSubmit
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let submit = onSubmit
        let id = context.register("field/\(key ?? placeholder)") { value in
            if case .text(let text) = value { try await submit(text) }
        }
        return [.textField(placeholder: placeholder, text: text, action: id)]
    }
}

/// A choice among a few options.
public struct Picker: StackbarView {
    var title: String
    var options: [String]
    var selection: String?
    var style: ChoiceStyle?
    var key: String?
    var onChange: @MainActor (String) async throws -> Void

    /// `style: .segmented` draws side-by-side segments, for a few short options.
    public init(_ title: String, options: [String], selection: String?, style: ChoiceStyle? = nil, key: String? = nil, onChange: @escaping @MainActor (String) async throws -> Void) {
        self.title = title
        self.options = options
        self.selection = selection
        self.style = style
        self.key = key
        self.onChange = onChange
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let change = onChange
        let options = options
        let id = context.register("picker/\(key ?? title)") { value in
            if case .text(let choice) = value, options.contains(choice) { try await change(choice) }
        }
        return [.picker(title: title, options: options, selection: selection, style: style, action: id)]
    }
}

/// A continuous value in a range.
public struct Slider: StackbarView {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double?
    var key: String?
    var live: Bool
    var onChange: @MainActor (Double) async throws -> Void

    /// Sends the value when the slider is let go. With `live` it also sends
    /// values while it is dragged (a few dozen a second at most), for a
    /// preview that follows the thumb; keep such a handler cheap. Hosts
    /// before protocol 23 send on release only.
    public init(_ title: String, value: Double, in range: ClosedRange<Double> = 0...1, step: Double? = nil, key: String? = nil, live: Bool = false, onChange: @escaping @MainActor (Double) async throws -> Void) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.key = key
        self.live = live
        self.onChange = onChange
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let change = onChange
        let range = range
        let id = context.register("slider/\(key ?? title)") { value in
            if case .number(let number) = value { try await change(min(max(number, range.lowerBound), range.upperBound)) }
        }
        return [.slider(title: title, value: value, min: range.lowerBound, max: range.upperBound, step: step, action: id, live: live ? true : nil)]
    }
}

/// Opens a URL. The host opens it directly.
public struct Link: StackbarView {
    var title: String
    var url: String

    public init(_ title: String, url: String) {
        self.title = title
        self.url = url
    }

    public func resolve(in context: RenderContext) -> [ViewNode] { [.link(title: title, url: url)] }
}

/// What to show when there's nothing to show.
public struct ContentUnavailableView: StackbarView {
    var title: String
    var symbol: String?
    var message: String?

    public init(_ title: String, symbol: String? = nil, message: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.message = message
    }

    public func resolve(in context: RenderContext) -> [ViewNode] { [.empty(title: title, symbol: symbol, message: message)] }
}

extension ContentUnavailableView {
    /// The standard panel for a refresh that threw, so every plugin says it
    /// the same way: `if let problem { ContentUnavailableView(problem) }`.
    /// A missing secret points at the host's prompt above it rather than
    /// reading as a failure.
    public init(_ error: any Error) {
        if case StackbarError.missingSecret(let name) = error {
            self.init("Waiting for \(name)", symbol: "key", message: "Enter it in the prompt above. Stackbar keeps it in your Keychain.")
        } else {
            self.init("Couldn't refresh", symbol: "exclamationmark.triangle", message: "\(error)")
        }
    }
}

/// Several fields submitted together, like "Create Quicklink".
///
/// ```swift
/// Form(submit: "Save") {
///     FormField.text("Name", name: "name", value: link.name)
///     FormField.multiline("Text", name: "text", value: snippet.text)
///     FormField.application("Open with", name: "app", bundleID: link.openWith)
///     FormField.picker("Tag", name: "tag", options: tags, selection: link.tag)
///     FormField.toggle("Pinned", name: "pinned", isOn: link.pinned)
/// } onSubmit: { values in
///     guard let name = values.string("name"), !name.isEmpty else { self.nameError = "Give it a name"; return }
///     ...
/// }
/// ```
///
/// Validate in `onSubmit` and set a field's `error` to keep the form open;
/// the palette closes a form's view when a submit leaves no error.
public struct Form: StackbarView {
    var fields: [FormField]
    var submitTitle: String
    var key: String?
    var onSubmit: @MainActor ([String: EventValue]) async throws -> Void

    public init(submit submitTitle: String = "Save", key: String? = nil, @FormBuilder fields: () -> [FormField], onSubmit: @escaping @MainActor ([String: EventValue]) async throws -> Void) {
        self.fields = fields()
        self.submitTitle = submitTitle
        self.key = key
        self.onSubmit = onSubmit
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let submit = onSubmit
        let id = context.register("form/\(key ?? submitTitle)") { value in
            if case .fields(let values)? = value { try await submit(values) }
        }
        return [.form(FormNode(fields: fields, submitTitle: submitTitle, action: id))]
    }
}

extension FormField {
    public static func text(_ label: String, name: String, value: String = "", placeholder: String? = nil, error: String? = nil) -> FormField {
        FormField(name: name, label: label, kind: .text(placeholder: placeholder), value: .text(value), error: error)
    }

    public static func multiline(_ label: String, name: String, value: String = "", placeholder: String? = nil, error: String? = nil) -> FormField {
        FormField(name: name, label: label, kind: .multiline(placeholder: placeholder), value: .text(value), error: error)
    }

    /// An installed app the host lets the user pick; the value is its bundle id.
    public static func application(_ label: String, name: String, bundleID: String? = nil, error: String? = nil) -> FormField {
        FormField(name: name, label: label, kind: .application, value: bundleID.map(EventValue.text), error: error)
    }

    public static func picker(_ label: String, name: String, options: [String], selection: String? = nil, error: String? = nil) -> FormField {
        FormField(name: name, label: label, kind: .picker(options: options), value: selection.map(EventValue.text), error: error)
    }

    public static func toggle(_ label: String, name: String, isOn: Bool = false) -> FormField {
        FormField(name: name, label: label, kind: .toggle, value: .bool(isOn))
    }
}

@resultBuilder
public enum FormBuilder {
    public static func buildExpression(_ field: FormField) -> [FormField] { [field] }
    public static func buildBlock(_ parts: [FormField]...) -> [FormField] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [FormField]?) -> [FormField] { part ?? [] }
    public static func buildEither(first part: [FormField]) -> [FormField] { part }
    public static func buildEither(second part: [FormField]) -> [FormField] { part }
    public static func buildArray(_ parts: [[FormField]]) -> [FormField] { parts.flatMap { $0 } }
}
