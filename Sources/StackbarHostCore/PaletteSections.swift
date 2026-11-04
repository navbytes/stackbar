import Foundation
import StackbarProtocol

/// The palette's root list in titled groups, as Raycast draws it: before
/// anything is typed, what you used lately, then commands, then the actions
/// plugins show on their panels; once you type, one ranked list.
public struct PaletteSection: Equatable, Sendable, Identifiable {
    public var title: String
    public var entries: [PaletteIndex.Entry]
    public var id: String { title }

    public init(title: String, entries: [PaletteIndex.Entry]) {
        self.title = title
        self.entries = entries
    }

    /// Groups `results` (already in search order) without reordering within
    /// a group. Empty groups are left out.
    public static func group(_ results: [PaletteIndex.Entry], query: String, recentLimit: Int = 5, isRecent: (PaletteIndex.Entry) -> Bool) -> [PaletteSection] {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return results.isEmpty ? [] : [PaletteSection(title: "Results", entries: results)]
        }
        var recent: [PaletteIndex.Entry] = []
        var commands: [PaletteIndex.Entry] = []
        var actions: [PaletteIndex.Entry] = []
        for entry in results {
            if recent.count < recentLimit, isRecent(entry) {
                recent.append(entry)
                continue
            }
            switch entry.kind {
            case .command, .showPanel: commands.append(entry)
            case .action, .open, .navigate: actions.append(entry)
            }
        }
        return [
            PaletteSection(title: "Recent", entries: recent),
            PaletteSection(title: "Commands", entries: commands),
            PaletteSection(title: "Panel Actions", entries: actions),
        ].filter { !$0.entries.isEmpty }
    }
}
