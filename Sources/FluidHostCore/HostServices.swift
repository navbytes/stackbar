import Foundation
import FluidProtocol

/// What the host does for plugins, and the one place their capabilities are
/// enforced.
///
/// Every `HostCall` arrives here with the capabilities the user granted the
/// plugin (normally its manifest's, after the install or update sheet). A call
/// outside them fails with a message naming the capability to add, so an agent
/// writing the plugin can fix it from the error alone.
public final class HostServices: Sendable {
    /// The host's side effects that need a UI or the OS.
    public struct Platform: Sendable {
        public var notify: @Sendable (_ plugin: String, _ title: String, _ body: String?) -> Void
        public var open: @Sendable (URL) -> Void
        public var copy: @Sendable (String) -> Void
        /// A plugin asked for a declared secret the user hasn't entered.
        public var secretMissing: @Sendable (_ pluginID: String, _ name: String) -> Void
        /// The clipboard, power and calendar.
        public var system: any SystemServices

        public init(
            notify: @escaping @Sendable (String, String, String?) -> Void = { _, _, _ in },
            open: @escaping @Sendable (URL) -> Void = { _ in },
            copy: @escaping @Sendable (String) -> Void = { _ in },
            secretMissing: @escaping @Sendable (String, String) -> Void = { _, _ in },
            system: any SystemServices = UnsupportedSystem()
        ) {
            self.notify = notify
            self.open = open
            self.copy = copy
            self.secretMissing = secretMissing
            self.system = system
        }
    }

    public let storage: StorageStore
    public let secrets: any SecretStore
    public let audit: NetworkAudit
    public let http: HTTPService
    public let oauth: OAuthBroker
    public let bus: PluginBus
    public let platform: Platform
    private let notifications = RateLimiter(limit: 10, per: 60)
    /// Every call a plugin makes, so a loop that hammers the host is cut off
    /// instead of starving the others.
    private let calls = RateLimiter(limit: 1200, per: 60)
    private let requests = RateLimiter(limit: 300, per: 60)

    public init(storage: StorageStore, secrets: any SecretStore, platform: Platform = Platform(), audit: NetworkAudit = NetworkAudit(), bus: PluginBus = PluginBus(), oauthTimeout: Double = 300) {
        self.storage = storage
        self.secrets = secrets
        self.audit = audit
        self.http = HTTPService(audit: audit)
        self.oauth = OAuthBroker(secrets: secrets, timeout: oauthTimeout, openURL: platform.open)
        self.bus = bus
        self.platform = platform
    }

    /// Services rooted in one directory, with the given secret store. For
    /// `fluidctl` and tests; the app builds its own with the Keychain.
    public static func local(directory: URL, secrets: (any SecretStore)? = nil, platform: Platform = Platform()) -> HostServices {
        let store = secrets ?? ChainedSecretStore([FileSecretStore(file: directory.appendingPathComponent("secrets.json")), EnvironmentSecretStore()])
        return HostServices(storage: StorageStore(directory: directory.appendingPathComponent("storage", isDirectory: true)), secrets: store, platform: platform)
    }

