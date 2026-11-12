import Foundation
import StackbarProtocol

/// Clipboard content the host hands to plugins by id: images as PNG, and
/// formatted copies as a snapshot of every pasteboard type. Files are named
/// by their hash; the newest are kept and the oldest pruned past `limit`
/// files or `maxBytes` in all. Lives in the host so a plugin's 1 MB of
/// storage only needs the ids.
public final class ClipboardImageStore: @unchecked Sendable {
    public let directory: URL
    public let limit: Int
    public let maxBytes: Int
    /// Saves between prunes: a prune lists and stats every kept file, so it
    /// runs on the first save and then once per this many.
    public let pruneEvery: Int
    private let lock = NSLock()
    private var savesSincePrune: Int?

    public init(directory: URL, limit: Int = 1000, maxBytes: Int = 512 * 1024 * 1024, pruneEvery: Int = 25) {
        self.directory = directory
        self.limit = limit
        self.maxBytes = maxBytes
        self.pruneEvery = max(1, pruneEvery)
    }

    /// Saves the data and returns its id. The same bytes get the same id.
    /// The hash and the write happen outside the lock, so a read of another
    /// item never waits on them; files are written atomically.
    @discardableResult
    public func save(_ data: Data) throws -> String {
        let id = String(SHA256.hex(data).prefix(32))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(id).bin")
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        } else {
            try data.write(to: file, options: .atomic)
        }
        if dueForPrune() { prune() }
        return id
    }

    public func data(for id: String) -> Data? {
        guard id.allSatisfy({ $0.isHexDigit }), !id.isEmpty else { return nil }
        return (try? Data(contentsOf: directory.appendingPathComponent("\(id).bin")))
            ?? (try? Data(contentsOf: directory.appendingPathComponent("\(id).png")))
    }

    /// Whether this save prunes: the first one, then every `pruneEvery`th.
    private func dueForPrune() -> Bool {
        lock.withLock {
            let count = savesSincePrune.map { $0 + 1 } ?? pruneEvery
            guard count >= pruneEvery else {
                savesSincePrune = count
                return false
            }
            savesSincePrune = 0
            return true
        }
    }

    private func prune() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let described = files.map { file -> (URL, Date, Int) in
            let values = try? file.resourceValues(forKeys: keys)
            return (file, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var bytes = 0
        for (index, entry) in described.enumerated() {
            bytes += entry.2
            if index >= limit || bytes > maxBytes { try? FileManager.default.removeItem(at: entry.0) }
        }
    }
}
