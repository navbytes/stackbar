import Foundation
import StackbarProtocol
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// One running plugin helper and the pipes to it.
///
/// stdout and stderr are each drained on their own thread until EOF, so a
/// plugin that writes a lot can never block on a full pipe, and stdout lines go
/// through a capped `LineBuffer`. Writes to a plugin that has already exited
/// fail quietly instead of killing the host: `SIGPIPE` is ignored process-wide
/// the first time a helper starts.
///
/// Helpers are launched with `posix_spawn` as process-group leaders (see
/// `ChildProcess`). Stopping one stops everything it started: its group, and
/// every descendant found by walking the process table (Foundation's `Process`
/// gives each child a group of its own). When a helper crashes, its group is
/// killed, and so is every descendant from the last snapshot (taken every
/// few seconds) that was orphaned. A child started less than a snapshot
/// interval before a crash can still escape.
public final class PluginProcess: @unchecked Sendable {
    public enum Event: Sendable {
        case message(PluginMessage)
        case stderr(String)
        case undecodable(String)
        case exit(Int32)
    }

    public let executable: URL
    private let arguments: [String]
    private let environment: [String: String]?
    private let writes = DispatchQueue(label: "stackbar.plugin-stdin")
    private var child: ChildProcess?

    public init(executable: URL, arguments: [String] = [], environment: [String: String]? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }

    public var processIdentifier: Int32 { child?.pid ?? 0 }
    public var isRunning: Bool { child?.isRunning ?? false }
    var trackedDescendants: [Int32] { child?.trackedDescendants ?? [] }

    /// Starts the helper in its own process group. `onEvent` is called from
    /// background threads, in order per pipe; `.exit` comes last, after both
    /// pipes reached EOF and the helper was reaped.
    public func start(onEvent: @escaping @Sendable (Event) -> Void) throws {
        Self.ignoreSIGPIPE
        let child = try ChildProcess(executable: executable.path, arguments: arguments, environment: environment)
        self.child = child
        child.trackDescendants()

        let drained = DispatchGroup()
        drained.enter()
        drained.enter()
        drained.enter()
        let exitReport = Once()
        let report: @Sendable () -> Void = { exitReport.run { onEvent(.exit(child.terminationStatus ?? -1)) } }
        child.onExit { _ in
            child.sweepGroup()
            drained.leave()
            // Something the helper started may still hold its pipes open;
            // the exit is reported anyway once the pipes had a moment.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.pipeGrace) { report() }
        }

        Self.drain(child.stdout, group: drained, onDropped: {
            onEvent(.undecodable("a message over \(LineBuffer.defaultMaxLineBytes / 1024 / 1024) MB was dropped"))
        }) { line in
            if let message = try? LineCodec.decode(PluginMessage.self, from: line) {
                onEvent(.message(message))
            } else {
                onEvent(.undecodable(String(decoding: line, as: UTF8.self)))
            }
        }
        // The log budget is applied here too, on the drain thread, so a
        // plugin printing in a loop can't queue lines faster than the
        // supervisor drops them.
        let stderrBudget = Budgeted()
        Self.drain(child.stderr, group: drained, onDropped: {}) { line in
            switch stderrBudget.take() {
            case .allow(let suppressed):
                if suppressed > 0 { onEvent(.stderr("[\(suppressed) more lines were dropped]")) }
                onEvent(.stderr(String(decoding: line, as: UTF8.self)))
            case .drop:
                break
            }
        }
        drained.notify(queue: .global()) { report() }
    }

    /// Seconds after the helper exits before its exit is reported even
    /// though its pipes are still open.
    static let pipeGrace: Double = 2

    /// Writes go through one serial queue, never blocking the caller (the
    /// supervisor actor) on a full pipe; order is kept.
    public func send(_ message: HostMessage) {
        guard let child, let data = try? LineCodec.encode(message) else { return }
        writes.async { try? child.stdin.write(contentsOf: data) }
    }

