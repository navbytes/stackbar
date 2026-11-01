import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import StackbarProtocol

/// A list of installable plugins: the store. Any static host can serve one
/// (a GitHub repository works), and a person can add more than one.
///
/// Each entry names a signed `.stackbarplugin` bundle and its SHA-256; the
/// installer checks both the digest and the bundle's own signature, so an
/// index can't swap a bundle without it being noticed.
public struct PluginIndex: Codable, Equatable, Sendable {
    /// The newest index format this Stackbar reads. Format 1 had no
    /// signature, revocations or the store fields; every field added since is
    /// optional, so an older app still reads a newer index.
    public static let currentFormat = 2

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var summary: String?
        public var version: String
        public var publisher: String
        /// Absolute, or relative to the index's own URL.
        public var bundle: String
        public var sha256: String
        public var capabilities: [String]
        /// The store groups entries by this, like `System` or `Developer`.
        public var category: String?
        public var surfaces: [String]?
        /// From the manifest: the oldest Stackbar that can build the plugin.
        public var minimumStackbar: String?
        /// Absolute, or relative to the index's own URL.
        public var screenshot: String?
        public var homepage: String?
        /// When this version was published, `YYYY-MM-DD`.
        public var updated: String?

        public init(id: String, name: String, summary: String? = nil, version: String, publisher: String, bundle: String, sha256: String, capabilities: [String], category: String? = nil, surfaces: [String]? = nil, minimumStackbar: String? = nil, screenshot: String? = nil, homepage: String? = nil, updated: String? = nil) {
            self.id = id
            self.name = name
            self.summary = summary
            self.version = version
            self.publisher = publisher
            self.bundle = bundle
            self.sha256 = sha256
            self.capabilities = capabilities
            self.category = category
            self.surfaces = surfaces
            self.minimumStackbar = minimumStackbar
            self.screenshot = screenshot
            self.homepage = homepage
            self.updated = updated
        }

        /// The Stackbar version this entry needs when `running` is too old to
        /// build it, otherwise nil. An unreadable requirement counts as too new.
        public func requiredStackbar(running: String = StackbarVersion.current) -> String? {
            guard let minimumStackbar else { return nil }
            guard let needed = VersionNumber(minimumStackbar), let current = VersionNumber(running) else { return minimumStackbar }
            return current < needed ? minimumStackbar : nil
        }

