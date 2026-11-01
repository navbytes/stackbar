import Foundation
import StackbarProtocol

/// Runs commands for every caller (the palette, hotkeys, links, Spotlight)
/// the same way: find the plugin, wait for it if it is starting, refuse when
/// it is waiting for approval, apply the result timeout, then perform the
/// result under the plugin's capabilities.
public final class CommandRunner: Sendable {
    /// What the runner knows about a plugin when a command arrives.
    public enum Target: Sendable {
        case supervisor(PluginSupervisor)
        /// The plugin can't take commands, and why ("waiting for your approval").
        case unavailable(String)
    }

    /// What happened, in words, for a HUD or Spotlight's dialog.
    public struct Outcome: Error, Equatable, Sendable {
        public var message: String?
        public var isError: Bool

        public init(message: String?, isError: Bool) {
            self.message = message
            self.isError = isError
        }

        public static func failure(_ message: String) -> Outcome { Outcome(message: message, isError: true) }
    }

    public let registry: CommandRegistry
    private let services: HostServices?
    private let resolve: @Sendable (String) async -> Target?
    private let waitForStart: Double
    private let timeout: Double

    /// `resolve` finds a plugin's supervisor by id (nil: not installed).
    public init(registry: CommandRegistry, services: HostServices?, waitForStart: Double = 10, timeout: Double = 30, resolve: @escaping @Sendable (String) async -> Target?) {
        self.registry = registry
        self.services = services
        self.resolve = resolve
        self.waitForStart = waitForStart
        self.timeout = timeout
    }

