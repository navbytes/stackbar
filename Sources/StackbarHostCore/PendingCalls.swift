import Foundation

/// Calls sent to a plugin that are waiting for its answer, each with a
/// timeout. A call is answered exactly once: by the plugin, by its timeout,
/// or by `failAll` when the plugin goes away; whichever comes later finds
/// nothing waiting and does nothing.
///
/// A value the supervisor keeps inside its actor, one per kind of call
/// (agent tools, run commands), so nothing here locks.
struct PendingCalls<Answer: Sendable> {
    private var nextID = 1
    private var waiting: [Int: CheckedContinuation<Answer, Never>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]

    /// Timeouts still running.
    var openTimeouts: Int { timeouts.count }

    /// The id of a new call; ids count up from 1 and are not reused.
    mutating func newID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// The task that answers the call when the plugin doesn't in time. It
    /// is cancelled when the call ends another way.
    mutating func setTimeout(_ timeout: Task<Void, Never>, for id: Int) {
        timeouts[id] = timeout
    }

    /// Who hears the call's answer.
    mutating func wait(for id: Int, _ continuation: CheckedContinuation<Answer, Never>) {
        waiting[id] = continuation
    }

    /// Answers the call and cancels its timeout. False when nobody is
    /// waiting on `id` any more (it was already answered).
    @discardableResult
    mutating func finish(_ id: Int, with answer: Answer) -> Bool {
        guard let continuation = waiting.removeValue(forKey: id) else { return false }
        timeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(returning: answer)
        return true
    }

    /// Answers every waiting call with `answer` and cancels every timeout.
    mutating func failAll(with answer: Answer) {
        let calls = waiting
        waiting = [:]
        for timeout in timeouts.values { timeout.cancel() }
        timeouts = [:]
        for continuation in calls.values { continuation.resume(returning: answer) }
    }
}
