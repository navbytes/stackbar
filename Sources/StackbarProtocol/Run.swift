import Foundation

// Running a command the plugin declared with `.run(commands:)`. The host runs
// it, not the plugin: a sandboxed helper can't spawn programs outside its
// sandbox, and the host is where the approved path, the environment and the
// limits are enforced.

/// One run of a declared command. `arguments` are passed exactly as given;
/// there is no shell.
public struct RunRequest: Codable, Equatable, Sendable {
    /// The name or absolute path exactly as the manifest declares it.
    public var command: String
    public var arguments: [String]
    /// Written to the command's stdin, which is then closed.
    public var input: Data?
    /// The plugin's own folder when `nil`; anything else must be inside a
    /// granted `.files` path.
    public var workingDirectory: String?
    /// Added to the host's minimal environment (PATH, HOME, LANG, TMPDIR).
    public var environment: [String: String]
    /// Seconds; at most 600.
    public var timeout: Double
    /// Output arrives as `runOutput` messages as it is written, then
    /// `runExit`, instead of one `RunResult` at the end.
    public var stream: Bool

    public init(command: String, arguments: [String] = [], input: Data? = nil, workingDirectory: String? = nil, environment: [String: String] = [:], timeout: Double = RunRequest.defaultTimeout, stream: Bool = false) {
        self.command = command
        self.arguments = arguments
        self.input = input
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
        self.stream = stream
    }

    public static let defaultTimeout: Double = 60
    public static let maxTimeout: Double = 600
    /// Bytes kept per output channel; the rest is dropped and `truncated` set.
    public static let maxOutput = 8 * 1024 * 1024
    /// Runs one plugin may have going at once.
    public static let maxConcurrent = 4
}

/// How a finished run went.
public struct RunResult: Codable, Equatable, Sendable {
    /// The exit code, or the signal number when it was killed.
    public var status: Int32
    public var stdout: Data
    public var stderr: Data
    /// Output passed `RunRequest.maxOutput` on a channel and was cut there.
    public var truncated: Bool
    /// The run passed its timeout and was stopped.
    public var timedOut: Bool
    public var duration: Double

    public init(status: Int32, stdout: Data = Data(), stderr: Data = Data(), truncated: Bool = false, timedOut: Bool = false, duration: Double = 0) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.truncated = truncated
        self.timedOut = timedOut
        self.duration = duration
    }

    /// stdout as UTF-8.
    public var text: String { String(decoding: stdout, as: UTF8.self) }
    public var errorText: String { String(decoding: stderr, as: UTF8.self) }
    public var succeeded: Bool { status == 0 && !timedOut }
}

public enum RunChannel: String, Codable, Sendable {
    case stdout, stderr
}

/// How a streamed run ended, in `HostMessage.runExit`.
public struct RunExit: Codable, Equatable, Sendable {
    public var status: Int32
    public var truncated: Bool
    public var timedOut: Bool
    /// Set when the run was stopped by the host (cancelled, the plugin
    /// stopping) or could not be read to the end.
    public var reason: String?

    public init(status: Int32, truncated: Bool = false, timedOut: Bool = false, reason: String? = nil) {
        self.status = status
        self.truncated = truncated
        self.timedOut = timedOut
        self.reason = reason
    }
}
