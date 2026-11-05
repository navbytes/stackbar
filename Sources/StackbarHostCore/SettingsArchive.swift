import Foundation

/// A whole Stackbar setup in one file, for a new Mac or a backup: the
/// plugins and where they came from, what each saved, command aliases and
/// hotkeys, palette favourites, and the app's own preferences.
///
/// Never in it: secrets, capability approvals, trusted publishers and agent
/// consent. A setup file is something people pass around, so importing one
/// can't grant a plugin anything; each plugin asks again as it would after a
/// fresh install.
public struct SettingsArchive: Codable, Equatable, Sendable {
    public static let fileExtension = "stackbarsettings"
    public static let currentFormat = 1
    /// Bigger files (a plugin's cache, say) are left out of an export.
    public static let maxFileBytes = 2 * 1024 * 1024

    /// The app preferences that travel. Everything else in UserDefaults stays.
    public static let defaultsKeys: Set<String> = [
        PaletteHotKey.defaultsKey, "pluginsOff", "autoUpdatePlugins", "indexURLs", "paletteCompact", "dockIconWithWindows",
    ]

    /// Files in the data directory that travel, by their path there.
    static let files: Set<String> = ["command-preferences.json", "palette-favorites.json", "installed.json", "bundled.json", "core-plugins.json"]
    /// Folders in the data directory that travel whole.
    static let folders: Set<String> = ["Plugins", "Storage"]
    static let installedRecord = "installed.json"

