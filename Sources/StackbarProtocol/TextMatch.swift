/// How the host matches what people type against titles: in the panel's
/// filter field and in the command palette. A prefix beats a substring, which
/// beats the letters in order ("gthb" finds "GitHub"); a run of matching
/// letters and a match at a word start score higher.
public enum TextMatch {
    /// A score, higher is better, or `nil` when `query` doesn't match.
    /// Case-insensitive; whitespace in the query is ignored.
    public static func score(_ query: String, in text: String) -> Int? {
        let query = query.lowercased().filter { !$0.isWhitespace }
        guard !query.isEmpty else { return 0 }
        let text = text.lowercased()
        if text.hasPrefix(query) { return 1000 - min(text.count, 300) }
        if text.contains(query) { return 700 - min(text.count, 300) }
        // Letters in order, but not across a huge text: a long clipboard item
        // would match nearly anything.
        let limited = text.prefix(500)
        var score = 0
        var run = 0
        var previous: Character = " "
        var remaining = Substring(query)
        for character in limited {
            guard let next = remaining.first else { break }
            if character == next {
                remaining = remaining.dropFirst()
                run += 1
                score += 10 + run * 5 + (" -_/.".contains(previous) ? 20 : 0)
            } else {
                run = 0
            }
            previous = character
        }
        // Letters in order rank below any match of the whole text, however
        // long the runs: "a-bcdefg" must not beat "abcdefg" for "abcdefg".
        return remaining.isEmpty ? min(score - limited.count, 399) : nil
    }
}

extension TextMatch {
    /// How a query matched, best tier first. The palette ranks by tier, then
    /// by `quality`, so a whole-word start always beats a scattered match.
    public enum Tier: Int, Comparable, Sendable, CaseIterable {
        case inOrder, substring, initials, wordStart, prefix, exact

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

        /// One tier lower, for words that matter less than a title
        /// (a subtitle, a keyword typed in part).
        public var lower: Tier { Tier(rawValue: max(0, rawValue - 1)) ?? .inOrder }
    }

    public struct Match: Equatable, Sendable {
        public var tier: Tier
        /// 0...60, higher is better within a tier: a shorter text for the
        /// whole-text tiers; tighter runs and word starts for `inOrder`.
        public var quality: Int

        public init(tier: Tier, quality: Int) {
            self.tier = tier
            self.quality = max(0, min(60, quality))
        }
    }

    /// Characters that start a new word after them.
    static let wordBreaks: Set<Character> = [" ", "-", "_", "/", ".", ":", "(", ")", ",", "+", "&"]

    /// How `query` matches `text`, or `nil`. Case-insensitive; runs of
    /// whitespace count as one space, and a query typed without spaces still
    /// matches a name with them ("prcockpit" → "PR Cockpit").
    public static func match(_ query: String, in text: String) -> Match? {
        let query = collapse(query)
        guard !query.isEmpty else { return nil }
        let text = collapse(text)
        guard !text.isEmpty else { return nil }
        let squeezedQuery = query.filter { $0 != " " }
        let squeezedText = text.filter { $0 != " " }
        let shortness = 60 - min(text.count, 60)
        if text == query || squeezedText == squeezedQuery { return Match(tier: .exact, quality: 60) }
        if text.hasPrefix(query) || squeezedText.hasPrefix(squeezedQuery) { return Match(tier: .prefix, quality: shortness) }
        let characters = Array(text)
        let starts = characters.indices.filter { $0 == 0 || wordBreaks.contains(characters[$0 - 1]) }
            .filter { !wordBreaks.contains(characters[$0]) }
        // `starts` are offsets in characters; walking to each from the front would be quadratic.
        let positions = Array(text.indices)
        if starts.contains(where: { text[positions[$0]...].hasPrefix(query) }) {
            return Match(tier: .wordStart, quality: shortness)
        }
        if squeezedQuery.count >= 2 {
            let initials = String(starts.map { characters[$0] })
            if initials.hasPrefix(squeezedQuery) { return Match(tier: .initials, quality: shortness) }
        }
        if text.contains(query) || squeezedText.contains(squeezedQuery) { return Match(tier: .substring, quality: shortness) }
        guard let loose = score(squeezedQuery, in: text) else { return nil }
        // `score` gives letters in order at most 399, less the text's length.
        return Match(tier: .inOrder, quality: max(0, loose) * 60 / 399)
    }

    /// Lowercased, with runs of whitespace as one space and none at the ends.
    public static func collapse(_ string: String) -> String {
        string.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
