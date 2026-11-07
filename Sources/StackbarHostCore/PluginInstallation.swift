import Foundation
import StackbarProtocol

/// Everything that installing or removing a plugin touches, in one place:
/// the plugins folder and its install record, the store's prebuilt helper,
/// the approvals in the ledger, the on/off switches, and the plugin's saved
/// data and sign-ins. The app, the Store window and `stackbarctl` all go
/// through it, so a plugin removed from any of them is removed the same way.
///
/// The app adds only what is live: stopping the plugin's process, reloading
/// it after an update, and the toast.
public final class PluginInstallation: @unchecked Sendable {
    /// Where prebuilt helpers go, and the StackbarKit they are named for.
    public struct Helpers: Sendable {
        public var directory: URL
        public var stackbarKit: String

        public init(directory: URL, stackbarKit: String) {
            self.directory = directory
            self.stackbarKit = stackbarKit
        }
    }

    public let installer: PluginInstaller
    public let ledger: CapabilityLedger
    public let switches: PluginSwitches
    private let storage: StorageStore?
    private let secrets: (any SecretStore)?
    private let helpers: Helpers?
    private let trash: @Sendable (URL) -> Void
    private let lock = NSLock()
    /// Signed manifests of bundles just installed, by file, until the built
    /// plugin is checked against them.
    private var expected: [String: Manifest] = [:]

    /// - `trash` moves a removed plugin's file away (the app uses the Trash;
    ///   the default deletes it).
    public init(installer: PluginInstaller, ledger: CapabilityLedger, switches: PluginSwitches, storage: StorageStore? = nil,
                secrets: (any SecretStore)? = nil, helpers: Helpers? = nil,
                trash: @escaping @Sendable (URL) -> Void = { try? FileManager.default.removeItem(at: $0) }) {
        self.installer = installer
        self.ledger = ledger
        self.switches = switches
        self.storage = storage
        self.secrets = secrets
        self.helpers = helpers
        self.trash = trash
    }

    public var installed: [PluginInstaller.Installed] { installer.installed }

    // MARK: - Installing

    /// Verifies and writes a store bundle (a first install or an update) and
    /// saves its prebuilt helper. Returns the plugin file. The plugin is
    /// then built, and `confirm` checks that what was built is what was
    /// signed.
    @discardableResult
    public func install(_ bundle: PluginBundle, helper: PrebuiltHelpers.Download? = nil) throws -> URL {
        let file = try installer.install(bundle)
        if let helper, let helpers {
            try PrebuiltHelpers.save(helper, in: helpers.directory, stackbarKit: helpers.stackbarKit)
        }
        lock.withLock { expected[Self.key(file)] = bundle.manifest }
        return file
    }

    /// The built plugin in `file` declared `built`. For a plugin just
    /// installed from a bundle it must have the signed manifest's id and ask
    /// for exactly its capabilities, or the install is undone and this
    /// throws. Any other plugin passes.
    ///
    /// Only what trust rests on is compared: a helper built against a newer
    /// StackbarKit can spell other manifest fields differently, and that
    /// must not uninstall a plugin that runs.
    public func confirm(_ built: Manifest, file: URL) throws {
        guard let signed = lock.withLock({ expected.removeValue(forKey: Self.key(file)) }) else { return }
        let sameCapabilities = built.capabilities.allSatisfy(signed.capabilities.contains) && signed.capabilities.allSatisfy(built.capabilities.contains)
        guard built.id == signed.id, sameCapabilities else {
            try? installer.uninstall(signed.id)
            throw PluginBundle.BundleError.manifestMismatch
        }
    }

    /// Whether `file` was just installed and its build not yet checked.
    public func isAwaitingConfirmation(_ file: URL) -> Bool {
        lock.withLock { expected[Self.key(file)] != nil }
    }

    // MARK: - Removing

    /// Every file a plugin is known by: the install record's, and `loaded`
    /// (the files it is running from).
    public func files(of pluginID: String, loaded: [URL] = []) -> [URL] {
        var files = loaded.map(\.standardizedFileURL)
        files += installer.installed.filter { $0.id == pluginID }.map { URL(fileURLWithPath: $0.file).standardizedFileURL }
        var seen = Set<String>()
        return files.filter { seen.insert($0.path).inserted }
    }

    /// Removes a plugin: its files go, the store forgets installing it (so
    /// it is offered again and the update check doesn't bring it back), its
    /// approvals are revoked (installing it again asks again), and its
    /// switch is reset. With `deleteData` its saved data and sign-ins go
    /// too; named secrets are shared between plugins and always stay.
    ///
    /// `providers` are the sign-ins its manifest declares, when it is
    /// loaded; the ones it was approved for are added from the ledger.
    public func uninstall(_ pluginID: String, loaded: [URL] = [], deleteData: Bool = false, providers: [OAuthProvider] = []) async {
        let files = files(of: pluginID, loaded: loaded)
        let approved = ledger.approval(for: pluginID)?.capabilities.compactMap { capability -> OAuthProvider? in
            if case .oauth(let provider) = capability { return provider }
            return nil
        } ?? []
        for file in files where FileManager.default.fileExists(atPath: file.path) { trash(file) }
        lock.withLock { for file in files { expected[Self.key(file)] = nil } }
        try? installer.forget(pluginID)
        try? ledger.revoke(pluginID)
        switches.set(pluginID, on: true)
        for file in files { switches.forget(file: file) }
        guard deleteData else { return }
        await storage?.erase(pluginID)
        if let secrets {
            var all = providers
            for provider in approved where !all.contains(provider) { all.append(provider) }
            let kept = OAuthBroker.forgetTokens(of: pluginID, providers: all, in: secrets)
            if !kept.isEmpty {
                HostLog.shared.write(.warning, "could not remove the saved sign-in for \(kept.joined(separator: ", ")); the Keychain refused", plugin: pluginID)
            }
        }
    }

    /// Removes a plugin its publisher withdrew from the store. Its data
    /// stays, as for an uninstall without deleting data.
    public func withdraw(_ plugin: PluginInstaller.Installed, loaded: [URL] = []) async {
        await uninstall(plugin.id, loaded: loaded)
    }

    private static func key(_ file: URL) -> String { file.standardizedFileURL.path }
}
