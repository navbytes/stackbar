import Foundation

/// Each plugin's saved values, one JSON file per plugin id.
///
/// Values are JSON strings chosen by the plugin. The store caps each plugin's
/// total so a runaway plugin can't fill the disk, and writes atomically so a
/// crash mid-write never leaves a half file.
public actor StorageStore {
    public static let defaultQuotaBytes = 1024 * 1024

    public let directory: URL
    public let quotaBytes: Int
    private var cache: [String: [String: String]] = [:]

    public init(directory: URL, quotaBytes: Int = StorageStore.defaultQuotaBytes) {
        self.directory = directory
        self.quotaBytes = quotaBytes
    }

    public func snapshot(for pluginID: String) -> [String: String] {
        load(pluginID)
    }

    /// Saves or removes one value. Throws when the plugin would go over quota.
    public func set(_ key: String, _ value: String?, for pluginID: String) throws {
        var values = load(pluginID)
        values[key] = value
        let size = values.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        if size > quotaBytes {
            throw StorageError.overQuota(pluginID: pluginID, bytes: size, quota: quotaBytes)
        }
        cache[pluginID] = values
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(values).write(to: file(for: pluginID), options: .atomic)
        removeLegacyFile(for: pluginID)
    }

    /// Forgets everything a plugin saved (when it is removed).
    public func erase(_ pluginID: String) {
        cache[pluginID] = [:]
        try? FileManager.default.removeItem(at: file(for: pluginID))
        removeLegacyFile(for: pluginID)
    }

    private func load(_ pluginID: String) -> [String: String] {
        if let values = cache[pluginID] { return values }
        // Values saved before per-id file names are read from the old file.
        let data = (try? Data(contentsOf: file(for: pluginID))) ?? (try? Data(contentsOf: legacyFile(for: pluginID)))
        let values = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        cache[pluginID] = values
        return values
    }

    private func file(for pluginID: String) -> URL {
        directory.appendingPathComponent(PluginBuilder.dataFileName(pluginID) + ".json")
    }

    private func legacyFile(for pluginID: String) -> URL {
        directory.appendingPathComponent(PluginBuilder.sanitizedName(pluginID) + ".json")
    }

    private func removeLegacyFile(for pluginID: String) {
        let legacy = legacyFile(for: pluginID)
        if legacy != file(for: pluginID) { try? FileManager.default.removeItem(at: legacy) }
    }

    public enum StorageError: Error, CustomStringConvertible {
        case overQuota(pluginID: String, bytes: Int, quota: Int)

        public var description: String {
            switch self {
            case .overQuota(let id, let bytes, let quota): return "\(id) would store \(bytes) bytes; the limit is \(quota)"
            }
        }
    }
}
