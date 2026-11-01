#if canImport(SwiftUI)
#if canImport(AppKit)
import AppKit
#endif
import Charts
import SwiftUI
import StackbarProtocol

/// Sends a plugin's action back to it: a click, a toggle, a submitted field.
public typealias SendAction = @MainActor (ActionID, EventValue?) -> Void

extension EnvironmentValues {
    /// Loads an image the host keeps (a clipboard image) for row previews.
    @Entry public var stackbarImageData: (@Sendable (String) -> Data?)?
    /// Widgets draw controls but can't act on them.
    @Entry public var stackbarReadOnly: Bool = false
    /// The row a keyboard-driven list has selected, drawn highlighted.
    @Entry public var stackbarSelectedRow: String? = nil
    /// ⌘1–⌘9 positions of the first rows in a keyboard-driven list.
    @Entry var stackbarRowNumbers: [String: Int] = [:]
    /// Scrolls the enclosing panel to a row key. Set by the host's scroll
    /// view so keyboard selection stays visible.
    @Entry public var stackbarScrollTo: (@MainActor (String) -> Void)? = nil
    /// Changes every time the host shows the surface again (the popover
    /// reopens), so lists reset their filter and take focus.
    @Entry public var stackbarShownCount: Int = 0
    /// A `styled` font, used by text in place of its text style's font.
    @Entry var stackbarFont: FontSpec? = nil
    /// A `styled` foreground, used in place of role colors.
    @Entry var stackbarForeground: Paint? = nil
}

/// Draws one `ViewNode` for the panel and window surfaces. Every case of the
/// vocabulary is handled here; the switch has no `default`, so a new node type
/// will not compile until the panel knows how to draw it (and
/// `SurfaceParity` says what every other surface does with it).
public struct NodeView: View {
    let node: ViewNode
    let send: SendAction
    @Environment(\.stackbarReadOnly) private var readOnly
    @Environment(\.stackbarFont) private var font
    @Environment(\.stackbarForeground) private var foreground

    public init(node: ViewNode, send: @escaping SendAction) {
        self.node = node
        self.send = send
    }

