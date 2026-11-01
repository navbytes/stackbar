import Foundation

/// The indexes the store reads, and what they say about installed plugins:
/// newer versions to install and versions their publisher withdrew.
public enum PluginStore {
    public struct Source: Equatable, Sendable {
        public var url: URL
        /// When set, the index must be signed by this key.
        public var publicKey: String?
        /// The built-in navbytes index: listed first, can't be removed.
        public var isOfficial: Bool

        public init(url: URL, publicKey: String? = nil, isOfficial: Bool = false) {
            self.url = url
            self.publicKey = publicKey
            self.isOfficial = isOfficial
        }
    }

    public struct Catalog: Equatable, Sendable {
        public var source: Source
        public var index: PluginIndex
    }

    public struct Update: Equatable, Sendable {
        public var entry: PluginIndex.Entry
        public var indexURL: URL
        public var installedVersion: String
    }

    public struct Withdrawn: Equatable, Sendable {
        public var installed: PluginInstaller.Installed
        public var reason: String
    }

    public struct Review: Equatable, Sendable {
        public var updates: [Update] = []
        public var withdrawn: [Withdrawn] = []
    }

    /// The official index (when its key is known) followed by the user's own.
    public static func sources(userURLs: [String]) -> [Source] {
        var result: [Source] = []
        if let key = OfficialIndex.publicKey {
            result.append(Source(url: OfficialIndex.url, publicKey: key, isOfficial: true))
        }
        for string in userURLs {
            guard let url = URL(string: string), url.scheme == "https" || url.isFileURL, url != OfficialIndex.url else { continue }
            result.append(Source(url: url))
        }
        return result
    }

    /// Fetches every source; a source that fails is reported, not fatal.
    public static func load(_ sources: [Source]) async -> (catalogs: [Catalog], problems: [String]) {
        var catalogs: [Catalog] = []
        var problems: [String] = []
        for source in sources {
            do {
                catalogs.append(Catalog(source: source, index: try await PluginIndex.fetch(source.url, publicKey: source.publicKey)))
            } catch {
                problems.append("\(source.url.absoluteString): \(error)")
            }
        }
        return (catalogs, problems)
    }

    /// Updates for plugins installed from a store, offered only by an entry
    /// from the same publisher (the installer's key pin refuses others
    /// anyway), and withdrawals. Only a signed index can withdraw a plugin,
    /// so an index anyone can host can't take someone else's plugin away.
    public static func review(_ catalogs: [Catalog], installed: [PluginInstaller.Installed], running: String = StackbarVersion.current) -> Review {
        var review = Review()
        for record in installed {
            if let withdrawal = catalogs.lazy.compactMap({ catalog -> PluginIndex.Revocation? in
                guard catalog.source.publicKey != nil else { return nil }
                return catalog.index.revocation(for: record.id, version: record.version)
            }).first {
                review.withdrawn.append(Withdrawn(installed: record, reason: withdrawal.reason))
                continue
            }
            var best: Update?
            for catalog in catalogs {
                let offered = PluginIndex(name: catalog.index.name, plugins: catalog.index.plugins.filter { $0.publisher == record.publisher }, revoked: catalog.index.revoked)
                guard let entry = offered.updates(installed: [record.id: record.version], running: running)[record.id] else { continue }
                if let current = best, !entry.isNewer(than: current.entry.version) { continue }
                best = Update(entry: entry, indexURL: catalog.source.url, installedVersion: record.version)
            }
            if let best { review.updates.append(best) }
        }
        return review
    }
}
