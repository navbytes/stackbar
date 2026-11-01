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
    /// A system-wide shortcut that opens the plugin's panel, spelled like
    /// row shortcuts: `cmd+shift+v`, `ctrl+option+k`. At least one of cmd,
    /// ctrl or option, plus one letter, digit, `space` or `f1`...`f12`.
    public var hotkey: String?
    /// The oldest Stackbar whose StackbarKit this source compiles against,
    /// like `0.10.0`. A plugin index hides the Install button on older apps.
    public var minimumStackbar: String?
    /// Where to read about the plugin: its README or repository.
    public var homepage: String?

    public init(id: String, name: String, version: String = "0.1.0", summary: String? = nil, surfaces: [Surface] = [.menuBar, .panel], triggers: [Trigger] = [.launch], capabilities: [Capability] = [], hotkey: String? = nil, minimumStackbar: String? = nil, homepage: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.summary = summary
        self.surfaces = surfaces
        self.triggers = triggers
        self.capabilities = capabilities
        self.hotkey = hotkey
        self.minimumStackbar = minimumStackbar
        self.homepage = homepage
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
        if let hotkey, HotKeySpec(hotkey) == nil {
            result.append("hotkey \"\(hotkey)\" needs cmd, ctrl or option plus one letter, digit, space or f1...f12, like cmd+shift+v")
        }
        if let minimumStackbar, !Self.isVersion(minimumStackbar) {
            result.append("minimumStackbar \"\(minimumStackbar)\" must be a version like 0.10.0")
        }
        if let homepage, !homepage.hasPrefix("https://") {
            result.append("homepage must be an https URL")
        }
        if triggers.contains(.clipboard), !capabilities.contains(.clipboard) {
            result.append("the .clipboard trigger needs the .clipboard capability")
        }
        for name in secretNames where !Self.isValidSecretName(name) {
            result.append("secret name \"\(name)\" must be 1 to 100 letters, digits, _, - or . (like GITHUB_TOKEN)")
        }
        for case .files(let paths) in capabilities where paths.contains(where: { !($0 == "~" || $0.hasPrefix("~/") || $0.hasPrefix("/")) }) {
            result.append("file paths start with ~/ or /, like ~/Notes")
        }
        let storageGrants = capabilities.compactMap { if case .storage(let megabytes) = $0 { return megabytes } else { return nil } }
        if storageGrants.count > 1 { result.append("declare .storage(megabytes:) once") }
        if storageGrants.contains(where: { !(1...Self.maxStorageMegabytes).contains($0) }) {
            result.append("storage is 1 to \(Self.maxStorageMegabytes) megabytes")
        }
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

    /// What a plugin also needs before any index lists it, on top of
    /// `problems`. A plugin a person runs from a file may skip these; a
    /// published one reaches apps of every version through a store card, so
    /// it must say what it does and which Stackbar it needs, and its version
    /// must order updates the same way in every app. A store's own policy
    /// (its id prefix, allowed imports) stays in that store's lint.
    public var publishingProblems: [String] {
        var result: [String] = []
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 3 || parts.contains(where: { $0.isEmpty || !$0.allSatisfy(\.isASCII) || !$0.allSatisfy(\.isNumber) }) {
            result.append("version \"\(version)\" must be three numbers, like 1.2.0")
        }
        if summary?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
            result.append("summary is missing; the store shows it on the plugin's card")
        }
        if minimumStackbar == nil {
            result.append("minimumStackbar is missing; without it an older app offers a plugin it can't build")
        }
        return result
    }

    public static let maxStorageMegabytes = 64

    /// The storage quota the manifest asks for, in bytes; nil means the
    /// default.
    public var storageQuotaBytes: Int? {
        for case .storage(let megabytes) in capabilities {
            return min(max(megabytes, 1), Self.maxStorageMegabytes) * 1024 * 1024
        }
        return nil
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

    /// Secret names are plain words. The host keeps OAuth tokens in the same
    /// store under `oauth/<plugin id>/<provider>`, so a name with a slash
    /// could read another plugin's tokens; such names are refused.
    public static func isVersion(_ text: String) -> Bool { VersionNumber(text) != nil }

    public static func isValidSecretName(_ name: String) -> Bool {
        (1...100).contains(name.utf8.count) && name.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "_-.".unicodeScalars.contains($0)) }
    }

    public var secretNames: [String] {
        capabilities.compactMap { capability in
            switch capability {
            case .secret(let name), .userServer(let name): return name
            default: return nil
            }
        }
    }

    /// The secrets that hold the URLs of servers the user chose.
    public var userServerSecrets: [String] {
        capabilities.compactMap { if case .userServer(let name) = $0 { return name } else { return nil } }
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
    /// When another plugin publishes to this topic (see `Stackbar.publish`).
    case topic(name: String)
    /// When anything new is copied to the clipboard, in any app. Needs the
    /// `.clipboard` capability; read the item with `Stackbar.clipboard()`.
    case clipboard

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
    /// A named secret the plugin reads with `Stackbar.secret(_:)`. The host keeps
    /// it in the Keychain and asks the user for it the first time.
    case secret(name: String)
    /// An OAuth 2.0 account the host signs in to for the plugin. The plugin
    /// gets only the access token, through `Stackbar.oauthToken(_:)`.
    case oauth(OAuthProvider)
    /// Reads what the user copies (`Stackbar.clipboard()`, the `.clipboard`
    /// trigger), and puts files and images back or pastes into the
    /// frontmost app (`Stackbar.paste`). Plain `Stackbar.copy` needs nothing.
    case clipboard
    /// Keeps the Mac awake (`Stackbar.keepAwake`) and reads battery, power and
    /// running apps (`Stackbar.systemStatus()`).
    case power
    /// Reads events from the user's calendars (`Stackbar.calendarEvents`).
    case calendar
    /// Reads what the user is in: the frontmost app, its window title, the
    /// selected text and Finder's selection (`Stackbar.context()`, and
    /// `CommandInvocation.context` when a command starts).
    case context
    /// URL schemes beyond the safe defaults (https, http, mailto, tel and the
    /// meeting apps) that `Stackbar.open` may open; `"*"` allows any scheme
    /// and file paths, which the install sheet warns about.
    case openURLs(schemes: [String])
    /// More room for `Stackbar.storage` than the default 1 MB: 1 to 64 MB.
    case storage(megabytes: Int)
    /// A server the user chooses, like a self-hosted proxy: the user enters
    /// its URL as the secret `name` (read it with `Stackbar.secret(name)`),
    /// and the plugin may reach that URL's host and no other. Stackbar 0.11.0
    /// and later.
    case userServer(secret: String)

    public static func network(_ hosts: String...) -> Capability { .network(hosts: hosts) }
}

