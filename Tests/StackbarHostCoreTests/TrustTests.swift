import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class CapabilityLedgerTests: XCTestCase {
    func testNewChangedAndRemovedCapabilities() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let ledger = CapabilityLedger(file: file)
        let plain = Manifest(id: "dev.t.plain", name: "Plain")
        XCTAssertEqual(ledger.review(plain), .approved(granted: []), "a plugin that asks for nothing needs no approval")

        let v1 = Manifest(id: "dev.t.p", name: "P", version: "1", capabilities: [.network("api.example.com")])
        XCTAssertEqual(ledger.review(v1), .needsApproval(added: [.network("api.example.com")], removed: [], granted: [], isNew: true))
        try ledger.approve(v1)
        XCTAssertEqual(ledger.review(v1), .approved(granted: [.network("api.example.com")]))

        let v2 = Manifest(id: "dev.t.p", name: "P", version: "2", capabilities: [.network("api.example.com"), .secret(name: "TOKEN")])
        XCTAssertEqual(ledger.review(v2), .needsApproval(added: [.secret(name: "TOKEN")], removed: [], granted: [.network("api.example.com")], isNew: false), "until approved, the update runs with what was approved before")

        let reopened = CapabilityLedger(file: file)
        let v3 = Manifest(id: "dev.t.p", name: "P", version: "3", capabilities: [])
        XCTAssertEqual(reopened.review(v3), .approved(granted: []), "dropping capabilities needs no approval")
        XCTAssertEqual(reopened.approval(for: "dev.t.p")?.version, "1")
    }

    func testAnUnapprovedCapabilityIsRefusedByTheHost() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore(["FIXTURE_SECRET": "s"]))
        let executable = PluginSupervisorTests.helper("FixturePlugin")
        let manifest = try PluginProcess.readManifest(executable: executable)
        let supervisor = PluginSupervisor(executable: executable, manifest: manifest, grantedCapabilities: [], services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        await supervisor.event("button/Secret")
        let refused = await waitUntil(10) {
            let settled = await supervisor.settledCount
            let panel = await supervisor.views[.panel].map { TreeTextRenderer.render($0) } ?? ""
            return settled >= 3 && panel.contains("status idle")
        }
        XCTAssertTrue(refused, "the secret read fails, so the status never changes")
        await supervisor.grant(manifest.capabilities)
        await supervisor.event("button/Secret")
        let granted = await waitUntil(10) { await supervisor.views[.panel].map { TreeTextRenderer.render($0) }?.contains("status secret s") == true }
        XCTAssertTrue(granted)
        await supervisor.stop()
    }

    func testDeclaredButUnapprovedSaysWaitingForApproval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore(["TOKEN": "t"]))
        let declared = Manifest(id: "dev.test.waiting", name: "Waiting", capabilities: [.power, .secret(name: "TOKEN"), .network("example.com")])
        var granted = declared
        granted.capabilities = []

        func message(_ call: HostCall, declared: Manifest?) async -> String {
            if case .failure(let text) = await services.handle(call, for: granted, declared: declared) { return text }
            return "not refused"
        }
        for call: HostCall in [.systemStatus, .secret(name: "TOKEN"), .http(HTTPRequest(url: "https://example.com/x"))] {
            let waiting = await message(call, declared: declared)
            XCTAssertTrue(waiting.contains("needs your approval"), waiting)
            let undeclared = await message(call, declared: nil)
            XCTAssertTrue(undeclared.contains("manifest's capabilities"), undeclared)
        }
    }
}

