import Foundation

/// What a store publishes next to its signed index in `site.json`: each
/// version's renders (every surface, light and dark) and each plugin's README
/// split into a description and its `- **Label:**` facts. The website builds
/// its plugin pages from it and Settings → Store its plugin detail page.
///
/// It is not signed: it only decorates entries the index already vouches
/// for, and it is optional, so a store without one still lists everything.
public struct StoreSite: Codable, Equatable, Sendable {
    public struct Render: Codable, Equatable, Sendable {
        public var light: String?
        public var dark: String?

        public init(light: String? = nil, dark: String? = nil) {
            self.light = light
            self.dark = dark
        }

        /// The path for the appearance, falling back to the other one.
        public func path(dark wantsDark: Bool) -> String? {
            wantsDark ? (dark ?? light) : (light ?? dark)
        }
    }

    public struct Fact: Codable, Equatable, Sendable {
        public var label: String
        public var text: String

        public init(label: String, text: String) {
            self.label = label
            self.text = text
        }
    }

    public struct About: Codable, Equatable, Sendable {
        /// The version the README was published with.
        public var version: String?
        /// Markdown; see `paragraphs`.
        public var description: String
        public var facts: [Fact]

        public init(version: String? = nil, description: String, facts: [Fact] = []) {
            self.version = version
            self.description = description
            self.facts = facts
        }

        /// The description's paragraphs with the README's hard line breaks
        /// joined, ready for `AttributedString(markdown:)`.
        public var paragraphs: [String] {
            description
                .components(separatedBy: "\n")
                .split { $0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { $0.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
        }
    }

    public static let currentFormat = 1
    /// The order surfaces are shown in, the most telling first.
    public static let surfaceOrder = ["panel", "window", "widget", "menuBar", "palette"]

    public var format: Int
    /// Plugin id → version → surface → render.
    public var plugins: [String: [String: [String: Render]]]
    /// Plugin id → its README.
    public var about: [String: About]?

    public init(format: Int = StoreSite.currentFormat, plugins: [String: [String: [String: Render]]] = [:], about: [String: About]? = nil) {
        self.format = format
        self.plugins = plugins
        self.about = about
    }

    /// The renders of one version, the most telling surface first.
    public func renders(_ id: String, version: String) -> [(surface: String, render: Render)] {
        let shots = plugins[id]?[version] ?? [:]
        return shots.keys
            .sorted { (Self.rank($0), $0) < (Self.rank($1), $1) }
            .compactMap { surface in shots[surface].map { (surface, $0) } }
    }

    /// The render a list row shows: the version's first surface.
    public func thumbnail(_ id: String, version: String) -> Render? {
        renders(id, version: version).first?.render
    }

    public func about(_ id: String) -> About? {
        about?[id]
    }

    private static func rank(_ surface: String) -> Int {
        surfaceOrder.firstIndex(of: surface) ?? surfaceOrder.count
    }

    /// `site.json` beside the index at `indexURL`.
    public static func url(beside indexURL: URL) -> URL {
        indexURL.deletingLastPathComponent().appendingPathComponent("site.json")
    }

    /// Reads it, or nil for a format this app does not know.
    public static func decode(_ data: Data) throws -> StoreSite? {
        let site = try JSONDecoder().decode(StoreSite.self, from: data)
        return site.format == currentFormat ? site : nil
    }

    /// The store's `site.json`, or nil when it has none or it can't be read.
    public static func fetch(beside indexURL: URL) async -> StoreSite? {
        guard let data = try? await PluginIndex.download(url(beside: indexURL)) else { return nil }
        return (try? decode(data)) ?? nil
    }
}

/// `stackbar://store/<plugin-id>`: opens that plugin's page in Settings →
/// Store. The website's "Get it in Stackbar" button uses it. It only shows
/// the page; installing still takes the user's click.
public struct StoreLink: Equatable, Sendable {
    public var pluginID: String

    public init(pluginID: String) { self.pluginID = pluginID }

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "stackbar", url.host?.lowercased() == "store" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 1, let id = parts.first?.removingPercentEncoding,
              !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { return nil }
        pluginID = id
    }

    public var url: URL { URL(string: "stackbar://store/\(pluginID)")! }
}
