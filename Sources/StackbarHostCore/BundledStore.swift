import Foundation
import StackbarProtocol

/// The plugins that ship with the app, in one place:
///
/// - the first-party plugins, which live in navbytes/stackbar-plugins and
///   install and update through the official store. The app carries their
///   signed bundles (`Resources/StackbarKit/Bundles`, fetched from the store
///   when the app is built) so a new Mac gets them without a network;
/// - the examples (`Examples/`), small teaching plugins copied into the
///   plugins folder as source, so they can be read and changed.
///
/// An example copy is replaced by a newer one only while it is still exactly
/// what Stackbar wrote (`bundled.json` keeps that digest). A copy the user
/// changed is theirs and stays.
public struct BundledStore {
    /// The first-party plugins the app carries, fetched by
    /// `stackbarctl index fetch` when the app is built.
    public static let pluginIDs: Set<String> = [
        "io.navbytes.stackbar.clipboard",
        "io.navbytes.stackbar.pr-cockpit",
        "io.navbytes.stackbar.quicklinks",
        "io.navbytes.stackbar.snippets",
        "io.navbytes.stackbar.stay-awake",
        "io.navbytes.stackbar.up-next",
    ]

    public let bundlesDirectory: URL
    /// The example sources, copied as they are.
    public let examplesDirectory: URL
    public let pluginsDirectory: URL
    /// `bundled.json`: what Stackbar last wrote for each copied example.
    public let record: URL
    public let installer: PluginInstaller
    /// The key bundles must be signed with; nil accepts none.
    public let publicKey: String?

    public init(bundlesDirectory: URL, examplesDirectory: URL, pluginsDirectory: URL, record: URL, installer: PluginInstaller, publicKey: String? = OfficialIndex.publicKey) {
        self.bundlesDirectory = bundlesDirectory
        self.examplesDirectory = examplesDirectory
        self.pluginsDirectory = pluginsDirectory
        self.record = record
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

    /// Installs every carried plugin that isn't installed yet and copies
    /// every example that isn't in the plugins folder. Returns the new files.
    @discardableResult
    public func installMissing() -> [URL] {
        let installed = Set(installer.installed.map(\.id))
        var result: [URL] = []
        for bundle in bundles() where !installed.contains(bundle.manifest.id) {
            if let file = try? installer.install(bundle) { result.append(file) }
        }
        return result + syncExamples(installMissing: true).installed
    }

    /// What `syncExamples` did, by file.
    public struct ExampleSync: Equatable, Sendable {
        public var installed: [URL] = []
        public var updated: [URL] = []
        public var kept: [URL] = []
    }

    /// Brings example copies up to date. At launch `installMissing` is false,
    /// so an example the user deleted stays deleted.
    @discardableResult
    public func syncExamples(installMissing: Bool = false) -> ExampleSync {
        let manager = FileManager.default
        var written = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: record))) ?? [:]
        var result = ExampleSync()
        try? manager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        for source in exampleSources() {
            guard let fresh = try? Data(contentsOf: source) else { continue }
            let name = source.lastPathComponent
            let destination = pluginsDirectory.appendingPathComponent(name)
            let digest = SHA256.hex(fresh)
            guard let current = try? Data(contentsOf: destination) else {
                if installMissing, (try? fresh.write(to: destination, options: .atomic)) != nil {
                    written[name] = digest
                    result.installed.append(destination)
                }
                continue
            }
            let currentDigest = SHA256.hex(current)
            if currentDigest == digest {
                written[name] = digest
            } else if written[name] == currentDigest, (try? fresh.write(to: destination, options: .atomic)) != nil {
                written[name] = digest
                result.updated.append(destination)
            } else {
                result.kept.append(destination)
            }
        }
        if let data = try? JSONEncoder().encode(written) {
            try? data.write(to: record, options: .atomic)
        }
        return result
    }

    private func exampleSources() -> [URL] {
        let files = FileManager.default.enumerator(at: examplesDirectory, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
