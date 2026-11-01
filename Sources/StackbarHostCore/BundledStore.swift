import Foundation
import StackbarProtocol

/// The first-party plugins, which live in navbytes/stackbar-plugins and
/// install and update through the official store. The app carries their
/// signed bundles (`Resources/StackbarKit/Bundles`, fetched from the store when
/// the app is built) so a new Mac gets them without a network.
///
/// Before the move they shipped as source in `Plugins/` and were copied into
/// the plugins folder by name. `migrate` turns an untouched copy into a store
/// install of the same plugin id, so its settings, storage and approvals
/// (all keyed by id) carry over and it starts receiving store updates.
public struct BundledStore {
    /// The file names the plugins had in `Plugins/`, by plugin id.
    public static let legacyFiles: [String: String] = [
        "Clipboard.swift": "io.navbytes.stackbar.clipboard",
        "PRCockpit.swift": "io.navbytes.stackbar.pr-cockpit",
        "StayAwake.swift": "io.navbytes.stackbar.stay-awake",
        "UpNext.swift": "io.navbytes.stackbar.up-next",
        "Quicklinks.swift": "io.navbytes.stackbar.quicklinks",
        "Snippets.swift": "io.navbytes.stackbar.snippets",
    ]

    /// The first-party plugins the app carries.
    public static var pluginIDs: Set<String> { Set(legacyFiles.values) }

    public struct Migration: Equatable, Sendable {
        public var old: URL
        public var new: URL
    }

    public let bundlesDirectory: URL
    public let pluginsDirectory: URL
    /// `bundled.json`: what Stackbar last wrote for each copied file.
    public let bundledRecord: URL
    public let installer: PluginInstaller
    /// The key bundles must be signed with; nil accepts none.
    public let publicKey: String?

    public init(bundlesDirectory: URL, pluginsDirectory: URL, bundledRecord: URL, installer: PluginInstaller, publicKey: String? = OfficialIndex.publicKey) {
        self.bundlesDirectory = bundlesDirectory
        self.pluginsDirectory = pluginsDirectory
        self.bundledRecord = bundledRecord
        self.installer = installer
        self.publicKey = publicKey
    }

    /// The carried bundles that verify and are signed by the official key,
    /// newest version per plugin id.
    public func bundles() -> [PluginBundle] {
        guard let publicKey else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: bundlesDirectory, includingPropertiesForKeys: nil)) ?? []
        var newest: [String: PluginBundle] = [:]
        for file in files where file.pathExtension == PluginBundle.fileExtension {
            guard let data = try? Data(contentsOf: file), let bundle = try? PluginBundle.decode(data),
                  bundle.publisher.publicKey == publicKey, (try? bundle.verify()) != nil else { continue }
            if let current = newest[bundle.manifest.id],
               let have = VersionNumber(current.manifest.version), let offered = VersionNumber(bundle.manifest.version), !(have < offered) { continue }
            newest[bundle.manifest.id] = bundle
        }
        return newest.values.sorted { $0.manifest.id < $1.manifest.id }
    }

    /// Installs every carried plugin that isn't installed yet and has no
    /// copy in the plugins folder. Returns the new files.
    @discardableResult
    public func installMissing() -> [URL] {
        let installed = Set(installer.installed.map(\.id))
        let legacyPresent = Set(Self.legacyFiles.filter { FileManager.default.fileExists(atPath: pluginsDirectory.appendingPathComponent($0.key).path) }.map(\.value))
        var result: [URL] = []
        for bundle in bundles() where !installed.contains(bundle.manifest.id) && !legacyPresent.contains(bundle.manifest.id) {
            if let file = try? installer.install(bundle) { result.append(file) }
        }
        return result
    }

    /// Replaces each untouched legacy copy (unchanged since Stackbar wrote
    /// it, or copied without a record by an older install script) with a
    /// store install of the same plugin. A copy the user edited is left
    /// alone: it is theirs now. The old file goes to `<name>.swift.bak` when
    /// there was no record to prove it untouched.
    @discardableResult
    public func migrate() -> [Migration] {
        let manager = FileManager.default
        var record = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: bundledRecord))) ?? [:]
        let available = Dictionary(uniqueKeysWithValues: bundles().map { ($0.manifest.id, $0) })
        let installed = Set(installer.installed.map(\.id))
        var result: [Migration] = []
        for (name, id) in Self.legacyFiles.sorted(by: { $0.key < $1.key }) {
            let old = pluginsDirectory.appendingPathComponent(name)
            guard let current = try? Data(contentsOf: old), let bundle = available[id], !installed.contains(id) else { continue }
            let recorded = record[name]
            if let recorded, recorded != SHA256.hex(current) { continue }
            guard let new = try? installer.install(bundle) else { continue }
            if new.standardizedFileURL != old.standardizedFileURL {
                if recorded == nil { try? current.write(to: old.appendingPathExtension("bak"), options: .atomic) }
                try? manager.removeItem(at: old)
            }
            record[name] = nil
            result.append(Migration(old: old, new: new))
        }
        if let data = try? JSONEncoder().encode(record) { try? data.write(to: bundledRecord, options: .atomic) }
        return result
    }
}
