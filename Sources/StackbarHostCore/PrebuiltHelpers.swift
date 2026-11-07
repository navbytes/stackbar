import Foundation
import StackbarProtocol

/// A plugin compiled ahead of time, so a Mac without Xcode or the Command Line
/// Tools can still run it.
///
/// A store publishes one helper per plugin version and StackbarKit, listed in
/// `helpers.json` beside its index. The record is signed by the plugin's
/// publisher with the key that signs its bundle, and names the exact source it
/// was built from, so neither the index nor whoever hosts the binary can swap
/// it: the app takes a helper only for the source in the plugins folder, and
/// only when the publisher of that source vouches for it.
public struct HelperRecord: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    /// SHA-256 of the plugin source, hex: the bundle's `sourceDigest`.
    public var sourceDigest: String
    /// `PluginBuilder.frameworkDigest` of the StackbarKit it was built against.
    public var stackbarKit: String
    /// The protocol that StackbarKit speaks.
    public var protocolVersion: Int
    /// `arm64` or `x86_64`.
    public var arch: String
    /// Absolute, or relative to `helpers.json`.
    public var url: String
    /// SHA-256 of the binary, hex.
    public var sha256: String
    public var size: Int?
    /// The publisher's raw Ed25519 public key, base64.
    public var publicKey: String
    /// Ed25519 signature of `signedBytes`, base64.
    public var signature: String

    enum CodingKeys: String, CodingKey {
        case id, version, sourceDigest, stackbarKit, protocolVersion = "protocol", arch, url, sha256, size, publicKey, signature
    }

    public init(id: String, version: String, sourceDigest: String, stackbarKit: String, protocolVersion: Int, arch: String, url: String, sha256: String, size: Int? = nil, publicKey: String = "", signature: String = "") {
        self.id = id
        self.version = version
        self.sourceDigest = sourceDigest
        self.stackbarKit = stackbarKit
        self.protocolVersion = protocolVersion
        self.arch = arch
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.publicKey = publicKey
        self.signature = signature
    }

    /// What the signature covers. The URL and size are left out: a binary
    /// may move, and its digest already pins its bytes.
    public var signedBytes: Data {
        Data("stackbarhelper/1\n\(id)\n\(version)\n\(sourceDigest.lowercased())\n\(stackbarKit)\n\(protocolVersion)\n\(arch)\n\(sha256.lowercased())".utf8)
    }

    /// Signs the record with the publisher's private key.
    public mutating func sign(privateKey: Data) throws {
        publicKey = try Signing.publicKey(for: privateKey).base64EncodedString()
        signature = try Signing.sign(signedBytes, privateKey: privateKey).base64EncodedString()
    }

    /// Throws unless the record is signed by `publicKey` (base64).
    public func verify(publicKey expected: String) throws {
        guard publicKey == expected else { throw PrebuiltHelpers.HelperError.wrongPublisher(id) }
        guard let key = Data(base64Encoded: publicKey), let signatureData = Data(base64Encoded: signature),
              try Signing.verify(signatureData, of: signedBytes, publicKey: key) else {
            throw PrebuiltHelpers.HelperError.badSignature(id)
        }
    }
}

/// `helpers.json`: the prebuilt helpers a store publishes.
public struct HelperIndex: Codable, Equatable, Sendable {
    public static let currentFormat = 1
    public static let fileName = "helpers.json"

    public var format: Int
    /// When it was written, ISO 8601.
    public var generated: String?
    public var helpers: [HelperRecord]

    public init(helpers: [HelperRecord], generated: String? = nil, format: Int = HelperIndex.currentFormat) {
        self.format = format
        self.generated = generated
        self.helpers = helpers
    }

    /// Where a store's helpers are listed: beside its index.
    public static func url(beside indexURL: URL) -> URL {
        indexURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    /// The store's helpers, or nil when it publishes none or the file
    /// can't be read: a store without helpers is not an error.
    public static func fetch(beside indexURL: URL) async -> (index: HelperIndex, url: URL)? {
        let url = url(beside: indexURL)
        guard let data = try? await PluginIndex.download(url),
              let index = try? JSONDecoder().decode(HelperIndex.self, from: data),
              index.format <= currentFormat else { return nil }
        return (index, url)
    }

    /// The helper to use for a plugin's source: one built against exactly
    /// `stackbarKit`, else (with `compatible`) the one with the same
    /// protocol whose StackbarKit is listed last, which the publisher
    /// writes newest last.
    public func match(id: String, sourceDigest: String, stackbarKit: String, protocolVersion: Int, arch: String = PrebuiltHelpers.arch, compatible: Bool) -> (record: HelperRecord, exact: Bool)? {
        let candidates = helpers.filter { $0.id == id && $0.sourceDigest.lowercased() == sourceDigest.lowercased() && $0.arch == arch }
        if let exact = candidates.first(where: { $0.stackbarKit == stackbarKit }) { return (exact, true) }
        guard compatible, let near = candidates.last(where: { $0.protocolVersion == protocolVersion }) else { return nil }
        return (near, false)
    }
}

/// `helpers.json` of each store, fetched once per pass (a nil answer too: a
/// store that publishes none is asked once, not once per plugin).
public final class HelperIndexCache: @unchecked Sendable {
    private let lock = NSLock()
    private var fetches: [URL: Task<(index: HelperIndex, url: URL)?, Never>] = [:]

