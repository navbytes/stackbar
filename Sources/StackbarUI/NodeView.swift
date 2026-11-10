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
    /// A `styled` symbol style, used by SF Symbol images inside.
    @Entry var stackbarSymbol: SymbolStyle? = nil
    /// The bytes of a remote image (`ImageSource.url`) the host has fetched
    /// for this plugin, or `nil` while it hasn't. Set by the app and by
    /// `Snapshot`.
    @Entry public var stackbarRemoteImage: (@Sendable (String) -> Data?)? = nil
    /// Drawing for `Snapshot`: AppKit-backed controls (text fields, pickers)
    /// don't render off screen, so they draw as SwiftUI look-alikes.
    @Entry public var stackbarSnapshot: Bool = false
    /// An editor fills the space it is given (a plugin window) instead of
    /// keeping its panel height.
    @Entry public var stackbarEditorFills: Bool = false
    /// Draws sections as System Settings–style grouped boxes, with switches
    /// and pickers trailing each row. Set by the Settings window for a
    /// plugin's `settings` surface.
    @Entry public var stackbarGroupedSections: Bool = false
    /// Makes a read-only surface's buttons, toggles, tappables and rows act
    /// after all. Set by the widget extension, where a press has to run an
    /// App Intent rather than a closure (protocol 17); nil elsewhere.
    @Entry public var stackbarWidgetButton: WidgetActionButton? = nil
}

/// Wraps a widget's control in a button that sends `action` (with `value`)
/// to the plugin through the app. `plain` is for content that draws its own
/// look (a row, a tappable).
public struct WidgetActionButton: Sendable {
    public let make: @MainActor @Sendable (_ action: ActionID, _ value: EventValue?, _ plain: Bool, _ label: AnyView) -> AnyView

    public init(make: @escaping @MainActor @Sendable (_ action: ActionID, _ value: EventValue?, _ plain: Bool, _ label: AnyView) -> AnyView) {
        self.make = make
    }
}