        /// Whether this entry is a newer version than `installed`.
        public func isNewer(than installed: String) -> Bool {
            guard let offered = VersionNumber(version), let current = VersionNumber(installed) else { return version != installed }
            return current < offered
        }
    }

    /// A published plugin that must not be installed or kept running.
    public struct Revocation: Codable, Equatable, Sendable {
        public var id: String
        /// The revoked versions; nil revokes every version of the plugin.
        public var versions: [String]?
        public var reason: String

        public init(id: String, versions: [String]? = nil, reason: String) {
            self.id = id
            self.versions = versions
            self.reason = reason
        }

        public func covers(id: String, version: String) -> Bool {
            guard id == self.id else { return false }
            guard let versions else { return true }
            return versions.contains { VersionNumber($0).flatMap { a in VersionNumber(version).map { a == $0 } } ?? ($0 == version) }
        }
    }

    public var format: Int?
    public var name: String
    public var homepage: String?
    /// When the index was built, ISO 8601.
    public var generated: String?
    public var plugins: [Entry]
    public var revoked: [Revocation]?
    /// Ed25519 signature of `signedBytes()`, base64, by the publisher whose
    /// public key the app trusts for this index.
    public var signature: String?

    public init(name: String, plugins: [Entry], format: Int? = PluginIndex.currentFormat, homepage: String? = nil, generated: String? = nil, revoked: [Revocation]? = nil, signature: String? = nil) {
        self.format = format
        self.name = name
        self.homepage = homepage
        self.generated = generated
        self.plugins = plugins
        self.revoked = revoked
        self.signature = signature
    }

    public func search(_ query: String) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        let listed = plugins.filter { revocation(for: $0.id, version: $0.version) == nil }
        guard !query.isEmpty else { return listed }
        return listed.filter { entry in
            [entry.name, entry.id, entry.summary ?? "", entry.publisher, entry.category ?? ""].contains { $0.lowercased().contains(query) }
        }
    }

    /// The revocation covering this plugin version, if any.
    public func revocation(for id: String, version: String) -> Revocation? {
        revoked?.first { $0.covers(id: id, version: version) }
    }

    /// Entries grouped by category, in name order, uncategorized last.
    public func byCategory(_ entries: [Entry]) -> [(category: String, entries: [Entry])] {
        let groups = Dictionary(grouping: entries) { $0.category ?? "Other" }
        return groups.keys.sorted { ($0 == "Other" ? 1 : 0, $0) < ($1 == "Other" ? 1 : 0, $1) }.map { key in
            (key, groups[key]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    /// Newer, buildable versions of installed plugins: plugin id → entry.
    public func updates(installed: [String: String], running: String = StackbarVersion.current) -> [String: Entry] {
        var result: [String: Entry] = [:]
        for entry in plugins {
            guard let current = installed[entry.id], entry.isNewer(than: current),
                  entry.requiredStackbar(running: running) == nil,
                  revocation(for: entry.id, version: entry.version) == nil else { continue }
            if let existing = result[entry.id], !entry.isNewer(than: existing.version) { continue }
            result[entry.id] = entry
        }
        return result
    }

    /// Throws when the entry is withdrawn or needs a newer Stackbar.
    public func checkInstallable(_ entry: Entry, running: String = StackbarVersion.current) throws {
        if let revocation = revocation(for: entry.id, version: entry.version) { throw IndexError.revoked(entry.id, revocation.reason) }
        if let needed = entry.requiredStackbar(running: running) { throw IndexError.needsNewerStackbar(entry.id, needed) }
    }

    // MARK: Signing

    /// What the signature covers: the whole index without its signature, as
    /// canonical JSON (sorted keys).
    public func signedBytes() throws -> Data {
        var unsigned = self
        unsigned.signature = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data("stackbarindex/1\n".utf8)
        data.append(try encoder.encode(unsigned))
        return data
    }

    public func signed(privateKey: Data) throws -> PluginIndex {
        var copy = self
        copy.signature = nil
        copy.signature = try Signing.sign(copy.signedBytes(), privateKey: privateKey).base64EncodedString()
        return copy
    }

    /// Throws unless the index carries a valid signature by `publicKey`
    /// (raw 32-byte Ed25519, base64).
    public func verify(publicKey: String) throws {
        guard let signature, let signatureData = Data(base64Encoded: signature) else { throw IndexError.unsigned }
        guard let key = Data(base64Encoded: publicKey),
              try Signing.verify(signatureData, of: signedBytes(), publicKey: key) else { throw IndexError.badSignature }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Downloads an index. With `publicKey`, it must be signed by that key.
    public static func fetch(_ url: URL, publicKey: String? = nil) async throws -> PluginIndex {
        let index = try JSONDecoder().decode(PluginIndex.self, from: try await download(url))
        if let format = index.format, format > currentFormat { throw IndexError.unsupportedFormat(format) }
        if let publicKey { try index.verify(publicKey: publicKey) }
        return index
    }

    /// Downloads an entry's bundle and checks it against the index's digest.
    public static func bundle(for entry: Entry, indexURL: URL) async throws -> PluginBundle {
        guard let url = URL(string: entry.bundle, relativeTo: indexURL)?.absoluteURL else { throw IndexError.badURL(entry.bundle) }
        let data = try await download(url)
        guard SHA256.hex(data) == entry.sha256.lowercased() else { throw IndexError.digestMismatch(entry.id) }
        return try PluginBundle.decode(data)
    }

    /// An index for a folder of bundles, with paths relative to the index.
    public static func build(name: String, bundles: [URL]) throws -> PluginIndex {
        let entries = try bundles.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { file -> Entry in
            try entry(for: file, path: file.lastPathComponent)
        }
        return PluginIndex(name: name, plugins: entries)
    }

    /// An index for every bundle under `root`, at any depth. A bundle in a
    /// subfolder takes that folder's name as its category (`System/x.stackbarplugin`),
    /// and a PNG with the bundle's id next to it (`System/<id>.png`) is its screenshot.
    public static func build(name: String, root: URL, homepage: String? = nil, revoked: [Revocation]? = nil, generated: Date = Date()) throws -> PluginIndex {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == PluginBundle.fileExtension }
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var entries: [Entry] = []
        for file in files {
            guard file.path.hasPrefix(rootPath) else { continue }
            let relative = String(file.path.dropFirst(rootPath.count))
            let folders = relative.split(separator: "/").dropLast()
            var entry = try entry(for: file, path: relative)
            entry.category = folders.first.map(String.init)
            let screenshot = file.deletingLastPathComponent().appendingPathComponent(entry.id + ".png")
            if FileManager.default.fileExists(atPath: screenshot.path) {
                entry.screenshot = (folders.map(String.init) + [entry.id + ".png"]).joined(separator: "/")
            }
            entries.append(entry)
        }
        entries.sort { ($0.id, VersionNumber($0.version) ?? VersionNumber("0")!) < ($1.id, VersionNumber($1.version) ?? VersionNumber("0")!) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return PluginIndex(name: name, plugins: entries, homepage: homepage, generated: formatter.string(from: generated), revoked: revoked?.isEmpty == false ? revoked : nil)
    }

    private static func entry(for file: URL, path: String) throws -> Entry {
        let data = try Data(contentsOf: file)
        let bundle = try PluginBundle.decode(data)
        let manifest = bundle.manifest
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
        let day = modified.map { date -> String in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter.string(from: date)
        }
        return Entry(id: manifest.id, name: manifest.name, summary: manifest.summary, version: manifest.version, publisher: bundle.publisher.name, bundle: path, sha256: SHA256.hex(data), capabilities: manifest.capabilities.map(\.summary), surfaces: manifest.surfaces.map(\.rawValue), minimumStackbar: manifest.minimumStackbar, homepage: manifest.homepage, updated: day)
    }

    public static func download(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        guard url.scheme == "https" || (url.scheme == "http" && url.host == "127.0.0.1") else { throw IndexError.insecure(url.absoluteString) }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndexError.status(url.absoluteString, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard data.count <= 8 * 1024 * 1024 else { throw IndexError.tooLarge(url.absoluteString) }
        return data
    }

    public enum IndexError: Error, CustomStringConvertible, Equatable {
        case badURL(String)
        case insecure(String)
        case status(String, Int)
        case tooLarge(String)
        case digestMismatch(String)
        case unsigned
        case badSignature
        case unsupportedFormat(Int)
        case revoked(String, String)
        case needsNewerStackbar(String, String)

        public var description: String {
            switch self {
            case .badURL(let url): return "\(url) is not a valid URL"
            case .insecure(let url): return "\(url) is not https"
            case .status(let url, let status): return "\(url) answered \(status)"
            case .tooLarge(let url): return "\(url) is too large"
            case .digestMismatch(let id): return "the bundle for \(id) does not match the index's digest"
            case .unsigned: return "the index is not signed, and this index must be"
            case .badSignature: return "the index's signature is not valid for its publisher's key"
            case .unsupportedFormat(let format): return "index format \(format) is newer than this Stackbar understands"
            case .revoked(let id, let reason): return "\(id) was withdrawn by its publisher: \(reason)"
            case .needsNewerStackbar(let id, let version): return "\(id) needs Stackbar \(version) or later"
            }
        }
    }
}

/// Puts verified bundles into the plugins folder and remembers where each
/// installed plugin came from.
public final class PluginInstaller: @unchecked Sendable {
    public struct Installed: Codable, Equatable, Sendable {
        public var id: String
        public var file: String
        public var version: String
        public var publisher: String
        public var installedAt: Date
    }

    public let pluginsDirectory: URL
    public let publishers: PublisherStore
    private let recordFile: URL
    private let lock = NSLock()

    public init(pluginsDirectory: URL, publishers: PublisherStore, recordFile: URL) {
        self.pluginsDirectory = pluginsDirectory
        self.publishers = publishers
        self.recordFile = recordFile
    }

    public var installed: [Installed] {
        lock.withLock { load() }
    }

    /// Verifies the bundle, pins or checks its publisher, and writes its
    /// source. Returns the plugin file; the host then builds it and checks
    /// that the built manifest matches `bundle.manifest` with `confirm`.
    @discardableResult
    public func install(_ bundle: PluginBundle) throws -> URL {
        try bundle.verify()
        try publishers.accept(bundle)
        return try lock.withLock {
            var records = load()
            let existing = records.first { $0.id == bundle.manifest.id }
            let file = existing.map { URL(fileURLWithPath: $0.file) } ?? pluginsDirectory.appendingPathComponent(PluginBuilder.sanitizedName(bundle.manifest.id) + ".swift")
            try FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
            try bundle.source.write(to: file, atomically: true, encoding: .utf8)
            records.removeAll { $0.id == bundle.manifest.id }
            records.append(Installed(id: bundle.manifest.id, file: file.path, version: bundle.manifest.version, publisher: bundle.publisher.name, installedAt: Date()))
            try save(records)
            return file
        }
    }

    /// After building an installed plugin: the manifest the code declares
    /// must be the one that was signed, or the install is undone.
    public func confirm(_ built: Manifest, matches bundle: PluginBundle, file: URL) throws {
        guard built == bundle.manifest else {
            try? uninstall(bundle.manifest.id)
            throw PluginBundle.BundleError.manifestMismatch
        }
    }

    public func uninstall(_ pluginID: String) throws {
        try lock.withLock {
            var records = load()
            if let record = records.first(where: { $0.id == pluginID }) {
                try? FileManager.default.removeItem(atPath: record.file)
            }
            records.removeAll { $0.id == pluginID }
            try save(records)
        }
    }

    private func load() -> [Installed] {
        (try? Data(contentsOf: recordFile)).flatMap { try? JSONDecoder.ledger.decode([Installed].self, from: $0) } ?? []
    }

    private func save(_ records: [Installed]) throws {
        try FileManager.default.createDirectory(at: recordFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.ledger.encode(records).write(to: recordFile, options: .atomic)
    }
}
