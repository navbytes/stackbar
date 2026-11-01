import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class VersionNumberTests: XCTestCase {
    func testOrdersPartByPart() throws {
        let v = { (text: String) in VersionNumber(text)! }
        XCTAssertLessThan(v("0.9.3"), v("0.10.0"))
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertEqual(Set([v("1.2"), v("1.2.0")]).count, 1)
        XCTAssertLessThan(v("1.0.0-beta.1"), v("1.0.0"))
        XCTAssertEqual(v("v2.0.1").description, "2.0.1")
        for bad in ["", "1..2", "a.b", "1.2.3.4.5", "1.0-", "-1.0"] { XCTAssertNil(VersionNumber(bad), bad) }
    }

    func testManifestStoreFieldsAreOptionalAndChecked() throws {
        let old = #"{"id":"dev.t.a","name":"A","version":"1","surfaces":["panel"],"triggers":[],"capabilities":[]}"#
        let decoded = try JSONDecoder().decode(Manifest.self, from: Data(old.utf8))
        XCTAssertNil(decoded.minimumStackbar)
        let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(encoded.contains("minimumStackbar"), "an unset field stays out, so existing signatures still verify")

        var manifest = Manifest(id: "dev.t.a", name: "A", minimumStackbar: "0.10.0", homepage: "https://example.com")
        XCTAssertEqual(manifest.problems, [])
        manifest.minimumStackbar = "soon"
        manifest.homepage = "http://example.com"
        XCTAssertEqual(manifest.problems.count, 2)
    }
}

final class PluginStoreTests: XCTestCase {
    func bundle(id: String, version: String, minimum: String? = nil, publisher: String = "navbytes") -> PluginBundle {
        let source = "// \(id) \(version)"
        let manifest = Manifest(id: id, name: id.split(separator: ".").last.map(String.init) ?? id, version: version, summary: "s", minimumStackbar: minimum)
        return PluginBundle(manifest: manifest, source: source, sourceDigest: SHA256.hex(Data(source.utf8)), publisher: .init(name: publisher, publicKey: "AAAA"), signature: "AAAA")
    }

    func entry(_ id: String, _ version: String, minimum: String? = nil, publisher: String = "navbytes") -> PluginIndex.Entry {
        PluginIndex.Entry(id: id, name: id, version: version, publisher: publisher, bundle: "\(id).stackbarplugin", sha256: "0", capabilities: [], minimumStackbar: minimum)
    }

    func record(_ id: String, _ version: String, publisher: String = "navbytes") -> PluginInstaller.Installed {
        PluginInstaller.Installed(id: id, file: "/tmp/\(id).swift", version: version, publisher: publisher, installedAt: Date())
    }

    func testBuildFromFoldersTakesCategoryAndScreenshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appendingPathComponent("System", isDirectory: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        try bundle(id: "dev.t.vitals", version: "1.0.0", minimum: "0.10.0").encoded().write(to: system.appendingPathComponent("vitals-1.0.0.stackbarplugin"))
        try bundle(id: "dev.t.vitals", version: "1.1.0").encoded().write(to: system.appendingPathComponent("vitals-1.1.0.stackbarplugin"))
        try Data([0x89]).write(to: system.appendingPathComponent("dev.t.vitals.png"))
        try bundle(id: "dev.t.loose", version: "0.1.0").encoded().write(to: root.appendingPathComponent("loose.stackbarplugin"))

        let index = try PluginIndex.build(name: "Test", root: root, homepage: "https://example.com", revoked: [])
        XCTAssertEqual(index.format, 2)
        XCTAssertNil(index.revoked, "an empty revocation list is left out")
        XCTAssertEqual(index.plugins.map { "\($0.id) \($0.version)" }, ["dev.t.loose 0.1.0", "dev.t.vitals 1.0.0", "dev.t.vitals 1.1.0"])
        let vitals = index.plugins[1]
        XCTAssertEqual(vitals.category, "System")
        XCTAssertEqual(vitals.bundle, "System/vitals-1.0.0.stackbarplugin")
        XCTAssertEqual(vitals.screenshot, "System/dev.t.vitals.png")
        XCTAssertEqual(vitals.minimumStackbar, "0.10.0")
        XCTAssertEqual(vitals.surfaces, ["menuBar", "panel"])
        XCTAssertNil(index.plugins[0].category)
        XCTAssertEqual(index.byCategory(index.plugins).map(\.category), ["System", "Other"])

        // A relative bundle path resolves against the index and passes the digest check.
        let indexFile = root.appendingPathComponent("index.json")
        try index.encoded().write(to: indexFile)
        let fetched = try awaitResult { try await PluginIndex.fetch(indexFile) }
        XCTAssertEqual(fetched, index)
    }