    public var body: some View {
        switch node {
        case .text(let string, let style, let role):
            Text(string).font(textFont(style)).foregroundStyle(tint(role)).textSelection(.enabled)
        case .label(let title, let symbol, let role):
            Label(title, systemImage: symbol).foregroundStyle(tint(role))
        case .stack(.vertical, let spacing, let alignment, let children):
            VStack(alignment: alignment?.horizontal ?? .leading, spacing: spacing.map { CGFloat($0) }) { NodeList(children: children, send: send) }
        case .stack(.horizontal, let spacing, let alignment, let children):
            HStack(alignment: alignment?.vertical ?? .center, spacing: spacing.map { CGFloat($0) }) { NodeList(children: children, send: send) }
        case .stack(.depth, _, let alignment, let children):
            ZStack(alignment: alignment.map { Alignment(horizontal: $0.horizontal, vertical: $0.vertical) } ?? .center) { NodeList(children: children, send: send) }
        case .list(let searchable, let children):
            ListNodeView(searchable: searchable, children: children, send: send)
        case .section(let title, let children):
            // Sections of rows read as list groups; sections of charts,
            // gauges and values sit on a card.
            let isCard = !children.contains { if case .row = $0 { return true } else { return false } }
            VStack(alignment: .leading, spacing: isCard ? 8 : 4) {
                if let title {
                    Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                NodeList(children: children, send: send)
            }
            .padding(isCard ? 10 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCard ? Color.primary.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 2)
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
        case .progress(let value, let total, let label, let role, let style, let timing):
            TimedFraction(value: value, total: total, timing: timing) { fraction in
                VStack(alignment: .leading, spacing: 4) {
                    if let label { Text(label).font(.caption) }
                    if case .ring(let lineWidth) = style {
                        RingView(fraction: fraction, paint: tint(role), lineWidth: lineWidth ?? 4)
                    } else {
                        BarView(fraction: fraction, paint: tint(role))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        case .divider:
            Divider()
        case .labeled(let label, let value, let role):
            LabeledContent(label) { Text(value).foregroundStyle(role.color).textSelection(.enabled) }
        case .chart(let values, let kind, let label, let role, let options):
            ChartNodeView(values: values, kind: kind, label: label, role: role, options: options ?? ChartOptions())
        case .textField(let placeholder, let text, let action):
            FieldNodeView(placeholder: placeholder, text: text, action: action, send: send)
                .disabled(readOnly)
        case .picker(let title, let options, let selection, let style, let action):
            let picker = Picker(title, selection: Binding(get: { selection ?? "" }, set: { send(action, .text($0)) })) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            Group {
                if style == .segmented {
                    picker.pickerStyle(.segmented).labelsHidden()
                } else {
                    picker
                }
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
        case .form(let form):
            FormNodeView(form: form, send: send)
                .disabled(readOnly)
        case .styled(let child, let style):
            NodeView(node: child, send: send).modifier(StyleModifier(style: style, animationValue: child))
        case .shape(let shape):
            shape.kind.view(fill: (shape.fill ?? (shape.stroke == nil ? foreground ?? .role(.primary) : nil))?.shapeStyle, stroke: shape.stroke?.shapeStyle, lineWidth: shape.lineWidth ?? 1)
        case .image(.symbol(let symbol)):
            Image(systemName: symbol)
        case .timer(let range, let countsDown):
            Text(timerInterval: range.start...range.end, countsDown: countsDown)
                .font(textFont(.body))
                .foregroundStyle(tint(.primary))
        case .spacer(let minLength):
            Spacer(minLength: minLength.map { CGFloat($0) })
        case .tappable(let content, let action):
            Button { send(action, nil) } label: {
                NodeView(node: content, send: send).contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .allowsHitTesting(!readOnly)
        }
    }

    /// A styled font over the text style's, keeping what the style leaves unset.
    private func textFont(_ style: TextStyle) -> Font { (font ?? FontSpec()).font(for: style) }

    /// A styled foreground when one is set, else the role's color.
    private func tint(_ role: Role) -> AnyShapeStyle { foreground?.shapeStyle ?? AnyShapeStyle(role.color) }
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
            if searchable, !readOnly, let preview = selected?.preview {
                PreviewPane(preview: preview)
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

/// The selected row's full text or image, under a searchable list.
struct PreviewPane: View {
    let preview: RowPreview
    @Environment(\.stackbarImageData) private var imageData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            #if canImport(AppKit)
            if let id = preview.imageID, let data = imageData?(id), let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            #endif
            if let text = preview.text, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
            if let caption = preview.caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

/// A row action's shortcut (`cmd+return`, `cmd+1`, `cmd+shift+k`) matched
/// against a key press.
public struct KeyShortcut: Equatable {
    public var key: KeyEquivalent
    public var modifiers: EventModifiers

    public init?(_ spec: String) {
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

    public static func == (lhs: KeyShortcut, rhs: KeyShortcut) -> Bool {
        lhs.key.character == rhs.key.character && lhs.modifiers == rhs.modifiers
    }

    public func matches(_ press: KeyPress) -> Bool {
        let relevant: EventModifiers = [.command, .shift, .option, .control]
        guard press.modifiers.intersection(relevant) == modifiers else { return false }
        if press.key.character == key.character { return true }
        // With ⌘ held, `characters` can be the shifted or unmodified glyph;
        // compare letters and digits case-insensitively.
        return String(press.key.character).lowercased() == String(key.character).lowercased()
    }
}

public struct RowView: View {
    let row: RowNode
    let send: SendAction

    public init(row: RowNode, send: @escaping SendAction) {
        self.row = row
        self.send = send
    }

    @State private var hovering = false
    @Environment(\.stackbarReadOnly) private var readOnly
    @Environment(\.stackbarSelectedRow) private var selectedRow
    @Environment(\.stackbarRowNumbers) private var rowNumbers

    private var highlight: Color {
        if selectedRow == row.key { return Color.accentColor.opacity(0.22) }
        return hovering && !row.actions.isEmpty && !readOnly ? Color.primary.opacity(0.08) : .clear
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let icon = row.appIcon.flatMap(AppIcons.icon) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else if let symbol = row.symbol {
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
        case .progress(let value, let total, _, let role, _, let timing):
            TimedFraction(value: value, total: total, timing: timing) { fraction in
                BarView(fraction: fraction, paint: AnyShapeStyle(role.color))
            }
            .frame(width: 64)
        case .chart(let values, _, _, let role, _):
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
    let options: ChartOptions

    struct Point: Identifiable {
        let index: Int
        let value: Double
        let name: String
        var id: Int { index }
    }

    private static let palette: [Color] = [.orange, .green, .purple, .pink, .teal, .yellow, .indigo, .gray]

    private var points: [Point] {
        values.enumerated().map { index, value in
            let names = options.labels ?? []
            return Point(index: index, value: value, name: names.indices.contains(index) ? names[index] : "\(index + 1)")
        }
    }

    private func formatted(_ value: Double) -> String {
        ChartNumber.format(value) + (options.unit ?? "")
    }

    private func color(_ index: Int) -> Color {
        index == 0 ? role.color : Self.palette[(index - 1) % Self.palette.count]
    }

    /// The highlighted point, or the latest one, as "Mon 3.5h".
    private var summary: String? {
        let points = points
        if let index = options.highlight, points.indices.contains(index) {
            return "\(options.labels == nil ? "" : points[index].name + " ")\(formatted(points[index].value))"
        }
        guard let last = points.last else { return nil }
        if kind == .heatmap { return "\(values.filter { $0 > 0 }.count) active days" }
        return kind == .bar ? "Total \(formatted(values.reduce(0, +)))" : "Now \(formatted(last.value))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let label { Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                if kind != .donut, let summary {
                    Text(summary).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            switch kind {
            case .donut: donut
            case .heatmap: HeatmapView(values: values, names: options.labels ?? [], unit: options.unit ?? "", color: role.color)
            case .line, .bar, .area: series
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var series: some View {
        Chart {
            ForEach(points) { point in
                if kind == .bar {
                    BarMark(x: .value("Point", String(point.index)), y: .value("Value", point.value))
                        .foregroundStyle(options.highlight == nil || options.highlight == point.index ? role.color : role.color.opacity(0.4))
                        .cornerRadius(3)
                } else if kind == .area {
                    AreaMark(x: .value("Point", point.index), y: .value("Value", point.value))
                        .foregroundStyle(LinearGradient(colors: [role.color.opacity(0.35), role.color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Point", point.index), y: .value("Value", point.value))
                        .foregroundStyle(role.color)
                        .interpolationMethod(.monotone)
                } else {
                    LineMark(x: .value("Point", point.index), y: .value("Value", point.value))
                        .foregroundStyle(role.color)
                        .interpolationMethod(.monotone)
                }
            }
            if let goal = options.goal {
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
            }
            if kind != .bar, let index = options.highlight, values.indices.contains(index) {
                PointMark(x: .value("Point", index), y: .value("Value", values[index]))
                    .foregroundStyle(role.color)
                    .symbolSize(30)
            }
        }
        .chartXAxis {
            if options.labels != nil {
                AxisMarks { value in
                    AxisValueLabel {
                        Text(xName(value))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(formatted(number)) }
                }
            }
        }
        .frame(height: options.labels == nil ? 72 : 96)
    }

    private func xName(_ value: AxisValue) -> String {
        let names = options.labels ?? []
        let index = value.as(Int.self) ?? value.as(String.self).flatMap(Int.init) ?? -1
        return names.indices.contains(index) ? names[index] : ""
    }

    private var donut: some View {
        let total = values.reduce(0, +)
        return HStack(spacing: 14) {
            Chart(points) { point in
                SectorMark(angle: .value("Value", max(point.value, 0)), innerRadius: .ratio(0.64), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(color(point.index))
            }
            .chartLegend(.hidden)
            .frame(width: 92, height: 92)
            .overlay {
                VStack(spacing: 0) {
                    Text(formatted(total)).font(.headline.monospacedDigit())
                    Text("total").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(points) { point in
                    HStack(spacing: 6) {
                        Circle().fill(color(point.index)).frame(width: 8, height: 8)
                        Text(point.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(formatted(point.value)).font(.caption.monospacedDigit())
                        if total > 0 {
                            Text(String(format: "%.1f%%", point.value / total * 100))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

/// Days as squares in week columns, Sunday on top, like a contribution
/// graph: five shades of the role's color by quartile of the active days.
struct HeatmapView: View {
    let values: [Double]
    let names: [String]
    let unit: String
    let color: Color

    var body: some View {
        let layout = HeatmapLayout(count: values.count, todayRow: Calendar.current.component(.weekday, from: Date()) - 1)
        let levels = HeatmapLayout.levels(values)
        let gap = 0.25
        VStack(alignment: .trailing, spacing: 6) {
            Canvas { context, size in
                let side = size.width / (Double(layout.columns) * (1 + gap) - gap)
                for index in values.indices {
                    let (column, row) = layout.cell(index)
                    let rect = CGRect(x: Double(column) * side * (1 + gap), y: Double(row) * side * (1 + gap), width: side, height: side)
                    context.fill(Path(roundedRect: rect, cornerRadius: side * 0.22), with: .color(shade(levels[index])))
                }
            }
            .aspectRatio((Double(layout.columns) * (1 + gap) - gap) / (7 * (1 + gap) - gap), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(summary)
            HStack(spacing: 3) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(shade(level)).frame(width: 9, height: 9)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        guard let peak = values.indices.max(by: { values[$0] < values[$1] }) else { return "No days" }
        let name = names.indices.contains(peak) ? names[peak] : "day \(peak + 1)"
        return "\(values.filter { $0 > 0 }.count) active days; busiest \(name), \(ChartNumber.format(values[peak]))\(unit)"
    }

    private func shade(_ level: Int) -> Color {
        level == 0 ? Color.primary.opacity(0.08) : color.opacity([0, 0.3, 0.5, 0.75, 1][min(level, 4)])
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
    public var font: Font { FontSpec().font(for: self) }

    var textStyle: Font.TextStyle {
        switch self {
        case .title: return .title2
        case .headline: return .headline
        case .body, .monospaced: return .body
        case .caption: return .caption
        }
    }

    var weight: Font.Weight? { self == .title ? .semibold : nil }
    var design: Font.Design { self == .monospaced ? .monospaced : .default }
}
/// A determinate bar drawn with shapes rather than `ProgressView`, whose
/// AppKit-backed style renders as a placeholder in `ImageRenderer` snapshots.
struct BarView: View {
    var fraction: Double
    var paint: AnyShapeStyle

    var body: some View {
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(paint).frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((clamped * 100).rounded())) percent"))
    }
}

#if canImport(AppKit)
/// Apps' icons by bundle id, for rows that name an app. Looked up once.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage?] = [:]

    static func icon(_ bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { url in
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            return icon
        }
        cache[bundleID] = image
        return image
    }
}
#endif

#endif
