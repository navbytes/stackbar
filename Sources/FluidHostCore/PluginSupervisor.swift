import Foundation
import FluidProtocol

/// Keeps one plugin alive and turns its messages into state the UI can show.
///
/// The supervisor owns the helper process: it says hello (with the plugin's
/// saved values), fires the manifest's triggers, forwards the user's events,
/// answers host calls through `HostServices`, routes topics and tool calls,
/// remembers the latest tree per surface, and restarts the helper with backoff
/// when it exits unexpectedly. The last trees stay on screen through a
/// restart, so a crash shows as a brief stale moment rather than an empty panel.
///
/// Process events are funnelled through one `AsyncStream` and handled in the
/// order they arrived, so a render can never be overtaken by an older one.
public actor PluginSupervisor {
    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case running
        case restarting(attempt: Int, inSeconds: Double)
        case failed(String)
    }

    public enum Update: Sendable {
        case state(State)
        case render(Surface, ViewNode)
        case log(LogLevel, String)
        case tools([ToolSpec])
    }

    public nonisolated let executable: URL
    public nonisolated let manifest: Manifest
    private let policy: BackoffPolicy
    private let environment: [String: String]?
    private let services: HostServices?
    private var inFlight = 0
    private var logBudget = LogBudget()
    private let onUpdate: @Sendable (Update) -> Void
    /// The capabilities the user approved; host calls are checked against
    /// these, not against whatever the manifest asks for.
    public private(set) var granted: Manifest

    public private(set) var state: State = .stopped
    public private(set) var views: [Surface: ViewNode] = [:]
    public private(set) var tools: [ToolSpec] = []
    public private(set) var restarts = 0
    /// What the helper's last descendant snapshot found (for tests).
    var trackedDescendants: [Int32] { process?.trackedDescendants ?? [] }
    /// The running helper's process id, for memory sampling.
    public var helperPID: Int32? { process.map(\.processIdentifier).flatMap { $0 > 0 ? $0 : nil } }
    /// How many host messages the current helper has finished handling. Tools
    /// and tests wait on it instead of guessing with sleeps.
    public private(set) var settledCount = 0
    /// Messages sent to the current helper that it answers with `settled`.
    private var sentCount = 0
    /// `sentCount` right after the last timer and file triggers, so a new one
    /// is skipped while the plugin hasn't got to the previous one yet.
    private var triggerMarks: [TriggerReason: Int] = [:]

    private var process: PluginProcess?
    private var generation = 0
    private var consecutiveFailures = 0
    private var startedAt = ContinuousClock.now
    private var stopping = false
    private var consumer: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var clipboardWatcher: Task<Void, Never>?
    private var pendingRestart: Task<Void, Never>?
    private var nextToolCall = 1
    private var toolCalls: [Int: CheckedContinuation<(text: String, isError: Bool), Never>] = [:]

    public init(executable: URL, manifest: Manifest, grantedCapabilities: [Capability]? = nil, policy: BackoffPolicy = .standard, environment: [String: String]? = nil, services: HostServices? = nil, onUpdate: @escaping @Sendable (Update) -> Void = { _ in }) {
        self.executable = executable
        self.manifest = manifest
        var granted = manifest
        if let grantedCapabilities { granted.capabilities = grantedCapabilities }
        self.granted = granted
        self.policy = policy
        self.environment = environment
        self.services = services
        self.onUpdate = onUpdate
    }

    /// Reads the plugin's manifest, then returns a supervisor for it (not yet started).
    public static func make(executable: URL, policy: BackoffPolicy = .standard, environment: [String: String]? = nil, services: HostServices? = nil, onUpdate: @escaping @Sendable (Update) -> Void = { _ in }) throws -> PluginSupervisor {
        let manifest = try PluginProcess.readManifest(executable: executable)
        return PluginSupervisor(executable: executable, manifest: manifest, policy: policy, environment: environment, services: services, onUpdate: onUpdate)
    }

    public func start() async {
        stopping = false
        consecutiveFailures = 0
        await spawn()
    }

    /// Stops the helper and every timer. Safe to call more than once.
    public func stop() async {
        stopping = true
        pendingRestart?.cancel()
        ticker?.cancel()
        watcher?.cancel()
        clipboardWatcher?.cancel()
        process?.terminate()
        process = nil
        services?.release(pluginID: manifest.id)
        failToolCalls("the plugin stopped")
        await services?.bus.unsubscribe(manifest.id)
        setState(.stopped)
    }

    /// Changes what the plugin may do from now on (after an update sheet).
    public func grant(_ capabilities: [Capability]) {
        granted.capabilities = capabilities
    }

    public func send(_ message: HostMessage) {
        guard state == .running || state == .starting, let process else { return }
        switch message {
        case .response, .shutdown: break
        default: sentCount += 1
        }
        process.send(message)
    }

    /// A timer or file trigger, unless the previous one of the same kind is
    /// still waiting. A refresh slower than its interval would otherwise
    /// queue triggers without bound and push the user's clicks behind them.
    private func sendCoalesced(_ reason: TriggerReason) {
        if let mark = triggerMarks[reason], settledCount < mark { return }
        send(.trigger(reason: reason))
        triggerMarks[reason] = sentCount
    }

    /// A user event: a click, a toggle, a filtered row.
    public func event(_ action: ActionID, value: EventValue? = nil) {
        send(.event(action: action, value: value))
    }

    public func refresh() {
        send(.trigger(reason: .manual))
    }

    /// The Mac woke from sleep. Only plugins that asked for `.wake` hear it.
    public func wake() {
        if manifest.triggers.contains(.wake) { send(.trigger(reason: .wake)) }
    }

    public func setVisible(_ surface: Surface, _ visible: Bool) {
        send(.visibility(surface: surface, visible: visible))
    }

    /// Calls one of the plugin's tools and waits for its answer.
    public func callTool(_ name: String, arguments: [String: EventValue] = [:], timeout: Double = 60) async -> (text: String, isError: Bool) {
        guard state == .running, let process else { return ("\(manifest.name) is not running", true) }
        let id = nextToolCall
        nextToolCall += 1
        let currentGeneration = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            await self?.finishToolCall(id, text: "\(name) timed out after \(Int(timeout))s", isError: true, generation: currentGeneration)
        }
        return await withCheckedContinuation { continuation in
            toolCalls[id] = continuation
            sentCount += 1
            process.send(.callTool(id: id, name: name, arguments: arguments))
        }
    }

    /// Messages the host sends a fresh helper before anything else: `hello`,
    /// plus a launch trigger when the manifest asks for one.
    public nonisolated var startupMessageCount: Int {
        manifest.triggers.contains(.launch) ? 2 : 1
    }

    // MARK: - Process lifecycle

    private func spawn() async {
        generation += 1
        let current = generation
        setState(.starting)
        let storage = await services?.storage.snapshot(for: manifest.id) ?? [:]
        guard current == generation, !stopping else { return }
        let helper = PluginProcess(executable: executable, environment: environment)
        let (events, continuation) = AsyncStream.makeStream(of: PluginProcess.Event.self)
        do {
            try helper.start { continuation.yield($0) }
        } catch {
            continuation.finish()
            onUpdate(.log(.error, "could not launch \(executable.lastPathComponent): \(error)"))
            handleExit(status: -1, generation: current)
            return
        }
        process = helper
        startedAt = .now
        settledCount = 0
        sentCount = startupMessageCount
        triggerMarks = [:]
        consumer = Task { [weak self] in
            for await event in events {
                await self?.handle(event, generation: current)
            }
        }
        let offered = manifest.surfaces.filter(Surface.allCases.contains)
        helper.send(.hello(protocolVersion: FluidProtocolVersion.current, surfaces: offered, storage: storage))
        if manifest.triggers.contains(.launch) {
            helper.send(.trigger(reason: .launch))
        }
        startTicker()
        startWatcher()
        startClipboardWatcher()
        if let services, !manifest.topics.isEmpty {
            await services.bus.subscribe(manifest.id, to: manifest.topics) { [weak self] topic, payload, from in
                Task { await self?.send(.topic(name: topic, payload: payload, from: from)) }
            }
        }
    }

    private func startTicker() {
        ticker?.cancel()
        guard let interval = manifest.refreshInterval else { return }
        let seconds = max(1, interval)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.sendCoalesced(.interval)
            }
        }
    }

    /// Polls the manifest's watched files every two seconds. Polling is dumb
    /// but works the same on every platform and inside the sandbox.
    private func startWatcher() {
        watcher?.cancel()
        let paths = manifest.watchedFiles.map { NSString(string: $0).expandingTildeInPath }
        guard !paths.isEmpty else { return }
        watcher = Task { [weak self] in
            var last = FileStamp.stamps(paths)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                let now = FileStamp.stamps(paths)
                if now != last {
                    last = now
                    await self?.sendCoalesced(.file)
                }
            }
        }
    }

    /// Polls the clipboard's change count twice a second for a plugin with a
    /// `.clipboard` trigger and the approved `.clipboard` capability. The
    /// count is one integer, so polling costs next to nothing.
    private func startClipboardWatcher() {
        clipboardWatcher?.cancel()
        guard manifest.triggers.contains(.clipboard), let system = services?.platform.system else { return }
        clipboardWatcher = Task { [weak self] in
            var last = system.clipboardChangeCount()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                let now = system.clipboardChangeCount()
                guard now != last else { continue }
                last = now
                await self?.clipboardChanged()
            }
        }
    }

    private func clipboardChanged() {
        guard granted.capabilities.contains(.clipboard) else { return }
        send(.trigger(reason: .clipboard))
    }

    private func handle(_ event: PluginProcess.Event, generation eventGeneration: Int) {
        guard eventGeneration == generation else { return }
        switch event {
        case .message(.ready(let version)):
            if version != FluidProtocolVersion.current {
                onUpdate(.log(.warning, "plugin speaks protocol \(version), host speaks \(FluidProtocolVersion.current); rebuild it"))
            }
            setState(.running)
        case .message(.render(let surface, let root)):
            views[surface] = root
            onUpdate(.render(surface, root))
        case .message(.log(let level, let message)):
            emitPluginLog(level, message)
        case .message(.settled):
            settledCount += 1
        case .message(.request(let id, let call)):
            answer(id, call, generation: eventGeneration)
        case .message(.tools(let specs)):
            tools = specs
            onUpdate(.tools(specs))
        case .message(.toolResult(let id, let text, let isError)):
            finishToolCall(id, text: text, isError: isError, generation: eventGeneration)
        case .stderr(let line):
            emitPluginLog(.debug, line)
        case .undecodable(let line):
            onUpdate(.log(.warning, "unreadable message from plugin: \(line.prefix(200))"))
        case .exit(let status):
            handleExit(status: status, generation: eventGeneration)
        }
    }

    private func answer(_ id: Int, _ call: HostCall, generation callGeneration: Int) {
        guard let services else {
            process?.send(.response(id: id, result: .failure("host services are not available here")))
            return
        }
        guard inFlight < Self.maxInFlight else {
            process?.send(.response(id: id, result: .failure("too many host calls in flight; at most \(Self.maxInFlight)")))
            return
        }
        inFlight += 1
        let granted = granted
        Task { [weak self] in
            let result = await services.handle(call, for: granted)
            await self?.respond(id, result, generation: callGeneration)
        }
    }

    /// Passes a plugin's own log line on, at most `LogBudget.limit` lines per
    /// window; past that, lines are counted and summarised once the window
    /// ends, so a plugin stuck printing in a loop cannot flood the host log.
    private func emitPluginLog(_ level: LogLevel, _ message: String) {
        switch logBudget.take() {
        case .allow(let suppressed):
            if suppressed > 0 { onUpdate(.log(.warning, "suppressed \(suppressed) log lines from this plugin")) }
            onUpdate(.log(level, String(message.prefix(4000))))
        case .drop:
            break
        }
    }

    /// Host calls one plugin may have outstanding at once.
    static let maxInFlight = 32

    private func respond(_ id: Int, _ result: HostResult, generation callGeneration: Int) {
        inFlight = max(0, inFlight - 1)
        guard callGeneration == generation else { return }
        process?.send(.response(id: id, result: result))
    }

    private func finishToolCall(_ id: Int, text: String, isError: Bool, generation callGeneration: Int) {
        guard callGeneration == generation, let continuation = toolCalls.removeValue(forKey: id) else { return }
        continuation.resume(returning: (text, isError))
    }

    private func failToolCalls(_ reason: String) {
        let calls = toolCalls
        toolCalls = [:]
        for continuation in calls.values { continuation.resume(returning: (reason, true)) }
    }

    private func handleExit(status: Int32, generation exitGeneration: Int) {
        guard exitGeneration == generation else { return }
        ticker?.cancel()
        watcher?.cancel()
        clipboardWatcher?.cancel()
        process = nil
        // A crashed plugin must not keep the Mac awake; a restarted one asks again.
        services?.release(pluginID: manifest.id)
        failToolCalls("the plugin exited")
        if stopping {
            setState(.stopped)
            return
        }
        if ContinuousClock.now - startedAt > .seconds(policy.stableAfter) {
            consecutiveFailures = 0
        }
        consecutiveFailures += 1
        guard let delay = policy.delay(afterFailures: consecutiveFailures) else {
            setState(.failed("exited with status \(status), \(consecutiveFailures) times in a row"))
            return
        }
        onUpdate(.log(.warning, "plugin exited with status \(status); restarting in \(delay)s"))
        setState(.restarting(attempt: consecutiveFailures, inSeconds: delay))
        pendingRestart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.restart(after: exitGeneration)
        }
    }

    private func restart(after exitGeneration: Int) async {
        guard !stopping, exitGeneration == generation else { return }
        restarts += 1
        await spawn()
    }

    private func setState(_ newState: State) {
        guard newState != state else { return }
        state = newState
        onUpdate(.state(newState))
    }
}

