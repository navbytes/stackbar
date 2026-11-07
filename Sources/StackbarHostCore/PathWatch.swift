import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Says when something at a set of paths may have changed; the caller works
/// out what. On macOS the kernel's file events say so as it happens, and a
/// slow poll is only the safety net; elsewhere, or when a path can't be
/// watched that way (it can't be opened, or there are too many), it polls
/// at the caller's interval as before. Everything runs on a queue of its
/// own, never on the caller's actor.
final class PathWatch: @unchecked Sendable {
    /// Paths watched with events at most; past that it polls.
    static let maxWatchedPaths = 256
    /// The poll while every path is watched with events.
    static let safetyPoll: Double = 30

    private let interval: Double
    private let paths: @Sendable () -> [String]
    private let onTick: @Sendable () -> Void
    private let queue = DispatchQueue(label: "stackbar.path-watch", qos: .utility)
    // Touched only on `queue`.
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var tickPending = false
    private var currentPoll: Double = 0
    private var armed: [String] = []
    #if canImport(Darwin)
    private var sources: [DispatchSourceFileSystemObject] = []
    #endif

    /// `paths` is asked again after every tick, so files that came or went
    /// are watched from then on. `onTick` is called on the watch's queue.
    init(pollEvery interval: Double, paths: @escaping @Sendable () -> [String], onTick: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.paths = paths
        self.onTick = onTick
    }

    /// Arms, then looks once, so a change made before the watch was armed
    /// is not left for the slow safety poll.
    func start() {
        queue.async { [weak self] in self?.tick() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.timer?.cancel()
            self.timer = nil
            self.disarm()
        }
    }

    deinit {
        timer?.cancel()
        #if canImport(Darwin)
        for source in sources { source.cancel() }
        #endif
    }

    /// Re-arms before the caller looks, so a change made while it looks
    /// still raises an event; again after, if the paths changed.
    private func tick() {
        guard !stopped else { return }
        arm()
        onTick()
        // New paths are watched from now on; look again so a change to one
        // between the look and the re-arm isn't missed.
        var rounds = 0
        while Self.hasEvents, !stopped, rounds < 3, paths() != armed {
            arm()
            onTick()
            rounds += 1
        }
    }

    #if canImport(Darwin)
    static let hasEvents = true
    #else
    static let hasEvents = false
    #endif

    /// Watches the current paths and sets the poll to match.
    private func arm() {
        guard !stopped else { return }
        guard Self.hasEvents else { return schedulePoll(interval) }
        armed = paths()
        // Nothing to raise an event: keep the caller's poll.
        if armed.isEmpty { disarm() }
        let everyPathWatched = !armed.isEmpty && watchEvents(armed)
        schedulePoll(everyPathWatched ? max(interval, Self.safetyPoll) : interval)
    }

    private func schedulePoll(_ every: Double) {
        guard timer == nil || every != currentPoll else { return }
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + every, repeating: every, leeway: .milliseconds(Int(every * 100)))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        currentPoll = every
    }

    private func eventArrived() {
        guard !stopped, !tickPending else { return }
        // Saves come in bursts (write, rename, attributes): one look after.
        tickPending = true
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.tickPending = false
            self.tick()
        }
    }

    #if canImport(Darwin)
    /// True when every path (or, for one that doesn't exist yet, its
    /// folder) is watched.
    private func watchEvents(_ paths: [String]) -> Bool {
        disarm()
        guard paths.count <= Self.maxWatchedPaths else { return false }
        var targets = Set<String>()
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                targets.insert(path)
            } else {
                targets.insert((path as NSString).deletingLastPathComponent)
            }
        }
        var all = true
        for path in targets {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else {
                all = false
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib, .link], queue: queue)
            source.setEventHandler { [weak self] in self?.eventArrived() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
        return all
    }

    private func disarm() {
        for source in sources { source.cancel() }
        sources = []
    }
    #else
    private func watchEvents(_ paths: [String]) -> Bool { false }
    private func disarm() {}
    #endif
}
