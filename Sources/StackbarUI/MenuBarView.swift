#if canImport(SwiftUI)
import SwiftUI
import StackbarProtocol

/// The menu-bar surface: the whole tree drawn compactly on one line.
///
/// Text, labels, badges, labeled values, progress and charts are shown;
/// controls and lists are not, because a click on the status item opens the
/// panel, where they live. `SurfaceParity` records the same choices.
public struct MenuBarView: View {
    let node: ViewNode?
    let fallback: (title: String, symbol: String?, role: Role)

    public init(node: ViewNode?, fallbackTitle: String, fallbackSymbol: String? = "puzzlepiece.extension", fallbackRole: Role = .primary) {
        self.node = node
        self.fallback = (fallbackTitle, fallbackSymbol, fallbackRole)
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let node, !MenuBarView.isBlank(node) {
                MenuBarNode(node: node)
            } else {
                if let symbol = fallback.symbol { Image(systemName: symbol) }
                if !fallback.title.isEmpty { Text(fallback.title) }
            }
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 4)
        .foregroundStyle(fallback.role == .primary ? Color.primary : fallback.role.color)
    }

    /// True when nothing in the tree has a menu-bar form.
    public static func isBlank(_ node: ViewNode) -> Bool {
        switch node {
        case .text, .label, .badge, .progress, .labeled, .chart, .empty:
            return false
        case .stack(_, _, let children):
            return children.allSatisfy(isBlank)
        case .list, .section, .row, .button, .toggle, .divider, .textField, .picker, .slider, .link:
            return true
        }
    }
}

struct MenuBarNode: View {
    let node: ViewNode

    var body: some View {
        switch node {
        case .text(let string, let style, let role):
            Text(string).font(style == .monospaced ? .system(size: 13, design: .monospaced) : .system(size: 13)).foregroundStyle(tint(role))
        case .label(let title, let symbol, let role):
            HStack(spacing: 3) {
                Image(systemName: symbol)
                if !title.isEmpty { Text(title) }
            }
            .foregroundStyle(tint(role))
        case .badge(let text, let role):
            Text(text).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 4).background(Capsule().fill(role.color.opacity(0.25)))
        case .labeled(let label, let value, let role):
            HStack(spacing: 2) {
                Text(label).foregroundStyle(.secondary)
                Text(value).foregroundStyle(tint(role))
            }
        case .progress(let value, let total, _, let role):
            let fraction = total > 0 ? min(1, max(0, value / total)) : 0
            ZStack {
                Circle().stroke(Color.primary.opacity(0.25), lineWidth: 2)
                Circle().trim(from: 0, to: fraction).stroke(tint(role), style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
        case .chart(let values, _, _, let role):
            Sparkline(values: values).stroke(tint(role), lineWidth: 1.25).frame(width: 32, height: 12)
        case .empty(let title, let symbol, _):
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
        case .stack(_, _, let children):
            HStack(spacing: 4) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    if !MenuBarView.isBlank(child) { MenuBarNode(node: child) }
                }
            }
        case .list, .section, .row, .button, .toggle, .divider, .textField, .picker, .slider, .link:
            EmptyView()
        }
    }

    /// The menu bar keeps the system's own color for primary content so it
    /// follows the menu bar's appearance.
    private func tint(_ role: Role) -> Color {
        role == .primary ? .primary : role.color
    }
}
#endif
