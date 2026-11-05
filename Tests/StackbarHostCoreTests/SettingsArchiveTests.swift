import Foundation
import XCTest
@testable import StackbarHostCore

final class SettingsArchiveTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        roots.append(url)
        return url
    }

    private func defaults() -> UserDefaults {
        let name = "archive-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func write(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testRoundTripsASetupToAnotherMac() throws {
        let old = try directory()
        try write("// plugin", "Plugins/Todo.swift", in: old)
        try write(#"{"items":"[]"}"#, "Storage/io.navbytes.todo.json", in: old)
        try write(#"{"aliases":{}}"#, "command-preferences.json", in: old)
        try write(#"[{"file":"\#(old.path)/Plugins/Todo.swift","id":"io.navbytes.todo","installedAt":0,"publisher":"navbytes","version":"2.0.0"}]"#, "installed.json", in: old)
        try write(#"{"token":"secret"}"#, "secrets.json", in: old)
        try write(#"{}"#, "approvals.json", in: old)
        try write("x", "Plugins/.DS_Store", in: old)
        let oldDefaults = defaults()
        oldDefaults.set("cmd+space", forKey: PaletteHotKey.defaultsKey)
        oldDefaults.set(["io.x"], forKey: "pluginsOff")
        oldDefaults.set(true, forKey: "agentGateway")

        let data = try SettingsArchive.export(dataDirectory: old, defaults: oldDefaults).encoded()
        let archive = try SettingsArchive.decode(data)
        XCTAssertEqual(Set(archive.files.keys), ["Plugins/Todo.swift", "Storage/io.navbytes.todo.json", "command-preferences.json", "installed.json"])
        XCTAssertNil(archive.preferences["agentGateway"])
        XCTAssertEqual(archive.summary, .init(pluginFiles: ["Todo.swift"], savedValues: 1, preferences: 2))

        let new = try directory()
        try write(#"[{"file":"\#(new.path)/Plugins/Clock.swift","id":"io.navbytes.clock","installedAt":0,"publisher":"navbytes","version":"1.0.0"}]"#, "installed.json", in: new)
        let newDefaults = defaults()
        try archive.apply(to: new, defaults: newDefaults)

        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("Plugins/Todo.swift"), encoding: .utf8), "// plugin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.appendingPathComponent("secrets.json").path))
        XCTAssertEqual(newDefaults.string(forKey: PaletteHotKey.defaultsKey), "cmd+space")
        XCTAssertEqual(newDefaults.stringArray(forKey: "pluginsOff"), ["io.x"])
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: new.appendingPathComponent("installed.json"))) as? [[String: Any]])
        let files = Dictionary(uniqueKeysWithValues: records.map { ($0["id"] as! String, $0["file"] as! String) })
        XCTAssertEqual(files["io.navbytes.todo"], new.path + "/Plugins/Todo.swift")
        XCTAssertEqual(files["io.navbytes.clock"], new.path + "/Plugins/Clock.swift")
    }

    func testRefusesPathsOutsideTheSettings() throws {
        for path in ["secrets.json", "approvals.json", "Plugins/../secrets.json", "/etc/passwd", "Plugins/", "Plugins/.hidden", "Run/x", "Storage/a\\b"] {
            let archive = SettingsArchive(format: 1, stackbarVersion: "1", exportedAt: Date(timeIntervalSince1970: 0), preferences: [:], files: [path: Data()])
            XCTAssertThrowsError(try SettingsArchive.decode(archive.encoded()), path) { error in
                XCTAssertEqual(error as? SettingsArchive.ArchiveError, .badPath(path))
            }
        }
    }

    func testRefusesOtherFilesAndNewerFormats() throws {
        XCTAssertThrowsError(try SettingsArchive.decode(Data("{}".utf8))) { XCTAssertEqual($0 as? SettingsArchive.ArchiveError, .notAnArchive) }
        let newer = SettingsArchive(format: 99, stackbarVersion: "9", exportedAt: Date(timeIntervalSince1970: 0), preferences: [:], files: [:])
        XCTAssertThrowsError(try SettingsArchive.decode(newer.encoded())) { XCTAssertEqual($0 as? SettingsArchive.ArchiveError, .newerFormat(99)) }
    }

    func testIgnoresUnknownPreferences() throws {
        let archive = SettingsArchive(format: 1, stackbarVersion: "1", exportedAt: Date(timeIntervalSince1970: 0), preferences: ["agentGateway": .bool(true), "paletteCompact": .bool(true)], files: [:])
        let defaults = defaults()
        try SettingsArchive.decode(archive.encoded()).apply(to: try directory(), defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "agentGateway"))
        XCTAssertTrue(defaults.bool(forKey: "paletteCompact"))
    }
}
