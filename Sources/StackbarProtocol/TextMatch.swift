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
        return remaining.isEmpty ? score - limited.count : nil
    }
}
