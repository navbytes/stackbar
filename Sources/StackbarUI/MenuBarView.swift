#if canImport(SwiftUI)
import SwiftUI
import StackbarProtocol

/// The menu-bar surface: the whole tree drawn compactly on one line.
///
/// Text, labels, badges, labeled values, progress, charts, symbols and timers are shown;
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
            if let node, !node.isBlankInMenuBar {
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
        .foregroundStyle(MenuBarView.tint(fallback.role))
    }

    /// Menu-bar colors. The bar is translucent over the wallpaper, so the
    /// accent blue (and green) disappeared on it; "on" and "fine" now draw in
    /// the bar's own color, and a plugin shows an active state with its
    /// symbol (a filled cup, say). Only warning and critical keep a color,
    /// because those should catch the eye.
    public static func tint(_ role: Role) -> Color {
        switch role {
        case .primary, .accent, .success: return .primary
        case .secondary: return .secondary
        case .warning, .critical: return role.color
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
        case .progress(let value, let total, _, let role, _, let timing):
            TimedFraction(value: value, total: total, timing: timing) { fraction in
                RingView(fraction: fraction, paint: AnyShapeStyle(tint(role)), lineWidth: 2, track: Color.primary.opacity(0.25))
            }
            .frame(width: 12, height: 12)
        case .chart(let values, _, _, let role, _):
            Sparkline(values: values).stroke(tint(role), lineWidth: 1.25).frame(width: 32, height: 12)
        case .empty(let title, let symbol, _):
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
        case .stack(.depth, _, _, let children):
            ZStack { visible(children) }
        case .stack(_, _, _, let children):
            HStack(spacing: 4) { visible(children) }
        case .styled(let child, _):
            MenuBarNode(node: child)
        case .image(.symbol(let symbol)):
            Image(systemName: symbol)
        case .timer(let range, let countsDown):
            Text(timerInterval: range.start...range.end, countsDown: countsDown).font(.system(size: 13).monospacedDigit())
        case .list, .section, .row, .button, .toggle, .divider, .textField, .picker, .slider, .link, .form, .shape, .spacer, .tappable:
            EmptyView()
        }
    }

    private func tint(_ role: Role) -> Color { MenuBarView.tint(role) }

    private func visible(_ children: [ViewNode]) -> some View {
        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
            if !child.isBlankInMenuBar { MenuBarNode(node: child) }
        }
    }
}
#endif
