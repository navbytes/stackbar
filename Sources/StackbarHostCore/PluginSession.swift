import Foundation
import StackbarProtocol

/// One plugin, built and running headless, with a log and a way to wait until
/// it has finished handling what it was sent. `stackbarctl` and both MCP servers
/// drive plugins through this.
public actor PluginSession {
    public let source: URL
    private let builder: PluginBuilder?
    private let services: HostServices?
    private var supervisor: PluginSupervisor?
    private var binary: URL?
    private var expected = 0
    private var logLines: [String] = []
    private let maxLogLines = 500

    public init(source: URL, builder: PluginBuilder?, services: HostServices?) {
        self.source = source
        self.builder = builder
        self.services = services
    }

    public var manifest: Manifest? { supervisor?.manifest }
    public var isRunning: Bool { supervisor != nil }

    /// Builds the plugin (when it is a `.swift` file) and starts it, or
    /// restarts it when the build produced a different helper. Throws
    /// `PluginBuilder.Failure` with diagnostics when it doesn't compile.
    @discardableResult
    public func ensureRunning() async throws -> Bool {
        let built: URL
        if source.pathExtension == "swift" {
            guard let builder else { throw SessionError.noBuilder }
            built = try await Task.detached { try builder.build(source: self.source).binary }.value
        } else {
            built = source
        }
        if let supervisor, built == binary, await supervisor.state != .stopped {
            if case .failed = await supervisor.state {} else { return false }
        }
        await supervisor?.stop()
        let manifest = try PluginProcess.readManifest(executable: built)
        let problems = manifest.problems
        if !problems.isEmpty { throw SessionError.badManifest(problems) }
        let next = PluginSupervisor(executable: built, manifest: manifest, policy: BackoffPolicy(initialDelay: 0.2, multiplier: 2, maxDelay: 2, maxConsecutiveFailures: 2), services: services) { [weak self] update in
            Task { await self?.record(update) }
        }
        supervisor = next
        binary = built
        expected = next.startupMessageCount
        await next.start()
        try await settle()
        return true
    }

    public func view(_ surface: Surface) async -> ViewNode? {
        await supervisor?.views[surface]
    }

    public func views() async -> [Surface: ViewNode] {
        await supervisor?.views ?? [:]
    }

    public func tools() async -> [ToolSpec] {
        await supervisor?.tools ?? []
    }

    /// The plugin's left-click action on its menu-bar item, if any.
    public func menuBarClick() async -> MenuBarClick? {
        await supervisor?.menuBarClick
    }

    public func state() async -> PluginSupervisor.State {
        await supervisor?.state ?? .stopped
    }

    /// Sends an event and waits until the plugin has handled it.
    public func event(_ action: ActionID, value: EventValue? = nil) async throws {
        guard let supervisor else { throw SessionError.notRunning }
        let actions = await supervisor.views.values.flatMap(\.actions)
        guard actions.contains(action) else {
            throw SessionError.unknownAction(action, available: actions)
        }
        await supervisor.event(action, value: value)
        expected += 1
        try await settle()
    }

    public func refresh() async throws {
        guard let supervisor else { throw SessionError.notRunning }
        await supervisor.refresh()
        expected += 1
        try await settle()
    }

    /// Fires a trigger (a simulated copy, say) and waits until it is handled.
    public func trigger(_ reason: TriggerReason) async throws {
        guard let supervisor else { throw SessionError.notRunning }
        await supervisor.send(.trigger(reason: reason))
        expected += 1
        try await settle()
    }

    public func callTool(_ name: String, arguments: [String: EventValue]) async throws -> (text: String, isError: Bool) {
        guard let supervisor else { throw SessionError.notRunning }
        let result = await supervisor.callTool(name, arguments: arguments)
        expected += 1
        try? await settle()
        return result
    }

    public func logs(last count: Int = 50) -> [String] {
        Array(logLines.suffix(count))
    }

    public func stop() async {
        await supervisor?.stop()
        supervisor = nil
        binary = nil
    }

    private func record(_ update: PluginSupervisor.Update) {
        switch update {
        case .log(let level, let message): logLines.append("[\(level.rawValue)] \(message)")
        case .state(let state): logLines.append("[state] \(state)")
        case .render, .tools, .menuBarClick: return
        }
        if logLines.count > maxLogLines { logLines.removeFirst(logLines.count - maxLogLines) }
    }

    private func settle(timeout: Double = 30) async throws {
        guard let supervisor else { throw SessionError.notRunning }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = await supervisor.state
            if case .failed(let reason) = state { throw SessionError.failed(reason, logs: logs(last: 20)) }
            if await supervisor.settledCount >= expected { return }
            if case .restarting = state {
                // A crash reset the count; wait for the fresh helper instead.
                expected = supervisor.startupMessageCount
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw SessionError.timedOut(logs: logs(last: 20))
    }

    public enum SessionError: Error, CustomStringConvertible {
        case noBuilder
        case notRunning
        case badManifest([String])
        case unknownAction(ActionID, available: [ActionID])
        case failed(String, logs: [String])
        case timedOut(logs: [String])

        public var description: String {
            switch self {
            case .noBuilder: return "no plugin builder is configured"
            case .notRunning: return "the plugin is not running"
            case .badManifest(let problems): return "the manifest has problems:\n- " + problems.joined(separator: "\n- ")
            case .unknownAction(let action, let available):
                return "no control has the action id \(action). Available: " + (available.isEmpty ? "none" : available.map(\.rawValue).joined(separator: ", "))
            case .failed(let reason, let logs): return "the plugin failed (\(reason)). Recent log:\n" + logs.joined(separator: "\n")
            case .timedOut(let logs): return "the plugin did not finish in time. Recent log:\n" + logs.joined(separator: "\n")
            }
        }
    }
}
