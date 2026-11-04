import Foundation

/// The plugin index navbytes publishes from navbytes/stackbar-plugins. The app
/// lists it first and can't remove it, and trusts it only when it is signed
/// by `publicKey`.
public enum OfficialIndex {
    public static let name = "Stackbar Plugins"
    public static let url = URL(string: "https://navbytes.github.io/stackbar-plugins/index.json")!
    public static let repository = URL(string: "https://github.com/navbytes/stackbar-plugins")!
    /// The navbytes publisher key (raw Ed25519, base64). The index and every
    /// bundle in it are signed with its private half, which lives only in the
    /// plugins repository's `release` environment (backed up by Naveen). Nil
    /// would make the app leave the official index out rather than trust it unsigned.
    public static let publicKey: String? = "4dpLtXEpFXdi+6cviY/KdYuUulJPbEmCxxIK0EEN2/w="

    public static var isAvailable: Bool { publicKey != nil }

    /// The Stackbar website, which has a page for every plugin in this index.
    public static let website = URL(string: "https://stackbar.app")!

    /// A plugin's page on the website: `/plugins/<slug>/`, the slug being the
    /// id's last part (`site/scripts/store.mjs` names pages the same way).
    public static func webPage(for pluginID: String) -> URL {
        let slug = pluginID.split(separator: ".").last.map(String.init) ?? pluginID
        return website.appendingPathComponent("plugins").appendingPathComponent(slug).appendingPathComponent("")
    }

    /// Downloads and verifies the official index.
    public static func fetch() async throws -> PluginIndex {
        guard let publicKey else { throw PluginIndex.IndexError.unsigned }
        return try await PluginIndex.fetch(url, publicKey: publicKey)
    }
}
