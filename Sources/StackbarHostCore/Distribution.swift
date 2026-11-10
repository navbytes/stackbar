import Foundation

/// Who publishes this build: its plugin store and signing key, its team (and
/// so its app group), where it updates from and where its links go.
///
/// The values are decided when the app is built, never at run time: the build
/// scripts merge `Packaging/distribution.json` with an optional
/// `Packaging/distribution.override.json` (`scripts/distribution.py`) and
/// write the result into Info.plist under `StackbarDistribution`, where the
/// app's code signature covers it. No environment variable or user default
/// can point an installed app at another store or key.
///
/// Upstream builds carry `Distribution.upstream`. An organization that builds
/// its own copy adds the override file and edits nothing else (see
/// docs/self-hosting.md).
public struct Distribution: Codable, Equatable, Sendable {
    /// The Info.plist key holding this, as a JSON string.
    public static let infoKey = "StackbarDistribution"
    /// The app's bundle id. Not part of the distribution: changing it would
    /// split settings, the keychain and the URL scheme from upstream builds.
    public static let bundleID = "io.navbytes.stackbar"

    public struct Store: Codable, Equatable, Sendable {
        /// What the store is called in Settings.
        public var name: String
        /// The signed index the app lists first and can't remove.
        public var url: URL
        /// Raw Ed25519 public key, base64. Nil leaves the store out rather
        /// than trusting it unsigned.
        public var publicKey: String?
        /// Shown as "Signed by …".
        public var publisher: String
        /// Where the store's plugins are developed.
        public var repository: URL?
        /// A site with a page per plugin at `/plugins/<slug>/`, if any.
        public var website: URL?
        /// The secret whose value goes as a bearer token to the store's host.
        public var authSecret: String?
    }

    public struct Updates: Codable, Equatable, Sendable {
        /// Sparkle's appcast. Nil builds an app that never updates itself.
        public var feed: URL?
        /// The appcast with pre-releases too, for Get beta versions.
        public var betaFeed: URL?
        /// What Settings says when the build can't update itself.
        public var manualNote: String
    }

    public struct Links: Codable, Equatable, Sendable {
        /// Help › Stackbar Website. Nil opens `repository` instead.
        public var website: URL?
        /// Welcome's "What each permission is for". Nil hides it.
        public var permissionsHelp: URL?
        /// Where releases, issues and problem reports go.
        public var repository: URL
    }

    /// The Apple team that signs the app; the app group starts with it.
    public var teamID: String
    public var store: Store
    /// Whether people may add other stores in Settings.
    public var allowUserStores: Bool
    public var updates: Updates
    public var links: Links

    /// The group the app and its widget share: macOS style, prefixed with
    /// the team id, so a Developer ID build needs no provisioning profile.
    public var appGroup: String { "\(teamID).\(Self.bundleID)" }

    /// Navbytes' own build. `Packaging/distribution.json` must say the same
    /// (DistributionTests checks it).
    public static let upstream = Distribution(
        teamID: "59J9RQXYYP",
        store: Store(
            name: "Stackbar Plugins",
            url: URL(string: "https://navbytes.github.io/stackbar-plugins/index.json")!,
            publicKey: "4dpLtXEpFXdi+6cviY/KdYuUulJPbEmCxxIK0EEN2/w=",
            publisher: "navbytes",
            repository: URL(string: "https://github.com/navbytes/stackbar-plugins")!,
            website: URL(string: "https://stackbar.app")!,
            authSecret: nil),
        allowUserStores: true,
        updates: Updates(
            feed: URL(string: "https://github.com/navbytes/stackbar/releases/latest/download/appcast.xml")!,
            betaFeed: URL(string: "https://github.com/navbytes/stackbar/releases/download/beta/appcast.xml")!,
            manualNote: "This build doesn't update itself. Update with Homebrew (brew upgrade --cask stackbar) or download the latest release from stackbar.app."),
        links: Links(
            website: URL(string: "https://stackbar.app")!,
            permissionsHelp: URL(string: "https://stackbar.app/docs/permissions/")!,
            repository: URL(string: "https://github.com/navbytes/stackbar")!))

    /// This build's distribution: the app's Info.plist, or for stackbarctl
    /// inside an app, that app's. Anything else (swift run, tests, Linux)
    /// is the upstream build.
    public static let current: Distribution = {
        if let found = from(info: Bundle.main.infoDictionary) { return found }
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath()
        let plist = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        if executable.deletingLastPathComponent().lastPathComponent == "MacOS",
           let data = try? Data(contentsOf: plist),
           let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let found = from(info: info) {
            return found
        }
        return .upstream
    }()

    /// The distribution an Info.plist dictionary carries, if any.
    public static func from(info: [String: Any]?) -> Distribution? {
        guard let text = info?[infoKey] as? String, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Distribution.self, from: data)
    }

    /// Releases, the issue list and the bug form live under `links.repository`.
    public var releasesURL: URL { links.repository.appendingPathComponent("releases") }
    public var latestReleaseURL: URL { releasesURL.appendingPathComponent("latest") }
    public var issuesURL: URL { links.repository.appendingPathComponent("issues") }
}
