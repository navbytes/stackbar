import Foundation
import StackbarProtocol

/// The palette's root list in titled groups, as Raycast draws it: before
/// anything is typed, your favourites, what you used lately, then commands,
/// then the actions plugins show on their panels; once you type, one ranked
/// list, then matching plugins from the Store that aren't installed.
public struct PaletteSection: Equatable, Sendable, Identifiable {
    /// What a section holds. Code tells sections apart by this, never by
    /// their titles, which are for people.
    public enum Kind: Equatable, Sendable {
        case favorites, recent, commands, panelActions
        case results, topHit, store, fallback
        /// A root-search command's rows.
        case plugin

        /// The heading of a section of this kind; a plugin's section and
        /// the fallbacks have their own.
        public var title: String? {
            switch self {
            case .favorites: return "Favorites"
            case .recent: return "Recent"
            case .commands: return "Commands"
            case .panelActions: return "Panel Actions"
            case .results: return "Results"
            case .topHit: return "Top Hit"
            case .store: return "From the Store"
            case .fallback, .plugin: return nil
            }
        }

        /// Every fixed heading, which a plugin's section must not repeat.
        public static let fixedTitles: Set<String> = Set([Kind.favorites, .recent, .commands, .panelActions, .results, .topHit, .store].compactMap(\.title))
    }

    public var title: String
    public var kind: Kind
    public var entries: [PaletteIndex.Entry]
    /// A plugin section that answers the typed text's shape (its root
    /// pattern matched, like `ABC-123`), so it comes before the results.
    public var leads: Bool
    public var id: String { title }

    public init(title: String, kind: Kind = .plugin, entries: [PaletteIndex.Entry], leads: Bool = false) {
        self.title = title
        self.kind = kind
        self.entries = entries
        self.leads = leads
    }

    /// A section of a fixed kind, under its own heading.
    public init(_ kind: Kind, entries: [PaletteIndex.Entry]) {
        self.init(title: kind.title ?? "", kind: kind, entries: entries)
    }

    /// Groups `results` (already in search order) without reordering within
    /// a group. `favorites` lead an empty query, in their own order, and are
    /// not repeated below; `store` follows a typed one. Empty groups are left
    /// out.
    ///
    /// A typed query also gets the plugins' root-search sections, ranked
    /// with the results on one scale (`PaletteRanker`): a section whose root
    /// pattern matched (`2+2`, `ABC-123`) first; then the best row of all,
    /// in a "Top Hit" section of its own when it isn't already first in its
    /// section; then the sections, Results among them, by their best row.
    /// `resultScore` is the first result's score (default: the ranker's).
    /// Then the Store's suggestions and the fallback commands.
    public static func group(_ results: [PaletteIndex.Entry], query: String, favorites: [PaletteIndex.Entry] = [], store: [PaletteIndex.Entry] = [],
                             plugins: [PaletteSection] = [], fallbacks: [PaletteIndex.Entry] = [], ranker: PaletteRanker? = nil,
                             resultScore: Int? = nil, recentLimit: Int = 5, isRecent: (PaletteIndex.Entry) -> Bool) -> [PaletteSection] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard typed.isEmpty else {
            let ranker = ranker ?? PaletteRanker(query: typed)
            // A fallback the search found already shows in Results.
            let shown = Set(results.map(\.id))
            let rest = fallbacks.filter { !shown.contains($0.id) }
            let top = rank(plugins, results: results, ranker: ranker, resultScore: resultScore)
            return (top + [PaletteSection(.store, entries: store), PaletteSection(title: fallbackTitle(typed), kind: .fallback, entries: rest)])
                .filter { !$0.entries.isEmpty }
        }
        let pinned = Set(favorites.map(\.id))
        var recent: [PaletteIndex.Entry] = []
        var commands: [PaletteIndex.Entry] = []
        var actions: [PaletteIndex.Entry] = []
        for entry in results where !pinned.contains(entry.id) {
            if recent.count < recentLimit, isRecent(entry) {
                recent.append(entry)
                continue
            }
            // Stackbar's own places (Settings, the Store) are commands too.
            if entry.pluginID == PaletteIndex.appID {
                commands.append(entry)
                continue
            }
            switch entry.kind {
            case .command, .showPanel: commands.append(entry)
            case .action, .open, .navigate, .copy: actions.append(entry)
            }
        }
        return [
            PaletteSection(.favorites, entries: favorites),
            PaletteSection(.recent, entries: recent),
            PaletteSection(.commands, entries: commands),
            PaletteSection(.panelActions, entries: actions),
        ].filter { !$0.entries.isEmpty }
    }
}