    /// Handles one call for a plugin whose granted capabilities are those of
    /// `granted` (its manifest with the approved capability list). `declared`
    /// is the manifest as written: a call it covers but `granted` does not is
    /// refused as waiting for approval, not as undeclared.
    public func handle(_ call: HostCall, for granted: Manifest, declared: Manifest? = nil) async -> HostResult {
        let declared = declared ?? granted
        func missing(_ capability: Capability, _ what: String) -> HostResult {
            declared.capabilities.contains(capability)
                ? Self.awaitingApproval(granted, "to \(what)")
                : Self.missing(capability, what)
        }
        guard calls.allow(granted.id) else { return .failure("too many host calls; at most 1200 a minute") }
        switch call {
        case .storageSet(let key, let value):
            do {
                try await storage.set(key, value, for: granted.id)
                return .ok
            } catch {
                return .failure("\(error)")
            }

        case .secret(let name):
            guard granted.secretNames.contains(name) else {
                if declared.secretNames.contains(name) { return Self.awaitingApproval(granted, "to read secret \(name)") }
                return .failure("secret \(name) is not declared; add .secret(name: \"\(name)\") to the manifest's capabilities")
            }
            do {
                if let value = try secrets.secret(name), !value.isEmpty { return .value(value) }
                platform.secretMissing(granted.id, name)
                return .value(nil)
            } catch {
                return .failure("could not read secret \(name): \(error)")
            }

        case .http(let request):
            guard requests.allow(granted.id) else { return .failure("too many HTTP requests; at most 300 a minute") }
            let result = await http.perform(request, pluginID: granted.id, allowedHosts: granted.networkHosts)
            if case .failure = result, let host = URLParts.host(of: request.url),
               !URLParts.host(host, matches: granted.networkHosts), URLParts.host(host, matches: declared.networkHosts) {
                return Self.awaitingApproval(granted, "to reach \(host)")
            }
            return result

        case .oauthToken(let name, let forceRefresh):
            guard let provider = granted.oauthProviders.first(where: { $0.name == name }) else {
                if declared.oauthProviders.contains(where: { $0.name == name }) { return Self.awaitingApproval(granted, "to sign in with \(name)") }
                return .failure("OAuth provider \(name) is not declared; add .oauth(OAuthProvider(name: \"\(name)\", ...)) to the manifest's capabilities")
            }
            do {
                return .value(try await oauth.token(pluginID: granted.id, provider: provider, forceRefresh: forceRefresh))
            } catch {
                return .failure("\(error)")
            }

        case .publish(let topic, let payload):
            do {
                try await bus.publish(topic, payload: payload, from: granted.id)
                return .ok
            } catch {
                return .failure("\(error)")
            }

        case .notify(let title, let body):
            guard notifications.allow(granted.id) else { return .failure("too many notifications; at most 10 a minute") }
            platform.notify(granted.name, String(title.prefix(200)), body.map { String($0.prefix(1000)) })
            return .ok

        case .openURL(let string):
            guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else {
                return .failure("only https, http and mailto URLs can be opened")
            }
            platform.open(url)
            return .ok

        case .copy(let text):
            guard text.utf8.count <= 1024 * 1024 else { return .failure("text is too large to copy") }
            platform.copy(text)
            return .ok

        case .clipboardRead:
            guard granted.capabilities.contains(.clipboard) else { return missing(.clipboard, "read the clipboard") }
            return .value(platform.system.readClipboard().map(SystemCodec.encode))

        case .clipboardWrite(let content), .paste(let content):
            guard granted.capabilities.contains(.clipboard) else { return missing(.clipboard, "write or paste clipboard content") }
            if case .text(let text) = content, text.utf8.count > 1024 * 1024 { return .failure("text is too large to copy") }
            do {
                if case .paste = call { try await platform.system.paste(content) } else { try platform.system.writeClipboard(content) }
                return .ok
            } catch {
                return .failure("\(error)")
            }

        case .keepAwake(let request):
            // Releasing never needs the capability, so a revoked plugin can let go.
            guard request == nil || granted.capabilities.contains(.power) else { return missing(.power, "keep the Mac awake") }
            do {
                try platform.system.keepAwake(request.map { KeepAwakeRequest(display: $0.display, reason: "\(granted.name): \($0.reason.prefix(120))") }, pluginID: granted.id)
                return .ok
            } catch {
                return .failure("\(error)")
            }

        case .systemStatus:
            guard granted.capabilities.contains(.power) else { return missing(.power, "read battery and running apps") }
            return .value(SystemCodec.encode(platform.system.systemStatus()))

        case .calendarEvents(let from, let to):
            guard granted.capabilities.contains(.calendar) else { return missing(.calendar, "read calendar events") }
            guard to > from else { return .failure("calendarEvents needs to > from") }
            guard to.timeIntervalSince(from) <= 31 * 86400 + 3600 else { return .failure("calendarEvents covers at most 31 days at a time") }
            do {
                let events = try await platform.system.calendarEvents(from: from, to: to).prefix(500).map { event -> CalendarEvent in
                    var event = event
                    event.notes = event.notes.map { String($0.prefix(4000)) }
                    return event
                }
                return .value(SystemCodec.encode(Array(events)))
            } catch {
                return .failure("\(error)")
            }
        }
    }

    /// Lets go of anything the plugin holds in the OS (its power assertion).
    /// The supervisor calls it whenever the helper stops or exits.
    public func release(pluginID: String) {
        try? platform.system.keepAwake(nil, pluginID: pluginID)
    }

    private static func awaitingApproval(_ granted: Manifest, _ what: String) -> HostResult {
        .failure("\(granted.name) needs your approval \(what); open its panel in Fluid and click Allow")
    }

    private static func missing(_ capability: Capability, _ what: String) -> HostResult {
        .failure("to \(what), add .\(capability.caseName) to the manifest's capabilities")
    }
}

/// At most `limit` events per key in a sliding window of `per` seconds.
final class RateLimiter: @unchecked Sendable {
    private let limit: Int
    private let window: Double
    private let lock = NSLock()
    private var events: [String: [Date]] = [:]

    init(limit: Int, per window: Double) {
        self.limit = limit
        self.window = window
    }

    func allow(_ key: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var recent = (events[key] ?? []).filter { now.timeIntervalSince($0) < window }
        guard recent.count < limit else {
            events[key] = recent
            return false
        }
        recent.append(now)
        events[key] = recent
        return true
    }
}
