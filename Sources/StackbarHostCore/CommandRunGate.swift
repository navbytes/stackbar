import Foundation
import StackbarProtocol
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Runs the commands plugins declare, within what the user approved.
///
/// The plugin names a command it declared; the gate runs the path the user
/// approved for that name, with argv exactly as given (no shell), a minimal
/// environment, a working directory inside the plugin's own folder or a
/// granted `.files` path, and limits on time, output and concurrency. A run
/// that times out, is cancelled, or outlives its plugin is stopped with its
/// whole process group: SIGTERM, then SIGKILL after a grace period.
///
/// Every run is recorded (command, status, duration, byte counts; never the
/// output) for the host log and the plugin's Settings page.
public final class CommandRunGate: @unchecked Sendable {
    public struct Limits: Sendable {
        public var maxConcurrent = RunRequest.maxConcurrent
        public var maxOutput = RunRequest.maxOutput
        public var maxTimeout = RunRequest.maxTimeout
        /// Between SIGTERM and SIGKILL.
        public var killGrace: Double = 2
        /// How long a finished command's output may stay open (a background
        /// child holding the pipe) before the run ends without it.
        public var drainGrace: Double = 2
        public init() {}
    }

    /// What one plugin may run, as the host's capability check found it.
    public struct Grant: Sendable {
        public var pluginID: String
        /// The approved program for each granted name. A name missing here
        /// resolves now (`stackbarctl` and tests, which have no ledger).
        public var approvedPaths: [String: String]?
        /// Granted `.files` paths, as written (`~/` allowed).
        public var folders: [String]

        public init(pluginID: String, approvedPaths: [String: String]? = nil, folders: [String] = []) {
            self.pluginID = pluginID
            self.approvedPaths = approvedPaths
            self.folders = folders
        }
    }

    /// One finished run, for the audit.
    public struct Record: Codable, Equatable, Sendable {
        public var path: String
        public var arguments: Int
        public var status: Int32
        public var duration: Double
        public var stdoutBytes: Int
        public var stderrBytes: Int
        public var timedOut: Bool
        public var cancelled: Bool
        public var at: Date
    }

    /// A run the gate would not start, and why, in words.
    public struct Refusal: Error, CustomStringConvertible, Equatable, Sendable {
        public enum Kind: Sendable { case invalid, notInstalled, moved, busy, spawn }
        public var kind: Kind
        public var description: String
    }

    public let root: URL
    public let resolver: CommandResolver
    public let limits: Limits
    private let log: @Sendable (_ pluginID: String, _ line: String) -> Void
    private let lock = NSLock()
    private var active: [String: [Int: Run]] = [:]
    private var records: [String: [Record]] = [:]

    /// `root` holds each plugin's folder (`<root>/<id>`), its default
    /// working directory, and the `tmp` folder inside it.
    public init(root: URL, resolver: CommandResolver = .standard, limits: Limits = Limits(), log: @escaping @Sendable (String, String) -> Void = { _, _ in }) {
        self.root = root
        self.resolver = resolver
        self.limits = limits
        self.log = log
    }

    public func folder(for pluginID: String) -> URL {
        root.appendingPathComponent(pluginID, isDirectory: true)
    }

    // MARK: Running

    /// Runs to the end and returns what it wrote.
    public func run(_ request: RunRequest, id: Int, grant: Grant) async -> Result<RunResult, Refusal> {
        var request = request
        request.stream = false
        let prepared: Prepared
        switch prepare(request, grant: grant) {
        case .success(let value): prepared = value
        case .failure(let refusal): return .failure(refusal)
        }
        return await withCheckedContinuation { continuation in
            let started = start(prepared, id: id, pluginID: grant.pluginID, emit: nil) { result in
                continuation.resume(returning: .success(result))
            }
            if let refusal = started { continuation.resume(returning: .failure(refusal)) }
        }
    }

