import Foundation
import StackbarProtocol

/// What the palette has learned about you, behind one interface: how often
/// and how lately each row was used (`PaletteUsage`), what you picked for
/// what you typed (`PalettePicks`), and what you pinned (`PaletteFavorites`).
///
/// Every change goes through here, so a reset, a clear or a plugin handover
/// reaches all three, and `revision` tells the palette's cache that what it
/// ranked with has changed.
public final class PaletteMemory: @unchecked Sendable {
    public let usage: PaletteUsage
    public let picks: PalettePicks
    public let favorites: PaletteFavorites
    private let lock = NSLock()
    private var changes = 0

    public init(usage: PaletteUsage, picks: PalettePicks, favorites: PaletteFavorites) {
        self.usage = usage
        self.picks = picks
        self.favorites = favorites
    }

    /// The three stores in `directory`, or in memory when it is nil.
    public convenience init(directory: URL?, now: @escaping @Sendable () -> Date = Date.init) {
        self.init(usage: PaletteUsage(file: directory?.appendingPathComponent("palette-usage.json"), now: now),
                  picks: PalettePicks(file: directory?.appendingPathComponent("palette-picks.json"), now: now),
                  favorites: PaletteFavorites(file: directory?.appendingPathComponent("palette-favorites.json")))
    }

    /// Bumped by every change that reorders or regroups the root (a reset,
    /// a clear, a pin, a handover). A use or a pick isn't one: the palette
    /// closes on it, and the next query ranks with it.
    public var revision: Int { lock.withLock { changes } }

    /// Returns once every use and pick is written, for quitting.
    public func flush() {
        usage.flush()
        picks.flush()
    }

    private func changed() { lock.withLock { changes += 1 } }

    // MARK: - Learning

    /// The entry was chosen in the palette. `query` is the root's text when
    /// it was chosen there, so it ranks higher for that text next time. A
    /// command's use is counted when it runs or opens (`used`), wherever it
    /// starts from, so it isn't counted here as well.
    public func chose(_ entry: PaletteIndex.Entry, query: String?) {
        if let query { picks.record(query: query, id: entry.learnID) }
        if entry.commandKey == nil { usage.record(entry.learnID) }
    }

    /// A command ran or opened, from the palette or anywhere else.
    public func used(_ command: CommandKey) {
        usage.record(PaletteIndex.Entry.commandID(command))
    }

    /// The ranker for what is typed now.
    public func ranker(for query: String) -> PaletteRanker {
        PaletteRanker(query: query, usage: usage, picks: picks)
    }

    /// Used in the last week, for the root's Recent section.
    public func isRecent(_ entry: PaletteIndex.Entry) -> Bool {
        usage.isRecent(entry.learnID)
    }

    // MARK: - Changes the user asks for

    /// ⌘K's Reset Ranking: forgets the entry's use and every pick of it.
    public func forget(_ entry: PaletteIndex.Entry) {
        usage.forget(entry.learnID)
        picks.forget(entry.learnID)
        changed()
    }

    /// Settings' Clear Search History: every use and pick. Pins stay.
    public func clear() {
        usage.clear()
        picks.clear()
        changed()
    }

    public func isFavorite(_ entry: PaletteIndex.Entry) -> Bool { favorites.contains(entry.id) }

    /// Pins the entry, or unpins it. True when it is now pinned.
    @discardableResult
    public func toggleFavorite(_ entry: PaletteIndex.Entry) -> Bool {
        defer { changed() }
        return favorites.toggle(entry.id)
    }

    /// Plugin `to` replaces plugin `from`: its commands' (and their rows')
    /// use, picks and pins move to `to`'s commands with the same ids, for
    /// each command id `carries` accepts.
    public func handOver(from: String, to: String, carries: (String) -> Bool = { _ in true }) {
        usage.move(pluginID: from, to: to, carries: carries)
        picks.move(pluginID: from, to: to, carries: carries)
        favorites.move(pluginID: from, to: to, carries: carries)
        changed()
    }

    /// The id `id` has under plugin `to`, when it belongs to one of plugin
    /// `from`'s commands that `carries` accepts: a command (`from/command`)
    /// or a row one of its root searches showed (`from|row|command|key`).
    /// Nil for anything else, such as the plugin's panel.
    public static func carried(_ id: String, from: String, to: String, carries: (String) -> Bool) -> String? {
        if id.hasPrefix(from + "/") {
            let command = String(id.dropFirst(from.count + 1))
            return carries(command) ? to + "/" + command : nil
        }
        let rowPrefix = from + "|row|"
        if id.hasPrefix(rowPrefix) {
            let rest = id.dropFirst(rowPrefix.count)
            guard let bar = rest.firstIndex(of: "|"), carries(String(rest[..<bar])) else { return nil }
            return to + "|row|" + rest
        }
        return nil
    }
}