/// An OAuth 2.0 authorization-code provider (with PKCE). The host runs the
/// browser sign-in with a loopback redirect, stores the tokens in the Keychain
/// and refreshes them; the plugin never sees the refresh token.
public struct OAuthProvider: Codable, Hashable, Sendable {
    /// What the plugin calls it: `Stackbar.oauthToken("github")`.
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

/// A parsed hotkey spec: modifiers and one key, all lowercased.
public struct HotKeySpec: Equatable, Sendable {
    public enum Modifier: String, Sendable, CaseIterable {
        case command, control, option, shift
    }

    public var modifiers: Set<Modifier>
    /// `a`...`z`, `0`...`9`, `space`, or `f1`...`f12`.
    public var key: String

    public init?(_ spec: String) {
        var modifiers: Set<Modifier> = []
        var key: String?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "shift", "⇧": modifiers.insert(.shift)
            default:
                guard key == nil else { return nil }
                key = part
            }
        }
        guard let key, Self.keys.contains(key), !modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        self.modifiers = modifiers
        self.key = key
    }

    public static let keys: Set<String> = {
        var keys = Set("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
        keys.insert("space")
        for number in 1...12 { keys.insert("f\(number)") }
        return keys
    }()
}

/// URL helpers that work the same on every platform without Foundation's URL
/// (StackbarProtocol depends on nothing).
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
