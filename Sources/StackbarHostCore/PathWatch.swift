import Foundation

/// Polls a set of paths on a queue of its own, never on the caller's actor,
/// and says when to look; the caller works out what changed.
///
/// A file-event version (vnode dispatch sources with a slow safety poll)
/// was tried and missed changes in the macOS tests, so it polls everywhere;
/// the idle probe measured the poll as negligible.
final class PathWatch: @unchecked Sendable {
    private let interval: Double
    private let onTick: @Sendable () -> Void
    private let queue = DispatchQueue(label: "stackbar.path-watch", qos: .utility)
    // Touched only on `queue`.
    private var timer: DispatchSourceTimer?
    private var stopped = false

    /// `paths` is kept for callers that list what they watch; the poll
    /// itself doesn't need it. `onTick` is called on the watch's queue.
    init(pollEvery interval: Double, paths: @escaping @Sendable () -> [String], onTick: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.stopped, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            let every = self.interval
            timer.schedule(deadline: .now() + every, repeating: every, leeway: .milliseconds(Int(every * 100)))
            timer.setEventHandler { [weak self] in
                guard let self, !self.stopped else { return }
                self.onTick()
            }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.timer?.cancel()
            self.timer = nil
        }
    }

    deinit {
        timer?.cancel()
    }
}
