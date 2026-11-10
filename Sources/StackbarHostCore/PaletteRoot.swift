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
        /// Found again by its title, so it can be pinned and kept: not a
        /// row answering the text's shape (a sum, an issue key).
        public var keepable = true
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

    /// One line of the root as drawn: a section's heading or one of its
    /// rows. The list draws these, in one flat run, by `id`.
    public enum Line: Equatable, Sendable, Identifiable {
        case header(section: String, title: String)
        case row(section: String, entry: PaletteIndex.Entry)

        /// The line's identity in the drawn list. A row's is its section's
        /// and its entry's together: the same entry under another heading
        /// (Recent before you type, Results after) is another line. Keyed
        /// by the entry alone, SwiftUI's lazy list kept the view it drew
        /// under the old heading, so the highlight never reached the new
        /// one while Return still ran it.
        public var id: String {
            switch self {
            case .header(let section, _): return "header\u{1F}\(section)"
            case .row(let section, let entry): return Self.rowID(section: section, entryID: entry.id)
            }
        }

        public static func rowID(section: String, entryID: String) -> String {
            "row\u{1F}\(section)\u{1F}\(entryID)"
        }
    }

    /// Headings and rows in the order drawn.
    public let lines: [Line]

    init(sections: [PaletteSection], roles: [String: Role]) {
        self.sections = sections
        self.roles = roles
        entries = sections.flatMap(\.entries)
        lines = sections.flatMap { section in
            [Line.header(section: section.id, title: section.title)] + section.entries.map { Line.row(section: section.id, entry: $0) }
        }
    }

    /// The id of the drawn line showing `entryID`, to scroll to it: the
    /// first section that lists it.
    public func lineID(of entryID: String) -> String? {
        sections.first { $0.entries.contains { $0.id == entryID } }.map { Line.rowID(section: $0.id, entryID: entryID) }
    }

    public func role(of entry: PaletteIndex.Entry) -> Role {
        roles[entry.id] ?? .result
    }

    public func pluginRow(_ entry: PaletteIndex.Entry) -> PluginRow? {
        if case .pluginRow(let row) = role(of: entry) { return row }
        return nil
    }

    /// Only what stays put can be pinned: not fallbacks, Store suggestions
    /// or answers, which come and go with the query. A plugin's row can,
    /// as a snapshot found again by its title (an app, a file).
    public func canPin(_ entry: PaletteIndex.Entry) -> Bool {
        switch role(of: entry) {
        case .result: return true
        case .pluginRow(let row): return row.keepable
        case .fallback, .storeSuggestion, .answer: return false
        }
    }

    /// The snapshot that keeps a plugin's row past this query: to pin it,
    /// or to list it under Frequently Used once it is used often.
    public func snapshot(_ entry: PaletteIndex.Entry) -> PaletteRememberedRows.Row? {
        guard let row = pluginRow(entry), row.keepable else { return nil }
        return PaletteRememberedRows.Row(pluginID: entry.pluginID, pluginName: entry.pluginName, commandID: row.command.commandID,
                                         rowKey: row.rowKey, title: entry.title, subtitle: entry.subtitle, symbol: entry.symbol,
                                         appIcon: entry.appIcon, fileIcon: entry.fileIcon, query: entry.title)
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
            case .remembered: return "Open"
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
    /// - `favorites` are pinned ids, found in the index or, for a plugin's
    ///   row, in `remembered` (its snapshots); `frequent` are apps used
    ///   often, shown when nothing is typed; `store` are the Store's suggestions;
    ///   `fallbacks` the `.fallback()` commands to offer (none when nothing
    ///   is typed), shown while fewer than `PaletteFallbacks.threshold` rows
    ///   match; the Store's suggestions show only when nothing does.
    /// - `scoped` is the root-search command an alias named (`gs stackbar`):
    ///   its rows lead.
    public static func build(query: String, index: PaletteIndex, ranker: PaletteRanker, usage: PaletteUsage? = nil, favorites: [String] = [],
                             remembered: [PaletteIndex.Entry] = [], frequent: [PaletteIndex.Entry] = [],
                             store: [PaletteIndex.Entry] = [], plugins: [PluginRows] = [], fallbacks: [CommandRegistry.Entry] = [],
                             scoped: CommandKey? = nil, isRecent: (PaletteIndex.Entry) -> Bool = { _ in false }) -> PaletteRoot {
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
            let entries = Self.entries(source, limit: pluginRowLimit, roles: &roles)
            guard !entries.isEmpty else { return nil }
            var title = command.spec.rootSection ?? command.spec.title
            if !usedTitles.insert(title).inserted {
                title += " — \(command.pluginName)"
                usedTitles.insert(title)
            }
            return PaletteSection(title: title, entries: entries, leads: command.spec.rootPattern != nil || command.key == scoped)
        }

        let offered = typed.isEmpty ? [] : fallbacks.map { entry in
            PaletteIndex.Entry(pluginID: entry.pluginID, pluginName: entry.pluginName, title: entry.spec.title,
                               subtitle: entry.pluginName, symbol: entry.spec.symbol, kind: .command(entry.spec))
        }
        // A panel action pinned before the main search dropped them stays
        // pinned: the user chose it.
        let pinned = PaletteFavorites.entries(favorites, in: all + remembered + index.entries)
        let sections = PaletteSection.group(found, query: query, favorites: pinned, frequent: typed.isEmpty ? frequent : [], store: store, plugins: pluginSections,
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

extension PaletteRoot {
    /// Rows a plugin shows when the palette searches only it, at most.
    public static let scopedRowLimit = 50

    /// The root while the palette searches inside one plugin (its name, then
    /// Tab, as in Spotlight): only that command's rows, under its name.
    /// Nothing else is offered, not even fallbacks; Esc leaves.
    public static func scoped(_ source: PluginRows?) -> PaletteRoot {
        guard let source else { return PaletteRoot(sections: [], roles: [:]) }
        var roles: [String: Role] = [:]
        let entries = entries(source, limit: scopedRowLimit, roles: &roles)
        guard !entries.isEmpty else { return PaletteRoot(sections: [], roles: [:]) }
        let title = source.command.spec.rootSection ?? source.command.pluginName
        return PaletteRoot(sections: [PaletteSection(title: title, entries: entries, leads: true)], roles: roles)
    }

    /// A root-search command's first `limit` rows as entries, each with its
    /// role in `roles`.
    static func entries(_ source: PluginRows, limit: Int, roles: inout [String: Role]) -> [PaletteIndex.Entry] {
        let command = source.command
        return source.rows.prefix(limit).compactMap { row -> PaletteIndex.Entry? in
            guard let primary = row.actions.first else { return nil }
            let kind: PaletteIndex.Entry.Kind = primary.navigate.map { .navigate($0) } ?? .action(primary.id, value: nil)
            var entry = PaletteIndex.Entry(pluginID: command.pluginID, pluginName: command.pluginName, title: row.title,
                                           subtitle: row.subtitle, symbol: row.symbol ?? command.spec.symbol, kind: kind)
            entry.appIcon = row.appIcon
            entry.fileIcon = row.fileIcon
            // Action ids change with every answer; the row's key doesn't.
            entry.rankKey = PaletteIndex.Entry.rowID(pluginID: command.pluginID, commandID: command.spec.id, rowKey: row.key)
            roles[entry.id] = .pluginRow(PluginRow(command: command.key, rowKey: row.key, actions: row.actions,
                                                   keepable: command.spec.rootPattern == nil))
            return entry
        }
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
        /// The command the palette searches only, after its name and Tab.
        public var scope: CommandKey?

        public init(query: String, index: Int, memory: Int, store: Int, rows: Int, scope: CommandKey? = nil) {
            self.query = query
            self.index = index
            self.memory = memory
            self.store = store
            self.rows = rows
            self.scope = scope
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
