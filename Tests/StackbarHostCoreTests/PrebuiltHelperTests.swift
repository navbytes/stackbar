import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class PrebuiltHelperTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("prebuilt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A StackbarKit package with nothing but what the digest reads.
    private func fakeKit() throws -> URL {
        let kit = directory.appendingPathComponent("Kit", isDirectory: true)
        for (folder, file, text) in [("StackbarKit", "Kit.swift", "// kit"), ("StackbarProtocol", "Messages.swift", "public enum StackbarProtocolVersion {\n    public static let current = \(StackbarProtocolVersion.current)\n}\n")] {
            let sources = kit.appendingPathComponent("Sources/\(folder)", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: sources.appendingPathComponent(file))
        }
        return kit
    }

    private func executable(_ name: String, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private func record(id: String = "dev.t.p", source: String = "a1", kit: String = "k1", protocolVersion: Int = 7, arch: String = PrebuiltHelpers.arch) -> HelperRecord {
        HelperRecord(id: id, version: "1.0.0", sourceDigest: source, stackbarKit: kit, protocolVersion: protocolVersion, arch: arch, url: "\(id)-\(kit)", sha256: "00")
    }

    func testMatchPrefersTheExactStackbarKit() {
        let index = HelperIndex(helpers: [
            record(kit: "old", protocolVersion: 7),
            record(kit: "k1", protocolVersion: 7),
            record(kit: "newer", protocolVersion: 7),
            record(source: "other", kit: "k2", protocolVersion: 8),
            record(kit: "k2", protocolVersion: 8, arch: "sparc"),
        ])
        XCTAssertEqual(index.match(id: "dev.t.p", sourceDigest: "A1", stackbarKit: "k1", protocolVersion: 7, compatible: false)?.record.stackbarKit, "k1", "digests compare without case")
        XCTAssertNil(index.match(id: "dev.t.p", sourceDigest: "a1", stackbarKit: "k2", protocolVersion: 8, compatible: true),
                     "no helper for this source and protocol on this architecture")
        let near = index.match(id: "dev.t.p", sourceDigest: "a1", stackbarKit: "k9", protocolVersion: 7, compatible: true)
        XCTAssertEqual(near?.record.stackbarKit, "newer", "the newest helper for the same protocol")
        XCTAssertEqual(near?.exact, false)
        XCTAssertNil(index.match(id: "dev.t.p", sourceDigest: "a1", stackbarKit: "k9", protocolVersion: 7, compatible: false))
        XCTAssertNil(index.match(id: "dev.t.other", sourceDigest: "a1", stackbarKit: "k1", protocolVersion: 7, compatible: true))
    }

    func testRecordEncodingAndSignedBytes() throws {
        let data = try JSONEncoder().encode(record())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["protocol"] as? Int, 7)
        XCTAssertEqual(try JSONDecoder().decode(HelperRecord.self, from: data), record())
        var moved = record()
        moved.url = "https://elsewhere.example/x"
        moved.size = 12
        XCTAssertEqual(moved.signedBytes, record().signedBytes, "a binary may move without a new signature")
        var other = record()
        other.sha256 = "01"
        XCTAssertNotEqual(other.signedBytes, record().signedBytes)
        XCTAssertThrowsError(try record().verify(publicKey: "someone")) { error in
            XCTAssertEqual(error as? PrebuiltHelpers.HelperError, .wrongPublisher("dev.t.p"))
        }
    }

    func testProtocolVersionOfThisPackage() {
        XCTAssertEqual(PluginBuilder.protocolVersion(of: StackbarPaths.stackbarPackage()), StackbarProtocolVersion.current)
        XCTAssertNil(PluginBuilder.protocolVersion(of: directory))
    }

    func testBuildUsesAnExactPrebuiltHelperWithoutCompiling() throws {
        let kit = try fakeKit()
        var builder = PluginBuilder(stackbarPackage: kit, cacheRoot: directory.appendingPathComponent("Cache"))
        builder.toolchain = false
        let source = directory.appendingPathComponent("Plugin.swift")
        try Data("// a plugin".utf8).write(to: source)
        let digest = SHA256.hex(Data("// a plugin".utf8))

        XCTAssertThrowsError(try builder.build(source: source)) { error in
            XCTAssertTrue("\(error)".contains("xcode-select --install"), "without a compiler or a helper, say what to install: \(error)")
        }

        let compatible = try executable(PrebuiltHelpers.compatibleName(sourceDigest: digest, protocolVersion: StackbarProtocolVersion.current), in: builder.downloadedHelpers)
        XCTAssertEqual(try builder.build(source: source).binary, compatible, "no compiler: a helper for the same protocol")
        XCTAssertTrue(builder.hasPrebuilt(sourceDigest: digest, compatible: true))
        XCTAssertFalse(builder.hasPrebuilt(sourceDigest: digest, compatible: false))

        let shipped = try executable(PrebuiltHelpers.exactName(sourceDigest: digest, stackbarKit: builder.stackbarKit), in: kit.appendingPathComponent("Prebuilt"))
        XCTAssertEqual(try builder.build(source: source).binary, shipped, "an exact helper wins")
        XCTAssertTrue(builder.hasPrebuilt(sourceDigest: digest, compatible: false))

        try Data("// changed by the user".utf8).write(to: source)
        XCTAssertThrowsError(try builder.build(source: source), "a changed source never runs someone's helper")

        try Data("// a plugin".utf8).write(to: kit.appendingPathComponent("Sources/StackbarKit/Kit.swift"))
        try Data("// a plugin".utf8).write(to: source)
        XCTAssertEqual(try builder.build(source: source).binary, compatible, "another StackbarKit: only the compatible helper fits")
    }

    func testSaveNamesTheHelperForWhatItRunsOn() throws {
        let binary = Data("#!/bin/sh\n".utf8)
        let exact = PrebuiltHelpers.Download(record: record(kit: "k1"), binary: binary, exact: true)
        let file = try PrebuiltHelpers.save(exact, in: directory, stackbarKit: "k1")
        XCTAssertEqual(file.lastPathComponent, "a1-k1")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: file.path))
        let near = PrebuiltHelpers.Download(record: record(kit: "k0", protocolVersion: 9), binary: binary, exact: false)
        XCTAssertEqual(try PrebuiltHelpers.save(near, in: directory, stackbarKit: "k1").lastPathComponent, "a1-p9")
    }

    func testWithoutAToolchainAnInstallNeedsAHelper() async throws {
        let kit = try fakeKit()
        let builder = PluginBuilder(stackbarPackage: kit, cacheRoot: directory.appendingPathComponent("Cache"))
        let store = directory.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let bundle = PluginBundle(manifest: Manifest(id: "dev.t.p", name: "P", version: "1.0.0"), source: "// p", sourceDigest: SHA256.hex(Data("// p".utf8)),
                                  publisher: .init(name: "Pub", publicKey: "key"), signature: "")
        let indexURL = store.appendingPathComponent("index.json")

        // A store without helpers.json: fine with a compiler, refused without.
        let withCompiler = try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: true)
        XCTAssertNil(withCompiler)
        do {
            _ = try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: false)
            XCTFail("nothing to run")
        } catch {
            XCTAssertEqual(error as? PrebuiltHelpers.HelperError, .notPrebuilt(name: "P", version: "1.0.0"))
        }

        // A helper signed by someone else is refused, not used.
        var forged = record(source: bundle.sourceDigest, kit: builder.stackbarKit, protocolVersion: StackbarProtocolVersion.current)
        forged.publicKey = "someone else"
        try JSONEncoder().encode(HelperIndex(helpers: [forged])).write(to: store.appendingPathComponent(HelperIndex.fileName))
        do {
            _ = try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: false)
            XCTFail("a forged helper")
        } catch {
            XCTAssertEqual(error as? PrebuiltHelpers.HelperError, .wrongPublisher("dev.t.p"))
        }
        let ignored = try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: true)
        XCTAssertNil(ignored, "with a compiler, a bad helper is just not used")

        // One already on this Mac: nothing to fetch.
        _ = try executable(PrebuiltHelpers.exactName(sourceDigest: bundle.sourceDigest, stackbarKit: builder.stackbarKit), in: builder.downloadedHelpers)
        let present = try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: false)
        XCTAssertNil(present)
    }

    #if canImport(CryptoKit)
    func testSignedHelpersDownloadVerifyAndRefresh() async throws {
        let kit = try fakeKit()
        let builder = PluginBuilder(stackbarPackage: kit, cacheRoot: directory.appendingPathComponent("Cache"))
        let key = try Signing.generateKey()
        let manifest = Manifest(id: "dev.t.p", name: "P", version: "1.0.0")
        let bundle = try Signing.bundle(source: "// p", manifest: manifest, publisherName: "Pub", privateKey: key.privateKey)
        let store = directory.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let indexURL = store.appendingPathComponent("index.json")
        let binary = Data("#!/bin/sh\necho helper\n".utf8)
        try binary.write(to: store.appendingPathComponent("helper-bin"))
        var signed = HelperRecord(id: manifest.id, version: manifest.version, sourceDigest: bundle.sourceDigest, stackbarKit: builder.stackbarKit,
                                  protocolVersion: StackbarProtocolVersion.current, arch: PrebuiltHelpers.arch, url: "helper-bin", sha256: SHA256.hex(binary))
        try signed.sign(privateKey: key.privateKey)
        XCTAssertNoThrow(try signed.verify(publicKey: bundle.publisher.publicKey))
        var tampered = signed
        tampered.sourceDigest = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try tampered.verify(publicKey: bundle.publisher.publicKey))
        try JSONEncoder().encode(HelperIndex(helpers: [signed])).write(to: store.appendingPathComponent(HelperIndex.fileName))

        let download = try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: false)
        XCTAssertEqual(download?.exact, true)
        XCTAssertEqual(download?.binary, binary)

        try Data("#!/bin/sh\necho swapped\n".utf8).write(to: store.appendingPathComponent("helper-bin"))
        do {
            _ = try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: false)
            XCTFail("a swapped binary")
        } catch {
            XCTAssertEqual(error as? PrebuiltHelpers.HelperError, .digestMismatch("dev.t.p"))
        }
        try binary.write(to: store.appendingPathComponent("helper-bin"))

        // An installed plugin without a helper (a Stackbar update changed
        // StackbarKit) gets one from its store.
        let publishers = PublisherStore(file: directory.appendingPathComponent("publishers.json"))
        let installer = PluginInstaller(pluginsDirectory: directory.appendingPathComponent("Plugins"), publishers: publishers, recordFile: directory.appendingPathComponent("installed.json"))
        try installer.install(bundle)
        let entry = PluginIndex.Entry(id: manifest.id, name: "P", version: "1.0.0", publisher: "Pub", bundle: "p.stackbarplugin", sha256: "00", capabilities: [])
        let catalog = PluginStore.Catalog(source: .init(url: indexURL), index: PluginIndex(name: "Store", plugins: [entry]))
        let refreshed = await PrebuiltHelpers.refresh(installed: installer.installed, catalogs: [catalog], publishers: publishers, builder: builder, toolchain: false)
        XCTAssertEqual(refreshed, ["dev.t.p"])
        XCTAssertTrue(builder.hasPrebuilt(sourceDigest: bundle.sourceDigest, compatible: false))
        let again = await PrebuiltHelpers.refresh(installed: installer.installed, catalogs: [catalog], publishers: publishers, builder: builder, toolchain: false)
        XCTAssertEqual(again, [], "already there")
    }
    #endif
}
