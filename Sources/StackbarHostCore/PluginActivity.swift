import Foundation
import StackbarProtocol

/// What a plugin's Settings page says it is doing, beyond "Running": when it
/// last showed something new, the latest thing that went wrong, and whether
/// a change made on the page is still being handled. Everything here comes
/// from messages the host already gets (renders, error logs, `settled`), so
/// no plugin has to change.
public struct PluginActivity: Equatable, Sendable {
    /// Something that went wrong, as the plugin's error log said it.
    public struct Problem: Equatable, Sendable {
        public var message: String
        public var at: Date
    }

    /// A change taking longer than this reads "Still applying".
    public static let slowAfter: TimeInterval = 5
    /// After this the page stops waiting out loud: the plugin may be stuck,
    /// and saying "Applying…" forever would be the same mystery.
    public static let giveUpAfter: TimeInterval = 60

    /// The last time the plugin sent anything to show.
    public private(set) var lastUpdate: Date?
    /// The latest error, until the plugin restarts, a new change is made,
    /// or the user dismisses it.
    public private(set) var problem: Problem?
    /// When a change from the page was sent, while it is unanswered.
    public private(set) var applyingSince: Date?
    /// The message number the plugin has to finish for that change.
    public private(set) var applyingTarget: Int?

    public init() {}

    /// The plugin (re)started, was rebuilt or turned off: its old problem
    /// and any change in flight belong to the helper that is gone.
    public mutating func restarted() {
        problem = nil
        applyingSince = nil
        applyingTarget = nil
    }

    /// The plugin drew a surface.
    public mutating func rendered(at date: Date) {
        lastUpdate = date
    }

    /// The plugin logged something. Errors become the page's problem.
    public mutating func logged(_ level: LogLevel, _ message: String, at date: Date) {
        guard level == .error else { return }
        problem = Problem(message: Self.plain(message), at: date)
    }

    /// A control on the Settings page sent `target` (from
    /// `PluginSupervisor.event`) while the plugin had finished `settled`
    /// messages. A new change clears the old problem: it comes back if the
    /// change fails the same way.
    public mutating func settingChanged(target: Int, settled: Int, at date: Date) {
        problem = nil
        if settled >= target { return }
        applyingSince = date
        applyingTarget = target
    }

    /// The plugin finished `count` messages.
    public mutating func settled(count: Int) {
        if let target = applyingTarget, count >= target {
            applyingSince = nil
            applyingTarget = nil
        }
    }

    /// The user closed the problem.
    public mutating func dismissProblem() {
        problem = nil
    }

    /// The line under the page header.
    public struct Line: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case applying, slow, problem, updated, waiting }
        public var kind: Kind
        public var text: String
        public var detail: String?
    }

    /// What to say now. `nil` when the plugin isn't running: the header's
    /// status already says why.
    public func line(now: Date, isRunning: Bool) -> Line? {
        guard isRunning else { return nil }
        if let since = applyingSince {
            let elapsed = now.timeIntervalSince(since)
            if elapsed < Self.slowAfter { return Line(kind: .applying, text: "Applying your change…") }
            if elapsed < Self.giveUpAfter {
                return Line(kind: .slow, text: "Still applying your change (\(Int(elapsed))s)…", detail: "The plugin is working on it. Some changes refetch everything, which can take a while.")
            }
            return Line(kind: .problem, text: "Your change hasn't finished after \(Int(Self.giveUpAfter))s", detail: "The plugin may be stuck. Restart it, or look at its log in Diagnostics.")
        }
        if let problem {
            return Line(kind: .problem, text: problem.message, detail: Self.ago(problem.at, now: now).capitalizedFirst)
        }
        guard let lastUpdate else { return Line(kind: .waiting, text: "Nothing shown yet") }
        return Line(kind: .updated, text: "Updated " + Self.ago(lastUpdate, now: now))
    }

    /// "just now", "2 min ago", "3 h ago", "2 days ago".
    public static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<45: return "just now"
        case ..<3_600: return "\(max(1, Int((seconds / 60).rounded()))) min ago"
        case ..<86_400: return "\(Int(seconds / 3_600)) h ago"
        default:
            let days = Int(seconds / 86_400)
            return days == 1 ? "yesterday" : "\(days) days ago"
        }
    }

    /// The kit logs a thrown handler as `action <id> failed: <error>` and a
    /// refresh as `refresh failed: <error>`. The page shows the error with a
    /// plain lead instead of the action's internal id.
    static func plain(_ message: String) -> String {
        guard let range = message.range(of: " failed: ") else { return message }
        let what = message[..<range.lowerBound]
        let error = String(message[range.upperBound...])
        if what == "refresh" { return "Couldn't refresh: " + error }
        if what.hasPrefix("action ") { return "Couldn't apply that: " + error }
        return "Couldn't \(what): " + error
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
