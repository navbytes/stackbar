import Foundation
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
            /// A row action that opens one of the plugin's commands.
            case navigate(CommandTarget)
            /// One of the plugin's declared commands.
            case command(CommandSpec)
            /// Opens the panel of a plugin that has no menu-bar item.
            case showPanel
            /// Copies the text: a calculator answer.
            case copy(String)
        }

        public var pluginID: String
        public var pluginName: String
        public var title: String
        public var subtitle: String?
        public var symbol: String?
        public var kind: Kind
        /// More words it is found by (a command's keywords).
        public var keywords: [String] = []
        /// The alias the user gave the command, shown on its row.
        public var alias: String?
        /// An app's bundle id or a file's path, whose icon the row shows: a
        /// root-search row's `appIcon` and `fileIcon`.
        public var appIcon: String?
        public var fileIcon: String?
        /// A stable id for what this row stands for, when `id` isn't one: a
        /// plugin's root-search row (`plugin|row|command|rowKey`), whose
        /// action ids change with every answer.
        public var rankKey: String?

        /// The id that use and learned picks are kept under.
        public var learnID: String { rankKey ?? id }

        public init(pluginID: String, pluginName: String, title: String, subtitle: String? = nil, symbol: String? = nil, kind: Kind,
                    keywords: [String] = [], alias: String? = nil) {
            self.pluginID = pluginID
            self.pluginName = pluginName
            self.title = title
            self.subtitle = subtitle
            self.symbol = symbol
            self.kind = kind
            self.keywords = keywords
            self.alias = alias
        }

        /// `typed` (lowercased, trimmed) is its whole title or one of its keywords.
        public func isExactMatch(_ typed: String) -> Bool {
            !typed.isEmpty && (title.lowercased() == typed || keywords.contains { $0.lowercased() == typed })
        }

        public var commandKey: CommandKey? {
            if case .command(let spec) = kind { return CommandKey(pluginID: pluginID, commandID: spec.id) }
            return nil
        }

        /// A command's id, as its palette row and its use are kept under,
        /// whether it ran from the palette or from a hotkey.
        public static func commandID(_ key: CommandKey) -> String { key.description }

        public var id: String {
            switch kind {
            case .action(let action, _): return "\(pluginID)|\(action.rawValue)"
            case .open(let url): return "\(pluginID)|open|\(url)"
            case .navigate(let target): return "\(pluginID)|navigate|\(target.command)|\(target.arguments.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))"
            case .command(let spec): return Self.commandID(CommandKey(pluginID: pluginID, commandID: spec.id))
            case .showPanel: return "\(pluginID)|panel"
            case .copy(let text): return "\(pluginID)|copy|\(text)"
            }
        }
    }

    /// Entries derived from panels (rows, buttons, toggles, links).
    public private(set) var entries: [Entry] = []
    /// Declared commands, listed before panel entries.
    public private(set) var commands: [Entry] = []
    /// "Open <Plugin>" for plugins without a menu-bar item.
    public private(set) var panels: [Entry] = []
    /// Goes up each time the entries change, so a search can be kept until
    /// then.
    public private(set) var revision = 0
    /// Lists Stackbar's own places (`appEntries`): on in the app.
    public var includesAppEntries = false

    public init(includesAppEntries: Bool = false) {
        self.includesAppEntries = includesAppEntries
    }

    /// Replaces one plugin's entries with those found in its panel tree,
    /// where its old ones were, so a plugin that re-renders doesn't move its
    /// entries behind everyone else's. False when nothing changed: a panel
    /// that re-renders the same affordances (a clock ticking) leaves the
    /// index, and an open palette, alone.
    @discardableResult
    public mutating func update(pluginID: String, pluginName: String, panel: ViewNode?) -> Bool {
        let found = panel.map { Self.entries(in: $0, pluginID: pluginID, pluginName: pluginName) } ?? []
        let start = entries.firstIndex { $0.pluginID == pluginID }
        guard entries.filter({ $0.pluginID == pluginID }) != found else { return false }
        entries.removeAll { $0.pluginID == pluginID }
        entries.insert(contentsOf: found, at: start ?? entries.endIndex)
        revision += 1
        return true
    }

    public mutating func remove(pluginID: String) {
        entries.removeAll { $0.pluginID == pluginID }
        commands.removeAll { $0.pluginID == pluginID }
        panels.removeAll { $0.pluginID == pluginID }
        revision += 1
    }

    /// The plugins whose panel opens from the palette, not the menu bar.
    public mutating func setHeadlessPanels(_ plugins: [(pluginID: String, name: String)]) {
        panels = plugins.map { Entry(pluginID: $0.pluginID, pluginName: $0.name, title: "Open \($0.name)", symbol: "macwindow", kind: .showPanel) }
        revision += 1
    }

    /// Replaces the command entries with the registry's enabled commands.
    public mutating func setCommands(_ registry: [CommandRegistry.Entry], preferences: [CommandKey: CommandPreference]) {
        commands = registry.compactMap { item in
            let preference = preferences[item.key] ?? .default
            guard preference.enabled else { return nil }
            var entry = Entry(pluginID: item.pluginID, pluginName: item.pluginName, title: item.spec.title, subtitle: item.spec.subtitle, symbol: item.spec.symbol, kind: .command(item.spec))
            entry.keywords = item.spec.keywords
            entry.alias = preference.alias
            return entry
        }
        revision += 1
    }

    /// Commands first, then Stackbar's own places, then panels to open,
    /// then panel entries. Each id once:
    /// a list keyed by id (the palette's) can't draw or select a duplicate,
    /// and two links to one URL are one thing to do.
    public var all: [Entry] {
        var seen = Set<String>()
        return (commands + (includesAppEntries ? Self.appEntries : []) + panels + entries).filter { seen.insert($0.id).inserted }
    }

    /// Entries matching `query`, best first, by `PaletteRanker`: an exact
    /// alias, then the text's tier, then what was picked for this text and
    /// what is used often. An empty query lists the most used first, then
    /// everything in plugin order.
    public func search(_ query: String, limit: Int = 50, usage: PaletteUsage? = nil, picks: PalettePicks? = nil) -> [Entry] {
        scored(query, limit: limit, ranker: PaletteRanker(query: query, usage: usage, picks: picks), usage: usage).map(\.entry)
    }

    /// `search` with each entry's score, for ranking it against plugins'
    /// rows. Empty-query scores are 0.
    public func scored(_ query: String, limit: Int = 50, ranker: PaletteRanker, usage: PaletteUsage? = nil) -> [(entry: Entry, score: Int)] {
        scored(query, limit: limit, ranker: ranker, usage: usage, in: all)
    }

    /// `scored` over `all`, for a caller that already has it.
    func scored(_ query: String, limit: Int, ranker: PaletteRanker, usage: PaletteUsage?, in all: [Entry]) -> [(entry: Entry, score: Int)] {
        guard !ranker.typed.isEmpty else {
            guard let usage else { return all.prefix(limit).map { ($0, 0) } }
            let used = all.map { usage.score($0.learnID) }
            return all.enumerated()
                .sorted { (used[$0.offset], -$0.offset) > (used[$1.offset], -$1.offset) }
                .prefix(limit)
                .map { ($0.element, 0) }
        }
        return all.enumerated()
            .compactMap { offset, entry in ranker.score(entry).map { (entry, $0, offset) } }
            // Ties keep the index's order, so the list doesn't reshuffle.
            .sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
            .prefix(limit)
            .map { ($0.0, $0.1) }
    }

    /// `gh react` → the command aliased `gh` and the rest of the line, which
    /// fills its first argument (or its view's query).
    public func aliasMatch(_ query: String) -> (entry: Entry, rest: String)? {
        let query = query.drop { $0 == " " }
        guard let space = query.firstIndex(of: " ") else { return nil }
        let alias = query[..<space].lowercased()
        guard !alias.isEmpty, let entry = commands.first(where: { $0.alias == alias }) else { return nil }
        return (entry, String(query[query.index(after: space)...]).trimmingCharacters(in: .whitespaces))
    }

    /// The tree's affordances the palette can press on its own: not inputs,
    /// which need their control, nor what a tappable wraps, nor a tappable
    /// with no words to find it by.
    static func entries(in node: ViewNode, pluginID: String, pluginName: String) -> [Entry] {
        node.affordances.compactMap { affordance in
            guard !affordance.isInsideTappable else { return nil }
            let kind: Entry.Kind
            switch affordance.kind {
            case .action(let action, let value):
                kind = .action(action, value: value)
            case .tappable(let action):
                guard !affordance.title.isEmpty else { return nil }
                kind = .action(action, value: nil)
            case .open(let url):
                kind = .open(url)
            case .navigate(let target, _):
                kind = .navigate(target)
            case .input:
                return nil
            }
            return Entry(pluginID: pluginID, pluginName: pluginName, title: affordance.title, subtitle: affordance.subtitle, symbol: affordance.symbol, kind: kind)
        }
    }

    /// Subsequence match with bonuses for word starts and runs; `nil` when
    /// the letters don't appear in order.
    static func score(_ query: String, in text: String) -> Int? {
        TextMatch.score(query, in: text)
    }
}
