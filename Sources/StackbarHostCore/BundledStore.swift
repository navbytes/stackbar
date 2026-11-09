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
    public static let pluginIDs: Set<String> = Set([
        "io.navbytes.stackbar.clipboard",
        "io.navbytes.stackbar.pr-cockpit",
        "io.navbytes.stackbar.quicklinks",
        "io.navbytes.stackbar.snippets",
        "io.navbytes.stackbar.stay-awake",
        "io.navbytes.stackbar.up-next",
        "io.navbytes.stackbar.plugins.system-commands",
    ]).union(corePluginIDs)

    /// One-click picks in the welcome window, for who you are. Each adds
    /// to `starterPluginIDs`; a plugin the app doesn't carry is skipped.
    public struct StarterSet: Equatable, Sendable, Identifiable {
        public var name: String
        public var summary: String
        public var pluginIDs: Set<String>
        public var id: String { name }
    }

    public static let starterSets: [StarterSet] = [
        StarterSet(name: "Launcher", summary: "Clipboard history, quicklinks, snippets and system commands",
                   pluginIDs: starterPluginIDs.union(["io.navbytes.stackbar.plugins.emoji"])),
        StarterSet(name: "Developer", summary: "Pull requests, Docker, ports, processes, recent projects and scripts",
                   pluginIDs: starterPluginIDs.union([
                       "io.navbytes.stackbar.pr-cockpit", "io.navbytes.stackbar.plugins.docker", "io.navbytes.stackbar.plugins.ports",
                       "io.navbytes.stackbar.plugins.kill-process", "io.navbytes.stackbar.plugins.recent-projects",
                       "io.navbytes.stackbar.plugins.script-commands", "io.navbytes.stackbar.plugins.git-sync",
                   ])),
        StarterSet(name: "Windows & Keys", summary: "Snap windows, save layouts, switch apps and windows from the keyboard",
                   pluginIDs: starterPluginIDs.union([
                       "io.navbytes.stackbar.plugins.workspaces", "io.navbytes.stackbar.plugins.app-switcher",
                       "io.navbytes.stackbar.plugins.window-switcher", "io.navbytes.stackbar.plugins.menu-search",
                   ])),
    ]

    /// What the welcome window offers switched on: the commands a launcher
    /// user reaches for in the first week.
    public static let starterPluginIDs: Set<String> = [
        "io.navbytes.stackbar.clipboard",
        "io.navbytes.stackbar.quicklinks",
        "io.navbytes.stackbar.snippets",
        "io.navbytes.stackbar.plugins.system-commands",
    ]

    /// The palette's own results (apps, sums, files) come from these
    /// plugins, so every Mac gets them once, new or upgraded. One the user
    /// removes stays removed.
    public static let corePluginIDs: Set<String> = [
        "io.navbytes.stackbar.plugins.applications",
        "io.navbytes.stackbar.plugins.calculator",
        "io.navbytes.stackbar.plugins.file-search",
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
    private let carried = CarriedBundles()

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
        // Reading and checking every carried bundle is the expensive part, and
        // they only change when the folder does (a new app version, a test).
        let signature = files.sorted { $0.path < $1.path }.map { file -> String in
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            return "\(file.lastPathComponent)|\((attributes?[.size] as? NSNumber)?.intValue ?? -1)|\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "\n") + "\n" + publicKey
        if let cached = carried.value(for: signature) { return cached }
        var newest: [String: PluginBundle] = [:]
        for file in files where file.pathExtension == PluginBundle.fileExtension {
            guard let data = try? Data(contentsOf: file), let bundle = try? PluginBundle.decode(data),
                  bundle.publisher.publicKey == publicKey, (try? bundle.verify()) != nil else { continue }
            if let current = newest[bundle.manifest.id],
               let have = VersionNumber(current.manifest.version), let offered = VersionNumber(bundle.manifest.version), !(have < offered) { continue }
            newest[bundle.manifest.id] = bundle
        }
        let result = newest.values.sorted { $0.manifest.id < $1.manifest.id }
        carried.store(result, for: signature)
        return result
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

    /// Installs the carried plugins with these ids that aren't installed yet
    /// (the welcome window's picks). Returns the new files.
    @discardableResult
    public func install(ids: Set<String>) -> [URL] {
        let installed = Set(installer.installed.map(\.id))
        return bundles().filter { ids.contains($0.manifest.id) && !installed.contains($0.manifest.id) }.compactMap { try? installer.install($0) }
    }

    /// The carried plugins a new user can pick from: everything but the core
    /// ones, which every Mac gets anyway.
    public func starters() -> [Manifest] {
        bundles().map(\.manifest).filter { !Self.corePluginIDs.contains($0.id) }.sorted { $0.name < $1.name }
    }

    /// Installs each carried core plugin that was never offered here, and
    /// notes it in `offered` so a removed one is not put back. Returns the
    /// new files.
    ///
    /// A core plugin is first-party and part of the app, like its palette:
    /// with a `ledger`, what it asks for is approved as it is installed, so
    /// apps, sums and files answer on the first search instead of waiting
    /// on an approval the user would have to find in Settings. Its page in
    /// Settings still lists what it can do and can take it back.
    @discardableResult
    public func installCore(offered: URL, approvingIn ledger: CapabilityLedger? = nil) -> [URL] {
        var done = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: offered))) ?? [])
        // Every launch after the first: nothing to offer, so don't decode
        // and verify every carried bundle to find that out.
        guard !Self.corePluginIDs.isSubset(of: done) else { return [] }
        let installed = Set(installer.installed.map(\.id))
        var result: [URL] = []
        for bundle in bundles() where Self.corePluginIDs.contains(bundle.manifest.id) && !done.contains(bundle.manifest.id) {
            if installed.contains(bundle.manifest.id) {
                done.insert(bundle.manifest.id)
            } else if let file = try? installer.install(bundle) {
                done.insert(bundle.manifest.id)
                result.append(file)
                if let ledger, ledger.approval(for: bundle.manifest.id) == nil {
                    try? ledger.approve(bundle.manifest)
                }
            }
        }
        if let data = try? JSONEncoder().encode(done.sorted()) {
            try? data.write(to: offered, options: .atomic)
        }
        return result
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

/// The verified bundles `BundledStore.bundles()` last found, and the folder
/// listing they came from.
private final class CarriedBundles: @unchecked Sendable {
    private let lock = NSLock()
    private var signature: String?
    private var bundles: [PluginBundle] = []

    func value(for signature: String) -> [PluginBundle]? {
        lock.withLock { self.signature == signature ? bundles : nil }
    }

    func store(_ bundles: [PluginBundle], for signature: String) {
        lock.withLock {
            self.signature = signature
            self.bundles = bundles
        }
    }
}
