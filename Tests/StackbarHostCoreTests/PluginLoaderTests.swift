import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class PluginLoaderTests: XCTestCase {
    func testPassesABuiltHelperThrough() throws {
        let helper = PluginSupervisorTests.helper("FixturePlugin")
        let loaded = try PluginLoader(builder: nil, sandbox: false).load(helper)
        XCTAssertEqual(loaded.binary, helper)
        XCTAssertEqual(loaded.manifest.id, "io.navbytes.stackbar.test.fixture")
    }

    func testRefusesAManifestWithProblems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A helper is anything that prints its manifest for `--manifest`.
        let helper = directory.appendingPathComponent("bad-helper")
        let manifest = String(decoding: try LineCodec.encode(Manifest(id: "nodots", name: "Bad")), as: UTF8.self)
        try Data("#!/bin/sh\ncat <<'EOF'\n\(manifest)EOF\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        XCTAssertThrowsError(try PluginLoader(builder: nil, sandbox: false).load(helper)) { error in
            guard case .badManifest(let problems) = error as? PluginLoader.LoadError else { return XCTFail("\(error)") }
            XCTAssertEqual(problems, ["id \"nodots\" must be reverse-DNS, like dev.example.clock"])
        }
    }

    func testASourceNeedsABuilder() {
        XCTAssertThrowsError(try PluginLoader(builder: nil, sandbox: false).load(URL(fileURLWithPath: "/tmp/Plugin.swift"))) { error in
            XCTAssertEqual(error as? PluginLoader.LoadError, .noBuilder)
        }
    }

    /// Compiles a plugin with SwiftPM, so it runs only when STACKBAR_BUILD_TESTS=1.
    func testLoadsASource() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STACKBAR_BUILD_TESTS"] == "1", "set STACKBAR_BUILD_TESTS=1 to compile plugins")
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("stackbar-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let cache = work.appendingPathComponent("cache")
        let builder = PluginBuilder(stackbarPackage: package, cacheRoot: cache, configuration: "debug")
        let source = package.appendingPathComponent("Tests/Fixtures/FixturePlugin/Fixture.swift")

        let loaded = try PluginLoader(builder: builder, sandbox: false).load(source)
        XCTAssertEqual(loaded.manifest.id, "io.navbytes.stackbar.test.fixture")
        XCTAssertEqual(loaded.binary, try builder.build(source: source).binary)
        #if os(macOS)
        let sandboxed = try PluginLoader(builder: builder, sandbox: true).load(source)
        XCTAssertEqual(sandboxed.binary.deletingLastPathComponent().lastPathComponent, "Sandboxed", "the signed copy is what runs")
        XCTAssertEqual(sandboxed.manifest, loaded.manifest)
        #endif
    }
}
