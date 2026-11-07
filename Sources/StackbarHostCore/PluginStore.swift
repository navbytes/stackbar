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
        /// The store's renders and READMEs, when it publishes them.
        public var site: StoreSite?

        public init(source: Source, index: PluginIndex, site: StoreSite? = nil) {
            self.source = source
            self.index = index
            self.site = site
        }

        /// The entry's page on the Stackbar website. Only the official
        /// index has pages there.
        public func webPage(for entry: PluginIndex.Entry) -> URL? {
            source.isOfficial ? OfficialIndex.webPage(for: entry.id) : nil
        }
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
    /// With `site`, also each store's `site.json` (renders and READMEs), which
    /// only the store's pages need, not the background update check.
    public static func load(_ sources: [Source], site: Bool = false) async -> (catalogs: [Catalog], problems: [String]) {
        var catalogs: [Catalog] = []
        var problems: [String] = []
        for source in sources {
            do {
                let index = try await PluginIndex.fetch(source.url, publicKey: source.publicKey)
                catalogs.append(Catalog(source: source, index: index, site: site ? await StoreSite.fetch(beside: source.url) : nil))
            } catch {
                problems.append("\(source.url.absoluteString): \(error)")
            }
        }
        return (catalogs, problems)
    }

    /// The listed entry for a plugin id (what the store shows for it: the
    /// newest version this app can build), from the first catalog that has it.
    public static func find(_ pluginID: String, in catalogs: [Catalog], running: String = StackbarVersion.current) -> (catalog: Catalog, entry: PluginIndex.Entry)? {
        for catalog in catalogs {
            if let entry = catalog.index.search("", running: running).first(where: { $0.id == pluginID }) { return (catalog, entry) }
        }
        return nil
    }

    /// Updates for plugins installed from a store, offered only by an entry
    /// from the same publisher (the installer's key pin refuses others
    /// anyway), and withdrawals. Only a signed index can withdraw a plugin,
    /// so an index anyone can host can't take someone else's plugin away.
    ///
    /// `isPinned` says whether the installer holds a publisher key for the
    /// plugin id. A record without one (it came in with an imported settings
    /// file, not from an install here) is matched to entries by publisher
    /// name alone, and the first key seen would be pinned; so it gets no
    /// automatic update. Installing it again from the Store, which the user
    /// does knowingly, pins it.
    public static func review(_ catalogs: [Catalog], installed: [PluginInstaller.Installed], running: String = StackbarVersion.current, isPinned: (String) -> Bool = { _ in true }) -> Review {
        var review = Review()
        for record in installed {
            if let withdrawal = catalogs.lazy.compactMap({ catalog -> PluginIndex.Revocation? in
                guard catalog.source.publicKey != nil else { return nil }
                return catalog.index.revocation(for: record.id, version: record.version)
            }).first {
                review.withdrawn.append(Withdrawn(installed: record, reason: withdrawal.reason))
                continue
            }
            guard isPinned(record.id) else { continue }
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
