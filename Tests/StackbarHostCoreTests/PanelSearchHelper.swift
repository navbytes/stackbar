@testable import StackbarHostCore

extension PaletteIndex {
    /// The ranker over the panel entries alone: the palette's main search
    /// no longer lists them (palette-root-commands), but ranking tests use
    /// a panel's buttons as handy entries.
    func searchPanels(_ query: String, limit: Int = 50, usage: PaletteUsage? = nil) -> [Entry] {
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.id).inserted }
        return scored(query, limit: limit, ranker: PaletteRanker(query: query, usage: usage), usage: usage, in: unique).map(\.entry)
    }
}