    /// Starts a streamed run: its output goes to `emit` as `runOutput`
    /// messages as it is written, then one `runExit`. Returns `nil` once it
    /// started.
    public func stream(_ request: RunRequest, id: Int, grant: Grant, emit: @escaping @Sendable (HostMessage) -> Void) -> Refusal? {
        var request = request
        request.stream = true
        switch prepare(request, grant: grant) {
        case .failure(let refusal): return refusal
        case .success(let prepared): return start(prepared, id: id, pluginID: grant.pluginID, emit: emit) { _ in }
        }
    }

    /// Stops one run. Returns false when there was none with that id.
    @discardableResult
    public func cancel(pluginID: String, id: Int) -> Bool {
        let run = lock.withLock { active[pluginID]?[id] }
        run?.stop(cancelled: true)
        return run != nil
    }

    /// Stops every run the plugin has going (it stopped or crashed).
    public func cancelAll(pluginID: String) {
        let runs = lock.withLock { active[pluginID].map { Array($0.values) } ?? [] }
        for run in runs { run.stop(cancelled: true) }
    }

    public func activeRuns(pluginID: String) -> Int {
        lock.withLock { active[pluginID]?.count ?? 0 }
    }

    /// The most recent runs, newest first.
    public func recentRuns(pluginID: String) -> [Record] {
        lock.withLock { records[pluginID]?.reversed() ?? [] }
    }

    // MARK: Checks

    struct Prepared {
        var path: String
        var request: RunRequest
        var directory: String
        var environment: [String: String]
        var timeout: Double
    }

    /// Variables a plugin may not set: what the host sets itself, and what
    /// would load other code into the approved program.
    static func isReservedVariable(_ name: String) -> Bool {
        ["PATH", "HOME", "TMPDIR"].contains(name) || name.hasPrefix("DYLD_") || name.hasPrefix("LD_")
    }

