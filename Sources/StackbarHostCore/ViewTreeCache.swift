import Foundation
import StackbarProtocol

/// The last list each view command showed, by the query it opened with, so
/// opening it again draws those rows at once while the plugin searches
/// (Raycast keeps a command's last data the same way). It lives in memory
/// only and keeps a few commands: a list can be large.
public struct ViewTreeCache: Sendable {
    public struct Key: Hashable, Sendable {
        public var command: CommandKey
        public var text: String
        public var arguments: [String: String]

        public init(command: CommandKey, query: CommandQuery) {
            self.command = command
            text = query.text
            arguments = query.arguments
        }
    }

    public let capacity: Int
    private var trees: [Key: ViewNode] = [:]
    /// Oldest first.
    private var order: [Key] = []

    public init(capacity: Int = 8) {
        self.capacity = capacity
    }

    /// The tree to draw while `key` opens, if one was kept.
    public mutating func tree(for key: Key) -> ViewNode? {
        guard let tree = trees[key] else { return nil }
        touch(key)
        return tree
    }

    /// Keeps an answer. Only lists with rows are kept: a form or a detail
    /// drawn from old data would mislead, and an empty list shows nothing.
    public mutating func remember(_ root: ViewNode, for key: Key) {
        guard !root.rows.isEmpty, !Self.hasForm(root) else {
            forget(key)
            return
        }
        trees[key] = root
        touch(key)
        while order.count > capacity { trees[order.removeFirst()] = nil }
    }

    public mutating func forget(_ key: Key) {
        trees[key] = nil
        order.removeAll { $0 == key }
    }

    /// Drops every tree of a plugin (it was updated or removed).
    public mutating func forget(pluginID: String) {
        for key in order where key.command.pluginID == pluginID { trees[key] = nil }
        order.removeAll { $0.command.pluginID == pluginID }
    }

    public var count: Int { trees.count }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private static func hasForm(_ node: ViewNode) -> Bool {
        if case .form = node { return true }
        return node.children.contains(where: hasForm)
    }
}
