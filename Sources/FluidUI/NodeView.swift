#if canImport(SwiftUI)
import Charts
import SwiftUI
import FluidProtocol

/// Sends a plugin's action back to it: a click, a toggle, a submitted field.
public typealias SendAction = @MainActor (ActionID, EventValue?) -> Void

extension EnvironmentValues {
    /// Widgets draw controls but can't act on them.
    @Entry public var fluidReadOnly: Bool = false
}

/// Draws one `ViewNode` for the panel and window surfaces. Every case of the
/// vocabulary is handled here; the switch has no `default`, so a new node type
/// will not compile until the panel knows how to draw it (and
/// `SurfaceParity` says what every other surface does with it).
public struct NodeView: View {
    let node: ViewNode
    let send: SendAction
    @Environment(\.fluidReadOnly) private var readOnly

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
            ProgressView(value: clamp(value, total), total: max(total, .leastNonzeroMagnitude)) {
                if let label { Text(label).font(.caption) }
            }
            .tint(role.color)
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
struct ListNodeView: View {
    let searchable: Bool
    let children: [ViewNode]
    let send: SendAction
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if searchable {
                TextField("Filter", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.bottom, 4)
            }
            ForEach(Array(visible.enumerated()), id: \.offset) { _, child in
                NodeView(node: child, send: send)
            }
            if visible.isEmpty && !query.isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            }
        }
    }

    private var visible: [ViewNode] {
        RowFilter.filter(children, query: query)
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
    @Environment(\.fluidReadOnly) private var readOnly

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
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering && !row.actions.isEmpty && !readOnly ? Color.primary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard !readOnly, let primary = row.actions.first else { return }
            send(primary.id, nil)
        }
        .contextMenu {
            if !readOnly {
                ForEach(row.actions, id: \.id) { action in
                    Button(action.title, role: action.role == .critical ? .destructive : nil) { send(action.id, nil) }
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
            ProgressView(value: min(max(value, 0), max(total, 0)), total: max(total, .leastNonzeroMagnitude))
                .tint(role.color)
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
#endif
