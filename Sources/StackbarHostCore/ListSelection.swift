/// Which line of a filtered list the keyboard is on.
///
/// It holds the line's id, not its position: a list that reorders under the
/// user (a plugin re-rendered, a search came back) keeps the same line
/// selected, and a list that no longer has it falls back to its first line.
/// A selection belongs to the query it was made under, so typing starts again
/// on the first line. The palette's root and its command views both use it,
/// as the panel's filter field does by key.
public struct ListSelection: Equatable, Sendable {
    public private(set) var id: String?
    private var query = ""

    public init() {}

    /// The selected id among `ids`: the chosen one while it is still listed
    /// under the same query, otherwise the first.
    public func selected(in ids: [String], query: String) -> String? {
        if let id, self.query == query, ids.contains(id) { return id }
        return ids.first
    }

    /// The position of `selected(in:query:)`, for an index into the list.
    public func index(in ids: [String], query: String) -> Int? {
        selected(in: ids, query: query).flatMap { ids.firstIndex(of: $0) }
    }

    /// Up or down from the selected line, stopping at either end.
    public mutating func move(_ delta: Int, in ids: [String], query: String) {
        guard !ids.isEmpty else { return }
        let current = index(in: ids, query: query) ?? 0
        select(ids[min(max(current + delta, 0), ids.count - 1)], query: query)
    }

    public mutating func select(_ id: String?, query: String) {
        self.id = id
        self.query = query
    }

    /// Back to the first line.
    public mutating func reset() {
        id = nil
        query = ""
    }
}
