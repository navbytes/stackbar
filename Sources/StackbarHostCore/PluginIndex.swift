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
    }

    public var name: String
    public var plugins: [Entry]

    public init(name: String, plugins: [Entry]) {
        self.name = name
        self.plugins = plugins
    }

    public func search(_ query: String) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return plugins }
        return plugins.filter { entry in
            [entry.name, entry.id, entry.summary ?? "", entry.publisher].contains { $0.lowercased().contains(query) }
        }
    }

    public static func fetch(_ url: URL) async throws -> PluginIndex {
        try JSONDecoder().decode(PluginIndex.self, from: try await download(url))
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
            let data = try Data(contentsOf: file)
            let bundle = try PluginBundle.decode(data)
            return Entry(id: bundle.manifest.id, name: bundle.manifest.name, summary: bundle.manifest.summary, version: bundle.manifest.version, publisher: bundle.publisher.name, bundle: file.lastPathComponent, sha256: SHA256.hex(data), capabilities: bundle.manifest.capabilities.map(\.summary))
        }
        return PluginIndex(name: name, plugins: entries)
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

        public var description: String {
            switch self {
            case .badURL(let url): return "\(url) is not a valid URL"
            case .insecure(let url): return "\(url) is not https"
            case .status(let url, let status): return "\(url) answered \(status)"
            case .tooLarge(let url): return "\(url) is too large"
            case .digestMismatch(let id): return "the bundle for \(id) does not match the index's digest"
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
