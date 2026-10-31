#if canImport(SwiftUI)
import Charts
import SwiftUI
import StackbarProtocol

/// Sends a plugin's action back to it: a click, a toggle, a submitted field.
public typealias SendAction = @MainActor (ActionID, EventValue?) -> Void

extension EnvironmentValues {
    /// Widgets draw controls but can't act on them.
    @Entry public var stackbarReadOnly: Bool = false
    /// The row a keyboard-driven list has selected, drawn highlighted.
    @Entry var stackbarSelectedRow: String? = nil
    /// ⌘1–⌘9 positions of the first rows in a keyboard-driven list.
    @Entry var stackbarRowNumbers: [String: Int] = [:]
    /// Scrolls the enclosing panel to a row key. Set by the host's scroll
    /// view so keyboard selection stays visible.
    @Entry public var stackbarScrollTo: (@MainActor (String) -> Void)? = nil
    /// Changes every time the host shows the surface again (the popover
    /// reopens), so lists reset their filter and take focus.
    @Entry public var stackbarShownCount: Int = 0
}

/// Draws one `ViewNode` for the panel and window surfaces. Every case of the
/// vocabulary is handled here; the switch has no `default`, so a new node type
/// will not compile until the panel knows how to draw it (and
/// `SurfaceParity` says what every other surface does with it).
public struct NodeView: View {
    let node: ViewNode
    let send: SendAction
    @Environment(\.stackbarReadOnly) private var readOnly

    public init(node: ViewNode, send: @escaping SendAction) {
        self.node = node
        self.send = send
    }

    public var body: some View {
        switch node {
        case .text(let string, let style, let role):
            Text(string).font(style.font).foregroundStyle(role.color).textSelection(.enabled)
        case .label(let title, let symbol, let role):
            Label(title, systemImage: symbol).foregroundStyle(role.color)
        case .stack(.vertical, let spacing, let children):
            VStack(alignment: .leading, spacing: spacing.map { CGFloat($0) }) { NodeList(children: children, send: send) }
        case .stack(.horizontal, let spacing, let children):
            HStack(spacing: spacing.map { CGFloat($0) }) { NodeList(children: children, send: send) }
        case .list(let searchable, let children):
            ListNodeView(searchable: searchable, children: children, send: send)
        case .section(let title, let children):
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
                }
                NodeList(children: children, send: send)
            }
        case .row(let row):
            RowView(row: row, send: send)
        case .badge(let text, let role):
            BadgeView(text: text, role: role)
        case .button(let title, let symbol, let role, let action):
            Button(role: role == .critical ? .destructive : nil) {
                send(action, nil)
            } label: {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .tint(role.color)
            .disabled(readOnly)
        case .toggle(let title, let isOn, let action):
            Toggle(title, isOn: Binding(get: { isOn }, set: { send(action, .bool($0)) }))
                .disabled(readOnly)
        case .progress(let value, let total, let label, let role):
            VStack(alignment: .leading, spacing: 4) {
                if let label { Text(label).font(.caption) }
                BarView(fraction: total > 0 ? clamp(value, total) / total : 0, color: role.color)
            }
            .accessibilityElement(children: .combine)
        case .divider:
            Divider()
        case .labeled(let label, let value, let role):
            LabeledContent(label) { Text(value).foregroundStyle(role.color).textSelection(.enabled) }
        case .chart(let values, let kind, let label, let role):
            ChartNodeView(values: values, kind: kind, label: label, role: role)
        case .textField(let placeholder, let text, let action):
            FieldNodeView(placeholder: placeholder, text: text, action: action, send: send)
                .disabled(readOnly)
        case .picker(let title, let options, let selection, let action):
            Picker(title, selection: Binding(get: { selection ?? "" }, set: { send(action, .text($0)) })) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .disabled(readOnly)
        case .slider(let title, let value, let low, let high, let step, let action):
            SliderNodeView(title: title, value: value, range: low...max(high, low), step: step, action: action, send: send)
                .disabled(readOnly)
        case .link(let title, let url):
            if let destination = URL(string: url) {
                Link(title, destination: destination)
            } else {
                Text(title)
            }
        case .empty(let title, let symbol, let message):
            ContentUnavailableView {
                Label(title, systemImage: symbol ?? "tray")
            } description: {
                if let message { Text(message) }
            }
        }
    }

    private func clamp(_ value: Double, _ total: Double) -> Double { min(max(value, 0), max(total, 0)) }
}

/// Children of a stack or section, in order.
struct NodeList: View {
    let children: [ViewNode]
    let send: SendAction

    var body: some View {
        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
            NodeView(node: child, send: send)
        }
    }
}