extension PaletteSection {
    /// The title of the section holding the best row of all, when that row
    /// isn't first in its own section.
    public static let topHitTitle = Kind.topHit.title ?? ""

    /// Results and the plugins' sections in the order drawn (see `group`).
    /// Rows inside a plugin's section keep the plugin's order.
    public static func rank(_ sections: [PaletteSection], results: [PaletteIndex.Entry], ranker: PaletteRanker,
                            resultScore: Int? = nil) -> [PaletteSection] {
        let resultTop = results.isEmpty ? nil : (resultScore ?? results.first.flatMap(ranker.score) ?? 0)
        var sections = sections
        let scores = sections.map { $0.entries.map(ranker.rowScore) }
        // The best plugin row outside the pattern-led sections; ties go to
        // the earlier section and row.
        var topHit: PaletteIndex.Entry?
        let candidates = sections.indices.filter { !sections[$0].leads }
        var bestRow: (section: Int, row: Int, score: Int)?
        for section in candidates {
            for (row, score) in scores[section].enumerated() where score > (bestRow?.score ?? Int.min) {
                bestRow = (section, row, score)
            }
        }
        if let bestRow, bestRow.row > 0, bestRow.score > (resultTop ?? Int.min) {
            topHit = sections[bestRow.section].entries.remove(at: bestRow.row)
        }
        // A section's best row once the Top Hit has left it.
        func best(_ index: Int) -> Int { sections[index].entries.map(ranker.rowScore).max() ?? Int.min }
        let led = sections.indices.filter { sections[$0].leads }.sorted { (best($0), -$0) > (best($1), -$1) }.map { sections[$0] }
        // Results is index -1: it wins ties with every plugin section.
        var ordered: [(section: PaletteSection, score: Int, index: Int)] = candidates.map { (sections[$0], best($0), $0) }
        if let resultTop { ordered.append((PaletteSection(.results, entries: results), resultTop, -1)) }
        ordered.sort { ($0.score, -$0.index) > ($1.score, -$1.index) }
        let hit = topHit.map { [PaletteSection(.topHit, entries: [$0])] } ?? []
        return (led + hit + ordered.map(\.section)).filter { !$0.entries.isEmpty }
    }

    /// The heading over the fallback commands.
    public static func fallbackTitle(_ typed: String) -> String {
        let short = typed.count > 40 ? String(typed.prefix(39)) + "…" : typed
        return "Use \u{201C}\(short)\u{201D} with"
    }
}

/// The palette entries pinned to the top of its root, in the order pinned.
public final class PaletteFavorites: @unchecked Sendable {
    private let file: URL?
    private let lock = NSLock()
    private var stored: [String] = []

    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            stored = decoded
        }
    }

    public var ids: [String] { lock.withLock { stored } }

    public func contains(_ id: String) -> Bool { lock.withLock { stored.contains(id) } }

    /// Pins the entry at the end, or unpins it. True when it is now pinned.
    @discardableResult
    public func toggle(_ id: String) -> Bool {
        let pinned = lock.withLock { () -> Bool in
            if let index = stored.firstIndex(of: id) {
                stored.remove(at: index)
                return false
            }
            stored.append(id)
            return true
        }
        save()
        return pinned
    }

    /// Re-pins plugin `from`'s pinned commands as plugin `to`'s commands with
    /// the same ids, in the same places.
    public func move(pluginID from: String, to: String, carries: (String) -> Bool = { _ in true }) {
        lock.withLock {
            var seen = Set<String>()
            stored = stored.map { id in
                guard id.hasPrefix(from + "/") else { return id }
                let command = String(id.dropFirst(from.count + 1))
                return carries(command) ? to + "/" + command : id
            }
                .filter { seen.insert($0).inserted }
        }
        save()
    }

    /// The pinned entries that still exist, in pinned order.
    public func entries(in all: [PaletteIndex.Entry]) -> [PaletteIndex.Entry] {
        Self.entries(ids, in: all)
    }

    /// The entries with these pinned ids that still exist, in pinned order.
    public static func entries(_ ids: [String], in all: [PaletteIndex.Entry]) -> [PaletteIndex.Entry] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    private func save() {
        guard let file else { return }
        let snapshot = ids
        if let data = try? JSONEncoder().encode(snapshot) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}

