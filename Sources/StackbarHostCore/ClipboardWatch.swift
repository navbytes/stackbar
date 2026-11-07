import Foundation

/// One clipboard poll shared by every plugin with a `.clipboard` trigger.
///
/// The change count is read twice a second on a queue of its own (the app's
/// read hops to the main thread), never on a plugin's supervisor, so a busy
/// main thread can't stall the plugins' message handling, and five plugins
/// cost one read instead of five. The poll runs only while someone listens.
public final class ClipboardWatch: @unchecked Sendable {
    private let interval: Double
    private let read: @Sendable () -> Int
    private let queue = DispatchQueue(label: "stackbar.clipboard-watch", qos: .utility)
    private let lock = NSLock()
    private var listeners: [UUID: @Sendable () -> Void] = [:]
    private var timer: DispatchSourceTimer?
    private var last = 0

    public init(interval: Double = 0.5, read: @escaping @Sendable () -> Int) {
        self.interval = interval
        self.read = read
    }

    /// Calls `onChange`, on the watch's queue, after each change from now
    /// on, until `remove` with the returned token.
    public func add(_ onChange: @escaping @Sendable () -> Void) -> UUID {
        let token = UUID()
        lock.withLock {
            listeners[token] = onChange
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            // The starting count, read on the queue before the first tick.
            queue.async { [weak self] in
                guard let self else { return }
                let count = self.read()
                self.lock.withLock { self.last = count }
            }
            timer.resume()
        }
        return token
    }

    public func remove(_ token: UUID) {
        lock.withLock {
            listeners[token] = nil
            guard listeners.isEmpty, let timer else { return }
            timer.cancel()
            self.timer = nil
        }
    }

    /// Whether the poll is running (for tests).
    var isPolling: Bool { lock.withLock { timer != nil } }

    private func poll() {
        let count = read()
        let notify = lock.withLock { () -> [@Sendable () -> Void] in
            guard count != last else { return [] }
            last = count
            return Array(listeners.values)
        }
        for listener in notify { listener() }
    }
}
