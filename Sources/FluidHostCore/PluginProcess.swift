import Foundation
import FluidProtocol
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
    private let writeLock = NSLock()
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
        child.onExit { _ in
            child.sweepGroup()
            drained.leave()
        }

        Self.drain(child.stdout, group: drained) { line in
            if let message = try? LineCodec.decode(PluginMessage.self, from: line) {
                onEvent(.message(message))
            } else {
                onEvent(.undecodable(String(decoding: line, as: UTF8.self)))
            }
        }
        Self.drain(child.stderr, group: drained) { line in
            onEvent(.stderr(String(decoding: line, as: UTF8.self)))
        }
        drained.notify(queue: .global()) {
            onEvent(.exit(child.terminationStatus ?? -1))
        }
    }

    public func send(_ message: HostMessage) {
        guard let child, let data = try? LineCodec.encode(message) else { return }
        writeLock.lock()
        defer { writeLock.unlock() }
        try? child.stdin.write(contentsOf: data)
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
        writeLock.lock()
        try? child.stdin.close()
        writeLock.unlock()
        DispatchQueue.global().async {
            if !child.wait(timeout: grace) {
                child.signalTree(SIGTERM)
                if !child.wait(timeout: grace) { child.signalTree(SIGKILL) }
            }
            // Whatever it started and left behind goes too.
            for pid in started {
                _ = killpg(pid, SIGKILL)
                _ = kill(pid, SIGKILL)
            }
        }
    }

    /// Runs `executable --manifest` and decodes what it prints.
    public static func readManifest(executable: URL, timeout: Double = 15) throws -> Manifest {
        let child = try ChildProcess(executable: executable.path, arguments: ["--manifest"], discardStderr: true)
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
        let data = collected.wait(timeout: 2)
        do {
            return try LineCodec.decode(Manifest.self, from: data)
        } catch {
            throw ManifestError.unreadable(executable.path, String(decoding: data.prefix(500), as: UTF8.self))
        }
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
            case .timedOut(let path): return "\(path) did not print its manifest in time"
            case .unreadable(let path, let output): return "\(path) printed no valid manifest: \(output)"
            }
        }
    }

    private static let ignoreSIGPIPE: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    private static func drain(_ handle: FileHandle, group: DispatchGroup, onLine: @escaping @Sendable (Data) -> Void) {
        let thread = Thread {
            var buffer = LineBuffer()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                for line in buffer.append(chunk) { onLine(line) }
            }
            group.leave()
        }
        thread.start()
    }
}
