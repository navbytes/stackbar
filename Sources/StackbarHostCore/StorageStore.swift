import Foundation

/// Each plugin's saved values, one JSON file per plugin id.
///
/// Values are JSON strings chosen by the plugin. The store caps each plugin's
/// total so a runaway plugin can't fill the disk, and writes atomically so a
/// crash mid-write never leaves a half file.
///
/// With a `writeDelay`, a `set` changes the values in memory (and checks the
/// quota) at once, and the file is written once the plugin has been quiet
/// for that long, on a queue of its own, so a burst of saves costs one write
/// and never holds up the other plugins. `flush(_:)` and `flushAll()` write
/// what is waiting straight away: when a plugin stops and when the app quits.
public actor StorageStore {
    public static let defaultQuotaBytes = 1024 * 1024

    public let directory: URL
    public let quotaBytes: Int
    /// Seconds a change waits before it is written; 0 writes inside `set`.
    public let writeDelay: Double
    private var cache: [String: [String: String]] = [:]
    /// Each cached plugin's total, so a set doesn't add up every value again.
    private var sizes: [String: Int] = [:]
    private nonisolated let writer: Writer

    public init(directory: URL, quotaBytes: Int = StorageStore.defaultQuotaBytes, writeDelay: Double = 0) {
        self.directory = directory
        self.quotaBytes = quotaBytes
        self.writeDelay = max(0, writeDelay)
        self.writer = Writer(directory: directory)
    }

    public func snapshot(for pluginID: String) -> [String: String] {
        load(pluginID)
    }

    /// Saves or removes one value. Throws when the plugin would go over its
    /// quota: `quota` when the plugin was granted `.storage(megabytes:)`,
    /// otherwise the store's default.
    public func set(_ key: String, _ value: String?, for pluginID: String, quota: Int? = nil) throws {
        let quota = quota ?? quotaBytes
        var values = load(pluginID)
        let old = values[key].map { key.utf8.count + $0.utf8.count } ?? 0
        let new = value.map { key.utf8.count + $0.utf8.count } ?? 0
        let size = (sizes[pluginID] ?? 0) - old + new
        if size > quota, value != nil {
            throw StorageError.overQuota(pluginID: pluginID, bytes: size, quota: quota)
        }
        values[key] = value
        cache[pluginID] = values
        sizes[pluginID] = size
        if writeDelay == 0 {
            try writer.write(values, for: pluginID)
        } else if writer.stage(values, for: pluginID) {
            writer.schedule(pluginID, after: writeDelay)
        }
    }

    /// Writes a plugin's waiting changes now (when it stops).
    public nonisolated func flush(_ pluginID: String) {
        writer.flush(pluginID)
    }

    /// Writes every waiting change now, on the calling thread, so it is safe
    /// to call while the app terminates.
    public nonisolated func flushAll() {
        writer.flush(nil)
    }

    /// While paused nothing reaches the disk, not even `flushAll`, so files
    /// replaced underneath (a settings import) aren't overwritten with the
    /// values in memory. Resuming writes what waited.
    public nonisolated func setWritesPaused(_ paused: Bool) {
        writer.setPaused(paused)
    }

    /// Forgets everything a plugin saved (when it is removed).
    public func erase(_ pluginID: String) {
        cache[pluginID] = [:]
        sizes[pluginID] = 0
        writer.erase(pluginID)
    }

    private func load(_ pluginID: String) -> [String: String] {
        if let values = cache[pluginID] { return values }
        let values = writer.read(pluginID)
        cache[pluginID] = values
        sizes[pluginID] = values.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        return values
    }

    public enum StorageError: Error, CustomStringConvertible {
        case overQuota(pluginID: String, bytes: Int, quota: Int)

        public var description: String {
            switch self {
            case .overQuota(let id, let bytes, let quota): return "\(id) would store \(bytes) bytes; the limit is \(quota)"
            }
        }
    }

    /// The files. Writes are serialized by `io` and taken from `pending`
    /// under it, so a newer snapshot is never overtaken by an older one.
    final class Writer: @unchecked Sendable {
        let directory: URL
        private let state = NSLock()
        private let io = NSLock()
        private var pending: [String: [String: String]] = [:]
        private var paused = false
        private let queue = DispatchQueue(label: "stackbar.storage", qos: .utility)

        init(directory: URL) {
            self.directory = directory
        }

        /// Remembers the latest values; true when nothing was waiting yet
        /// (so the caller schedules the write).
        func stage(_ values: [String: String], for pluginID: String) -> Bool {
            state.withLock { pending.updateValue(values, forKey: pluginID) == nil }
        }

        func schedule(_ pluginID: String, after delay: Double) {
            // Strong: a write that is due happens even if the store goes away.
            queue.asyncAfter(deadline: .now() + delay) { self.flush(pluginID) }
        }

        /// Writes what is waiting for one plugin, or for all of them.
        func flush(_ pluginID: String?) {
            io.lock()
            defer { io.unlock() }
            let due = state.withLock { () -> [String: [String: String]] in
                guard !paused else { return [:] }
                if let pluginID {
                    return pending.removeValue(forKey: pluginID).map { [pluginID: $0] } ?? [:]
                }
                defer { pending.removeAll() }
                return pending
            }
            for (pluginID, values) in due {
                do {
                    try writeLocked(values, for: pluginID)
                } catch {
                    HostLog.shared.write(.error, "could not save stored values: \(error)", plugin: pluginID)
                }
            }
        }

        func write(_ values: [String: String], for pluginID: String) throws {
            io.lock()
            defer { io.unlock() }
            state.withLock { _ = pending.removeValue(forKey: pluginID) }
            try writeLocked(values, for: pluginID)
        }

        func setPaused(_ value: Bool) {
            state.withLock { paused = value }
            if !value { queue.async { self.flush(nil) } }
        }

        func erase(_ pluginID: String) {
            io.lock()
            defer { io.unlock() }
            state.withLock { _ = pending.removeValue(forKey: pluginID) }
            try? FileManager.default.removeItem(at: file(for: pluginID))
            removeLegacyFile(for: pluginID)
        }

        func read(_ pluginID: String) -> [String: String] {
            // Values saved before per-id file names are read from the old file.
            let data = (try? Data(contentsOf: file(for: pluginID))) ?? (try? Data(contentsOf: legacyFile(for: pluginID)))
            return data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        }

        private func writeLocked(_ values: [String: String], for pluginID: String) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(values).write(to: file(for: pluginID), options: .atomic)
            removeLegacyFile(for: pluginID)
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
    }
}