    /// The running supervisor for a plugin, waiting up to `waitForStart`
    /// seconds while it starts or restarts.
    public func supervisor(for pluginID: String) async -> Result<PluginSupervisor, Outcome> {
        guard let target = await resolve(pluginID) else { return .failure(.failure("\(pluginID) is not installed")) }
        switch target {
        case .unavailable(let reason):
            return .failure(.failure(reason))
        case .supervisor(let supervisor):
            let deadline = Date().addingTimeInterval(waitForStart)
            while true {
                let state = await supervisor.state
                switch state {
                case .running:
                    return .success(supervisor)
                case .failed(let reason):
                    return .failure(.failure("\(supervisor.manifest.name) failed: \(reason)"))
                case .stopped:
                    return .failure(.failure("\(supervisor.manifest.name) is stopped"))
                case .starting, .restarting:
                    guard Date() < deadline else { return .failure(.failure("\(supervisor.manifest.name) did not start in time")) }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    /// Runs a run command and performs its result.
    public func run(_ key: CommandKey, arguments: [String: String] = [:], source: InvocationSource, context: InvocationContext? = nil) async -> Outcome {
        guard let entry = registry.entry(key) else { return .failure("\(key) is not a command") }
        guard entry.spec.kind == .run else { return .failure("\(entry.spec.title) opens a view") }
        if source == .link || source == .spotlight || source == .shortcuts, entry.spec.exposure == .stackbarOnly {
            return .failure("\(entry.spec.title) can only be run from inside Stackbar")
        }
        for argument in entry.spec.requiredArguments where (arguments[argument.name] ?? "").isEmpty {
            return .failure("\(entry.spec.title) needs \(argument.placeholder)")
        }
        let supervisor: PluginSupervisor
        switch await self.supervisor(for: key.pluginID) {
        case .success(let found): supervisor = found
        case .failure(let outcome): return outcome
        }
        let result = await supervisor.runCommand(key.commandID, arguments: arguments, source: source, context: context, timeout: timeout)
        return await perform(result, for: supervisor)
    }

    /// Performs a result the way the matching host call would, so a command
    /// can't do more than its plugin's capabilities allow.
    public func perform(_ result: CommandResult, for supervisor: PluginSupervisor) async -> Outcome {
        switch result {
        case .message(let message):
            return Outcome(message: message, isError: false)
        case .failure(let message):
            return .failure(message)
        case .open(let url, let app):
            return await host(.open(url: url, app: app), supervisor, success: nil)
        case .copy(let text):
            return await host(.copy(text), supervisor, success: "Copied")
        case .paste(let text, let cursor):
            // A command's paste is a one-off: the user's clipboard comes back.
            return await host(.paste(.text(text), options: PasteOptions(restoreClipboard: true, cursorFromEnd: cursor)), supervisor, success: nil)
        }
    }

    private func host(_ call: HostCall, _ supervisor: PluginSupervisor, success: String?) async -> Outcome {
        guard let services else { return .failure("host services are not available here") }
        let granted = await supervisor.granted
        switch await services.handle(call, for: granted, declared: supervisor.manifest) {
        case .failure(let message): return .failure(message)
        case .ok, .value, .http: return Outcome(message: success, isError: false)
        }
    }
}

/// `stackbar://commands/<plugin-id>/<command-id>?name=value`: a link that
/// opens or runs a command.
public struct CommandLink: Equatable, Sendable {
    public var key: CommandKey
    public var arguments: [String: String]

    public init(key: CommandKey, arguments: [String: String] = [:]) {
        self.key = key
        self.arguments = arguments
    }

    public static let scheme = "stackbar"

    public init?(_ text: String) {
        guard let components = URLComponents(string: text), components.scheme?.lowercased() == Self.scheme, components.host == "commands" else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 2, let key = CommandKey("\(parts[0])/\(parts[1])") else { return nil }
        var arguments: [String: String] = [:]
        for item in components.queryItems ?? [] where !item.name.isEmpty {
            arguments[item.name] = item.value ?? ""
        }
        self.init(key: key, arguments: arguments)
    }

    public var url: String {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "commands"
        components.path = "/\(key.pluginID)/\(key.commandID)"
        if !arguments.isEmpty {
            components.queryItems = arguments.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.string ?? "\(Self.scheme)://commands/\(key.pluginID)/\(key.commandID)"
    }
}

/// One open command view: keeps at most one query in flight and the newest
/// one waiting, and drops trees older than the newest shown, so fast typing
/// never queues stale searches behind each other.
public struct ViewSessionState: Sendable {
    public let session: Int
    public private(set) var query: CommandQuery
    private var nextSeq = 1
    /// The seq of the query the plugin is working on, if any.
    public private(set) var inFlight: Int?
    private var pending = false
    /// The newest seq whose tree was shown.
    public private(set) var shownSeq = 0
    public private(set) var root: ViewNode?

    /// What the caller should send now.
    public enum Send: Equatable, Sendable {
        case open(seq: Int, query: CommandQuery)
        case update(seq: Int, query: CommandQuery)
    }

    public init(session: Int, query: CommandQuery) {
        self.session = session
        self.query = query
    }

    /// The first message for the session.
    public mutating func open() -> Send {
        let seq = take()
        inFlight = seq
        return .open(seq: seq, query: query)
    }

    /// The user changed the query; returns an update to send now, or nil
    /// when one is in flight (the newest is sent when it answers).
    public mutating func change(_ query: CommandQuery) -> Send? {
        guard query != self.query else { return nil }
        self.query = query
        guard inFlight == nil else {
            pending = true
            return nil
        }
        let seq = take()
        inFlight = seq
        return .update(seq: seq, query: query)
    }

    /// A tree arrived. Returns whether to show it, and the pending query to
    /// send next.
    public mutating func received(seq: Int, root: ViewNode) -> (show: Bool, next: Send?) {
        guard seq >= shownSeq else { return (false, nil) }
        shownSeq = seq
        self.root = root
        if inFlight.map({ seq >= $0 }) == true { inFlight = nil }
        guard inFlight == nil, pending else { return (true, nil) }
        pending = false
        let next = take()
        inFlight = next
        return (true, .update(seq: next, query: query))
    }

    /// Whether the newest query is still being answered (show "Searching…").
    public var isSearching: Bool { inFlight != nil || pending }

    private mutating func take() -> Int {
        defer { nextSeq += 1 }
        return nextSeq
    }
}
