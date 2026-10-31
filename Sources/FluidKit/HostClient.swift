import Foundation

/// The plugin's line to the host for everything it can't or shouldn't do
/// itself: secrets, HTTP to declared domains, OAuth tokens, notifications,
/// topics, and saved values.
///
/// Calls are `request` messages answered by `response` messages. Responses are
/// routed here straight from the reader thread, not through the runtime's
/// one-message-at-a-time loop, so a `refresh()` that awaits the host never
/// waits on itself.
public final class HostClient: @unchecked Sendable {
    public static let shared = HostClient()

    private let lock = NSLock()
    private var nextID = 1
    private var pending: [Int: @Sendable (HostResult) -> Void] = [:]
    private var sendMessage: (@Sendable (PluginMessage) -> Void)?

    init() {}

    /// Points the client at a transport. The runtime does this; tests can too.
    public func configure(send: @escaping @Sendable (PluginMessage) -> Void) {
        lock.lock()
        sendMessage = send
        lock.unlock()
    }

    /// Sends a call and waits for its answer.
    public func call(_ call: HostCall) async -> HostResult {
        await withCheckedContinuation { continuation in
            send(call) { continuation.resume(returning: $0) }
        }
    }

    /// Sends a call without waiting. A failure is reported to the host's log.
    public func fire(_ call: HostCall) {
        let label = Self.label(call)
        send(call) { [weak self] result in
            if case .failure(let message) = result {
                self?.deliver(.log(level: .warning, message: "\(label) failed: \(message)"))
            }
        }
    }

    /// Delivers a response. Returns `false` for an id nobody is waiting on.
    @discardableResult
    public func resolve(id: Int, result: HostResult) -> Bool {
        lock.lock()
        let handler = pending.removeValue(forKey: id)
        lock.unlock()
        handler?(result)
        return handler != nil
    }

    /// Answers every waiting call with a failure.
    public func failAll(_ reason: String) {
        lock.lock()
        let handlers = pending
        pending.removeAll()
        sendMessage = nil
        lock.unlock()
        for handler in handlers.values { handler(.failure(reason)) }
    }

    /// How many calls are waiting on the host (for tests).
    public var openRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    private func send(_ call: HostCall, onResult: @escaping @Sendable (HostResult) -> Void) {
        lock.lock()
        guard let sendMessage else {
            lock.unlock()
            onResult(.failure("not running inside Fluid"))
            return
        }
        let id = nextID
        nextID += 1
        pending[id] = onResult
        lock.unlock()
        sendMessage(.request(id: id, call: call))
    }

    private func deliver(_ message: PluginMessage) {
        lock.lock()
        let sendMessage = sendMessage
        lock.unlock()
        sendMessage?(message)
    }

    static func label(_ call: HostCall) -> String {
        switch call {
        case .storageSet(let key, _): return "saving \(key)"
        case .secret(let name): return "reading secret \(name)"
        case .http(let request): return "\(request.method) \(request.url)"
        case .oauthToken(let provider, _): return "signing in to \(provider)"
        case .publish(let topic, _): return "publishing to \(topic)"
        case .notify: return "notification"
        case .openURL(let url): return "opening \(url)"
        case .copy: return "copying"
        }
    }
}

/// A host call that failed: a missing capability, a network error, a sign-in
/// the user cancelled. `message` says what happened in words.
public struct HostError: Error, CustomStringConvertible, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Host services, for use in `refresh()` and action closures.
///
/// ```swift
/// let token = try await Fluid.secret("GITHUB_TOKEN")
/// let prs: [PR] = try await Fluid.getJSON("https://api.github.com/...", headers: ["Authorization": "Bearer \(token ?? "")"])
/// ```
///
/// Every call is checked against the manifest's capabilities as approved by
/// the user, and the error says which capability is missing.
public enum Fluid {
    /// Saved values, also available as `@Stored` properties.
    @MainActor public static let storage = PluginStorage()

    /// A secret the manifest declares with `.secret(name:)`, or `nil` when the
    /// user hasn't entered it yet (the host asks them for it).
    public static func secret(_ name: String) async throws -> String? {
        switch await HostClient.shared.call(.secret(name: name)) {
        case .value(let value): return value
        case .failure(let message): throw HostError(message)
        default: throw HostError("unexpected answer to secret(\(name))")
        }
    }

    /// An HTTP request made by the host to a domain the manifest declares.
    public static func http(_ request: HTTPRequest) async throws -> HTTPResponse {
        switch await HostClient.shared.call(.http(request)) {
        case .http(let response): return response
        case .failure(let message): throw HostError(message)
        default: throw HostError("unexpected answer to \(request.method) \(request.url)")
        }
    }

    public static func get(_ url: String, headers: [String: String] = [:]) async throws -> HTTPResponse {
        try await http(HTTPRequest(url: url, headers: headers))
    }

    /// GETs a URL and decodes its JSON body; a non-2xx status throws.
    public static func getJSON<T: Decodable>(_ url: String, as type: T.Type = T.self, headers: [String: String] = [:], decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var headers = headers
        if headers["Accept"] == nil { headers["Accept"] = "application/json" }
        let response = try await get(url, headers: headers)
        guard (200..<300).contains(response.status) else {
            throw HostError("\(url) answered \(response.status): \(String(decoding: response.body.prefix(300), as: UTF8.self))")
        }
        return try decoder.decode(T.self, from: response.body)
    }

    /// An access token for a provider declared with `.oauth(...)`. The first
    /// call opens the browser to sign in; later calls reuse or refresh it.
    public static func oauthToken(_ provider: String, forceRefresh: Bool = false) async throws -> String {
        switch await HostClient.shared.call(.oauthToken(provider: provider, forceRefresh: forceRefresh)) {
        case .value(let token?): return token
        case .failure(let message): throw HostError(message)
        default: throw HostError("no token for \(provider)")
        }
    }

    /// Sends a payload to every plugin listening on the topic with a
    /// `.topic(name:)` trigger.
    public static func publish(_ topic: String, _ payload: String) {
        HostClient.shared.fire(.publish(topic: topic, payload: payload))
    }

    /// Encodes `value` as JSON and publishes it.
    public static func publish(_ topic: String, json value: some Encodable) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        publish(topic, String(decoding: data, as: UTF8.self))
    }

    public static func notify(_ title: String, body: String? = nil) {
        HostClient.shared.fire(.notify(title: title, body: body))
    }

    public static func open(_ url: String) {
        HostClient.shared.fire(.openURL(url))
    }

    public static func copy(_ text: String) {
        HostClient.shared.fire(.copy(text))
    }
}
