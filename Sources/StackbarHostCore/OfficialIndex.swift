import Foundation

/// The store this build lists first and can't remove: navbytes' index for
/// upstream builds, or an organization's own (`Distribution.store`). The app
/// trusts it only when it is signed by `publicKey`.
public enum OfficialIndex {
    public static var name: String { Distribution.current.store.name }
    public static var url: URL { Distribution.current.store.url }
    public static var repository: URL? { Distribution.current.store.repository }
    /// The publisher key (raw Ed25519, base64). The index and every bundle in
    /// it are signed with its private half, which lives only in the plugins
    /// repository's `release` environment. Nil makes the app leave the store
    /// out rather than trust it unsigned.
    public static var publicKey: String? { Distribution.current.store.publicKey }
    /// Shown as "Signed by …".
    public static var publisher: String { Distribution.current.store.publisher }

    public static var isAvailable: Bool { publicKey != nil }

    /// The site with a page for every plugin in this index, if the store has one.
    public static var website: URL? { Distribution.current.store.website }

    /// A plugin's page on the website: `/plugins/<slug>/`, the slug being the
    /// id's last part (`site/scripts/store.mjs` names pages the same way).
    public static func webPage(for pluginID: String) -> URL? {
        guard let website else { return nil }
        let slug = pluginID.split(separator: ".").last.map(String.init) ?? pluginID
        return website.appendingPathComponent("plugins").appendingPathComponent(slug).appendingPathComponent("")
    }

    /// Downloads and verifies the official index.
    public static func fetch() async throws -> PluginIndex {
        guard let publicKey else { throw PluginIndex.IndexError.unsigned }
        return try await PluginIndex.fetch(url, publicKey: publicKey)
    }
}
