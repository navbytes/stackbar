import Foundation

/// What a plugin declares about itself before it ever runs.
///
/// The host reads it by launching the plugin with `--manifest`, so the
/// declaration lives in the plugin's own Swift source and is type-checked with
/// it. The host uses it to decide which surfaces to give the plugin, when to
/// wake it, and — from `capabilities` — which sandbox entitlements to sign it
/// with and what to show on the install sheet.
public struct Manifest: Codable, Equatable, Sendable {
    /// Reverse-DNS, stable for the life of the plugin: `dev.navbytes.pr-cockpit`.
    public var id: String
    public var name: String
    public var version: String
    public var surfaces: [Surface]
    public var triggers: [Trigger]
    public var capabilities: [Capability]
    /// One sentence for the plugin index, the install sheet and the palette.
    public var summary: String?

    public init(id: String, name: String, version: String = "0.1.0", summary: String? = nil, surfaces: [Surface] = [.menuBar, .panel], triggers: [Trigger] = [.launch], capabilities: [Capability] = []) {
        self.id = id
        self.name = name
        self.version = version
        self.summary = summary
        self.surfaces = surfaces
        self.triggers = triggers
        self.capabilities = capabilities
    }

    /// Problems that make the manifest unusable, in words. Empty means valid.
    public var problems: [String] {
        var result: [String] = []
        let idPattern = id.split(separator: ".", omittingEmptySubsequences: false)
        if idPattern.count < 2 || idPattern.contains(where: { $0.isEmpty || !$0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) {
            result.append("id \"\(id)\" must be reverse-DNS, like dev.example.clock")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { result.append("name is empty") }
        if surfaces.isEmpty { result.append("surfaces is empty") }
        for capability in capabilities {
            if case .network(let hosts) = capability, hosts.contains(where: { $0.contains("/") || $0.contains(":") }) {
                result.append("network hosts are bare domain names (api.github.com, *.example.com), not URLs")
            }
            if case .oauth(let provider) = capability, provider.authorizeURL.hasPrefix("https://") == false || provider.tokenURL.hasPrefix("https://") == false {
                if !(provider.authorizeURL.hasPrefix("http://127.0.0.1") && provider.tokenURL.hasPrefix("http://127.0.0.1")) {
                    result.append("oauth provider \(provider.name) must use https URLs")
                }
            }
        }
        return result
    }

    /// The domains the plugin may reach through the host, from `.network` and
    /// the token endpoints of its `.oauth` providers.
    public var networkHosts: [String] {
        capabilities.flatMap { capability -> [String] in
            switch capability {
            case .network(let hosts): return hosts
            case .oauth(let provider): return [provider.tokenURL, provider.authorizeURL].compactMap { URLParts.host(of: $0) }
            default: return []
            }
        }
    }

    public var secretNames: [String] {
        capabilities.compactMap { if case .secret(let name) = $0 { return name } else { return nil } }
    }

    public var oauthProviders: [OAuthProvider] {
        capabilities.compactMap { if case .oauth(let provider) = $0 { return provider } else { return nil } }
    }

    public var watchedFiles: [String] {
        triggers.compactMap { if case .file(let path) = $0 { return path } else { return nil } }
    }

    public var topics: [String] {
        triggers.compactMap { if case .topic(let name) = $0 { return name } else { return nil } }
    }

    /// The shortest periodic trigger, if any — what the host schedules.
    public var refreshInterval: Double? {
        triggers.compactMap { trigger -> Double? in
            if case .every(let seconds) = trigger { return seconds }
            return nil
        }.min()
    }
}

/// When the host asks a plugin to `refresh()`.
public enum Trigger: Codable, Hashable, Sendable {
    /// Right after the plugin starts (and after every restart).
    case launch
    /// Periodically. Values under one second are raised to one second.
    case every(seconds: Double)
    /// When the Mac wakes from sleep.
    case wake
    /// When a file or folder changes. `~` is expanded. Needs a `.files`
    /// capability that covers the path when the plugin is sandboxed.
    case file(path: String)
    /// When another plugin publishes to this topic (see `Fluid.publish`).
    case topic(name: String)

    public static func every(_ duration: Duration) -> Trigger {
        let (seconds, attoseconds) = duration.components
        return .every(seconds: max(1, Double(seconds) + Double(attoseconds) / 1e18))
    }

    public static func minutes(_ count: Double) -> Trigger { .every(seconds: max(1, count * 60)) }
}

/// What a plugin may touch. Declared here, enforced by the sandbox entitlements
/// the host signs the plugin with, and shown to the user before install.
public enum Capability: Codable, Hashable, Sendable {
    /// Outgoing connections. The OS sandbox can only switch the network on or
    /// off; the host lists the domains so the user knows what to expect.
    case network(hosts: [String])
    /// Folders the user grants read/write access to.
    case files(paths: [String])
    /// Commands the plugin may run.
    case run(commands: [String])
    /// A named secret the plugin reads with `Fluid.secret(_:)`. The host keeps
    /// it in the Keychain and asks the user for it the first time.
    case secret(name: String)
    /// An OAuth 2.0 account the host signs in to for the plugin. The plugin
    /// gets only the access token, through `Fluid.oauthToken(_:)`.
    case oauth(OAuthProvider)

    public static func network(_ hosts: String...) -> Capability { .network(hosts: hosts) }
}

/// An OAuth 2.0 authorization-code provider (with PKCE). The host runs the
/// browser sign-in with a loopback redirect, stores the tokens in the Keychain
/// and refreshes them; the plugin never sees the refresh token.
public struct OAuthProvider: Codable, Hashable, Sendable {
    /// What the plugin calls it: `Fluid.oauthToken("github")`.
    public var name: String
    public var authorizeURL: String
    public var tokenURL: String
    public var clientID: String
    /// Only for providers that insist on one even with PKCE (GitHub OAuth
    /// apps). It ships inside the plugin, so it is not a secret in any real
    /// sense; prefer providers that accept PKCE alone.
    public var clientSecret: String?
    public var scopes: [String]

    public init(name: String, authorizeURL: String, tokenURL: String, clientID: String, clientSecret: String? = nil, scopes: [String] = []) {
        self.name = name
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.scopes = scopes
    }
}

/// URL helpers that work the same on every platform without Foundation's URL
/// (FluidProtocol depends on nothing).
public enum URLParts {
    /// The lowercased host of an absolute URL, without port or credentials.
    public static func host(of url: String) -> String? {
        guard let schemeEnd = url.range(of: "://") else { return nil }
        var rest = url[schemeEnd.upperBound...]
        if let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { rest = rest[..<end] }
        if let at = rest.lastIndex(of: "@") { rest = rest[rest.index(after: at)...] }
        if rest.hasPrefix("[") { return rest.split(separator: "]").first.map { String($0.dropFirst()).lowercased() } }
        if let colon = rest.lastIndex(of: ":") { rest = rest[..<colon] }
        return rest.isEmpty ? nil : rest.lowercased()
    }

    /// Whether `host` is covered by a declared pattern: an exact domain, or
    /// `*.example.com` for any subdomain (not the apex itself).
    public static func host(_ host: String, matches patterns: [String]) -> Bool {
        let host = host.lowercased()
        return patterns.contains { pattern in
            let pattern = pattern.lowercased()
            if pattern == "*" { return true }
            if pattern.hasPrefix("*.") { return host.hasSuffix(pattern.dropFirst(1)) }
            return host == pattern
        }
    }
}