    public init() {}

    public func fetch(beside indexURL: URL) async -> (index: HelperIndex, url: URL)? {
        let task = lock.withLock { () -> Task<(index: HelperIndex, url: URL)?, Never> in
            if let running = fetches[indexURL] { return running }
            let created = Task { await HelperIndex.fetch(beside: indexURL) }
            fetches[indexURL] = created
            return created
        }
        return await task.value
    }
}

/// Prebuilt helpers on this Mac: `Prebuilt/` in the build cache (downloaded)
/// and in the app's StackbarKit (built with the app and covered by its
/// signature). Files are named after what they were built from:
/// `<sourceDigest>-<stackbarKit>` for an exact build, and
/// `<sourceDigest>-p<protocol>` for one built against another StackbarKit
/// that speaks the same protocol.
public enum PrebuiltHelpers {
    public static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// The largest helper the app downloads.
    public static let maximumSize = 64 * 1024 * 1024

    public static func exactName(sourceDigest: String, stackbarKit: String) -> String {
        "\(sourceDigest.lowercased())-\(stackbarKit)"
    }

    public static func compatibleName(sourceDigest: String, protocolVersion: Int) -> String {
        "\(sourceDigest.lowercased())-p\(protocolVersion)"
    }

    /// The first executable helper with `name` in `directories`.
    public static func find(_ name: String, in directories: [URL]) -> URL? {
        directories.lazy.map { $0.appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// A downloaded, verified helper, ready to save once its source is in place.
    public struct Download: Sendable {
        public var record: HelperRecord
        public var binary: Data
        public var exact: Bool
    }

    /// Downloads and verifies the helper `index` lists for a source.
    /// `publicKey` is the key that signed the source's bundle.
    public static func download(_ record: HelperRecord, exact: Bool, from indexURL: URL, publicKey: String) async throws -> Download {
        try record.verify(publicKey: publicKey)
        guard let url = URL(string: record.url, relativeTo: indexURL)?.absoluteURL else { throw PluginIndex.IndexError.badURL(record.url) }
        let data = try await PluginIndex.download(url, limit: maximumSize)
        guard SHA256.hex(data) == record.sha256.lowercased() else { throw HelperError.digestMismatch(record.id) }
        return Download(record: record, binary: data, exact: exact)
    }

    /// Finds, downloads and verifies the helper for a source from the store
    /// at `indexURL`. Nil when the store lists none that fits.
    ///
    /// With `cache`, a store's `helpers.json` is downloaded once for all the
    /// plugins a pass looks at instead of once for each.
    public static func fetch(id: String, sourceDigest: String, publicKey: String, indexURL: URL, stackbarKit: String, protocolVersion: Int = StackbarProtocolVersion.current, compatible: Bool, cache: HelperIndexCache? = nil) async throws -> Download? {
        let found: (index: HelperIndex, url: URL)?
        if let cache { found = await cache.fetch(beside: indexURL) } else { found = await HelperIndex.fetch(beside: indexURL) }
        guard let (index, url) = found,
              let (record, exact) = index.match(id: id, sourceDigest: sourceDigest, stackbarKit: stackbarKit, protocolVersion: protocolVersion, compatible: compatible) else { return nil }
        return try await download(record, exact: exact, from: url, publicKey: publicKey)
    }

    /// Writes a verified helper into `directory`, named for what it runs on
    /// this Mac: exact for `stackbarKit`, or compatible by protocol.
    @discardableResult
    public static func save(_ download: Download, in directory: URL, stackbarKit: String) throws -> URL {
        let record = download.record
        let name = download.exact && record.stackbarKit == stackbarKit
            ? exactName(sourceDigest: record.sourceDigest, stackbarKit: stackbarKit)
            : compatibleName(sourceDigest: record.sourceDigest, protocolVersion: record.protocolVersion)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        let temporary = directory.appendingPathComponent(".\(name).\(UUID().uuidString)")
        try download.binary.write(to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        _ = try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
        return file
    }

    public enum HelperError: Error, CustomStringConvertible, Equatable {
        case wrongPublisher(String)
        case badSignature(String)
        case digestMismatch(String)
        case notPrebuilt(name: String, version: String)

        public var description: String {
            switch self {
            case .wrongPublisher(let id): return "the prebuilt \(id) is signed by someone other than its publisher"
            case .badSignature(let id): return "the prebuilt \(id) has no valid signature"
            case .digestMismatch(let id): return "the prebuilt \(id) does not match its digest"
            case .notPrebuilt(let name, let version):
                return "\(name) \(version) isn't prebuilt for this version of Stackbar yet, and building it needs the Command Line Tools (xcode-select --install). Try again later."
            }
        }
    }
}

extension PluginBuilder {
    /// The protocol version the StackbarKit at `stackbarPackage` speaks,
    /// read from its source (`StackbarProtocolVersion.current`).
    public static func protocolVersion(of stackbarPackage: URL) -> Int? {
        let file = stackbarPackage.appendingPathComponent("Sources/StackbarProtocol/Messages.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let range = text.range(of: #"static let current = (\d+)"#, options: .regularExpression) else { return nil }
        return Int(text[range].split(separator: " ").last ?? "")
    }

    /// Builds a helper to publish, always from the source, and describes it.
    /// The record still needs its URL and the publisher's signature.
    public func buildHelper(source: URL) throws -> (binary: URL, record: HelperRecord) {
        var builder = self
        builder.usesPrebuilt = false
        let binary = try builder.build(source: source).binary
        let manifest = try PluginProcess.readManifest(executable: binary)
        guard let protocolVersion = Self.protocolVersion(of: stackbarPackage) else {
            throw Failure(diagnostics: [], log: "can't read the protocol version of the StackbarKit at \(stackbarPackage.path)")
        }
        let data = try Data(contentsOf: binary)
        let record = HelperRecord(id: manifest.id, version: manifest.version, sourceDigest: SHA256.hex(try Data(contentsOf: source)),
                                  stackbarKit: stackbarKit, protocolVersion: protocolVersion, arch: PrebuiltHelpers.arch,
                                  url: "", sha256: SHA256.hex(data), size: data.count)
        return (binary, record)
    }
}

extension PrebuiltHelpers {
    /// The helper to save with a bundle that is about to be installed from
    /// the store at `indexURL`: an exact one when the store has it, else
    /// (without a toolchain) one for this host's protocol. Nil when this Mac
    /// already has one, or can build the plugin itself.
    ///
    /// Throws when, without a toolchain, the plugin could not run: there is
    /// no usable helper, so installing it would only break it. An update then
    /// waits until the store has built one.
    public static func prepare(_ bundle: PluginBundle, indexURL: URL, builder: PluginBuilder, toolchain: Bool) async throws -> Download? {
        if builder.hasPrebuilt(sourceDigest: bundle.sourceDigest, compatible: !toolchain) { return nil }
        do {
            if let download = try await fetch(id: bundle.manifest.id, sourceDigest: bundle.sourceDigest, publicKey: bundle.publisher.publicKey,
                                               indexURL: indexURL, stackbarKit: builder.stackbarKit, compatible: !toolchain) {
                return download
            }
        } catch {
            // With a compiler the plugin builds anyway; a bad helper is
            // simply not used.
            if !toolchain { throw error }
            return nil
        }
        if !toolchain { throw HelperError.notPrebuilt(name: bundle.manifest.name, version: bundle.manifest.version) }
        return nil
    }

    /// Fetches the missing helpers for plugins installed from a store, such
    /// as after a Stackbar update changed StackbarKit. Only for a source that
    /// is still exactly what was installed, and only signed by the key the
    /// plugin is pinned to. Returns the ids that got one.
    public static func refresh(installed: [PluginInstaller.Installed], catalogs: [PluginStore.Catalog], publishers: PublisherStore, builder: PluginBuilder, toolchain: Bool) async -> [String] {
        let stackbarKit = builder.stackbarKit
        let cache = HelperIndexCache()
        var refreshed: [String] = []
        for record in installed {
            guard let source = try? Data(contentsOf: URL(fileURLWithPath: record.file)),
                  let publicKey = publishers.publisher(for: record.id)?.publicKey,
                  let catalog = catalogs.first(where: { catalog in catalog.index.plugins.contains { $0.id == record.id } }) else { continue }
            let digest = SHA256.hex(source)
            if builder.hasPrebuilt(sourceDigest: digest, compatible: false) { continue }
            // Without a compiler, a compatible helper keeps the plugin
            // running; once there is one, only an exact match is worth a
            // download.
            let compatible = !toolchain && !builder.hasPrebuilt(sourceDigest: digest, compatible: true)
            guard let download = try? await fetch(id: record.id, sourceDigest: digest, publicKey: publicKey, indexURL: catalog.source.url,
                                                  stackbarKit: stackbarKit, compatible: compatible, cache: cache),
                  (try? save(download, in: builder.downloadedHelpers, stackbarKit: stackbarKit)) != nil else { continue }
            refreshed.append(record.id)
        }
        return refreshed
    }
}
