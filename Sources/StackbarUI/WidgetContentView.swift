#if canImport(SwiftUI)
import SwiftUI
import StackbarProtocol

/// The widget surface: the tree drawn read-only, clipped to the widget, with
/// lists cut to what fits. Shared by the widget extension and snapshots.
public struct WidgetContentView: View {
    let node: ViewNode
    let maxRows: Int

    public init(node: ViewNode, maxRows: Int = 4) {
        self.node = node
        self.maxRows = maxRows
    }

    public var body: some View {
        NodeView(node: WidgetContentView.trimmed(node, maxRows: maxRows), send: { _, _ in })
            .environment(\.stackbarReadOnly, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
    }

    /// Lists keep their first `maxRows` children; controls stay but are
    /// disabled by `stackbarReadOnly`.
    public static func trimmed(_ node: ViewNode, maxRows: Int) -> ViewNode {
        switch node {
        case .list(_, let children):
            return .list(searchable: false, children: Array(children.prefix(maxRows)).map { trimmed($0, maxRows: maxRows) })
        case .stack(let axis, let spacing, let children):
            return .stack(axis: axis, spacing: spacing, children: children.map { trimmed($0, maxRows: maxRows) })
        case .section(let title, let children):
            return .section(title: title, children: children.map { trimmed($0, maxRows: maxRows) })
        default:
            return node
        }
    }
}
#endif
