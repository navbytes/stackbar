import Foundation
import StackbarProtocol

/// The palette's root list for what is typed: every section in the order
/// drawn, and what each row is, which decides what Return, ⌘K and pinning do
/// with it. Built from snapshots, so it is tested on Linux; the palette only
/// keeps the live views the plugin rows come from.
public struct PaletteRoot: Equatable, Sendable {
    /// What a row on the root is.
    public enum Role: Equatable, Sendable {
        /// Found in the index: a command, a panel's action, one of
        /// Stackbar's own places.
        case result
        /// A row a root-search command answered with.
        case pluginRow(PluginRow)
        /// A `.fallback()` command offered for the whole typed text.
        case fallback
        /// A Store plugin that isn't installed.
        case storeSuggestion
        /// A calculator answer to copy.
        case answer
    }

    /// Where a plugin row came from, so the palette can find its live view.
    public struct PluginRow: Equatable, Sendable {
        public var command: CommandKey
        public var rowKey: String
        /// The row's actions; the first is what Return does.
        public var actions: [ActionRef]
    }

    /// What one root-search command shows now: its rows, already filtered
    /// by what was typed.
    public struct PluginRows: Equatable, Sendable {
        public var command: CommandRegistry.Entry
        public var rows: [RowNode]

        public init(command: CommandRegistry.Entry, rows: [RowNode]) {
            self.command = command
            self.rows = rows
        }
    }

    /// Rows from each plugin, at most.
    public static let pluginRowLimit = 3

    public let sections: [PaletteSection]
    private let roles: [String: Role]

    /// Every row in the order drawn, which the arrows walk. Flattened once:
    /// each arrow press and redraw reads it several times.
    public let entries: [PaletteIndex.Entry]

    init(sections: [PaletteSection], roles: [String: Role]) {
        self.sections = sections
        self.roles = roles
        entries = sections.flatMap(\.entries)
    }

    public func role(of entry: PaletteIndex.Entry) -> Role {
        roles[entry.id] ?? .result
    }

    public func pluginRow(_ entry: PaletteIndex.Entry) -> PluginRow? {
        if case .pluginRow(let row) = role(of: entry) { return row }
        return nil
    }

    /// Only what stays put can be pinned: not plugin rows, fallbacks, Store
    /// suggestions or answers, which come and go with the query.
    public func canPin(_ entry: PaletteIndex.Entry) -> Bool {
        role(of: entry) == .result
    }

    /// Whether choosing it teaches the ranking: everything but a Store
    /// suggestion, which isn't something you use.
    public func learns(_ entry: PaletteIndex.Entry) -> Bool {
        role(of: entry) != .storeSuggestion
    }

    /// What Return does to the row, for the footer and ⌘K's first action.
    public func primaryTitle(_ entry: PaletteIndex.Entry) -> String {
        switch role(of: entry) {
        case .pluginRow(let row): return row.actions.first?.title ?? "Open"
        case .storeSuggestion: return "Show in Store"
        case .answer: return "Copy Answer"
        case .result, .fallback:
            switch entry.kind {
            case .command(let spec): return spec.kind == .view || !spec.arguments.isEmpty ? "Open" : "Run"
            case .navigate, .showPanel, .open: return "Open"
            case .action: return "Run"
            case .copy: return "Copy Answer"
            }
        }
    }

    /// The text a command chosen from the root is given: all of it for a
    /// fallback, the rest after an alias (`gh react`), otherwise none.
    public func input(for entry: PaletteIndex.Entry, query: String, index: PaletteIndex) -> String {
        if role(of: entry) == .fallback { return query }
        return index.aliasMatch(query).flatMap { $0.entry.id == entry.id ? $0.rest : nil } ?? ""
    }

