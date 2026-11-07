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
    /// Whether `text` should go to `spec`'s root search: it is a root-search
    /// view the user hasn't turned off, and the text matches its pattern.
    public static func accepts(_ spec: CommandSpec, text: String, preference: CommandPreference = .default) -> Bool {
        guard spec.rootSearch, spec.kind == .view, preference.enabled, preference.inRootSearch else { return false }
        return matches(spec, text: text)
    }

    /// Whether the whole of `text` matches the command's root pattern;
    /// always true without one, never for a pattern that doesn't compile.
    public static func matches(_ spec: CommandSpec, text: String) -> Bool {
        guard let pattern = spec.rootPattern else { return true }
        guard let regex = cache.regex(pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [.anchored], range: range) != nil
    }

    /// Whether `spec` is offered as a fallback for typed text.
    public static func offersFallback(_ spec: CommandSpec, preference: CommandPreference = .default) -> Bool {
        spec.fallback && preference.enabled && preference.inRootSearch
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
