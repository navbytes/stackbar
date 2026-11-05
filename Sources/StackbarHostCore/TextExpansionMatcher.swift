import Foundation
import StackbarProtocol

/// Watches typed text for registered keywords. The Mac monitor feeds it
/// each typed character and tells it when typing was interrupted (a click,
/// an arrow key, a shortcut, another app); it answers the keyword typed, if
/// one just was. Pure, so it is tested on Linux.
///
/// A keyword expands the moment its last character is typed, as Raycast
/// does, but only at the start of a word: `addr` expands in "my addr" and
/// not in "xaddr". The longest keyword wins when one ends another.
public struct TextExpansionMatcher: Sendable {
    public struct Match: Equatable, Sendable {
        public var keyword: String
        public var pluginID: String
        public var command: String
        /// Backspaces that delete the keyword: one per grapheme cluster.
        public var deleteCount: Int
    }

    /// Characters remembered, enough for the longest keyword and the one
    /// before it.
    public static let memory = TextExpansion.maxKeywordLength + 1

    private var typed: [Character] = []
    /// Keyword → its plugin and command, longest keywords first.
    private var table: [(keyword: [Character], pluginID: String, command: String)] = []

    public init(_ registrations: [TextExpansionRegistry.Entry] = []) {
        update(registrations)
    }

    /// Replaces the keywords watched for; what was typed so far stays.
    public mutating func update(_ registrations: [TextExpansionRegistry.Entry]) {
        table = registrations
            .map { (keyword: Array($0.keyword), pluginID: $0.pluginID, command: $0.command) }
            .sorted { $0.keyword.count > $1.keyword.count }
    }

    public var isEmpty: Bool { table.isEmpty }

    /// Typing was interrupted: what came before no longer counts.
    public mutating func reset() { typed.removeAll(keepingCapacity: true) }

    /// Backspace: forget the last character.
    public mutating func deleteBackward() { if !typed.isEmpty { typed.removeLast() } }

    /// The text one key press typed (usually one character). Answers the
    /// keyword it completed, and then starts over.
    public mutating func type(_ text: String) -> Match? {
        for character in text {
            typed.append(character)
            if typed.count > Self.memory { typed.removeFirst(typed.count - Self.memory) }
        }
        guard let match = completed() else { return nil }
        reset()
        return match
    }

    private func completed() -> Match? {
        for entry in table where typed.count >= entry.keyword.count {
            let start = typed.count - entry.keyword.count
            guard Array(typed[start...]) == entry.keyword else { continue }
            if start > 0, Self.isWordCharacter(typed[start - 1]), Self.isWordCharacter(entry.keyword[0]) { continue }
            return Match(keyword: String(entry.keyword), pluginID: entry.pluginID, command: entry.command, deleteCount: entry.keyword.count)
        }
        return nil
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

/// The keywords plugins have registered. A keyword two plugins register
/// belongs to the one that registered it first; the other reports it as
/// taken until the first lets go.
public final class TextExpansionRegistry: @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public var keyword: String
        public var pluginID: String
        public var pluginName: String
        public var command: String
    }

    private let lock = NSLock()
    /// Plugins in the order they first registered, with their keywords.
    private var plugins: [(pluginID: String, pluginName: String, expansions: [TextExpansion])] = []
    /// Called after every change, with the keywords now live.
    public var onChange: (@Sendable ([Entry]) -> Void)?

    public init() {}

    /// Registers or replaces a plugin's keywords (keeping its place in
    /// line); an empty list removes them. Throws their problems.
    public func set(_ expansions: [TextExpansion], pluginID: String, pluginName: String) throws {
        if let problem = TextExpansion.problems(expansions).first { throw SystemServiceError(problem) }
        let live: [Entry] = lock.withLock {
            if expansions.isEmpty {
                plugins.removeAll { $0.pluginID == pluginID }
            } else if let index = plugins.firstIndex(where: { $0.pluginID == pluginID }) {
                plugins[index].expansions = expansions
                plugins[index].pluginName = pluginName
            } else {
                plugins.append((pluginID, pluginName, expansions))
            }
            return liveLocked()
        }
        onChange?(live)
    }

    /// Every keyword that expands, each to its first plugin.
    public var live: [Entry] { lock.withLock { liveLocked() } }

    public var isEmpty: Bool { lock.withLock { plugins.isEmpty } }

    /// How many keywords the plugin registered.
    public func count(for pluginID: String) -> Int {
        lock.withLock { plugins.first { $0.pluginID == pluginID }?.expansions.count ?? 0 }
    }

    /// The plugin's keywords that another plugin registered first.
    public func taken(for pluginID: String) -> [String] {
        lock.withLock {
            guard let index = plugins.firstIndex(where: { $0.pluginID == pluginID }) else { return [] }
            let earlier = Set(plugins[..<index].flatMap { $0.expansions.map(\.keyword) })
            return plugins[index].expansions.map(\.keyword).filter(earlier.contains)
        }
    }

    private func liveLocked() -> [Entry] {
        var seen: Set<String> = []
        var result: [Entry] = []
        for plugin in plugins {
            for expansion in plugin.expansions where seen.insert(expansion.keyword).inserted {
                result.append(Entry(keyword: expansion.keyword, pluginID: plugin.pluginID, pluginName: plugin.pluginName, command: expansion.command))
            }
        }
        return result
    }
}
