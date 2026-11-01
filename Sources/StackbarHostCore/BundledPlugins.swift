import Foundation

/// Keeps the plugins Stackbar ships (Plugins/ and Examples/) current in the
/// user's plugins folder without overwriting their edits.
///
/// A copy is replaced when it is still exactly what Stackbar last wrote (the
/// record holds that digest). A copy with no record, from before the record
/// existed, or one that imports `FluidKit` (from before the rename, so it no
/// longer builds) is replaced too, after being kept beside it as
/// `<name>.swift.bak`. A copy the user changed since Stackbar wrote it stays.
public struct BundledPlugins {
    public struct Result: Equatable, Sendable {
        public var installed: [URL] = []
        public var updated: [URL] = []
        public var kept: [URL] = []
    }

    public let directory: URL
    public let recordFile: URL

    public init(directory: URL, recordFile: URL) {
        self.directory = directory
        self.recordFile = recordFile
    }

    /// With `installMissing` false only copies already in the folder are
    /// refreshed, so a bundled plugin the user deleted stays deleted.
    @discardableResult
    public func sync(_ sources: [URL], installMissing: Bool = true) -> Result {
        let manager = FileManager.default
        var record = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: recordFile))) ?? [:]
        var result = Result()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for source in sources {
            guard let fresh = try? Data(contentsOf: source) else { continue }
            let name = source.lastPathComponent
            let destination = directory.appendingPathComponent(name)
            let digest = SHA256.hex(fresh)
            guard let current = try? Data(contentsOf: destination) else {
                if installMissing, (try? fresh.write(to: destination, options: .atomic)) != nil {
                    record[name] = digest
                    result.installed.append(destination)
                }
                continue
            }
            let currentDigest = SHA256.hex(current)
            if currentDigest == digest {
                record[name] = digest
                continue
            }
            let untouched = record[name] == currentDigest
            let stale = record[name] == nil || String(decoding: current, as: UTF8.self).contains("import FluidKit")
            guard untouched || stale else {
                result.kept.append(destination)
                continue
            }
            if stale, !untouched {
                try? current.write(to: destination.appendingPathExtension("bak"), options: .atomic)
            }
            if (try? fresh.write(to: destination, options: .atomic)) != nil {
                record[name] = digest
                result.updated.append(destination)
            }
        }
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: recordFile, options: .atomic)
        }
        return result
    }
}