    func testRevokedAndTooNewEntriesAreNotInstallable() throws {
        let index = PluginIndex(name: "T", plugins: [entry("dev.t.a", "1.0.0"), entry("dev.t.a", "1.1.0"), entry("dev.t.b", "2.0.0", minimum: "99.0.0")],
                                revoked: [.init(id: "dev.t.a", versions: ["1.1"], reason: "leaks tokens")])
        XCTAssertEqual(index.search("").map(\.version), ["1.0.0", "2.0.0"], "a withdrawn version isn't listed")
        XCTAssertThrowsError(try index.checkInstallable(index.plugins[1])) { XCTAssertEqual($0 as? PluginIndex.IndexError, .revoked("dev.t.a", "leaks tokens")) }
        XCTAssertThrowsError(try index.checkInstallable(index.plugins[2], running: "0.10.0")) { XCTAssertEqual($0 as? PluginIndex.IndexError, .needsNewerStackbar("dev.t.b", "99.0.0")) }
        XCTAssertNoThrow(try index.checkInstallable(index.plugins[0]))
        XCTAssertNil(entry("x.y", "1", minimum: "0.10.0").requiredStackbar(running: "0.10.0"))
        XCTAssertEqual(entry("x.y", "1", minimum: "0.10.0").requiredStackbar(running: "0.9.9"), "0.10.0")
    }

    func testReviewFindsUpdatesAndWithdrawals() {
        let official = PluginStore.Source(url: URL(string: "https://example.com/official.json")!, publicKey: "KEY", isOfficial: true)
        let other = PluginStore.Source(url: URL(string: "https://example.com/other.json")!)
        let catalogs = [
            PluginStore.Catalog(source: official, index: PluginIndex(name: "O", plugins: [entry("dev.t.a", "1.2.0"), entry("dev.t.a", "1.3.0"), entry("dev.t.c", "5.0.0", minimum: "99.0")],
                                                                      revoked: [.init(id: "dev.t.w", reason: "malware")])),
            PluginStore.Catalog(source: other, index: PluginIndex(name: "X", plugins: [entry("dev.t.b", "2.0.0"), entry("dev.t.b", "3.0.0", publisher: "mallory")],
                                                                   revoked: [.init(id: "dev.t.a", reason: "says who")])),
        ]
        let review = PluginStore.review(catalogs, installed: [record("dev.t.a", "1.0.0"), record("dev.t.b", "1.0.0"), record("dev.t.c", "1.0.0"), record("dev.t.w", "1.0.0")], running: "0.10.0")
        XCTAssertEqual(review.updates.map { "\($0.entry.id) \($0.entry.version)" }, ["dev.t.a 1.3.0", "dev.t.b 2.0.0"],
                       "the newest buildable version from the same publisher; another publisher's higher version is ignored")
        XCTAssertEqual(review.updates.first?.indexURL, official.url)
        XCTAssertEqual(review.withdrawn.map(\.installed.id), ["dev.t.w"], "only a signed index can withdraw a plugin")
    }

    func testForgetDropsTheRecordAndKeepsTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordFile = directory.appendingPathComponent("installed.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("a.swift")
        try Data("// a".utf8).write(to: file)
        try JSONEncoder.ledger.encode([record("dev.t.a", "1.0.0"), record("dev.t.b", "1.0.0")]).write(to: recordFile)
        let installer = PluginInstaller(pluginsDirectory: directory, publishers: PublisherStore(file: directory.appendingPathComponent("p.json")), recordFile: recordFile)
        XCTAssertEqual(installer.installed.map(\.id), ["dev.t.a", "dev.t.b"])
        try installer.forget("dev.t.a")
        XCTAssertEqual(installer.installed.map(\.id), ["dev.t.b"], "an uninstalled plugin is no longer offered updates or shown as installed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testOfficialIndexIsListedOnlyWithAKey() {
        let sources = PluginStore.sources(userURLs: ["https://example.com/a.json", OfficialIndex.url.absoluteString, "not a url \u{0}"])
        XCTAssertEqual(sources.filter { !$0.isOfficial }.map(\.url.absoluteString), ["https://example.com/a.json"])
        XCTAssertEqual(sources.contains { $0.isOfficial }, OfficialIndex.isAvailable)
    }

    func testANewerFormatAndAMissingSignatureAreRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("index.json")
        try PluginIndex(name: "T", plugins: [], format: 3).encoded().write(to: file)
        XCTAssertThrowsError(try awaitResult { try await PluginIndex.fetch(file) }) { XCTAssertEqual($0 as? PluginIndex.IndexError, .unsupportedFormat(3)) }
        try PluginIndex(name: "T", plugins: []).encoded().write(to: file)
        XCTAssertThrowsError(try awaitResult { try await PluginIndex.fetch(file, publicKey: "AAAA") }) { XCTAssertEqual($0 as? PluginIndex.IndexError, .unsigned) }
        let legacy = #"{"name":"Old","plugins":[]}"#
        try Data(legacy.utf8).write(to: file)
        XCTAssertEqual(try awaitResult { try await PluginIndex.fetch(file) }.name, "Old", "a format 1 index still reads")
    }

