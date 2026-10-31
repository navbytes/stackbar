import StackbarProtocol

/// The command palette's entries: everything a user can do across every
/// plugin, found by typing.
///
/// Entries come from what plugins already render on their panels (rows'
/// actions, buttons, toggles, links), so a plugin gets palette support without
/// writing anything for it. `SurfaceParity`'s palette column says the same.
public struct PaletteIndex: Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public enum Kind: Equatable, Sendable {
            case action(ActionID, value: EventValue?)
            case open(String)
        }

        public var pluginID: String
        public var pluginName: String
        public var title: String
        public var subtitle: String?
        public var symbol: String?
        public var kind: Kind

        public var id: String {
            switch kind {
            case .action(let action, _): return "\(pluginID)|\(action.rawValue)"
            case .open(let url): return "\(pluginID)|open|\(url)"
            }
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// Replaces one plugin's entries with those found in its panel tree.
    public mutating func update(pluginID: String, pluginName: String, panel: ViewNode?) {
        entries.removeAll { $0.pluginID == pluginID }
        guard let panel else { return }
        entries += Self.entries(in: panel, pluginID: pluginID, pluginName: pluginName)
    }

    public mutating func remove(pluginID: String) {
        entries.removeAll { $0.pluginID == pluginID }
    }

    /// Entries matching `query`, best first. An empty query lists everything
    /// in plugin order.
    public func search(_ query: String, limit: Int = 50) -> [Entry] {
        let query = query.lowercased().filter { !$0.isWhitespace }
        guard !query.isEmpty else { return Array(entries.prefix(limit)) }
        return entries
            .compactMap { entry -> (Entry, Int)? in
                let haystacks = [entry.title, entry.subtitle ?? "", entry.pluginName]
                let best = haystacks.enumerated().compactMap { index, text in
                    Self.score(query, in: text.lowercased()).map { $0 - index * 5 }
                }.max()
                return best.map { (entry, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    static func entries(in node: ViewNode, pluginID: String, pluginName: String) -> [Entry] {
        func entry(_ title: String, _ subtitle: String?, _ symbol: String?, _ kind: Entry.Kind) -> Entry {
            Entry(pluginID: pluginID, pluginName: pluginName, title: title, subtitle: subtitle, symbol: symbol, kind: kind)
        }
        switch node {
        case .row(let row):
            return row.actions.enumerated().map { index, action in
                let title = index == 0 ? row.title : "\(action.title): \(row.title)"
                return entry(title, row.subtitle ?? (index == 0 ? action.title : nil), row.symbol, .action(action.id, value: nil))
            }
        case .button(let title, let symbol, _, let action):
            return [entry(title, nil, symbol, .action(action, value: nil))]
        case .toggle(let title, let isOn, let action):
            return [entry("\(isOn ? "Turn off" : "Turn on") \(title)", nil, isOn ? "switch.2" : "switch.2", .action(action, value: .bool(!isOn)))]
        case .link(let title, let url):
            return [entry(title, url, "link", .open(url))]
        case .stack(_, _, let children), .list(_, let children), .section(_, let children):
            return children.flatMap { entries(in: $0, pluginID: pluginID, pluginName: pluginName) }
        case .text, .label, .badge, .progress, .divider, .labeled, .chart, .textField, .picker, .slider, .empty:
            return []
        }
    }

    /// Subsequence match with bonuses for word starts and runs; `nil` when
    /// the letters don't appear in order.
    static func score(_ query: String, in text: String) -> Int? {
        TextMatch.score(query, in: text)
    }
}
