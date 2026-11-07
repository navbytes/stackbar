import Foundation
import StackbarProtocol
@testable import StackbarHostCore
import XCTest

/// Removing a plugin is the same from every path: Settings, the Store
/// window, a withdrawal and stackbarctl all go through `PluginInstallation`.
final class PluginInstallationTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let id = "dev.t.removed"
    private let provider = OAuthProvider(name: "gh", authorizeURL: "https://example.com/a", tokenURL: "https://example.com/t", clientID: "c")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Plugins"), withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private struct World {
        var installation: PluginInstallation
        var file: URL
        var storage: StorageStore
        var secrets: MemorySecretStore
        var trashed: Trash
    }

    final class Trash: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        var all: [URL] { lock.withLock { urls } }
        func add(_ url: URL) {
            lock.withLock { urls.append(url) }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// An installed, approved plugin that was turned off, with saved data
    /// and a sign-in.
    private func world() async throws -> World {
        let file = directory.appendingPathComponent("Plugins/\(id).swift")
        try "// plugin".write(to: file, atomically: true, encoding: .utf8)
        let record = #"[{"id":"\#(id)","file":"\#(file.path)","version":"1.0.0","publisher":"Pub","installedAt":"2026-11-07T00:00:00Z"}]"#
        try Data(record.utf8).write(to: directory.appendingPathComponent("installed.json"))
        let installer = PluginInstaller(pluginsDirectory: directory.appendingPathComponent("Plugins"), publishers: PublisherStore(file: directory.appendingPathComponent("p.json")), recordFile: directory.appendingPathComponent("installed.json"))
        let ledger = CapabilityLedger(file: directory.appendingPathComponent("ledger.json"))
        try ledger.approve(Manifest(id: id, name: "Removed", capabilities: [.oauth(provider), .clipboard]))
        let switches = PluginSwitches(defaults: defaults)
        switches.adopt(id, for: file)
        switches.set(id, on: false)
        let storage = StorageStore(directory: directory.appendingPathComponent("Storage"))
        try await storage.set("k", "v", for: id)
        let secrets = MemorySecretStore(["oauth/\(id)/gh": "token", "SHARED": "s"])
        let trash = Trash()
        let installation = PluginInstallation(installer: installer, ledger: ledger, switches: switches, storage: storage, secrets: secrets, trash: { trash.add($0) })
        return World(installation: installation, file: file, storage: storage, secrets: secrets, trashed: trash)
    }

    func testUninstallForgetsEverythingButData() async throws {
        let world = try await world()
        await world.installation.uninstall(id)
        XCTAssertEqual(world.trashed.all.map(\.path), [world.file.standardizedFileURL.path])
        XCTAssertEqual(world.installation.installed, [], "the store offers it again")
        XCTAssertNil(world.installation.ledger.approval(for: id), "installing it again asks again")
        XCTAssertTrue(world.installation.switches.isOn(id))
        XCTAssertNil(world.installation.switches.knownID(for: world.file))
        let saved = await world.storage.snapshot(for: id)
        XCTAssertEqual(saved, ["k": "v"], "data stays unless asked")
        XCTAssertEqual(world.secrets.secret("oauth/\(id)/gh"), "token")
    }

    func testUninstallWithDataDeletesItsSignInsFromTheLedgerToo() async throws {
        let world = try await world()
        // Not loaded, so no manifest: the sign-ins come from what it was approved for.
        await world.installation.uninstall(id, deleteData: true)
        let saved = await world.storage.snapshot(for: id)
        XCTAssertEqual(saved, [:])
        XCTAssertNil(world.secrets.secret("oauth/\(id)/gh"))
        XCTAssertEqual(world.secrets.secret("SHARED"), "s", "named secrets are shared and stay")
    }

    func testWithdrawalRemovesLikeAnUninstall() async throws {
        let world = try await world()
        let record = try XCTUnwrap(world.installation.installed.first)
        await world.installation.withdraw(record)
        XCTAssertEqual(world.installation.installed, [])
        XCTAssertNil(world.installation.ledger.approval(for: id), "a withdrawn plugin's approvals go")
        XCTAssertTrue(world.installation.switches.isOn(id))
        let saved = await world.storage.snapshot(for: id)
        XCTAssertEqual(saved, ["k": "v"])
    }

    func testFilesIncludeLoadedCopiesOnce() async throws {
        let world = try await world()
        let copy = directory.appendingPathComponent("Dev/\(id).swift")
        let files = world.installation.files(of: id, loaded: [world.file, copy])
        XCTAssertEqual(files.map(\.path), [world.file.standardizedFileURL.path, copy.standardizedFileURL.path])
    }

    func testConfirmPassesAPluginThatWasNotJustInstalled() async throws {
        let world = try await world()
        XCTAssertNoThrow(try world.installation.confirm(Manifest(id: "dev.other", name: "Other"), file: world.file))
        XCTAssertEqual(world.installation.installed.map(\.id), [id])
    }

    #if canImport(CryptoKit)
    func testConfirmUndoesAnInstallWhoseBuildDiffersFromTheSignedManifest() throws {
        let installer = PluginInstaller(pluginsDirectory: directory.appendingPathComponent("Plugins"), publishers: PublisherStore(file: directory.appendingPathComponent("p.json")), recordFile: directory.appendingPathComponent("i.json"))
        let installation = PluginInstallation(installer: installer, ledger: CapabilityLedger(file: directory.appendingPathComponent("l.json")), switches: PluginSwitches(defaults: defaults))
        let key = try Signing.generateKey()
        let manifest = Manifest(id: "dev.t.bundle", name: "Bundle")
        let bundle = try Signing.bundle(source: "// plugin", manifest: manifest, publisherName: "Pub", privateKey: key.privateKey)

        let file = try installation.install(bundle)
        XCTAssertTrue(installation.isAwaitingConfirmation(file))
        XCTAssertNoThrow(try installation.confirm(manifest, file: file))
        XCTAssertFalse(installation.isAwaitingConfirmation(file), "checked once")

        let renamed = try installation.install(bundle)
        XCTAssertNoThrow(try installation.confirm(Manifest(id: "dev.t.bundle", name: "Renamed"), file: renamed), "only the id and capabilities count")

        let again = try installation.install(bundle)
        XCTAssertThrowsError(try installation.confirm(Manifest(id: "dev.t.bundle", name: "Bundle", capabilities: [.clipboard]), file: again))
        XCTAssertEqual(installer.installed, [], "a manifest mismatch undoes the install")
    }
    #endif
}