/// Modification dates and sizes for a set of paths (and a folder's direct
/// children), compared between polls.
enum FileStamp {
    static func stamps(_ paths: [String]) -> [String: String] {
        var result: [String: String] = [:]
        let manager = FileManager.default
        for path in paths {
            result[path] = stamp(path)
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                for child in (try? manager.contentsOfDirectory(atPath: path)) ?? [] {
                    let full = (path as NSString).appendingPathComponent(child)
                    result[full] = stamp(full)
                }
            }
        }
        return result
    }

    private static func stamp(_ path: String) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return "missing" }
        let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return "\(date)-\(size)"
    }
}

/// At most `limit` log lines per `window` seconds; the rest are counted.
struct LogBudget {
    static let limit = 200
    static let window: Double = 10
    enum Outcome: Equatable {
        /// Pass the line; `suppressed` lines were dropped since the last one passed.
        case allow(suppressed: Int)
        case drop
    }

    private var windowStart = Date.distantPast
    private var used = 0
    private var dropped = 0

    mutating func take(now: Date = Date()) -> Outcome {
        if now.timeIntervalSince(windowStart) >= Self.window {
            windowStart = now
            used = 0
        }
        guard used < Self.limit else {
            dropped += 1
            return .drop
        }
        used += 1
        defer { dropped = 0 }
        return .allow(suppressed: dropped)
    }
}
