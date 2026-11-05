import Foundation

/// A keyword the host expands as the user types it, in any app: it deletes
/// the keyword and runs the plugin's command, which pastes (a snippet, say).
/// The plugin registers its keywords up front with `Stackbar.setExpansions`;
/// it never sees what the user types. Protocol 19.
public struct TextExpansion: Codable, Equatable, Hashable, Sendable {
    /// What the user types, like `;sig`: 1 to 32 characters, no whitespace,
    /// quotes or backticks.
    public var keyword: String
    /// The id of the plugin's command that runs when it is typed.
    public var command: String

    public init(keyword: String, command: String) {
        self.keyword = keyword
        self.command = command
    }

    public static let maxKeywordLength = 32
    public static let maxPerPlugin = 1000

    /// Raycast's rule: no whitespace, quotes or backticks.
    public static func isValidKeyword(_ keyword: String) -> Bool {
        guard !keyword.isEmpty, keyword.count <= maxKeywordLength else { return false }
        return !keyword.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || "\"'`".unicodeScalars.contains($0) }
    }

    /// Problems that make a set of expansions unusable, in words.
    public static func problems(_ expansions: [TextExpansion]) -> [String] {
        var result: [String] = []
        if expansions.count > maxPerPlugin { result.append("at most \(maxPerPlugin) keywords") }
        var seen: Set<String> = []
        for expansion in expansions {
            if !isValidKeyword(expansion.keyword) {
                result.append("keyword \"\(expansion.keyword)\" must be 1 to \(maxKeywordLength) characters without spaces, quotes or backticks")
            }
            if expansion.command.isEmpty { result.append("keyword \"\(expansion.keyword)\" has no command") }
            if !seen.insert(expansion.keyword).inserted { result.append("keyword \"\(expansion.keyword)\" is registered twice") }
        }
        return result
    }
}

/// Whether a plugin's keywords expand, and why not.
public struct ExpansionStatus: Codable, Equatable, Sendable {
    /// Typing a registered keyword expands it.
    public var listening: Bool
    /// How many of the plugin's keywords are registered (none when off).
    public var keywords: Int
    /// The user switched expansion off in Settings.
    public var turnedOff: Bool
    /// Stackbar needs Accessibility access before it can listen.
    public var needsAccessibility: Bool
    /// The app holding Secure Input, which blocks every key listener while
    /// it is on (password fields turn it on).
    public var secureInputApp: String?
    /// Keywords another plugin registered first, which expand to that
    /// plugin's command instead.
    public var taken: [String]

    public init(listening: Bool = false, keywords: Int = 0, turnedOff: Bool = false, needsAccessibility: Bool = false, secureInputApp: String? = nil, taken: [String] = []) {
        self.listening = listening
        self.keywords = keywords
        self.turnedOff = turnedOff
        self.needsAccessibility = needsAccessibility
        self.secureInputApp = secureInputApp
        self.taken = taken
    }

    /// No keywords are registered.
    public static let off = ExpansionStatus()
}