    func prepare(_ request: RunRequest, grant: Grant) -> Result<Prepared, Refusal> {
        func refuse(_ kind: Refusal.Kind, _ message: String) -> Result<Prepared, Refusal> {
            .failure(Refusal(kind: kind, description: message))
        }
        let name = request.command
        guard CommandResolver.isValidName(name) else {
            return refuse(.invalid, "\(name) is not a command name or an absolute path")
        }
        guard let now = resolver.resolve(name) else {
            let looked = name.hasPrefix("/") ? "" : " (looked in " + resolver.directories.joined(separator: ", ") + ")"
            return refuse(.notInstalled, "\(name) is not installed\(looked)")
        }
        if let approved = grant.approvedPaths, approved[name] != now {
            let before = approved[name].map { " from \($0)" } ?? ""
            return refuse(.moved, "\(name) moved\(before) to \(now); approve the plugin again to run it")
        }
        guard !request.arguments.contains(where: { $0.contains("\0") }),
              request.arguments.reduce(0, { $0 + $1.utf8.count }) <= 1024 * 1024, request.arguments.count <= 4096 else {
            return refuse(.invalid, "arguments are at most 4096 strings and 1 MB, without NUL characters")
        }
        if let input = request.input, input.count > limits.maxOutput {
            return refuse(.invalid, "input is at most \(limits.maxOutput / 1024 / 1024) MB")
        }
        guard request.timeout <= limits.maxTimeout else {
            return refuse(.invalid, "timeout is at most \(Int(limits.maxTimeout)) seconds")
        }
        let timeout = request.timeout > 0 ? request.timeout : RunRequest.defaultTimeout

        let home = folder(for: grant.pluginID)
        let tmp = home.appendingPathComponent("tmp", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        } catch {
            return refuse(.spawn, "could not create the plugin's folder: \(error)")
        }
        let directory: String
        if let wanted = request.workingDirectory {
            let expanded = Self.canonical(NSString(string: wanted).expandingTildeInPath)
            guard wanted.hasPrefix("/") || wanted.hasPrefix("~") else {
                return refuse(.invalid, "workingDirectory must be an absolute or ~/ path")
            }
            let allowed = [Self.canonical(home.path)] + grant.folders.map { Self.canonical(NSString(string: $0).expandingTildeInPath) }
            guard allowed.contains(where: { expanded == $0 || expanded.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) else {
                return refuse(.invalid, "\(wanted) is outside the plugin's folder and its .files paths")
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
                return refuse(.invalid, "\(wanted) is not a folder")
            }
            directory = expanded
        } else {
            directory = home.path
        }

        var environment: [String: String] = [
            "PATH": CommandResolver.searchPath.joined(separator: ":"),
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
            "TMPDIR": tmp.path + "/",
        ]
        var size = 0
        for (key, value) in request.environment {
            guard !key.isEmpty, !key.contains("="), !key.contains("\0"), !value.contains("\0") else {
                return refuse(.invalid, "environment variable \(key) has an invalid name or value")
            }
            guard !Self.isReservedVariable(key) else {
                return refuse(.invalid, "\(key) is set by the host and can't be changed")
            }
            size += key.utf8.count + value.utf8.count
            environment[key] = value
        }
        guard size <= 64 * 1024 else { return refuse(.invalid, "environment is at most 64 KB") }
        return .success(Prepared(path: now, request: request, directory: directory, environment: environment, timeout: timeout))
    }

    /// A path with symlinks resolved, so `..` and links can't step outside.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: Processes

    private func start(_ prepared: Prepared, id: Int, pluginID: String, emit: (@Sendable (HostMessage) -> Void)?, finished: @escaping @Sendable (RunResult) -> Void) -> Refusal? {
        lock.lock()
        var runs = active[pluginID] ?? [:]
        guard runs.count < limits.maxConcurrent else {
            lock.unlock()
            return Refusal(kind: .busy, description: "at most \(limits.maxConcurrent) commands may run at once")
        }
        guard runs[id] == nil else {
            lock.unlock()
            return Refusal(kind: .invalid, description: "a run with id \(id) is already going")
        }
        let child: ChildProcess
        do {
            child = try ChildProcess(executable: prepared.path, arguments: prepared.request.arguments, environment: prepared.environment, workingDirectory: prepared.directory)
        } catch {
            lock.unlock()
            return Refusal(kind: .spawn, description: "\(error)")
        }
        let run = Run(child: child, id: id, limits: limits, emit: emit) { [weak self] run, result in
            self?.finish(run, pluginID: pluginID, path: prepared.path, arguments: prepared.request.arguments.count, result: result)
            finished(result)
        }
        runs[id] = run
        active[pluginID] = runs
        lock.unlock()
        run.begin(input: prepared.request.input, timeout: prepared.timeout)
        return nil
    }

    private func finish(_ run: Run, pluginID: String, path: String, arguments: Int, result: RunResult) {
        let record = Record(path: path, arguments: arguments, status: result.status, duration: result.duration, stdoutBytes: run.bytes.stdout, stderrBytes: run.bytes.stderr, timedOut: result.timedOut, cancelled: run.wasCancelled, at: Date())
        lock.withLock {
            if active[pluginID]?[run.id] === run { active[pluginID]?[run.id] = nil }
            var list = records[pluginID] ?? []
            list.append(record)
            if list.count > 50 { list.removeFirst(list.count - 50) }
            records[pluginID] = list
        }
        let how = result.timedOut ? "timed out" : (run.wasCancelled ? "cancelled" : "exit \(result.status)")
        log(pluginID, "ran \(path) (\(arguments) arguments): \(how) in \(String(format: "%.2f", result.duration))s, \(record.stdoutBytes) + \(record.stderrBytes) bytes")
    }
}

/// One running command: two readers, the exit, the timeout.
private final class Run: @unchecked Sendable {
    let id: Int
    private let child: ChildProcess
    private let limits: CommandRunGate.Limits
    private let emit: (@Sendable (HostMessage) -> Void)?
    private let done: @Sendable (Run, RunResult) -> Void
    private let lock = NSLock()
    private let started = Date()
    private var output = Data()
    private var errors = Data()
    private var truncated = false
    private var timedOut = false
    private var cancelled = false
    private var finished = false
    private var status: Int32?
    private let group = DispatchGroup()

