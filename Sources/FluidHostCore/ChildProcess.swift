import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A child process started with `posix_spawn` as the leader of its own process
/// group, so `signalGroup` reaches everything it spawned too (a plugin that
/// shells out cannot leave orphans behind).
///
/// Every pipe end the host keeps is close-on-exec, so concurrent spawns never
/// inherit each other's pipes and a helper's EOF arrives when it should.
public final class ChildProcess: @unchecked Sendable {
    public let pid: pid_t
    public let stdin: FileHandle
    public let stdout: FileHandle
    public let stderr: FileHandle

    private let lock = NSLock()
    private var exitStatus: Int32?
    private let exited = DispatchSemaphore(value: 0)
    private var exitHandlers: [@Sendable (Int32) -> Void] = []
    private var snapshot: [pid_t] = []
    private var tracker: DispatchSourceTimer?

    public enum SpawnError: Error, CustomStringConvertible {
        case failed(String, Int32)
        public var description: String {
            switch self {
            case .failed(let path, let code): return "could not start \(path): \(String(cString: strerror(code)))"
            }
        }
    }

    /// Starts `executable`. `environment` nil inherits the host's.
    /// `discardStderr` sends stderr to /dev/null.
    public init(executable: String, arguments: [String] = [], environment: [String: String]? = nil, discardStderr: Bool = false) throws {
        let input = try Self.pipe()
        let output = try Self.pipe()
        let errors = try Self.pipe()

        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        #endif
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_adddup2(&actions, input.read, 0)
        posix_spawn_file_actions_adddup2(&actions, output.write, 1)
        if discardStderr {
            posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        } else {
            posix_spawn_file_actions_adddup2(&actions, errors.write, 2)
        }
        // A fresh process group, and default signal handling: the host ignores
        // SIGPIPE, and an ignored signal would otherwise be inherited.
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF))

        let argv = [executable] + arguments
        let env = (environment ?? ProcessInfo.processInfo.environment).map { "\($0.key)=\($0.value)" }
        var child: pid_t = 0
        let result = Self.withCStrings(argv) { argvPointer in
            Self.withCStrings(env) { envPointer in
                posix_spawn(&child, executable, &actions, &attributes, argvPointer, envPointer)
            }
        }
        for fd in [input.read, output.write, errors.write] { close(fd) }
        guard result == 0 else {
            for fd in [input.write, output.read, errors.read] { close(fd) }
            throw SpawnError.failed(executable, result)
        }
        pid = child
        stdin = FileHandle(fileDescriptor: input.write, closeOnDealloc: true)
        stdout = FileHandle(fileDescriptor: output.read, closeOnDealloc: true)
        stderr = FileHandle(fileDescriptor: errors.read, closeOnDealloc: true)

        let spawned = child
        let thread = Thread { [self] in
            var status: Int32 = 0
            while waitpid(spawned, &status, 0) == -1 && errno == EINTR {}
            // Exited normally: the exit code. Killed: the signal number, which is
            // what Foundation's Process reports too.
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : status & 0x7f
            lock.lock()
            exitStatus = code
            let handlers = exitHandlers
            exitHandlers = []
            lock.unlock()
            exited.signal()
            for handler in handlers { handler(code) }
        }
        thread.name = "fluid.wait.\(spawned)"
        thread.start()
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exitStatus == nil
    }

    public var terminationStatus: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return exitStatus
    }

    /// Calls `handler` once the child has exited (immediately if it already has).
    public func onExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        if let exitStatus {
            lock.unlock()
            handler(exitStatus)
            return
        }
        exitHandlers.append(handler)
        lock.unlock()
    }

    /// Waits up to `timeout` seconds; true if the child exited.
    @discardableResult
    public func wait(timeout: Double) -> Bool {
        if !isRunning { return true }
        if exited.wait(timeout: .now() + timeout) == .success {
            exited.signal()
            return true
        }
        return false
    }

    /// Sends `signal` to the child's whole process group. Does nothing once the
    /// child has been reaped, so a recycled pid is never signalled.
    public func signalGroup(_ signal: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard exitStatus == nil else { return }
        if killpg(pid, signal) != 0 { kill(pid, signal) }
    }

    /// Every live descendant of the child, children first. Foundation's
    /// `Process` puts each child in a group of its own, so a process group does
    /// not reach those; walking the tree does, as long as the child is still
    /// alive to anchor it.
    public func descendants() -> [pid_t] {
        ProcessTable.descendants(of: pid)
    }

    /// Stops the child and everything under it: each descendant and its group
    /// get `signal`, then the child's own group.
    public func signalTree(_ signal: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard exitStatus == nil else { return }
        for descendant in ProcessTable.descendants(of: pid) {
            _ = killpg(descendant, signal)
            _ = kill(descendant, signal)
        }
        if killpg(pid, signal) != 0 { kill(pid, signal) }
    }

    /// Kills whatever is left in the child's process group after the child
    /// itself has exited, plus any descendant from the last `trackDescendants`
    /// snapshot that has since been orphaned. Called right after the reap, so
    /// the group id cannot have been recycled while members remain.
    public func sweepGroup() {
        _ = killpg(pid, SIGKILL)
        lock.lock()
        let known = Set(snapshot)
        tracker?.cancel()
        tracker = nil
        lock.unlock()
        guard !known.isEmpty else { return }
        for (candidate, parent) in ProcessTable.parentLinks() where known.contains(candidate) {
            // Still one of ours: orphaned to init, or under another orphan of ours.
            // Anything else is a recycled pid and is left alone.
            if parent == 1 || known.contains(parent) {
                _ = kill(candidate, SIGKILL)
            }
        }
    }

    /// The descendants found by the last `trackDescendants` snapshot.
    var trackedDescendants: [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    /// Snapshots the child's descendants every `interval` seconds while it
    /// runs, so `sweepGroup` can find children that left its process group
    /// (Foundation's `Process` puts each in a group of its own) even after a
    /// crash re-parents them.
    public func trackDescendants(every interval: Double = 3) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            let found = ProcessTable.descendants(of: self.pid)
            self.lock.lock()
            if self.exitStatus == nil { self.snapshot = found }
            self.lock.unlock()
        }
        lock.lock()
        tracker = timer
        lock.unlock()
        timer.resume()
    }

    private static func pipe() throws -> (read: Int32, write: Int32) {
        var fds: [Int32] = [0, 0]
        guard fds.withUnsafeMutableBufferPointer({ systemPipe($0.baseAddress!) }) == 0 else {
            throw SpawnError.failed("pipe", errno)
        }
        for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        return (fds[0], fds[1])
    }

    private static func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        pointers.append(nil)
        defer { for pointer in pointers { free(pointer) } }
        return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
    }
}