    /// Asks the helper to exit, then escalates: SIGTERM to its whole process
    /// group after `grace`, SIGKILL after another `grace`. Anything the helper
    /// spawned goes with it.
    public func terminate(grace: Double = 2) {
        guard let child else { return }
        // Remember what the helper started before asking it to exit, while it
        // is still there to anchor the tree; once it exits, its children are
        // re-parented and lost.
        let started = child.descendants()
        send(.shutdown)
        writes.async { try? child.stdin.close() }
        DispatchQueue.global().async {
            if !child.wait(timeout: grace) {
                child.signalTree(SIGTERM)
                if !child.wait(timeout: grace) { child.signalTree(SIGKILL) }
            }
            // Whatever it started and left behind goes too, if it is still
            // ours: orphaned, or under the helper or another of its own. A
            // pid that was reused since is left alone.
            guard !started.isEmpty else { return }
            let ours = Set(started).union([child.pid])
            for (pid, parent) in ProcessTable.parentLinks() where ours.contains(pid) && pid != child.pid {
                guard parent == 1 || ours.contains(parent) else { continue }
                _ = killpg(pid, SIGKILL)
                _ = kill(pid, SIGKILL)
            }
        }
    }

    /// Runs `executable --manifest` and decodes what it prints.
    public static func readManifest(executable: URL, timeout: Double = 15) throws -> Manifest {
        let data = try printed(by: executable, flag: "--manifest", timeout: timeout)
        do {
            return try LineCodec.decode(Manifest.self, from: data)
        } catch {
            throw ManifestError.unreadable(executable.path, String(decoding: data.prefix(500), as: UTF8.self))
        }
    }

    /// Runs `executable --previews` and decodes what it prints. A plugin
    /// built before previews existed prints nothing, which is no previews.
    public static func readPreviews(executable: URL, timeout: Double = 15) throws -> [PreviewSpec] {
        let data = try printed(by: executable, flag: "--previews", timeout: timeout)
        if data.allSatisfy({ $0 == 0x0A || $0 == 0x20 }) { return [] }
        do {
            return try LineCodec.decode([PreviewSpec].self, from: data)
        } catch {
            throw ManifestError.unreadable(executable.path, String(decoding: data.prefix(500), as: UTF8.self))
        }
    }

    private static func printed(by executable: URL, flag: String, timeout: Double) throws -> Data {
        let child = try ChildProcess(executable: executable.path, arguments: [flag], discardStderr: true)
        try? child.stdin.close()
        let collected = Collected()
        let reader = Thread {
            collected.set(child.stdout.readDataToEndOfFile())
        }
        reader.start()
        guard child.wait(timeout: timeout) else {
            child.signalGroup(SIGKILL)
            throw ManifestError.timedOut(executable.path)
        }
        return collected.wait(timeout: 2)
    }

    private final class Collected: @unchecked Sendable {
        private var data = Data()
        private let done = DispatchSemaphore(value: 0)
        func set(_ value: Data) { data = value; done.signal() }
        func wait(timeout: Double) -> Data {
            _ = done.wait(timeout: .now() + timeout)
            return data
        }
    }

    public enum ManifestError: Error, CustomStringConvertible {
        case timedOut(String)
        case unreadable(String, String)

        public var description: String {
            switch self {
            case .timedOut(let path): return "\(path) did not answer in time"
            case .unreadable(let path, let output): return "\(path) printed no valid manifest: \(output)"
            }
        }
    }

    private static let ignoreSIGPIPE: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    private static func drain(_ handle: FileHandle, group: DispatchGroup, onDropped: @escaping @Sendable () -> Void, onLine: @escaping @Sendable (Data) -> Void) {
        let thread = Thread {
            var buffer = LineBuffer()
            // A pool per read: see `withAutoreleasePool`.
            while withAutoreleasePool({ () -> Bool in
                let chunk = handle.availableData
                if chunk.isEmpty { return false }
                let dropped = buffer.droppedLines
                for line in buffer.append(chunk) { onLine(line) }
                if buffer.droppedLines > dropped { onDropped() }
                return true
            }) {}
            group.leave()
        }
        thread.start()
    }

    /// Runs its body once, whoever calls first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) {
            let first = lock.withLock { () -> Bool in
                defer { done = true }
                return !done
            }
            if first { body() }
        }
    }

    /// `LogBudget` for the stderr drain thread.
    private final class Budgeted: @unchecked Sendable {
        private let lock = NSLock()
        private var budget = LogBudget()
        func take() -> LogBudget.Outcome { lock.withLock { budget.take() } }
    }
}
