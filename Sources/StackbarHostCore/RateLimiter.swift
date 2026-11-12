import Foundation
import StackbarProtocol

/// At most `limit` events per key in a sliding window of `per` seconds.
final class RateLimiter: @unchecked Sendable {
    private let limit: Int
    private let window: Double
    private let lock = NSLock()
    private var events: [String: [Date]] = [:]

    init(limit: Int, per window: Double) {
        self.limit = limit
        self.window = window
    }

    /// The refusal once `key` has used up its calls: "too many sounds; at
    /// most 10 a minute". `what` names the calls in the plural.
    func refusal(_ key: String, _ what: String, now: Date = Date()) -> HostResult? {
        guard !allow(key, now: now) else { return nil }
        let count = limit == 1 ? "one" : "\(limit)"
        let span = window == 60 ? "a minute" : "every \(Int(window)) seconds"
        return .failure("too many \(what); at most \(count) \(span)")
    }

    func allow(_ key: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var recent = (events[key] ?? []).filter { now.timeIntervalSince($0) < window }
        guard recent.count < limit else {
            events[key] = recent
            return false
        }
        recent.append(now)
        events[key] = recent
        return true
    }
}