    init(child: ChildProcess, id: Int, limits: CommandRunGate.Limits, emit: (@Sendable (HostMessage) -> Void)?, done: @escaping @Sendable (Run, RunResult) -> Void) {
        self.child = child
        self.id = id
        self.limits = limits
        self.emit = emit
        self.done = done
    }

    var wasCancelled: Bool { lock.withLock { cancelled } }
    private var counts = (stdout: 0, stderr: 0)
    var bytes: (stdout: Int, stderr: Int) { lock.withLock { counts } }

    func begin(input: Data?, timeout: Double) {
        let stdin = child.stdin
        DispatchQueue.global().async {
            if let input, !input.isEmpty { try? stdin.write(contentsOf: input) }
            try? stdin.close()
        }
        read(child.stdout, .stdout)
        read(child.stderr, .stderr)
        group.enter()
        // Held strongly until the exit, so a run outlives a dropped gate.
        child.onExit { [self] code in
            self.lock.withLock { self.status = code }
            // Whatever it left in its group goes too, so the pipes close.
            self.child.sweepGroup()
            self.group.leave()
            DispatchQueue.global().asyncAfter(deadline: .now() + self.limits.drainGrace) {
                self.complete(reason: "output still open after the command exited")
            }
        }
        // Strong: once the readers and the exit let go, this block is all
        // that holds the run.
        group.notify(queue: .global()) { self.complete(reason: nil) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.child.isRunning else { return }
            self.lock.withLock { self.timedOut = true }
            self.terminate()
        }
    }

    func stop(cancelled: Bool) {
        lock.withLock { if cancelled { self.cancelled = true } }
        terminate()
    }

    private func terminate() {
        child.signalGroup(SIGTERM)
        let child = child
        DispatchQueue.global().asyncAfter(deadline: .now() + limits.killGrace) {
            child.signalGroup(SIGKILL)
        }
    }

    private func read(_ handle: FileHandle, _ channel: RunChannel) {
        group.enter()
        let thread = Thread { [self] in
            while withAutoreleasePool({ () -> Bool in
                let chunk = handle.availableData
                if chunk.isEmpty { return false }
                append(chunk, channel)
                return true
            }) {}
            group.leave()
        }
        thread.name = "stackbar.run.\(channel.rawValue)"
        thread.start()
    }

    private func append(_ chunk: Data, _ channel: RunChannel) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        let held = channel == .stdout ? counts.stdout : counts.stderr
        let room = max(0, limits.maxOutput - held)
        let kept = chunk.prefix(room)
        if kept.count < chunk.count { truncated = true }
        guard !kept.isEmpty else { return }
        if channel == .stdout { counts.stdout += kept.count } else { counts.stderr += kept.count }
        if let emit {
            emit(.runOutput(id: id, channel: channel, data: Data(kept)))
        } else if channel == .stdout {
            output.append(kept)
        } else {
            errors.append(kept)
        }
    }

    private func complete(reason: String?) {
        lock.lock()
        guard !finished, let status else {
            lock.unlock()
            return
        }
        finished = true
        let result = RunResult(status: status, stdout: output, stderr: errors, truncated: truncated, timedOut: timedOut, duration: Date().timeIntervalSince(started))
        let why = cancelled ? "cancelled" : (timedOut ? "timed out" : reason)
        emit?(.runExit(id: id, exit: RunExit(status: status, truncated: truncated, timedOut: timedOut, reason: why)))
        lock.unlock()
        done(self, result)
    }
}