    public enum Preference: Codable, Equatable, Sendable {
        case bool(Bool)
        case string(String)
        case strings([String])

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else { self = .strings(try container.decode([String].self)) }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .strings(let value): try container.encode(value)
            }
        }

        /// The value to hand UserDefaults.
        public var propertyListValue: Any {
            switch self {
            case .bool(let value): return value
            case .string(let value): return value
            case .strings(let value): return value
            }
        }
    }

    public var format: Int
    public var stackbarVersion: String
    public var exportedAt: Date
    public var preferences: [String: Preference]
    /// Path in the data directory → contents.
    public var files: [String: Data]

    public enum ArchiveError: Error, CustomStringConvertible, Equatable {
        case notAnArchive
        case newerFormat(Int)
        case badPath(String)

        public var description: String {
            switch self {
            case .notAnArchive: return "this is not a Stackbar settings file"
            case .newerFormat(let format): return "this settings file is format \(format), newer than this Stackbar reads; update Stackbar first"
            case .badPath(let path): return "the settings file names a place Stackbar doesn't keep settings: \(path)"
            }
        }
    }

    /// What an import will do, for the confirmation sheet.
    public struct Summary: Equatable, Sendable {
        public var pluginFiles: [String]
        public var savedValues: Int
        public var preferences: Int
    }

    // MARK: Export

    /// Reads the setup out of `dataDirectory` and the given preferences.
    public static func export(dataDirectory: URL, defaults: UserDefaults = .standard, now: Date = Date()) throws -> SettingsArchive {
        var preferences: [String: Preference] = [:]
        for key in defaultsKeys {
            switch defaults.object(forKey: key) {
            case let value as String: preferences[key] = .string(value)
            case let value as [String]: preferences[key] = .strings(value)
            case let value as Bool: preferences[key] = .bool(value)
            default: break
            }
        }
        var files: [String: Data] = [:]
        let manager = FileManager.default
        for name in Self.files {
            let url = dataDirectory.appendingPathComponent(name)
            guard var data = try? Data(contentsOf: url), data.count <= maxFileBytes else { continue }
            if name == installedRecord { data = try relocate(data, from: dataDirectory.path, to: "") }
            files[name] = data
        }
        for folder in folders {
            let root = dataDirectory.appendingPathComponent(folder, isDirectory: true)
            guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= maxFileBytes else { continue }
                let base = root.resolvingSymlinksInPath().path
                let path = url.resolvingSymlinksInPath().path
                guard path.hasPrefix(base + "/") else { continue }
                let relative = String(path.dropFirst(base.count + 1))
                files[folder + "/" + relative] = try Data(contentsOf: url)
            }
        }
        return SettingsArchive(format: currentFormat, stackbarVersion: StackbarVersion.current, exportedAt: now, preferences: preferences, files: files)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return try encoder.encode(self)
    }

    // MARK: Import

    /// Reads and checks a settings file. Every path must be one the export
    /// writes; anything else refuses the whole file.
    public static func decode(_ data: Data) throws -> SettingsArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        guard let archive = try? decoder.decode(SettingsArchive.self, from: data) else { throw ArchiveError.notAnArchive }
        guard archive.format <= currentFormat else { throw ArchiveError.newerFormat(archive.format) }
        for path in archive.files.keys where !isAllowed(path) { throw ArchiveError.badPath(path) }
        return archive
    }

    static func isAllowed(_ path: String) -> Bool {
        if files.contains(path) { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, folders.contains(String(parts[0])) else { return false }
        return parts.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") } && !path.contains("\\")
    }

    public var summary: Summary {
        let plugins = files.keys.filter { $0.hasPrefix("Plugins/") }.map { String($0.dropFirst("Plugins/".count)) }.sorted()
        let values = files.filter { $0.key.hasPrefix("Storage/") }.values.reduce(0) { total, data in
            total + ((try? JSONDecoder().decode([String: String].self, from: data))?.count ?? 0)
        }
        return Summary(pluginFiles: plugins, savedValues: values, preferences: preferences.count)
    }

    /// Writes the files into `dataDirectory`, replacing ones with the same
    /// name and leaving the rest, and sets the preferences. Plugins already
    /// here that the file doesn't have stay installed.
    public func apply(to dataDirectory: URL, defaults: UserDefaults = .standard) throws {
        let manager = FileManager.default
        for (path, contents) in files {
            guard Self.isAllowed(path) else { throw ArchiveError.badPath(path) }
            var data = contents
            if path == Self.installedRecord {
                data = try Self.mergedRecords(data, into: dataDirectory)
            }
            let url = dataDirectory.appendingPathComponent(path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        for (key, value) in preferences where Self.defaultsKeys.contains(key) {
            defaults.set(value.propertyListValue, forKey: key)
        }
    }

    /// The installer keeps absolute paths. An export makes the ones inside
    /// the data directory relative, so they land in the new Mac's.
    static func relocate(_ data: Data, from old: String, to new: String) throws -> Data {
        guard var records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return data }
        let oldPrefix = old.hasSuffix("/") || old.isEmpty ? old : old + "/"
        let newPrefix = new.hasSuffix("/") || new.isEmpty ? new : new + "/"
        for index in records.indices {
            guard let file = records[index]["file"] as? String else { continue }
            if oldPrefix.isEmpty {
                if !file.hasPrefix("/") { records[index]["file"] = newPrefix + file }
            } else if file.hasPrefix(oldPrefix) {
                records[index]["file"] = newPrefix + file.dropFirst(oldPrefix.count)
            }
        }
        return try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
    }

    /// The file's records, made absolute here, plus this Mac's records for
    /// plugins the file doesn't mention.
    static func mergedRecords(_ data: Data, into dataDirectory: URL) throws -> Data {
        let incoming = (try? JSONSerialization.jsonObject(with: relocate(data, from: "", to: dataDirectory.path)) as? [[String: Any]]) ?? []
        let existingURL = dataDirectory.appendingPathComponent(installedRecord)
        let existing = (try? Data(contentsOf: existingURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        let ids = Set(incoming.compactMap { $0["id"] as? String })
        let kept = existing.filter { !ids.contains($0["id"] as? String ?? "") }
        return try JSONSerialization.data(withJSONObject: incoming + kept, options: [.prettyPrinted, .sortedKeys])
    }
}