/// A list, with the optional filter field `searchable` asks for. Filtering is
/// done here, by the host, so it works the same for every plugin.
///
/// A searchable list is also driven from the keyboard: the filter field takes
/// focus when the surface opens, so typing filters at once; ↑ and ↓ move the
/// selection across rows (the first row is selected to start), Return runs
/// the selected row's first action, and every action shortcut works, on the
/// selected row first (⌘P, ⌘⌫) and then on whichever row declares it.
/// ⌘1–⌘9 run the first action of the first nine rows shown, which follow the
/// filter.
struct ListNodeView: View {
    let searchable: Bool
    let children: [ViewNode]
    let send: SendAction
    @State private var query = ""
    @State private var selectedKey: String?
    @FocusState private var focused: Bool
    @Environment(\.stackbarReadOnly) private var readOnly
    @Environment(\.stackbarScrollTo) private var scrollTo
    @Environment(\.stackbarShownCount) private var shownCount

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if searchable {
                TextField("Filter", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.bottom, 4)
                    .focused($focused)
                    .onSubmit { runSelected() }
                    .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
                    .onChange(of: query) { _, _ in select(rows.first?.key) }
            }
            ForEach(Array(visible.enumerated()), id: \.offset) { _, child in
                NodeView(node: child, send: send)
            }
            if visible.isEmpty && !query.isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            }
        }
        .environment(\.stackbarSelectedRow, searchable && !readOnly ? selected?.key : nil)
        .environment(\.stackbarRowNumbers, searchable && !readOnly ? numbers : [:])
        .onAppear { reset() }
        .onChange(of: shownCount) { _, _ in reset() }
    }

    private var visible: [ViewNode] {
        RowFilter.filter(children, query: query)
    }

    private var rows: [RowNode] { visible.flatMap(\.rows) }

    /// The first nine rows that do something, numbered from 1.
    private var numbers: [String: Int] {
        let actionable = rows.filter { !$0.actions.isEmpty }.prefix(9)
        return Dictionary(actionable.enumerated().map { ($1.key, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    }

    /// The chosen row, or the first one when nothing (still visible) is.
    private var selected: RowNode? {
        let rows = rows
        return rows.first { $0.key == selectedKey } ?? rows.first
    }

    private func reset() {
        guard searchable, !readOnly else { return }
        query = ""
        selectedKey = nil
        // Focus after the popover's window is key, or it doesn't take.
        DispatchQueue.main.async { focused = true }
    }

    private func select(_ key: String?) {
        selectedKey = key
        if let key { scrollTo?(key) }
    }

    private func move(_ delta: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.key == selected?.key } ?? 0
        select(rows[min(max(current + delta, 0), rows.count - 1)].key)
    }

    private func runSelected() {
        guard !readOnly, let action = selected?.actions.first else { return }
        send(action.id, nil)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard !readOnly else { return .ignored }
        switch press.key {
        case .downArrow where press.modifiers.isDisjoint(with: [.command, .option, .control]):
            move(1)
            return .handled
        case .upArrow where press.modifiers.isDisjoint(with: [.command, .option, .control]):
            move(-1)
            return .handled
        default:
            break
        }
        // A shortcut on the selected row wins, then any row's (⌘1 is "this row").
        let candidates = (selected.map { [$0] } ?? []) + rows
        for row in candidates {
            if let action = row.actions.first(where: { $0.shortcut.map { KeyShortcut($0)?.matches(press) ?? false } ?? false }) {
                select(row.key)
                send(action.id, nil)
                return .handled
            }
        }
        if press.modifiers.intersection([.command, .shift, .option, .control]) == .command, let digit = press.key.character.wholeNumberValue, (1...9).contains(digit) {
            let actionable = rows.filter { !$0.actions.isEmpty }
            guard actionable.indices.contains(digit - 1), let action = actionable[digit - 1].actions.first else { return .handled }
            select(actionable[digit - 1].key)
            send(action.id, nil)
            return .handled
        }
        return .ignored
    }
}

/// A row action's shortcut (`cmd+return`, `cmd+1`, `cmd+shift+k`) matched
/// against a key press.
struct KeyShortcut: Equatable {
    var key: KeyEquivalent
    var modifiers: EventModifiers

    init?(_ spec: String) {
        var modifiers: EventModifiers = []
        var key: KeyEquivalent?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            case "return", "enter": key = .return
            case "delete", "backspace": key = .delete
            case "forwarddelete": key = .deleteForward
            case "escape", "esc": key = .escape
            case "space": key = .space
            case "tab": key = .tab
            case "up": key = .upArrow
            case "down": key = .downArrow
            case "left": key = .leftArrow
            case "right": key = .rightArrow
            default:
                guard part.count == 1, let character = part.first else { return nil }
                key = KeyEquivalent(character)
            }
        }
        guard let key else { return nil }
        self.key = key
        self.modifiers = modifiers
    }

    static func == (lhs: KeyShortcut, rhs: KeyShortcut) -> Bool {
        lhs.key.character == rhs.key.character && lhs.modifiers == rhs.modifiers
    }

    func matches(_ press: KeyPress) -> Bool {
        let relevant: EventModifiers = [.command, .shift, .option, .control]
        guard press.modifiers.intersection(relevant) == modifiers else { return false }
        if press.key.character == key.character { return true }
        // With ⌘ held, `characters` can be the shifted or unmodified glyph;
        // compare letters and digits case-insensitively.
        return String(press.key.character).lowercased() == String(key.character).lowercased()
    }
}

