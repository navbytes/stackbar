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

    /// Downloads and verifies the official index.
    public static func fetch() async throws -> PluginIndex {
        guard let publicKey else { throw PluginIndex.IndexError.unsigned }
        return try await PluginIndex.fetch(url, publicKey: publicKey)
    }
}
