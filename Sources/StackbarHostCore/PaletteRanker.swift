import Foundation
import StackbarProtocol

/// Which result people picked for what they typed, as Raycast, Alfred and
/// LaunchBar remember it: pick Slack twice after typing "s", and Slack leads
/// for "s". Picks decay with the same 14-day half-life as `PaletteUsage`.
public final class PalettePicks: @unchecked Sendable {
    private struct Pick: Codable {
        var score: Double
        var last: Date
    }

    /// (query, item) pairs kept, at most; the oldest go first.
    public static let limit = 2000
    private let file: URL?
    private let lock = NSLock()
    /// Typed text (collapsed, lowercased) → item id → its picks.
    private var picks: [String: [String: Pick]] = [:]
    private let now: @Sendable () -> Date

    public init(file: URL?, now: @escaping @Sendable () -> Date = Date.init) {
        self.file = file
        self.now = now
        if let file, let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode([String: [String: Pick]].self, from: data) {
            picks = decoded
        }
    }

    static func normalize(_ query: String) -> String {
        TextMatch.collapse(query)
    }

    /// Records that the item with this id was chosen after typing `query`.
    public func record(query: String, id: String) {
        let key = Self.normalize(query)
        guard !key.isEmpty else { return }
        let time = now()
        lock.withLock {
            let current = picks[key]?[id].map { $0.score * PaletteUsage.decay(from: $0.last, to: time) } ?? 0
            picks[key, default: [:]][id] = Pick(score: current + 1, last: time)
            trim()
        }
        save()
    }

    /// Each item's learned weight for `query`: its decayed picks for exactly
    /// this text, plus half its picks for longer text that starts with it
    /// (choosing Slack after "slack" also teaches "sl").
    public func weights(for query: String) -> [String: Double] {
        let key = Self.normalize(query)
        guard !key.isEmpty else { return [:] }
        let time = now()
        return lock.withLock {
            var weights: [String: Double] = [:]
            for (typed, items) in picks where typed.hasPrefix(key) {
                let share = typed == key ? 1 : 0.5
                for (id, pick) in items {
                    weights[id, default: 0] += share * pick.score * PaletteUsage.decay(from: pick.last, to: time)
                }
            }
            return weights
        }
    }

    /// Forgets every pick of one item (⌘K's Reset Ranking).
    public func forget(_ id: String) {
        lock.withLock {
            for key in picks.keys {
                picks[key]?[id] = nil
                if picks[key]?.isEmpty == true { picks[key] = nil }
            }
        }
        save()
    }

    /// Forgets everything (Settings' Clear Search History).
    public func clear() {
        lock.withLock { picks = [:] }
        save()
    }

    /// Carries the picks of plugin `from`'s commands and root rows over to
    /// plugin `to` (see `PaletteMemory.carried`), adding to what is there.
    public func move(pluginID from: String, to: String, carries: (String) -> Bool = { _ in true }) {
        lock.withLock {
            for (typed, items) in picks {
                for (id, pick) in items {
                    guard let target = PaletteMemory.carried(id, from: from, to: to, carries: carries) else { continue }
                    picks[typed]?[id] = nil
                    if let existing = picks[typed]?[target] {
                        picks[typed]?[target] = Pick(score: existing.score + pick.score, last: max(existing.last, pick.last))
                    } else {
                        picks[typed, default: [:]][target] = pick
                    }
                }
            }
        }
        save()
    }

    /// Drops the oldest pairs past `limit`. Called with the lock held.
    private func trim() {
        let count = picks.values.reduce(0) { $0 + $1.count }
        guard count > Self.limit else { return }
        let all = picks.flatMap { key, items in items.map { (key: key, id: $0.key, last: $0.value.last) } }
        for old in all.sorted(by: { $0.last < $1.last }).prefix(count - Self.limit) {
            picks[old.key]?[old.id] = nil
            if picks[old.key]?.isEmpty == true { picks[old.key] = nil }
        }
    }