final class ForkTests: XCTestCase {
    func testForkRenamesTheManifestOnly() {
        let source = """
        static let manifest = Manifest(
            id: "io.navbytes.stackbar.example.todo",
            name: "To-do",
        )
        struct Item { var id: String; var name: String }
        let other = Thing(id: "keep", name: "keep")
        """
        let forked = PluginFork.fork(source, name: "My \"List\"", id: "dev.local.mylist")
        XCTAssertTrue(forked.contains(#"id: "dev.local.mylist""#))
        XCTAssertTrue(forked.contains(#"name: "My 'List'""#))
        XCTAssertTrue(forked.contains(#"Thing(id: "keep", name: "keep")"#), "only the first id and name change")
    }

    func testClaudeScriptQuotesPaths() {
        let script = PluginFork.claudeScript(for: URL(fileURLWithPath: "/Users/x/It's here/Todo.swift"), stackbarctl: "/Applications/Stackbar.app/Contents/MacOS/stackbarctl")
        XCTAssertTrue(script.contains(#"cd '/Users/x/It'\''s here'"#))
        XCTAssertTrue(script.contains("claude mcp add stackbar -- '/Applications/Stackbar.app/Contents/MacOS/stackbarctl' mcp"))
    }
}

final class BundleTests: XCTestCase {
    let manifest = Manifest(id: "dev.t.bundle", name: "Bundle", version: "1.0.0", capabilities: [.network("api.example.com")])

    func fakeBundle(source: String = "print(1)", key: String = "AAAA") -> PluginBundle {
        PluginBundle(manifest: manifest, source: source, sourceDigest: SHA256.hex(Data(source.utf8)), publisher: .init(name: "Pub", publicKey: key), signature: "AAAA")
    }

    func testTamperedSourceIsCaughtBeforeTheSignature() {
        var bundle = fakeBundle()
        bundle.source = "print(2)"
        XCTAssertThrowsError(try bundle.verify()) { XCTAssertEqual($0 as? PluginBundle.BundleError, .digestMismatch) }
    }

    func testPublisherIsPinnedOnFirstUse() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = PublisherStore(file: file)
        try store.accept(fakeBundle(key: "KEY1"))
        try store.accept(fakeBundle(key: "KEY1"))
        XCTAssertThrowsError(try PublisherStore(file: file).accept(fakeBundle(key: "KEY2"))) { error in
            guard case .publisherChanged = error as? PluginBundle.BundleError else { return XCTFail("\(error)") }
        }
    }

    func testIndexBuildSearchAndDigestCheck() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleFile = directory.appendingPathComponent("b.stackbarplugin")
        try fakeBundle().encoded().write(to: bundleFile)
        let index = try PluginIndex.build(name: "Test", bundles: [bundleFile])
        XCTAssertEqual(index.plugins.map(\.id), ["dev.t.bundle"])
        XCTAssertEqual(index.plugins.first?.capabilities, ["Connects to api.example.com"])
        XCTAssertEqual(index.search("bund").count, 1)
        XCTAssertEqual(index.search("nothing").count, 0)

        let indexFile = directory.appendingPathComponent("index.json")
        try JSONEncoder().encode(index).write(to: indexFile)
        let fetched = try await PluginIndex.fetch(indexFile)
        let bundle = try await PluginIndex.bundle(for: fetched.plugins[0], indexURL: indexFile)
        XCTAssertEqual(bundle.manifest, manifest)

        var tampered = fetched.plugins[0]
        tampered.sha256 = String(repeating: "0", count: 64)
        do {
            _ = try await PluginIndex.bundle(for: tampered, indexURL: indexFile)
            XCTFail("a digest mismatch must be refused")
        } catch {
            XCTAssertEqual(error as? PluginIndex.IndexError, .digestMismatch("dev.t.bundle"))
        }
    }

    #if canImport(CryptoKit)
    func testSignVerifyAndInstall() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = try Signing.generateKey()
        let bundle = try Signing.bundle(source: "// plugin", manifest: manifest, publisherName: "Pub", privateKey: key.privateKey)
        XCTAssertNoThrow(try bundle.verify())
        var forged = bundle
        forged.manifest.capabilities.append(.secret(name: "EXTRA"))
        XCTAssertThrowsError(try forged.verify(), "changing the manifest breaks the signature")

        let installer = PluginInstaller(pluginsDirectory: directory.appendingPathComponent("Plugins"), publishers: PublisherStore(file: directory.appendingPathComponent("p.json")), recordFile: directory.appendingPathComponent("i.json"))
        let file = try installer.install(bundle)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "// plugin")
        XCTAssertEqual(installer.installed.map(\.id), ["dev.t.bundle"])
        let other = try Signing.generateKey()
        let impostor = try Signing.bundle(source: "// evil", manifest: manifest, publisherName: "Evil", privateKey: other.privateKey)
        XCTAssertThrowsError(try installer.install(impostor))
        XCTAssertThrowsError(try installer.confirm(Manifest(id: "dev.t.bundle", name: "Other"), matches: bundle, file: file))
        XCTAssertEqual(installer.installed, [], "a manifest mismatch undoes the install")
    }
    #endif
}
