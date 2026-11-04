import Foundation
import StackbarProtocol

/// The palette's root list in titled groups, as Raycast draws it: before
/// anything is typed, your favourites, what you used lately, then commands,
/// then the actions plugins show on their panels; once you type, one ranked
/// list, then matching plugins from the Store that aren't installed.
public struct PaletteSection: Equatable, Sendable, Identifiable {
    public var title: String
    public var entries: [PaletteIndex.Entry]
    public var id: String { title }

    public init(title: String, entries: [PaletteIndex.Entry]) {
        self.title = title
        self.entries = entries
    }

    /// Groups `results` (already in search order) without reordering within
    /// a group. `favorites` lead an empty query, in their own order, and are
    /// not repeated below; `store` follows a typed one. Empty groups are left
    /// out.
    ///
    /// A typed query also gets the calculator's answer first, then the
    /// matching apps and System Settings panes: before the plugin results
    /// when the best one's name starts with what was typed (`saf` → Safari),
    /// after them otherwise.
    public static func group(_ results: [PaletteIndex.Entry], query: String, favorites: [PaletteIndex.Entry] = [], store: [PaletteIndex.Entry] = [],
                             calculator: [PaletteIndex.Entry] = [], apps: [PaletteIndex.Entry] = [],
                             recentLimit: Int = 5, isRecent: (PaletteIndex.Entry) -> Bool) -> [PaletteSection] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard typed.isEmpty else {
            let appsLead = apps.first.map { $0.title.lowercased().hasPrefix(typed.lowercased()) } ?? false
            let appSection = PaletteSection(title: "Applications", entries: apps)
            let result = PaletteSection(title: "Results", entries: results)
            return ([PaletteSection(title: "Calculator", entries: calculator)]
                + (appsLead ? [appSection, result] : [result, appSection])
                + [PaletteSection(title: "From the Store", entries: store)])
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
            switch entry.kind {
            case .command, .showPanel: commands.append(entry)
            case .action, .open, .navigate, .copy: actions.append(entry)
            }
        }
        return [
            PaletteSection(title: "Favorites", entries: favorites),
            PaletteSection(title: "Recent", entries: recent),
            PaletteSection(title: "Commands", entries: commands),
            PaletteSection(title: "Panel Actions", entries: actions),
        ].filter { !$0.entries.isEmpty }
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

    /// The pinned entries that still exist, in pinned order.
    public func entries(in all: [PaletteIndex.Entry]) -> [PaletteIndex.Entry] {
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
            if words.contains(where: { $0.hasPrefix(typed) }) { return (entry, 100) }
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