    private func save() {
        guard let file else { return }
        let snapshot = lock.withLock { picks }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// The palette's one score for every row it can show, whatever its source:
/// commands, Stackbar's places, panel rows, and plugins' root-search rows
/// (apps, files, clipboard). Text decides first, in tiers; what you picked
/// for this text and how much you use a thing reorder among close matches.
///
/// ```
/// score = tier points + quality + learned + frecency + kind
/// ```
public struct PaletteRanker: Sendable {
    /// Points for each tier: a whole tier is worth more than any quality.
    public static func points(_ tier: TextMatch.Tier) -> Int { 100 * (tier.rawValue + 1) }
    /// What an exact alias scores: it always leads.
    public static let exactAlias = 100_000
    /// An alias that starts with the text: under an exact name, over a prefix.
    public static let aliasPrefix = 580
    /// Learned picks lift at most this much: two picks for the same text
    /// move a row up one tier, as in Alfred and LaunchBar.
    public static let learnedCap = 150
    public static let perPick = 80.0
    /// Use counts at most this much: it breaks near-ties only.
    public static let frecencyCap = 40
    /// Commands, Stackbar's places and plugins' rows over panel buttons.
    public static let kindBonus = 5

    public let typed: String
    private let learned: [String: Double]
    private let usage: PaletteUsage?

    public init(query: String, usage: PaletteUsage? = nil, picks: PalettePicks? = nil) {
        typed = TextMatch.collapse(query)
        self.usage = usage
        learned = picks?.weights(for: query) ?? [:]
    }

    /// The learned lift for an item, 0 when never picked for this text.
    public func learnedBonus(_ id: String) -> Int {
        guard let weight = learned[id], weight > 0 else { return 0 }
        return min(Self.learnedCap, Int((Self.perPick * weight).rounded()))
    }

    /// The use lift for an item, 0 when never used.
    public func frecencyBonus(_ id: String) -> Int {
        guard let use = usage?.score(id), use > 0 else { return 0 }
        return min(Self.frecencyCap, Int(16 * log2(1 + use)))
    }

    /// How well the entry's words match, or `nil`: its title fully; its
    /// subtitle and keywords one tier lower at half the quality, except a
    /// keyword typed whole;
    /// its plugin's name no better than a mid-word match, so "git" doesn't
    /// list every row of a plugin called GitHub ahead of "Reset Git Cache".
    public func textScore(_ entry: PaletteIndex.Entry) -> Int? {
        guard !typed.isEmpty else { return nil }
        if let alias = entry.alias?.lowercased() {
            if alias == typed { return Self.exactAlias }
            if alias.hasPrefix(typed) { return Self.aliasPrefix }
        }
        var best: Int?
        func consider(_ match: TextMatch.Match?, _ adjust: (TextMatch.Match) -> TextMatch.Match = { $0 }) {
            guard let match = match.map(adjust) else { return }
            best = max(best ?? Int.min, Self.points(match.tier) + match.quality)
        }
        consider(TextMatch.match(typed, in: entry.title))
        // Words beside the title: a tier lower and half the quality, so a
        // title that starts with the text beats a subtitle that is the text.
        let aside: (TextMatch.Match) -> TextMatch.Match = { .init(tier: $0.tier.lower, quality: $0.quality / 2) }
        if let subtitle = entry.subtitle { consider(TextMatch.match(typed, in: subtitle), aside) }
        for keyword in entry.keywords {
            consider(TextMatch.match(typed, in: keyword)) { $0.tier == .exact ? $0 : aside($0) }
        }
        // A root-search row's plugin name ("Applications") says nothing about the row.
        if entry.rankKey == nil {
            consider(TextMatch.match(typed, in: entry.pluginName)) { .init(tier: min($0.tier, .substring), quality: 0) }
        }
        return best
    }

    /// The entry's whole score for the text, or `nil` when its words don't
    /// match: learning reorders what matches, it never adds a row.
    public func score(_ entry: PaletteIndex.Entry) -> Int? {
        guard let text = textScore(entry) else { return nil }
        return text + boost(entry)
    }

    /// A plugin's root-search row: scored like any entry when its words
    /// match; otherwise (a file found by its contents, a sum's answer) by
    /// what it learned alone.
    public func rowScore(_ entry: PaletteIndex.Entry) -> Int {
        (textScore(entry) ?? 0) + boost(entry)
    }

    private func boost(_ entry: PaletteIndex.Entry) -> Int {
        learnedBonus(entry.learnID) + frecencyBonus(entry.learnID) + (Self.ranksAsCommand(entry) ? Self.kindBonus : 0)
    }

    static func ranksAsCommand(_ entry: PaletteIndex.Entry) -> Bool {
        entry.commandKey != nil || entry.pluginID == PaletteIndex.appID || entry.rankKey != nil
    }
}