@inline(__always)
private func systemPipe(_ fds: UnsafeMutablePointer<Int32>) -> Int32 {
    pipe(fds)
}

/// Reads parent links for every process on the machine.
enum ProcessTable {
    static func descendants(of root: pid_t) -> [pid_t] {
        var children: [pid_t: [pid_t]] = [:]
        for (pid, parent) in parentLinks() { children[parent, default: []].append(pid) }
        var result: [pid_t] = []
        var queue = children[root] ?? []
        var seen: Set<pid_t> = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard seen.insert(next).inserted else { continue }
            result.append(next)
            queue += children[next] ?? []
        }
        return result
    }

    #if os(Linux)
    static func parentLinks() -> [(pid_t, pid_t)] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return [] }
        return entries.compactMap { entry in
            guard let pid = pid_t(entry),
                  let stat = try? String(contentsOfFile: "/proc/\(entry)/stat", encoding: .utf8),
                  let close = stat.lastIndex(of: ")") else { return nil }
            // "pid (comm) state ppid ...": comm may hold spaces, so count from ')'.
            let fields = stat[stat.index(after: close)...].split(separator: " ")
            guard fields.count > 1, let parent = pid_t(fields[1]) else { return nil }
            return (pid, parent)
        }
    }
    #elseif canImport(Darwin)
    static func parentLinks() -> [(pid_t, pid_t)] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&name, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // The table can grow between the two calls.
        size += size / 8
        let capacity = size / MemoryLayout<kinfo_proc>.stride
        var table = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        guard sysctl(&name, 3, &table, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return table.prefix(count).map { ($0.kp_proc.p_pid, $0.kp_eproc.e_ppid) }
    }
    #else
    static func parentLinks() -> [(pid_t, pid_t)] { [] }
    #endif
}
