import Foundation

/// The host messages waiting for the runtime, which handles them one at a
/// time.
///
/// Messages that only ask for the plugin's current state collapse while they
/// wait: a refresh trigger already queued for the same reason absorbs the
/// next one, and a queued visibility change for a surface takes the newest
/// value. Everything else (clicks, commands, tool calls) queues in order.
/// Without this, a host that triggers faster than `refresh()` finishes (a
/// soak at a 5-second tick, a burst of `.apps` triggers) grew the queue
/// without bound and pushed the user's clicks further behind each time.
///
/// The host counts one `settled` per message it sent, so each entry carries
/// how many messages it absorbed and the runtime settles for those too.
final class Mailbox: @unchecked Sendable {
    struct Entry {
        var message: HostMessage
        /// Messages folded into this one, each still owed a `settled`.
        var absorbed = 0
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var waiter: CheckedContinuation<Entry?, Never>?
    private var finished = false

    /// Queues `message`, or folds it into a waiting one that covers it.
    func push(_ message: HostMessage) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: Entry(message: message))
            return
        }
        if let index = entries.firstIndex(where: { Self.covers($0.message, message) }) {
            entries[index].message = message
            entries[index].absorbed += 1
        } else {
            entries.append(Entry(message: message))
        }
        lock.unlock()
    }

    /// No more messages: the runtime finishes what is queued, then `next`
    /// answers `nil`.
    func finish() {
        lock.lock()
        finished = true
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(returning: nil)
    }

    /// The next message, waiting for one if none is queued. One consumer.
    func next() async -> Entry? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if !entries.isEmpty {
                let entry = entries.removeFirst()
                if entries.isEmpty { entries = [] }
                lock.unlock()
                continuation.resume(returning: entry)
            } else if finished {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    /// Messages waiting, for tests.
    var count: Int { lock.withLock { entries.count } }

    /// Whether `queued`, still waiting, makes `new` redundant once it takes
    /// `new`'s values.
    static func covers(_ queued: HostMessage, _ new: HostMessage) -> Bool {
        switch (queued, new) {
        case (.trigger(let a), .trigger(let b)): a == b
        case (.visibility(let a, _), .visibility(let b, _)): a == b
        default: false
        }
    }
}
