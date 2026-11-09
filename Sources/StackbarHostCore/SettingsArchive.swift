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
        "textExpansion", "textExpansionExcludedApps", TerminalChoice.defaultsKey,
        HyperKey.defaultsKey, HyperKey.escapeDefaultsKey, PaletteTabTarget.defaultsKey, CommandResolver.extraFoldersKey,
    ]

    /// Files in the data directory that travel, by their path there.
    static let files: Set<String> = ["command-preferences.json", "palette-favorites.json", "palette-rows.json", "installed.json", "bundled.json", "core-plugins.json"]
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

    /// What a settings file can carry, to export only some of it (a team
    /// baseline of commands and preferences, say, without anyone's data).
    public enum Part: String, CaseIterable, Sendable {
        /// The plugins and where they came from.
        case plugins
        /// What each plugin saved (its lists, its settings).
        case data
        /// Aliases, hotkeys and which commands show.
        case commands
        /// Favourites and kept palette rows.
        case palette
        /// The app's own preferences (the palette hotkey, plugins turned off…).
        case preferences

        /// The part a data-directory path belongs to.
        static func of(_ path: String) -> Part {
            if path.hasPrefix("Storage/") { return .data }
            switch path {
            case "command-preferences.json": return .commands
            case "palette-favorites.json", "palette-rows.json": return .palette
            default: return .plugins
            }
        }

        /// `plugins,commands` → those parts; nil names an unknown one.
        public static func parse(_ list: String) -> Set<Part>? {
            var parts = Set<Part>()
            for name in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) where !name.isEmpty {
                guard let part = Part(rawValue: name) else { return nil }
                parts.insert(part)
            }
            return parts.isEmpty ? nil : parts
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
    public static func export(dataDirectory: URL, defaults: UserDefaults = .standard, now: Date = Date(),
                              parts: Set<Part> = Set(Part.allCases)) throws -> SettingsArchive {
        var preferences: [String: Preference] = [:]
        for key in defaultsKeys where parts.contains(.preferences) {
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
        files = files.filter { parts.contains(Part.of($0.key)) }
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

    /// Writes the files into `dataDirectory` and sets the preferences.
    /// Plugins already here that the file doesn't have stay installed.
    ///
    /// By default a file merges into the one here: an alias, a saved value
    /// or a favourite the file doesn't mention stays, and the file wins
    /// where both have one. `replacing` writes the file's copy over it
    /// instead, as a restore from backup does.
    public func apply(to dataDirectory: URL, defaults: UserDefaults = .standard, replacing: Bool = false) throws {
        let manager = FileManager.default
        for (path, contents) in files {
            guard Self.isAllowed(path) else { throw ArchiveError.badPath(path) }
            var data = contents
            if path == Self.installedRecord {
                data = try Self.mergedRecords(data, into: dataDirectory)
            } else if !replacing, path.hasSuffix(".json"), let existing = try? Data(contentsOf: dataDirectory.appendingPathComponent(path)) {
                data = Self.merged(data, into: existing)
            }
            let url = dataDirectory.appendingPathComponent(path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        for (key, value) in preferences where Self.defaultsKeys.contains(key) {
            defaults.set(value.propertyListValue, forKey: key)
        }
    }

    /// A JSON file merged into the one here: objects key by key (the
    /// incoming value wins), lists with the incoming items this one lacks
    /// added at the end. Anything else, or anything unreadable, is the
    /// incoming file.
    static func merged(_ incoming: Data, into existing: Data) -> Data {
        guard let new = try? JSONSerialization.jsonObject(with: incoming, options: [.fragmentsAllowed]),
              let old = try? JSONSerialization.jsonObject(with: existing, options: [.fragmentsAllowed]) else { return incoming }
        let result: Any
        if let new = new as? [String: Any], let old = old as? [String: Any] {
            result = old.merging(new) { _, incoming in incoming }
        } else if let new = new as? [Any], let old = old as? [Any] {
            let known = Set(old.compactMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) })
            result = old + new.filter { item in
                guard let key = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys, .fragmentsAllowed]) else { return true }
                return !known.contains(key)
            }
        } else {
            return incoming
        }
        return (try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])) ?? incoming
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
