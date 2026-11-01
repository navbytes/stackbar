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

public struct VStack: StackbarView {
    var spacing: Double?
    var content: ViewContent

    public init(spacing: Double? = nil, @ViewBuilder content: () -> ViewContent) {
        self.spacing = spacing
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.stack(axis: .vertical, spacing: spacing, children: content.resolve(in: context))]
    }
}

public struct HStack: StackbarView {
    var spacing: Double?
    var content: ViewContent

    public init(spacing: Double? = nil, @ViewBuilder content: () -> ViewContent) {
        self.spacing = spacing
        self.content = content()
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.stack(axis: .horizontal, spacing: spacing, children: content.resolve(in: context))]
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
    var accessories: [ViewNode] = []
    var actions: [(title: String, shortcut: String?, role: Role, handler: RenderContext.Handler?, navigate: CommandTarget?)] = []
    var preview: RowPreview?

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

    /// Adds an action. The first one is what a click on the row does.
    public func action(_ title: String, shortcut: String? = nil, role: Role = .primary, perform: @escaping @MainActor () async throws -> Void) -> Row {
        var copy = self
        copy.actions.append((title, shortcut, role, { _ in try await perform() }, nil))
        return copy
    }

    /// Adds an action that opens another of this plugin's commands, with
    /// arguments. The host opens it without calling the plugin: in the
    /// palette it is pushed as a new view (Esc comes back).
    public func navigate(_ title: String, to command: String, arguments: [String: String] = [:], shortcut: String? = nil) -> Row {
        var copy = self
        copy.actions.append((title, shortcut, .primary, nil, CommandTarget(command: command, arguments: arguments)))
        return copy
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let refs = actions.map { action in
            let base = "row/\(key)/\(action.title)"
            let id = action.handler.map { context.register(base, $0) } ?? ActionID(context.prefix + base)
            return ActionRef(id: id, title: action.title, shortcut: action.shortcut, role: action.role, navigate: action.navigate)
        }
        return [.row(RowNode(key: key, title: title, subtitle: subtitle, symbol: symbol, appIcon: appIcon, accessories: accessories, actions: refs, preview: preview))]
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
    var handler: RenderContext.Handler

    public init(_ title: String, symbol: String? = nil, role: Role = .primary, key: String? = nil, action: @escaping @MainActor () async throws -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.key = key
        self.handler = { _ in try await action() }
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let id = context.register("button/\(key ?? title)", handler)
        return [.button(title: title, symbol: symbol, role: role, action: id)]
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

    public init(_ label: String? = nil, value: Double, total: Double = 1, role: Role = .accent) {
        self.label = label
        self.value = value
        self.total = total
        self.role = role
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        [.progress(value: value, total: total, label: label, role: role)]
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
    /// `highlight` emphasizes one point (today, say).
    public init(_ label: String? = nil, values: [Double], kind: ChartKind = .line, role: Role = .accent, labels: [String]? = nil, unit: String? = nil, goal: Double? = nil, highlight: Int? = nil) {
        self.label = label
        self.values = values
        self.kind = kind
        self.role = role
        if labels != nil || unit != nil || goal != nil || highlight != nil {
            options = ChartOptions(labels: labels, unit: unit, goal: goal, highlight: highlight)
        }
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        // Non-finite values would not survive JSON; the host draws gaps as 0.
        [.chart(values: values.map { $0.isFinite ? $0 : 0 }, kind: kind, label: label, role: role, options: options)]
    }
}

/// A one-line text input. `onSubmit` gets the text when the user presses return.
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
    var key: String?
    var onChange: @MainActor (String) async throws -> Void

    public init(_ title: String, options: [String], selection: String?, key: String? = nil, onChange: @escaping @MainActor (String) async throws -> Void) {
        self.title = title
        self.options = options
        self.selection = selection
        self.key = key
        self.onChange = onChange
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let change = onChange
        let options = options
        let id = context.register("picker/\(key ?? title)") { value in
            if case .text(let choice) = value, options.contains(choice) { try await change(choice) }
        }
        return [.picker(title: title, options: options, selection: selection, action: id)]
    }
}

/// A continuous value in a range.
public struct Slider: StackbarView {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double?
    var key: String?
    var onChange: @MainActor (Double) async throws -> Void

    public init(_ title: String, value: Double, in range: ClosedRange<Double> = 0...1, step: Double? = nil, key: String? = nil, onChange: @escaping @MainActor (Double) async throws -> Void) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.key = key
        self.onChange = onChange
    }

    public func resolve(in context: RenderContext) -> [ViewNode] {
        let change = onChange
        let range = range
        let id = context.register("slider/\(key ?? title)") { value in
            if case .number(let number) = value { try await change(min(max(number, range.lowerBound), range.upperBound)) }
        }
        return [.slider(title: title, value: value, min: range.lowerBound, max: range.upperBound, step: step, action: id)]
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