    /// Builds the root for `query`.
    ///
    /// - An alias typed with a space (`gh react`) puts its command first,
    ///   unless what was typed is another entry's whole name.
    /// - Before anything is typed the root lists everything (up to 500), so
    ///   Stackbar's own places aren't cut off; a typed query keeps the best 30.
    /// - Each plugin gives its first `pluginRowLimit` rows, as a section
    ///   under its `rootSection` title, or the plugin's name after it when
    ///   another section already has that title.
    /// - `favorites` are pinned ids; `store` are the Store's suggestions;
    ///   `fallbacks` the `.fallback()` commands to offer (none when nothing
    ///   is typed).
    public static func build(query: String, index: PaletteIndex, ranker: PaletteRanker, usage: PaletteUsage? = nil, favorites: [String] = [],
                             store: [PaletteIndex.Entry] = [], plugins: [PluginRows] = [], fallbacks: [CommandRegistry.Entry] = [],
                             isRecent: (PaletteIndex.Entry) -> Bool = { _ in false }) -> PaletteRoot {
        let typed = query.lowercased().trimmingCharacters(in: .whitespaces)
        // `all` rebuilds every entry's id and filters duplicates: once per build.
        let all = index.all
        let scored = index.scored(query, limit: typed.isEmpty ? 500 : 30, ranker: ranker, usage: usage, in: all)
        var found = scored.map(\.entry)
        var resultScore = scored.first?.score
        if let match = index.aliasMatch(query), found.first?.isExactMatch(typed) != true {
            found.removeAll { $0.id == match.entry.id }
            found.insert(match.entry, at: 0)
            resultScore = PaletteRanker.exactAlias
        }

        var roles: [String: Role] = [:]
        var usedTitles = PaletteSection.Kind.fixedTitles
        let pluginSections = plugins.sorted { $0.command.spec.title < $1.command.spec.title }.compactMap { source -> PaletteSection? in
            let command = source.command
            let entries = source.rows.prefix(pluginRowLimit).compactMap { row -> PaletteIndex.Entry? in
                guard let primary = row.actions.first else { return nil }
                let kind: PaletteIndex.Entry.Kind = primary.navigate.map { .navigate($0) } ?? .action(primary.id, value: nil)
                var entry = PaletteIndex.Entry(pluginID: command.pluginID, pluginName: command.pluginName, title: row.title,
                                               subtitle: row.subtitle, symbol: row.symbol ?? command.spec.symbol, kind: kind)
                entry.appIcon = row.appIcon
                entry.fileIcon = row.fileIcon
                // Action ids change with every answer; the row's key doesn't.
                entry.rankKey = "\(command.pluginID)|row|\(command.spec.id)|\(row.key)"
                roles[entry.id] = .pluginRow(PluginRow(command: command.key, rowKey: row.key, actions: row.actions))
                return entry
            }
            guard !entries.isEmpty else { return nil }
            var title = command.spec.rootSection ?? command.spec.title
            if !usedTitles.insert(title).inserted {
                title += " — \(command.pluginName)"
                usedTitles.insert(title)
            }
            return PaletteSection(title: title, entries: entries, leads: command.spec.rootPattern != nil)
        }

        let offered = typed.isEmpty ? [] : fallbacks.map { entry in
            PaletteIndex.Entry(pluginID: entry.pluginID, pluginName: entry.pluginName, title: entry.spec.title,
                               subtitle: entry.pluginName, symbol: entry.spec.symbol, kind: .command(entry.spec))
        }
        let pinned = PaletteFavorites.entries(favorites, in: all)
        let sections = PaletteSection.group(found, query: query, favorites: pinned, store: store, plugins: pluginSections,
                                            fallbacks: offered, ranker: ranker, resultScore: resultScore, isRecent: isRecent)
        for section in sections {
            for entry in section.entries where roles[entry.id] == nil {
                switch section.kind {
                case .store: roles[entry.id] = .storeSuggestion
                case .fallback: roles[entry.id] = .fallback
                default: if case .copy = entry.kind { roles[entry.id] = .answer }
                }
            }
        }
        return PaletteRoot(sections: sections, roles: roles)
    }
}

/// Keeps the root built for the inputs it was built from, so the palette's
/// body (which reads the root many times a pass) and every arrow press reuse
/// it, and only a change in what the root is made of builds it again.
///
/// The key is a handful of counters, not the data: comparing a plugin's
/// rows to know whether they changed cost a pass over every row, per read.
public struct PaletteRootCache {
    public struct Key: Equatable, Sendable {
        public var query: String
        /// `PaletteIndex.revision`.
        public var index: Int
        /// `PaletteMemory.revision`.
        public var memory: Int
        /// How many Store catalogs have arrived.
        public var store: Int
        /// `RootSearchSession.rowsStamp`.
        public var rows: Int

        public init(query: String, index: Int, memory: Int, store: Int, rows: Int) {
            self.query = query
            self.index = index
            self.memory = memory
            self.store = store
            self.rows = rows
        }
    }

    private var kept: (key: Key, root: PaletteRoot)?

    public init() {}

    /// The root kept for `key`, or the one `build` makes, which is kept.
    public mutating func root(for key: Key, build: () -> PaletteRoot) -> PaletteRoot {
        if let kept, kept.key == key { return kept.root }
        let root = build()
        kept = (key, root)
        return root
    }

    public mutating func clear() { kept = nil }
}