public extension PaletteIndex.Entry {
    /// Entries (apps, Settings panes) that match `query` by title or
    /// keyword, best first, with a bonus for what was used often and lately.
    static func matching(_ entries: [PaletteIndex.Entry], query: String, limit: Int = 5, usage: PaletteUsage? = nil) -> [PaletteIndex.Entry] {
        let typed = query.lowercased().filter { !$0.isWhitespace }
        guard !typed.isEmpty else { return [] }
        return entries
            .compactMap { entry -> (PaletteIndex.Entry, Int)? in
                let best = ([entry.title] + entry.keywords).compactMap { TextMatch.score(typed, in: $0) }.max()
                guard let best else { return nil }
                let used = usage.map { $0.score(entry.id) } ?? 0
                return (entry, best + (used > 0 ? min(300, Int(60 * log2(1 + used))) : 0))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

public extension StoreListing {
    /// Store plugins that aren't installed and match what was typed, as
    /// palette entries that open the plugin's Store page. Names match
    /// fuzzily; summaries and categories only by a word they contain. Nothing
    /// for fewer than two letters, which would match half the store.
    static func paletteSuggestions(_ catalogs: [PluginStore.Catalog], query: String, installed: Installed, limit: Int = 3,
                                   running: String = StackbarVersion.current) -> [PaletteIndex.Entry] {
        let typed = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard typed.filter({ !$0.isWhitespace }).count >= 2 else { return [] }
        var seen = Set<String>()
        let scored = all(catalogs, running: running).compactMap { item -> (PluginIndex.Entry, Int)? in
            let entry = item.entry
            guard !installed.contains(entry.id), entry.requiredStackbar(running: running) == nil, seen.insert(entry.id).inserted else { return nil }
            if let score = TextMatch.score(typed, in: entry.name) { return (entry, 1000 + score) }
            let words = [entry.summary ?? "", entry.category ?? ""].joined(separator: " ").lowercased()
                .split { !$0.isLetter && !$0.isNumber }
            // Every word typed starts a word of the summary ("time zone").
            let parts = typed.split(separator: " ")
            if parts.allSatisfy({ part in words.contains { $0.hasPrefix(part) } }) { return (entry, 100) }
            return nil
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { entry, _ in
                PaletteIndex.Entry(pluginID: entry.id, pluginName: "Store", title: entry.name, subtitle: entry.summary,
                                   symbol: entry.symbol, kind: .open(StoreLink(pluginID: entry.id).url.absoluteString))
            }
    }
}

/// What `findFiles` keeps of Spotlight's hits, and how a folder reads.
public enum FileSearchFilter {
    /// Nothing anyone means to open from a launcher: apps (Applications
    /// lists them), anything inside a bundle, hidden files and folders,
    /// Library internals and node_modules.
    public static func keeps(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        guard !components.isEmpty, url.pathExtension != "app" else { return false }
        let bundles: Set<String> = ["app", "framework", "bundle", "photoslibrary", "musiclibrary", "xcarchive", "appex", "plugin"]
        for (index, component) in components.enumerated() {
            if component.hasPrefix("."), index > 0 { return false }
            if index < components.count - 1, bundles.contains((component as NSString).pathExtension.lowercased()) { return false }
            if component == "Library", index < components.count - 1 { return false }
            if component == "node_modules" { return false }
        }
        return true
    }

    /// The file found at `path`, its folder written from `~`.
    public static func found(path: String, home: String, isFolder: Bool = false, lastUsed: Date? = nil) -> FoundFile? {
        guard keeps(path) else { return nil }
        let url = URL(fileURLWithPath: path)
        return FoundFile(path: path, name: url.lastPathComponent, folder: abbreviate(url.deletingLastPathComponent().path, home: home),
                         isFolder: isFolder, lastUsed: lastUsed)
    }

    /// Spotlight's query for names holding every word, case and accents
    /// ignored: `kMDItemFSName == "*q3*"cd && kMDItemFSName == "*plan*"cd`.
    /// Quotes, backslashes and wildcards in a word are matched literally.
    public static func spotlightQuery(_ words: [String]) -> String {
        words.map { word -> String in
            var escaped = ""
            for character in word {
                if "\\\"*?".contains(character) { escaped.append("\\") }
                escaped.append(character)
            }
            return "kMDItemFSName == \"*\(escaped)*\"cd"
        }.joined(separator: " && ")
    }

    /// `/Users/n/Documents/x` → `~/Documents/x`.
    public static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        let prefix = home.hasSuffix("/") ? home : home + "/"
        return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
    }
}
