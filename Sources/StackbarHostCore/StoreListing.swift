import Foundation

/// What Settings → Store shows: every store's entries as one list, filtered by
/// search, category and whether they're installed or have an update, plus the
/// "New and updated" shelf. No UI here, so it is tested on Linux.
public enum StoreListing {
    public enum Filter: String, CaseIterable, Sendable {
        case all, installed, updates
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public var catalog: PluginStore.Catalog
        public var entry: PluginIndex.Entry
        /// Unique across stores, which may list the same plugin.
        public var id: String { catalog.source.url.absoluteString + "#" + entry.id }

        public init(catalog: PluginStore.Catalog, entry: PluginIndex.Entry) {
            self.catalog = catalog
            self.entry = entry
        }
    }

    /// What is installed: plugin id → installed version, and the plugins that
    /// are loaded without a store record (a copy the user dropped in).
    public struct Installed: Equatable, Sendable {
        public var versions: [String: String]
        public var loaded: Set<String>

        public init(versions: [String: String] = [:], loaded: Set<String> = []) {
            self.versions = versions
            self.loaded = loaded
        }

        public func contains(_ id: String) -> Bool { versions[id] != nil || loaded.contains(id) }

        /// Whether `entry` is a newer version this app can build.
        public func hasUpdate(_ entry: PluginIndex.Entry, running: String = StackbarVersion.current) -> Bool {
            guard let installed = versions[entry.id] else { return false }
            return entry.isNewer(than: installed) && entry.requiredStackbar(running: running) == nil
        }
    }

    /// Every listed entry across stores, in store order then by name.
    public static func all(_ catalogs: [PluginStore.Catalog], query: String = "", running: String = StackbarVersion.current) -> [Item] {
        catalogs.flatMap { catalog in
            catalog.index.search(query, running: running)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { Item(catalog: catalog, entry: $0) }
        }
    }

    public static func items(_ catalogs: [PluginStore.Catalog], query: String = "", category: String? = nil, filter: Filter = .all,
                             installed: Installed = Installed(), running: String = StackbarVersion.current) -> [Item] {
        all(catalogs, query: query, running: running).filter { item in
            if let category, (item.entry.category ?? "Other") != category { return false }
            switch filter {
            case .all: return true
            case .installed: return installed.contains(item.entry.id)
            case .updates: return installed.hasUpdate(item.entry, running: running)
            }
        }
    }

    /// The categories with something listed, in the order the website uses,
    /// then any others alphabetically, then "Other".
    public static func categories(_ catalogs: [PluginStore.Catalog], running: String = StackbarVersion.current) -> [String] {
        let present = Set(all(catalogs, running: running).map { $0.entry.category ?? "Other" })
        let known = ["Productivity", "Developer", "Monitoring", "System", "Network"]
        let rest = present.subtracting(known).subtracting(["Other"]).sorted()
        return known.filter(present.contains) + rest + (present.contains("Other") ? ["Other"] : [])
    }

    /// Plugins published in the last `days`, newest first.
    public static func recent(_ catalogs: [PluginStore.Catalog], now: Date = Date(), days: Int = 14, limit: Int = 6,
                              running: String = StackbarVersion.current) -> [Item] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let dated = all(catalogs, running: running).compactMap { item -> (Item, Date)? in
            guard let day = item.entry.updated, let date = formatter.date(from: day), date >= cutoff else { return nil }
            return (item, date)
        }
        var seen = Set<String>()
        return dated.sorted { $0.1 > $1.1 }
            .map(\.0)
            .filter { seen.insert($0.entry.id).inserted }
            .prefix(limit)
            .map { $0 }
    }
}