/// Draws one `ViewNode` for the panel and window surfaces. Every case of the
/// vocabulary is handled here; the switch has no `default`, so a new node type
/// will not compile until the panel knows how to draw it (and
/// `SurfaceParity` says what every other surface does with it).
public struct NodeView: View {
    let node: ViewNode
    let send: SendAction
    @Environment(\.stackbarReadOnly) private var readOnly
    @Environment(\.stackbarSnapshot) private var snapshot
    @Environment(\.stackbarFont) private var font
    @Environment(\.stackbarForeground) private var foreground
    @Environment(\.stackbarSymbol) private var symbolStyle
    @Environment(\.stackbarGroupedSections) private var grouped
    @Environment(\.stackbarWidgetButton) private var widgetButton
    @Environment(\.stackbarEditorFills) private var editorFills

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
        case .section(let title, let children) where grouped:
            SettingsGroup(title) {
                NodeList(children: children, send: send)
            }
            .padding(.bottom, 14)
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
        case .button(let title, let symbol, _, let action, _) where readOnly && widgetButton != nil:
            widgetButton?.make(action, nil, false, AnyView(Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }))
        case .toggle(let title, let isOn, let action) where readOnly && widgetButton != nil && !snapshot:
            widgetButton?.make(action, .bool(!isOn), true, AnyView(
                Toggle(title, isOn: .constant(isOn)).allowsHitTesting(false)
            ))
        case .button(let title, let symbol, let role, let action, _):
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
        case .toggle(let title, let isOn, _) where snapshot:
            SnapshotToggle(title: title, isOn: isOn, trailing: grouped)
        case .toggle(let title, let isOn, let action) where grouped:
            Toggle(title, isOn: Binding(get: { isOn }, set: { send(action, .bool($0)) }))
                .toggleStyle(TrailingSwitchStyle())
                .disabled(readOnly)
        case .toggle(let title, let isOn, let action):
            Toggle(title, isOn: Binding(get: { isOn }, set: { send(action, .bool($0)) }))
                .disabled(readOnly)
        case .progress(let value, let total, let label, let role, let style, let timing):
            TimedFraction(value: value, total: total, timing: timing) { fraction in
                VStack(alignment: .leading, spacing: 4) {
                    if let label { Text(label).font(.caption) }
                    if case .ring(let lineWidth) = style {
                        RingView(fraction: fraction, paint: tint(role), lineWidth: lineWidth ?? 4, track: track(0.2))
                    } else {
                        BarView(fraction: fraction, paint: tint(role), track: track(0.25))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        case .divider:
            Divider()
        case .labeled(let label, let value, let role):
            LabeledContent(label) { Text(value).foregroundStyle(tint(role)).textSelection(.enabled) }
        case .chart(let values, let kind, let label, let role, let options):
            ChartNodeView(values: values, kind: kind, label: label, role: role, options: options ?? ChartOptions(), tint: foreground?.flatColor)
        case .textField(let placeholder, let text, let action):
            if snapshot {
                SnapshotField(placeholder: placeholder, text: text)
            } else {
                FieldNodeView(placeholder: placeholder, text: text, action: action, send: send)
                    .disabled(readOnly)
            }
        case .picker(let title, let options, let selection, let style, _) where snapshot:
            SnapshotPicker(title: title, options: options, selection: selection, segmented: style == .segmented)
        case .picker(let title, let options, let selection, let style, let action):
            let picker = Picker(title, selection: Binding(get: { selection ?? "" }, set: { send(action, .text($0)) })) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            Group {
                if style == .segmented {
                    picker.pickerStyle(.segmented).labelsHidden()
                } else if grouped {
                    HStack {
                        Text(title)
                        Spacer(minLength: 12)
                        picker.labelsHidden().fixedSize()
                    }
                } else {
                    picker
                }
            }
            .disabled(readOnly)
        case .slider(let title, let value, let low, let high, _, _, _) where snapshot:
            SnapshotSlider(title: title, fraction: high > low ? (value - low) / (high - low) : 0, tint: foreground?.flatColor ?? .accentColor)
        case .slider(let title, let value, let low, let high, let step, let action, let live):
            SliderNodeView(title: title, value: value, range: low...max(high, low), step: step, action: action, live: live == true, send: send)
                .tint(foreground?.flatColor)
                .disabled(readOnly)
        case .link(let title, _) where snapshot:
            Text(title).foregroundStyle(foreground?.flatColor ?? .accentColor)
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
            NodeView(node: child, send: send).modifier(StyleModifier(style: style, animationValue: child, interactive: !readOnly && !snapshot))
        case .shape(let shape):
            shape.kind.view(fill: (shape.fill ?? (shape.stroke == nil ? foreground ?? .role(.primary) : nil))?.shapeStyle, stroke: shape.stroke?.shapeStyle, lineWidth: shape.lineWidth ?? 1)
        case .image(.symbol(let symbol)):
            SymbolView(name: symbol, style: symbolStyle)
        case .image(.url(let url, let placeholder)):
            RemoteImageView(url: url, placeholder: placeholder)
        case .grid(let columns, let spacing, let children):
            GridNodeView(columns: columns, spacing: spacing, children: children, send: send)
        case .timer(let range, let countsDown):
            Text(timerInterval: range.start...range.end, countsDown: countsDown)
                .font(textFont(.body))
                .foregroundStyle(tint(.primary))
        case .clock(let face) where snapshot:
            Text(face.string(at: Date()))
                .font(textFont(.body).monospacedDigit())
                .foregroundStyle(tint(.primary))
        case .clock(let face):
            ClockText(face: face)
                .font(textFont(.body).monospacedDigit())
                .foregroundStyle(tint(.primary))
        case .editor(let editor) where snapshot || readOnly:
            SnapshotEditor(editor: editor)
                .frame(maxWidth: .infinity, minHeight: editorFills ? nil : editor.minHeight ?? EditorNode.defaultHeight, alignment: .topLeading)
        case .editor(let editor):
            #if canImport(AppKit)
            EditorNodeView(editor: editor, send: send)
                .frame(maxWidth: .infinity, maxHeight: editorFills ? .infinity : nil)
                .frame(height: editorFills ? nil : editor.minHeight ?? EditorNode.defaultHeight)
            #else
            SnapshotEditor(editor: editor)
            #endif
        case .spacer(let minLength):
            Spacer(minLength: minLength.map { CGFloat($0) })
        case .tappable(let content, let action, _) where readOnly && widgetButton != nil:
            widgetButton?.make(action, nil, true, AnyView(NodeView(node: content, send: send).contentShape(Rectangle())))
        case .tappable(let content, let action, _):
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

    /// A progress track: a faint copy of the foreground, so a bar styled
    /// white on a photo keeps a visible track and a gradient ring sits on
    /// its own hue. A gradient's track is its last stop, a little fainter.
    private func track(_ opacity: Double) -> Color {
        switch foreground {
        case .color(let color):
            return color.color.opacity(opacity)
        case .linearGradient(let colors, _), .radialGradient(let colors, _, _, _), .angularGradient(let colors, _):
            return (colors.last?.color ?? .secondary).opacity(opacity * 0.75)
        default:
            return .secondary.opacity(opacity)
        }
    }
}

/// A child node with the identity SwiftUI keeps its state under.
struct IdentifiedNode: Identifiable {
    let id: String
    let node: ViewNode

    /// The children, each with an id from what it says about itself, not from
    /// where it stands. A row is its key, a section its title, a field or a
    /// slider its action: they hold state (a draft, a position) that must
    /// stay with them when a sibling above comes or goes, as a conditional
    /// field does. A node that says nothing like that, and holds no state of
    /// its own to lose, is its place. A repeat gets `#2`, `#3`.
    static func list(_ children: [ViewNode]) -> [IdentifiedNode] {
        var seen: [String: Int] = [:]
        return children.enumerated().map { index, child in
            guard var base = name(of: child) else { return IdentifiedNode(id: "at|\(index)", node: child) }
            let count = seen[base, default: 0] + 1
            seen[base] = count
            if count > 1 { base += "#\(count)" }
            return IdentifiedNode(id: base, node: child)
        }
    }

    private static func name(of node: ViewNode) -> String? {
        switch node {
        case .row(let row): return "row|\(row.key)"
        case .section(let title, _): return "section|\(title ?? "")"
        case .textField(_, _, let action): return "field|\(action.rawValue)"
        case .slider(_, _, _, _, _, let action, _): return "slider|\(action.rawValue)"
        case .editor(let editor): return "editor|\(editor.action.rawValue)"
        case .styled(let child, _): return name(of: child).map { "styled|" + $0 }
        default: return nil
        }
    }
}

/// Children of a stack or section, in order.
struct NodeList: View {
    let children: [ViewNode]
    let send: SendAction

    var body: some View {
        ForEach(IdentifiedNode.list(children)) { child in
            NodeView(node: child.node, send: send)
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
    @Environment(\.stackbarSnapshot) private var snapshot

    var body: some View {
        // Filtered and flattened once for this pass; the filter scores every
        // row, and the list, the selection and the numbers all need it.
        let visible = RowFilter.filter(children, query: query)
        let rows = visible.flatMap(\.rows)
        let selected = Self.selected(in: rows, key: selectedKey)
        VStack(alignment: .leading, spacing: 2) {
            if searchable && snapshot {
                SnapshotField(placeholder: "Filter", text: "").padding(.bottom, 4)
            } else if searchable {
                TextField("Filter", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.bottom, 4)
                    .focused($focused)
                    .onSubmit { runSelected() }
                    .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
                    .onChange(of: query) { _, _ in select(self.rows.first?.key) }
            }
            ForEach(IdentifiedNode.list(visible)) { child in
                NodeView(node: child.node, send: send)
            }
            if visible.isEmpty && !query.isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            }
            if searchable, !readOnly, let preview = selected?.preview {
                PreviewPane(preview: preview)
            }
        }
        .environment(\.stackbarSelectedRow, searchable && !readOnly ? selected?.key : nil)
        .environment(\.stackbarRowNumbers, searchable && !readOnly ? Self.numbers(of: rows) : [:])
        .onAppear { reset() }
        .onChange(of: shownCount) { _, _ in reset() }
    }

    /// What is shown now, for the key handlers, which run outside a pass.
    private var rows: [RowNode] { RowFilter.filter(children, query: query).flatMap(\.rows) }

    /// The first nine rows that do something, numbered from 1.
    private static func numbers(of rows: [RowNode]) -> [String: Int] {
        let actionable = rows.filter { !$0.actions.isEmpty }.prefix(9)
        return Dictionary(actionable.enumerated().map { ($1.key, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    }

    /// The chosen row, or the first one when nothing (still visible) is.
    private static func selected(in rows: [RowNode], key: String?) -> RowNode? {
        rows.first { $0.key == key } ?? rows.first
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
        let current = rows.firstIndex { $0.key == Self.selected(in: rows, key: selectedKey)?.key } ?? 0
        select(rows[min(max(current + delta, 0), rows.count - 1)].key)
    }

    private func runSelected() {
        guard !readOnly, let action = Self.selected(in: rows, key: selectedKey)?.actions.first else { return }
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
        let rows = rows
        let candidates = (Self.selected(in: rows, key: selectedKey).map { [$0] } ?? []) + rows
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

/// The selected row's view, full text or image, under a searchable list.
struct PreviewPane: View {
    let preview: RowPreview
    @Environment(\.stackbarImageData) private var imageData
    @Environment(\.stackbarSnapshot) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            #if canImport(AppKit)
            // Kept images are named by their content, so the id keys the decode.
            if let id = preview.imageID, let image = DecodedImages.image(key: "kept|\(id)", data: { imageData?(id) }) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            #endif
            if let view = preview.shownView {
                Group {
                    if snapshot {
                        PreviewNodeView(node: view)
                    } else {
                        ScrollView { PreviewNodeView(node: view) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
            } else if let text = preview.text, !text.isEmpty {
                // ImageRenderer draws a scroll view empty, so a snapshot shows
                // the first lines instead.
                Group {
                    if snapshot {
                        Text(text).lineLimit(8)
                    } else {
                        ScrollView {
                            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: 140, alignment: .topLeading)
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

/// A row preview's view (protocol 29), drawn display-only: nothing in it
/// takes focus from the search field or sends anything, and controls show
/// disabled as on a widget. The row's actions and ⌘K are how to act.
public struct PreviewNodeView: View {
    let node: ViewNode

    public init(node: ViewNode) {
        self.node = node
    }

    public var body: some View {
        NodeView(node: node) { _, _ in }
            .environment(\.stackbarReadOnly, true)
            .environment(\.stackbarWidgetButton, nil)
            .environment(\.stackbarSelectedRow, nil)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A row action's shortcut (`cmd+return`, `cmd+1`, `cmd+shift+k`) matched
/// against a key press. `KeyCombo` reads the spec.
public struct KeyShortcut: Equatable {
    public var key: KeyEquivalent
    public var modifiers: EventModifiers

    public init?(_ spec: String) {
        guard let combo = KeyCombo(spec) else { return nil }
        var modifiers: EventModifiers = []
        for modifier in combo.modifiers {
            switch modifier {
            case .command: modifiers.insert(.command)
            case .shift: modifiers.insert(.shift)
            case .option: modifiers.insert(.option)
            case .control: modifiers.insert(.control)
            }
        }
        switch combo.key {
        case .character(let character): key = KeyEquivalent(character)
        case .return: key = .return
        case .delete: key = .delete
        case .forwardDelete: key = .deleteForward
        case .escape: key = .escape
        case .space: key = .space
        case .tab: key = .tab
        case .up: key = .upArrow
        case .down: key = .downArrow
        case .left: key = .leftArrow
        case .right: key = .rightArrow
        // SwiftUI has no key equivalent for F-keys; a row can't use one.
        case .function: return nil
        }
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
    @Environment(\.stackbarWidgetButton) private var widgetButton

    private var highlight: Color {
        if selectedRow == row.key { return Color.accentColor.opacity(0.22) }
        return hovering && !row.actions.isEmpty && !readOnly ? Color.primary.opacity(0.08) : .clear
    }

    public var body: some View {
        if readOnly, let widgetButton, let primary = row.actions.first, primary.navigate == nil {
            widgetButton.make(primary.id, nil, true, AnyView(content))
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            if row.appIcon != nil || row.fileIcon != nil {
                LookupIcon(appIcon: row.appIcon, fileIcon: row.fileIcon) { icon in
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } placeholder: {
                    if let symbol = row.symbol {
                        Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
                    } else {
                        Color.clear.frame(width: 18, height: 18)
                    }
                }
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
    /// A styled foreground, which colors the marks in place of the role.
    var tint: Color? = nil

    /// The series color: the styled foreground, else the role's.
    private var main: Color { tint ?? role.color }

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
        index == 0 ? main : Self.palette[(index - 1) % Self.palette.count]
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
        if options.compact == true, kind != .donut, kind != .heatmap {
            sparkline
        } else {
            full
        }
    }

    /// Marks alone, filling the frame, with the latest value dotted.
    private var sparkline: some View {
        Chart {
            ForEach(points) { point in
                if kind == .bar {
                    BarMark(x: .value("Point", String(point.index)), y: .value("Value", point.value))
                        .foregroundStyle(point.index == values.count - 1 ? main : main.opacity(0.45))
                        .cornerRadius(2)
                } else {
                    if kind == .area {
                        AreaMark(x: .value("Point", point.index), y: .value("Value", point.value))
                            .foregroundStyle(LinearGradient(colors: [main.opacity(0.4), main.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("Point", point.index), y: .value("Value", point.value))
                        .foregroundStyle(main)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            if kind != .bar, let last = points.last {
                PointMark(x: .value("Point", last.index), y: .value("Value", last.value))
                    .foregroundStyle(main)
                    .symbolSize(28)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text([label, summary].compactMap { $0 }.joined(separator: ", ")))
    }

    private var full: some View {
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
            case .heatmap: HeatmapView(values: values, names: options.labels ?? [], unit: options.unit ?? "", color: main)
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
                        .foregroundStyle(options.highlight == nil || options.highlight == point.index ? main : main.opacity(0.4))
                        .cornerRadius(3)
                } else if kind == .area {
                    AreaMark(x: .value("Point", point.index), y: .value("Value", point.value))
                        .foregroundStyle(LinearGradient(colors: [main.opacity(0.35), main.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Point", point.index), y: .value("Value", point.value))
                        .foregroundStyle(main)
                        .interpolationMethod(.monotone)
                } else {
                    LineMark(x: .value("Point", point.index), y: .value("Value", point.value))
                        .foregroundStyle(main)
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
                    .foregroundStyle(main)
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
            .onSubmit {
                send(action, .text(draft))
                // Back to what the plugin last said: empty for an add field,
                // so the next entry starts fresh. A plugin that keeps the
                // text sends it back and onChange restores it.
                draft = text
            }
            .onAppear { draft = text }
            .onChange(of: text) { _, newValue in draft = newValue }
    }
}

/// A `clock` node: the time in its pattern, redrawn on the second or on the
/// minute by SwiftUI's timeline, never by the plugin.
struct ClockText: View {
    let face: ClockFace

    var body: some View {
        let formatter = face.formatter()
        if face.showsSeconds {
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down)), by: 1)) { context in
                Text(formatter.string(from: context.date))
            }
        } else {
            TimelineView(.everyMinute) { context in
                Text(formatter.string(from: context.date))
            }
        }
    }
}

/// A slider that sends its value when the user lets go, not on every pixel.
/// A live one also sends while it is dragged, at most every 30 ms, and holds
/// the thumb where the pointer is while the plugin's answers catch up.
struct SliderNodeView: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let action: ActionID
    var live = false
    let send: SendAction
    @State private var current = 0.0
    @State private var dragging = false
    @State private var lastSent: (value: Double, at: Date)?

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
        .onChange(of: value) { _, newValue in if !dragging { current = newValue } }
        .onChange(of: current) { _, newValue in
            guard live, dragging else { return }
            let now = Date()
            if let last = lastSent, last.value == newValue || now.timeIntervalSince(last.at) < 0.03 { return }
            lastSent = (newValue, now)
            send(action, .number(newValue))
        }
    }

    private func commit(_ editing: Bool) {
        dragging = editing
        if !editing {
            lastSent = nil
            send(action, .number(current))
        }
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
    var track: Color = .secondary.opacity(0.25)

    var body: some View {
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
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
///
/// `icon` and `fileIcon` look up at once, on the caller's thread, for
/// snapshots (which can't wait). A row on screen uses `cached` and `load`
/// (see `LookupIcon`): the Workspace lookup and the bitmap are done off the
/// main thread, so the first draw of a list of many apps doesn't stall.
@MainActor
public enum AppIcons {
    private static var cache: [String: NSImage?] = [:]
    private static var files: [String: NSImage] = [:]

    /// A picture handed from the task that drew it; it is not touched again there.
    private struct Drawn: @unchecked Sendable {
        let image: NSImage?
    }

    /// A file or folder's Finder icon, kept for the next draw.
    public static func fileIcon(_ path: String) -> NSImage {
        if let cached = files[path] { return cached }
        if files.count > 500 { files = [:] }
        let image = flattened(NSWorkspace.shared.icon(forFile: path))
        files[path] = image
        return image
    }

    public static func icon(_ bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let image = renderApp(bundleID)
        cache[bundleID] = image
        return image
    }

    /// The icon if it was looked up before; nothing is fetched.
    public static func cached(appIcon: String?, fileIcon path: String?) -> NSImage? {
        // A remembered miss (`.some(nil)`) is not an answer: the file icon
        // is still tried.
        if let appIcon, let known = cache[appIcon], let image = known { return image }
        if let path, let known = files[path] { return known }
        return nil
    }

    /// The icon of the app or file, looked up off the main thread and kept.
    /// An app wins when both are named, as in a row. Nil when there is none.
    public static func load(appIcon: String?, fileIcon path: String?) async -> NSImage? {
        if let appIcon {
            // A remembered miss (`.some(nil)`) falls through to the file icon.
            var image: NSImage?
            if let known = cache[appIcon] {
                image = known
            } else {
                let drawn = await Task.detached(priority: .userInitiated) { Drawn(image: renderApp(appIcon)) }.value
                cache[appIcon] = drawn.image
                image = drawn.image
            }
            if let image { return image }
        }
        guard let path else { return nil }
        if let known = files[path] { return known }
        let drawn = await Task.detached(priority: .userInitiated) { Drawn(image: renderFile(path)) }.value
        if files.count > 500 { files = [:] }
        files[path] = drawn.image
        return drawn.image
    }

    private nonisolated static func renderApp(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { url in
            flattened(NSWorkspace.shared.icon(forFile: url.path))
        }
    }

    private nonisolated static func renderFile(_ path: String) -> NSImage {
        flattened(NSWorkspace.shared.icon(forFile: path))
    }

    /// The icon drawn once into a plain bitmap. Workspace icons are lazy,
    /// many-sized images that `ImageRenderer` draws as a grey veil over the
    /// whole snapshot; a bitmap draws like any other picture.
    private nonisolated static func flattened(_ icon: NSImage) -> NSImage {
        let points = NSSize(width: 32, height: 32)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            icon.size = points
            return icon
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = points
        let image = NSImage(size: points)
        image.addRepresentation(bitmap)
        return image
    }
}

/// A row's app or file icon, drawn when it is known and `placeholder` until
/// then, so a list of many apps appears at once and the icons fill in. A
/// snapshot looks the icon up at once: it draws a single frame.
public struct LookupIcon<Icon: View, Placeholder: View>: View {
    let appIcon: String?
    let fileIcon: String?
    let icon: (NSImage) -> Icon
    let placeholder: Placeholder
    @State private var loaded: NSImage?
    @Environment(\.stackbarSnapshot) private var snapshot

    public init(appIcon: String?, fileIcon: String?, @ViewBuilder icon: @escaping (NSImage) -> Icon, @ViewBuilder placeholder: () -> Placeholder) {
        self.appIcon = appIcon
        self.fileIcon = fileIcon
        self.icon = icon
        self.placeholder = placeholder()
    }

    public var body: some View {
        Group {
            if let image = known {
                icon(image)
            } else {
                placeholder
            }
        }
        .task(id: "\(appIcon ?? "")|\(fileIcon ?? "")") {
            guard !snapshot, AppIcons.cached(appIcon: appIcon, fileIcon: fileIcon) == nil else { return }
            loaded = await AppIcons.load(appIcon: appIcon, fileIcon: fileIcon)
        }
    }

    private var known: NSImage? {
        if snapshot { return appIcon.flatMap(AppIcons.icon) ?? fileIcon.map(AppIcons.fileIcon) }
        return AppIcons.cached(appIcon: appIcon, fileIcon: fileIcon) ?? loaded
    }
}
#endif

#endif
