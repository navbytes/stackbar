import Foundation
import StackbarProtocol

/// Which root-search commands the palette asks about what was typed, and
/// how long it waits for them.
///
/// Many plugins answering every keystroke is only fine while each one is
/// quick and only asked about text it can answer. A command's root pattern
/// keeps other text from it; the user can turn a command's root search off;
/// and one that is slow several times in a row is left out for a while.
public enum RootSearchGate {
    /// Whether `text` should go to `entry`'s root search: it is a
    /// root-search view, on for the main search, and the text matches its
    /// pattern.
    public static func accepts(_ entry: CommandRegistry.Entry, text: String, preference: CommandPreference = .default) -> Bool {
        searches(entry.spec, preference: preference) && isOn(entry, preference: preference) && matches(entry.spec, text: text)
    }

    /// Whether the command can search from the palette at all: a
    /// root-search view the user hasn't turned off. An alias typed before
    /// the text (`gs stackbar`) reaches it even when it is off for the main
    /// search, and whatever its pattern.
    public static func searches(_ spec: CommandSpec, preference: CommandPreference = .default) -> Bool {
        spec.rootSearch && spec.kind == .view && preference.enabled
    }

    /// Whether a root-search command answers in the main search: the
    /// user's choice, else `defaultOn`.
    public static func isOn(_ entry: CommandRegistry.Entry, preference: CommandPreference = .default) -> Bool {
        preference.inRootSearch ?? defaultOn(entry)
    }

    /// On by default: the core plugins (apps, sums, files), and commands
    /// with a root pattern, which only ever see text of their own shape.
    /// A plugin answering any text is off until the user turns it on: a
    /// plugin asks for the main search, the user decides.
    public static func defaultOn(_ entry: CommandRegistry.Entry) -> Bool {
        entry.spec.rootPattern != nil || BundledStore.corePluginIDs.contains(entry.pluginID)
    }

    /// Whether the whole of `text` matches the command's root pattern;
    /// always true without one, never for a pattern that doesn't compile.
    public static func matches(_ spec: CommandSpec, text: String) -> Bool {
        guard let pattern = spec.rootPattern else { return true }
        guard let regex = cache.regex(pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [.anchored], range: range) != nil
    }

    /// Whether `spec` can be a fallback: one the user hasn't disabled.
    /// Which are offered, and in what order, is `PaletteFallbacks`.
    public static func offersFallback(_ spec: CommandSpec, preference: CommandPreference = .default) -> Bool {
        spec.fallback && preference.enabled
    }

    private static let cache = RegexCache()

    private final class RegexCache: @unchecked Sendable {
        private let lock = NSLock()
        private var compiled: [String: NSRegularExpression?] = [:]

        func regex(_ pattern: String) -> NSRegularExpression? {
            lock.withLock {
                if let known = compiled[pattern] { return known }
                // The pattern as written must compile; it is then matched as
                // a whole, so that an alternative matching only a prefix
                // (`\d+|\d+-\d+` on `12-3`) doesn't hide one matching all.
                let made = (try? NSRegularExpression(pattern: pattern)).flatMap { _ in
                    try? NSRegularExpression(pattern: "\\A(?:\(pattern))\\z")
                }
                compiled[pattern] = made
                return made
            }
        }
    }
}

/// How long each root search takes to answer, so one slow plugin can't make
/// typing at the root feel slow.
///
/// A command whose last `strikes` answers each took longer than `limit` is
/// benched for `bench`: the palette stops asking it, though its own command
/// still works. One quick answer clears its strikes.
public final class RootSearchBudget: @unchecked Sendable {
    public let limit: TimeInterval
    public let strikes: Int
    public let bench: TimeInterval

    private struct Record {
        var slow = 0
        var benchedUntil: Date?
    }

    private let lock = NSLock()
    private var records: [CommandKey: Record] = [:]

    public init(limit: TimeInterval = 0.4, strikes: Int = 3, bench: TimeInterval = 10 * 60) {
        self.limit = limit
        self.strikes = strikes
        self.bench = bench
    }

    /// Notes how long an answer took. True when that benches the command.
    @discardableResult
    public func record(_ key: CommandKey, took seconds: TimeInterval, now: Date = Date()) -> Bool {
        lock.withLock {
            var record = records[key] ?? Record()
            guard seconds > limit else {
                record.slow = 0
                records[key] = record
                return false
            }
            record.slow += 1
            let benched = record.slow >= strikes
            if benched {
                record.slow = 0
                record.benchedUntil = now.addingTimeInterval(bench)
            }
            records[key] = record
            return benched
        }
    }

    /// Whether the palette should leave the command out for now.
    public func isBenched(_ key: CommandKey, now: Date = Date()) -> Bool {
        lock.withLock {
            guard let until = records[key]?.benchedUntil else { return false }
            if until > now { return true }
            records[key]?.benchedUntil = nil
            return false
        }
    }

    /// Forgets a plugin's records, when it restarts or is updated.
    public func forget(pluginID: String) {
        lock.withLock { records = records.filter { $0.key.pluginID != pluginID } }
    }
}

/// The fallback commands the palette offers under what was typed: the
/// user's list in Settings, in its order, or `defaults` until they choose.
public enum PaletteFallbacks {
    /// Search Google and Ask AI, as Raycast starts with a web search.
    public static let defaults: [CommandKey] = [
        CommandKey(pluginID: "io.navbytes.stackbar.quicklinks", commandID: "web-search"),
        CommandKey(pluginID: "io.navbytes.stackbar.plugins.ask-ai", commandID: "ask"),
    ]

    /// Offered only while fewer rows than this match what was typed.
    public static let threshold = 3

    /// The fallbacks to offer, in order, among `available` (the enabled
    /// `.fallback()` commands). `chosen` is the user's list; unset, it is
    /// `defaults` less any the user had turned off before lists existed.
    public static func offered(_ available: [CommandRegistry.Entry], chosen: [CommandKey]?,
                               preference: (CommandKey) -> CommandPreference) -> [CommandRegistry.Entry] {
        let byKey = Dictionary(available.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let list = chosen ?? defaults.filter { preference($0).inRootSearch != false }
        return list.compactMap { byKey[$0] }
    }
}