/// The host's list filter, shared by panels and the palette.
public enum RowFilter {
    public static func filter(_ children: [ViewNode], query: String) -> [ViewNode] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return children }
        return children.filter { child in
            child.rows.contains { row in
                row.title.localizedCaseInsensitiveContains(query) || (row.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
    }
}

struct RowView: View {
    let row: RowNode
    let send: SendAction
    @State private var hovering = false
    @Environment(\.stackbarReadOnly) private var readOnly
    @Environment(\.stackbarSelectedRow) private var selectedRow
    @Environment(\.stackbarRowNumbers) private var rowNumbers

    private var highlight: Color {
        if selectedRow == row.key { return Color.accentColor.opacity(0.22) }
        return hovering && !row.actions.isEmpty && !readOnly ? Color.primary.opacity(0.08) : .clear
    }

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = row.symbol {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).lineLimit(2)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ForEach(Array(row.accessories.enumerated()), id: \.offset) { _, accessory in
                accessoryView(accessory)
            }
            if let number = rowNumbers[row.key] {
                Text("⌘\(number)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(highlight))
        .id(row.key)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard !readOnly, let primary = row.actions.first else { return }
            send(primary.id, nil)
        }
        .contextMenu {
            if !readOnly {
                ForEach(row.actions, id: \.id) { action in
                    if let shortcut = action.shortcut.flatMap(KeyShortcut.init) {
                        Button(action.title, role: action.role == .critical ? .destructive : nil) { send(action.id, nil) }
                            .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                    } else {
                        Button(action.title, role: action.role == .critical ? .destructive : nil) { send(action.id, nil) }
                    }
                }
            }
        }
        .help(row.actions.first?.title ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.actions.isEmpty ? [] : .isButton)
    }

    @ViewBuilder private func accessoryView(_ node: ViewNode) -> some View {
        switch node {
        case .progress(let value, let total, _, let role):
            BarView(fraction: total > 0 ? min(max(value, 0), total) / total : 0, color: role.color)
                .frame(width: 64)
        case .chart(let values, _, _, let role):
            Sparkline(values: values).stroke(role.color, lineWidth: 1.5).frame(width: 48, height: 16)
        default:
            NodeView(node: node, send: send)
        }
    }
}

public struct BadgeView: View {
    let text: String
    let role: Role

    public init(text: String, role: Role) {
        self.text = text
        self.role = role
    }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(role.color)
            .background(Capsule().fill(role.color.opacity(0.15)))
    }
}

struct ChartNodeView: View {
    let values: [Double]
    let kind: ChartKind
    let label: String?
    let role: Role

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    if kind == .bar {
                        BarMark(x: .value("Index", index), y: .value("Value", value))
                    } else {
                        LineMark(x: .value("Index", index), y: .value("Value", value))
                    }
                }
            }
            .foregroundStyle(role.color)
            .chartXAxis(.hidden)
            .frame(height: 80)
        }
    }
}

/// A one-line field that keeps its own draft and sends it on return.
struct FieldNodeView: View {
    let placeholder: String
    let text: String
    let action: ActionID
    let send: SendAction
    @State private var draft = ""

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .onSubmit { send(action, .text(draft)) }
            .onAppear { draft = text }
            .onChange(of: text) { _, newValue in draft = newValue }
    }
}

/// A slider that sends its value when the user lets go, not on every pixel.
struct SliderNodeView: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let action: ActionID
    let send: SendAction
    @State private var current = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Group {
                if let step, step > 0 {
                    Slider(value: $current, in: range, step: step, onEditingChanged: commit)
                } else {
                    Slider(value: $current, in: range, onEditingChanged: commit)
                }
            }
        }
        .onAppear { current = value }
        .onChange(of: value) { _, newValue in current = newValue }
    }

    private func commit(_ editing: Bool) {
        if !editing { send(action, .number(current)) }
    }
}

/// A series drawn as a line scaled to its own min and max.
public struct Sparkline: Shape {
    let values: [Double]

    public init(values: [Double]) { self.values = values }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let low = values.min(), let high = values.max() else { return path }
        let span = high - low
        for (index, value) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let fraction = span == 0 ? 0.5 : (value - low) / span
            let point = CGPoint(x: x, y: rect.maxY - rect.height * CGFloat(fraction))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

extension Role {
    public var color: Color {
        switch self {
        case .primary: return .primary
        case .secondary: return .secondary
        case .accent: return .accentColor
        case .success: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

extension TextStyle {
    public var font: Font {
        switch self {
        case .title: return .title2.weight(.semibold)
        case .headline: return .headline
        case .body: return .body
        case .caption: return .caption
        case .monospaced: return .system(.body, design: .monospaced)
        }
    }
}
/// A determinate bar drawn with shapes rather than `ProgressView`, whose
/// AppKit-backed style renders as a placeholder in `ImageRenderer` snapshots.
struct BarView: View {
    var fraction: Double
    var color: Color

    var body: some View {
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(color).frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((clamped * 100).rounded())) percent"))
    }
}

#endif
