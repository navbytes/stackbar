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
        NodeView(node: node.trimmed(maxRows: maxRows), send: { _, _ in })
            .environment(\.stackbarReadOnly, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
    }
}
#endif
