import Foundation
import StackbarProtocol

/// What the user set for one command. These belong to the user, not the
/// plugin, so they live with the host and survive plugin updates.
public struct CommandPreference: Codable, Equatable, Sendable {
    /// A word typed in the palette that jumps straight to the command.
    public var alias: String?
    /// A system-wide shortcut, spelled like a manifest hotkey.
    public var hotkey: String?
    public var enabled: Bool
    public var showInSpotlight: Bool
    /// Whether `stackbar://` links may run it without asking.
    public var linksAllowed: Bool

    public init(alias: String? = nil, hotkey: String? = nil, enabled: Bool = true, showInSpotlight: Bool = true, linksAllowed: Bool = false) {
        self.alias = alias
        self.hotkey = hotkey
        self.enabled = enabled
        self.showInSpotlight = showInSpotlight
        self.linksAllowed = linksAllowed
    }

    public static let `default` = CommandPreference()

    /// Aliases are one word: lowercase letters, digits, `-`, `_` and `.`.
    public static func normalizedAlias(_ text: String) -> String? {
        let alias = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard (1...24).contains(alias.count), alias.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }) else { return nil }
        return alias
    }
}

/// Command preferences and palette usage, saved in the data directory.
public final class CommandPreferences: @unchecked Sendable {
    private struct Saved: Codable {
        var commands: [CommandKey: CommandPreference] = [:]
        var spotlightEnabled = true
    }

    private let file: URL?
    private let lock = NSLock()
    private var saved = Saved()
    public var onChange: (@Sendable () -> Void)?

    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        }
    }

    public subscript(_ key: CommandKey) -> CommandPreference {
        lock.withLock { saved.commands[key] ?? .default }
    }

    /// The commands' Spotlight switch for all of Stackbar.
    public var spotlightEnabled: Bool {
        get { lock.withLock { saved.spotlightEnabled } }
        set {
            lock.withLock { saved.spotlightEnabled = newValue }
            save()
        }
    }

    public var all: [CommandKey: CommandPreference] {
        lock.withLock { saved.commands }
    }

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case badAlias(String)
        case aliasTaken(String, by: CommandKey)
        case badHotkey(String)
        case hotkeyTaken(String, by: String)

        public var description: String {
            switch self {
            case .badAlias(let alias): return "\"\(alias)\" can't be an alias; use one word of letters, digits, - or _"
            case .aliasTaken(let alias, let key): return "\"\(alias)\" is already the alias of \(key)"
            case .badHotkey(let hotkey): return "\(hotkey) needs cmd, ctrl or option plus one letter, digit, space or f1...f12"
            case .hotkeyTaken(let hotkey, let owner): return "\(hotkey) is already used by \(owner)"
            }
        }
    }

    /// Sets one command's preference after checking the alias and hotkey.
    /// `otherHotkeys` are shortcuts used elsewhere (plugin hotkeys, the
    /// palette's own), by who uses them.
    public func set(_ preference: CommandPreference, for key: CommandKey, otherHotkeys: [String: String] = [:]) throws {
        var preference = preference
        if let alias = preference.alias, !alias.isEmpty {
            guard let normalized = CommandPreference.normalizedAlias(alias) else { throw Problem.badAlias(alias) }
            if let owner = lock.withLock({ saved.commands.first(where: { $0.key != key && $0.value.alias == normalized })?.key }) {
                throw Problem.aliasTaken(normalized, by: owner)
            }
            preference.alias = normalized
        } else {
            preference.alias = nil
        }
        if let hotkey = preference.hotkey, !hotkey.isEmpty {
            guard let spec = HotKeySpec(hotkey) else { throw Problem.badHotkey(hotkey) }
            for (other, owner) in otherHotkeys where HotKeySpec(other) == spec {
                throw Problem.hotkeyTaken(hotkey, by: owner)
            }
            if let owner = lock.withLock({ saved.commands.first(where: { $0.key != key && $0.value.hotkey.flatMap(HotKeySpec.init) == spec })?.key }) {
                throw Problem.hotkeyTaken(hotkey, by: owner.description)
            }
        } else {
            preference.hotkey = nil
        }
        lock.withLock {
            if preference == .default { saved.commands[key] = nil } else { saved.commands[key] = preference }
        }
        save()
    }

    /// The command an alias names, if any.
    public func command(forAlias alias: String) -> CommandKey? {
        let alias = alias.lowercased()
        return lock.withLock { saved.commands.first(where: { $0.value.alias == alias })?.key }
    }

    /// Drops the preferences of commands that no longer exist.
    public func retain(only keys: Set<CommandKey>) {
        let changed: Bool = lock.withLock {
            let before = saved.commands.count
            saved.commands = saved.commands.filter { keys.contains($0.key) }
            return saved.commands.count != before
        }
        if changed { save() }
    }

    private func save() {
        if let file {
            let snapshot = lock.withLock { saved }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            if let data = try? encoder.encode(snapshot) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
        }
        onChange?()
    }
}

/// How often and how recently each palette entry was used, decaying with a
/// 14-day half-life, so what you use now ranks first.
public final class PaletteUsage: @unchecked Sendable {
    private struct Use: Codable {
        var score: Double
        var last: Date
    }

    public static let halfLife: Double = 14 * 24 * 3600
    private let file: URL?
    private let lock = NSLock()
    private var uses: [String: Use] = [:]
    private let now: @Sendable () -> Date

    public init(file: URL?, now: @escaping @Sendable () -> Date = Date.init) {
        self.file = file
        self.now = now
        if let file, let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode([String: Use].self, from: data) {
            uses = decoded
        }
    }

    /// Records one use of the entry with this id.
    public func record(_ id: String) {
        let time = now()
        lock.withLock {
            let current = uses[id].map { $0.score * Self.decay(from: $0.last, to: time) } ?? 0
            uses[id] = Use(score: current + 1, last: time)
            if uses.count > 2000 {
                let oldest = uses.sorted { $0.value.last < $1.value.last }.prefix(uses.count - 2000).map(\.key)
                for key in oldest { uses[key] = nil }
            }
        }
        save()
    }

    /// The decayed use count of an entry (0 when never used).
    public func score(_ id: String) -> Double {
        let time = now()
        return lock.withLock { uses[id].map { $0.score * Self.decay(from: $0.last, to: time) } ?? 0 }
    }

    static func decay(from: Date, to: Date) -> Double {
        pow(0.5, max(0, to.timeIntervalSince(from)) / halfLife)
    }

    private func save() {
        guard let file else { return }
        let snapshot = lock.withLock { uses }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}
