import Foundation
import FluidProtocol
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A signed, distributable plugin: one `.fluidplugin` JSON file with the
/// source, its manifest, and an Ed25519 signature by its publisher.
///
/// Bundles carry source, not binaries: the host builds every plugin locally,
/// which is what makes the per-plugin sandbox possible, and lets anyone read
/// what they install. The signature covers the source and the manifest, and
/// the host pins each plugin id to the first publisher key it saw (trust on
/// first use), so an update signed by someone else is refused.
public struct PluginBundle: Codable, Equatable, Sendable {
    public static let fileExtension = "fluidplugin"

    public struct Publisher: Codable, Equatable, Sendable {
        public var name: String
        /// Raw 32-byte Ed25519 public key, base64.
        public var publicKey: String
    }

    public var format = 1
    public var manifest: Manifest
    public var source: String
    /// SHA-256 of the source, hex.
    public var sourceDigest: String
    public var publisher: Publisher
    /// Ed25519 signature of `signedBytes`, base64.
    public var signature: String

    /// What the signature covers: the format, the manifest (canonical JSON)
    /// and the source digest.
    public static func signedBytes(manifest: Manifest, sourceDigest: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data("fluidplugin/1\n".utf8)
        data.append(try encoder.encode(manifest))
        data.append(Data("\n\(sourceDigest)".utf8))
        return data
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> PluginBundle {
        let bundle = try JSONDecoder().decode(PluginBundle.self, from: data)
        guard bundle.format == 1 else { throw BundleError.unsupportedFormat(bundle.format) }
        return bundle
    }

    /// Checks the digest and the signature. Doesn't check who the publisher
    /// is; `PublisherStore` does that.
    public func verify() throws {
        guard SHA256.hex(Data(source.utf8)) == sourceDigest else { throw BundleError.digestMismatch }
        let problems = manifest.problems
        guard problems.isEmpty else { throw BundleError.badManifest(problems) }
        guard let key = Data(base64Encoded: publisher.publicKey), let signatureData = Data(base64Encoded: signature) else {
            throw BundleError.badSignature
        }
        guard try Signing.verify(signatureData, of: Self.signedBytes(manifest: manifest, sourceDigest: sourceDigest), publicKey: key) else {
            throw BundleError.badSignature
        }
    }

    public enum BundleError: Error, CustomStringConvertible, Equatable {
        case unsupportedFormat(Int)
        case digestMismatch
        case badSignature
        case badManifest([String])
        case manifestMismatch
        case publisherChanged(pluginID: String, pinned: String, offered: String)
        case signingUnavailable

        public var description: String {
            switch self {
            case .unsupportedFormat(let format): return "bundle format \(format) is newer than this Fluid understands"
            case .digestMismatch: return "the source does not match its digest; the bundle was modified"
            case .badSignature: return "the signature is not valid for this bundle"
            case .badManifest(let problems): return "the manifest has problems: " + problems.joined(separator: "; ")
            case .manifestMismatch: return "the manifest in the bundle doesn't match the one the source declares"
            case .publisherChanged(let id, let pinned, let offered): return "\(id) was published by \(pinned); this update is signed by \(offered) and was refused"
            case .signingUnavailable: return "signing needs macOS (CryptoKit)"
            }
        }
    }
}

/// Ed25519 keys and signatures. CryptoKit on macOS; elsewhere signing is
/// unavailable (bundles still decode and their digests still check).
public enum Signing {
    /// A new private key, raw 32 bytes, and its public key.
    public static func generateKey() throws -> (privateKey: Data, publicKey: Data) {
        #if canImport(CryptoKit)
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation, key.publicKey.rawRepresentation)
        #else
        throw PluginBundle.BundleError.signingUnavailable
        #endif
    }

    public static func publicKey(for privateKey: Data) throws -> Data {
        #if canImport(CryptoKit)
        return try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey).publicKey.rawRepresentation
        #else
        throw PluginBundle.BundleError.signingUnavailable
        #endif
    }

    public static func sign(_ data: Data, privateKey: Data) throws -> Data {
        #if canImport(CryptoKit)
        return try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey).signature(for: data)
        #else
        throw PluginBundle.BundleError.signingUnavailable
        #endif
    }

    public static func verify(_ signature: Data, of data: Data, publicKey: Data) throws -> Bool {
        #if canImport(CryptoKit)
        return try Curve25519.Signing.PublicKey(rawRepresentation: publicKey).isValidSignature(signature, for: data)
        #else
        throw PluginBundle.BundleError.signingUnavailable
        #endif
    }

    /// Signs a plugin's source into a bundle. `manifest` must be the one the
    /// source declares (read it from the built helper).
    public static func bundle(source: String, manifest: Manifest, publisherName: String, privateKey: Data) throws -> PluginBundle {
        let digest = SHA256.hex(Data(source.utf8))
        let signature = try sign(PluginBundle.signedBytes(manifest: manifest, sourceDigest: digest), privateKey: privateKey)
        return PluginBundle(manifest: manifest, source: source, sourceDigest: digest, publisher: .init(name: publisherName, publicKey: try publicKey(for: privateKey).base64EncodedString()), signature: signature.base64EncodedString())
    }
}

/// Trust on first use: the publisher key each plugin id was first installed
/// with. Later bundles for the same id must be signed by the same key.
public final class PublisherStore: @unchecked Sendable {
    public let file: URL
    private let lock = NSLock()
    private var pins: [String: PluginBundle.Publisher]

    public init(file: URL) {
        self.file = file
        self.pins = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: PluginBundle.Publisher].self, from: $0) } ?? [:]
    }

    public func publisher(for pluginID: String) -> PluginBundle.Publisher? {
        lock.withLock { pins[pluginID] }
    }

    /// Accepts the bundle's publisher for its plugin id, pinning it the first
    /// time; throws when the id is pinned to another key.
    public func accept(_ bundle: PluginBundle) throws {
        try lock.withLock {
            if let pinned = pins[bundle.manifest.id] {
                guard pinned.publicKey == bundle.publisher.publicKey else {
                    throw PluginBundle.BundleError.publisherChanged(pluginID: bundle.manifest.id, pinned: pinned.name, offered: bundle.publisher.name)
                }
                return
            }
            pins[bundle.manifest.id] = bundle.publisher
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.ledger.encode(pins).write(to: file, options: .atomic)
        }
    }

    public func forget(_ pluginID: String) throws {
        try lock.withLock {
            pins[pluginID] = nil
            try JSONEncoder.ledger.encode(pins).write(to: file, options: .atomic)
        }
    }
}
