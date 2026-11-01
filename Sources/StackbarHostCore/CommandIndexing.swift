import Foundation
import StackbarProtocol

/// What Spotlight and Shortcuts know about a command: the same title,
/// keywords and ranking as the palette, kept to commands the user lets out
/// of Stackbar. The app's App Intents and its Spotlight index are thin
/// wrappers over this.
public struct CommandIndexItem: Equatable, Sendable, Identifiable {
    /// `plugin-id/command-id`, the entity's identifier.
    public var id: String
    public var title: String
    /// "PR Cockpit · Search pull requests"
    public var summary: String
    public var symbol: String
    public var keywords: [String]
    public var kind: CommandSpec.Kind
    /// 0...10, higher for what the user runs often and lately.
    public var priority: Int

    public init(id: String, title: String, summary: String, symbol: String, keywords: [String], kind: CommandSpec.Kind, priority: Int) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.keywords = keywords
        self.kind = kind
        self.priority = priority
    }

    public var key: CommandKey? { CommandKey(id) }
}

public enum CommandIndexing {
    /// Whether a command may show in Spotlight and Shortcuts.
    public static func isExposed(_ entry: CommandRegistry.Entry, preferences: CommandPreferences) -> Bool {
        let preference = preferences[entry.key]
        return preferences.spotlightEnabled && entry.spec.exposure == .everywhere && preference.enabled && preference.showInSpotlight
    }

    public static func item(_ entry: CommandRegistry.Entry, preferences: CommandPreferences, usage: PaletteUsage?) -> CommandIndexItem {
        let spec = entry.spec
        let summary = [entry.pluginName, spec.subtitle].compactMap { $0 }.joined(separator: " · ")
        var keywords = spec.keywords + [entry.pluginName]
        if let alias = preferences[entry.key].alias { keywords.append(alias) }
        let score = usage?.score(entry.key.description) ?? 0
        let priority = score > 0 ? min(10, Int((log2(1 + score) * 2).rounded())) : 0
        return CommandIndexItem(
            id: entry.key.description,
            title: spec.title,
            summary: summary,
            symbol: spec.symbol ?? (spec.kind == .view ? "list.bullet.rectangle" : "command"),
            keywords: keywords,
            kind: spec.kind,
            priority: priority
        )
    }

    /// Every command Spotlight should have, in registry order.
    public static func items(registry: CommandRegistry, preferences: CommandPreferences, usage: PaletteUsage?) -> [CommandIndexItem] {
        registry.entries.filter { isExposed($0, preferences: preferences) }.map { item($0, preferences: preferences, usage: usage) }
    }

    /// What to index again (new or changed) and what to delete, going from
    /// what the index holds to what it should hold.
    public static func diff(from old: [CommandIndexItem], to new: [CommandIndexItem]) -> (upsert: [CommandIndexItem], delete: [String]) {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Set(new.map(\.id))
        let upsert = new.filter { before[$0.id] != $0 }
        let delete = old.map(\.id).filter { !after.contains($0) }
        return (upsert, delete)
    }

    /// Commands matching what was typed in Shortcuts' picker, ranked like
    /// the palette. An empty query gives the most used.
    public static func search(_ text: String, registry: CommandRegistry, preferences: CommandPreferences, usage: PaletteUsage?, limit: Int = 20) -> [CommandIndexItem] {
        let exposed = registry.entries.filter { isExposed($0, preferences: preferences) }
        var index = PaletteIndex()
        index.setCommands(exposed, preferences: preferences.all)
        let byKey = Dictionary(exposed.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return index.search(text, limit: limit, usage: usage).compactMap { entry in
            entry.commandKey.flatMap { byKey[$0] }.map { item($0, preferences: preferences, usage: usage) }
        }
    }
}