    #if canImport(CryptoKit)
    func testSignedIndexVerifiesAndTamperingBreaksIt() throws {
        let key = try Signing.generateKey()
        let publicKey = key.publicKey.base64EncodedString()
        let index = try PluginIndex(name: "T", plugins: [entry("dev.t.a", "1.0.0")]).signed(privateKey: key.privateKey)
        XCTAssertNoThrow(try index.verify(publicKey: publicKey))
        var tampered = index
        tampered.revoked = nil
        tampered.plugins[0].sha256 = "1"
        XCTAssertThrowsError(try tampered.verify(publicKey: publicKey)) { XCTAssertEqual($0 as? PluginIndex.IndexError, .badSignature) }
        let other = try Signing.generateKey().publicKey.base64EncodedString()
        XCTAssertThrowsError(try index.verify(publicKey: other))
    }
    #endif
}

/// Runs an async throwing call from a synchronous test.
func awaitResult<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task {
        do { box.result = .success(try await body()) } catch { box.result = .failure(error) }
        done.signal()
    }
    done.wait()
    return try box.result!.get()
}

private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

#if canImport(CryptoKit)
final class BundledStoreTests: XCTestCase {
    func testMigratesUntouchedCopiesAndKeepsEditedOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundles = root.appendingPathComponent("Bundles"), plugins = root.appendingPathComponent("Plugins")
        try FileManager.default.createDirectory(at: bundles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        let key = try Signing.generateKey()
        func sign(_ id: String, _ version: String) throws {
            let bundle = try Signing.bundle(source: "// \(id) \(version)", manifest: Manifest(id: id, name: id, version: version), publisherName: "navbytes", privateKey: key.privateKey)
            try bundle.encoded().write(to: bundles.appendingPathComponent("\(id)-\(version).stackbarplugin"))
        }
        try sign("io.navbytes.stackbar.clipboard", "1.0.0")
        try sign("io.navbytes.stackbar.clipboard", "1.2.0")
        try sign("io.navbytes.stackbar.up-next", "1.0.0")
        try sign("io.navbytes.stackbar.stay-awake", "1.0.0")
        // Signed by someone else: never used.
        let other = try Signing.bundle(source: "// evil", manifest: Manifest(id: "io.navbytes.stackbar.pr-cockpit", name: "x", version: "9.0.0"), publisherName: "navbytes", privateKey: Signing.generateKey().privateKey)
        try other.encoded().write(to: bundles.appendingPathComponent("evil.stackbarplugin"))

        let record = root.appendingPathComponent("bundled.json")
        try Data("// old clipboard".utf8).write(to: plugins.appendingPathComponent("Clipboard.swift"))   // no record: an install.sh copy
        try Data("// my up next".utf8).write(to: plugins.appendingPathComponent("UpNext.swift"))          // edited since recorded
        try JSONEncoder().encode(["UpNext.swift": SHA256.hex(Data("// shipped up next".utf8))]).write(to: record)

        let installer = PluginInstaller(pluginsDirectory: plugins, publishers: PublisherStore(file: root.appendingPathComponent("p.json")), recordFile: root.appendingPathComponent("installed.json"))
        let store = BundledStore(bundlesDirectory: bundles, pluginsDirectory: plugins, bundledRecord: record, installer: installer, publicKey: key.publicKey.base64EncodedString())
        XCTAssertEqual(store.bundles().map { "\($0.manifest.id) \($0.manifest.version)" },
                       ["io.navbytes.stackbar.clipboard 1.2.0", "io.navbytes.stackbar.stay-awake 1.0.0", "io.navbytes.stackbar.up-next 1.0.0"])

        let migrated = store.migrate()
        XCTAssertEqual(migrated.map(\.old.lastPathComponent), ["Clipboard.swift"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plugins.appendingPathComponent("Clipboard.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plugins.appendingPathComponent("Clipboard.swift.bak").path))
        XCTAssertEqual(try String(contentsOf: migrated[0].new, encoding: .utf8), "// io.navbytes.stackbar.clipboard 1.2.0")
        XCTAssertEqual(try String(contentsOf: plugins.appendingPathComponent("UpNext.swift"), encoding: .utf8), "// my up next", "an edited copy stays the user's")

        let added = store.installMissing()
        XCTAssertEqual(added.count, 1, "Stay Awake is new; Up Next has the user's copy; Clipboard is installed")
        XCTAssertEqual(Set(installer.installed.map(\.id)), ["io.navbytes.stackbar.clipboard", "io.navbytes.stackbar.stay-awake"])
        XCTAssertEqual(store.migrate(), [], "running it again changes nothing")
    }
}
#endif
