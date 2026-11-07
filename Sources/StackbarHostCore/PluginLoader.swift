import Foundation
import StackbarProtocol

/// A plugin ready to start: the helper to launch and the manifest it declared.
public struct LoadedPlugin: Sendable {
    public let binary: URL
    public let manifest: Manifest
}

/// Turns a plugin source into a helper the host may run, the same way for the
/// app, `stackbarctl` and the MCP servers: build it, read its manifest, refuse
/// one with problems, and sign it into the App Sandbox. What the host then
/// does with it (approvals, duplicate ids, restarts) stays with the caller.
public struct PluginLoader: Sendable {
    private let builder: PluginBuilder?
    private let sandbox: Bool

    /// `sandbox` signs helpers into the App Sandbox. Only macOS has one;
    /// elsewhere it changes nothing.
    public init(builder: PluginBuilder?, sandbox: Bool) {
        self.builder = builder
        self.sandbox = sandbox
    }

    /// The helper a source runs as: a `.swift` file is built (cached by
    /// content), anything else is taken to be a helper already. Throws
    /// `PluginBuilder.Failure` with diagnostics when it doesn't compile.
    public func helper(for source: URL, ticket: BuildTicket? = nil) throws -> PluginBuilder.Output {
        guard source.pathExtension == "swift" else { return PluginBuilder.Output(binary: source, cached: true) }
        guard let builder else { throw LoadError.noBuilder }
        return try builder.build(source: source, ticket: ticket)
    }

    /// Builds a `.swift` source (or takes a helper as is), reads its
    /// manifest, refuses one with problems, and signs the helper into the
    /// sandbox when `sandbox` is set. Blocks while it builds.
    public func load(_ source: URL, ticket: BuildTicket? = nil) throws -> LoadedPlugin {
        let built = try helper(for: source, ticket: ticket).binary
        let manifest = try PluginProcess.readManifest(executable: built)
        let problems = manifest.problems
        if !problems.isEmpty { throw LoadError.badManifest(problems) }
        #if os(macOS)
        if sandbox {
            // The signed copy is what runs; the manifest read from the
            // unsigned build is the same code's.
            guard let builder else { throw LoadError.noBuilder }
            return LoadedPlugin(binary: try builder.sign(binary: built, manifest: manifest), manifest: manifest)
        }
        #endif
        return LoadedPlugin(binary: built, manifest: manifest)
    }

    /// `load` without holding a cooperative thread: a build can wait for
    /// minutes behind others, so it waits on a dispatch thread instead.
    /// Cancelling `ticket` (a newer load of the same plugin) skips the build
    /// if it hasn't started, throwing `PluginBuilder.Superseded`.
    public func loadInBackground(_ source: URL, ticket: BuildTicket? = nil) async throws -> LoadedPlugin {
        try await Self.inBackground { try self.load(source, ticket: ticket) }
    }

    /// Runs blocking work (a build, a manifest read) on a dispatch thread.
    public static func inBackground<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private static let queue = DispatchQueue(label: "stackbar.plugin-load", qos: .userInitiated, attributes: .concurrent)

    public enum LoadError: Error, CustomStringConvertible, Equatable {
        case noBuilder
        case badManifest([String])

        public var description: String {
            switch self {
            case .noBuilder: return "no plugin builder is configured"
            case .badManifest(let problems): return "the manifest has problems:\n- " + problems.joined(separator: "\n- ")
            }
        }
    }
}

/// Lets a newer load call off an older build that is still waiting its turn.
public final class BuildTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() { lock.withLock { cancelled = true } }

    public var isCancelled: Bool { lock.withLock { cancelled } }
}
