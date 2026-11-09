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

    func testAnImportMergesIntoWhatIsHereUnlessItReplaces() throws {
        let team = try directory()
        try write(#"{"gh/search":{"alias":"gh"},"jira/open":{"alias":"j"}}"#, "command-preferences.json", in: team)
        try write(#"["gh/search"]"#, "palette-favorites.json", in: team)
        try write(#"{"region":"eu"}"#, "Storage/io.t.p.json", in: team)
        let archive = try SettingsArchive.decode(SettingsArchive.export(dataDirectory: team, defaults: defaults()).encoded())

        let mine = try directory()
        try write(#"{"jira/open":{"alias":"ji"},"todo/add":{"alias":"t"}}"#, "command-preferences.json", in: mine)
        try write(#"["apps|row|search|safari"]"#, "palette-favorites.json", in: mine)
        try write(#"{"items":"[1]"}"#, "Storage/io.t.p.json", in: mine)
        try archive.apply(to: mine, defaults: defaults())
        func json(_ path: String) throws -> Any { try JSONSerialization.jsonObject(with: Data(contentsOf: mine.appendingPathComponent(path))) }
        let preferences = try XCTUnwrap(json("command-preferences.json") as? [String: [String: String]])
        XCTAssertEqual(preferences["todo/add"]?["alias"], "t", "mine stays")
        XCTAssertEqual(preferences["jira/open"]?["alias"], "j", "the file wins where both have one")
        XCTAssertEqual(preferences["gh/search"]?["alias"], "gh")
        XCTAssertEqual(try json("palette-favorites.json") as? [String], ["apps|row|search|safari", "gh/search"])
        XCTAssertEqual(try json("Storage/io.t.p.json") as? [String: String], ["items": "[1]", "region": "eu"])

        try archive.apply(to: mine, defaults: defaults(), replacing: true)
        XCTAssertEqual(try json("palette-favorites.json") as? [String], ["gh/search"], "a restore replaces")
    }

    func testAnExportCanLeaveParts() throws {
        let root = try directory()
        try write("// plugin", "Plugins/Todo.swift", in: root)
        try write(#"{"items":"[]"}"#, "Storage/io.navbytes.todo.json", in: root)
        try write(#"{}"#, "command-preferences.json", in: root)
        try write(#"[]"#, "palette-favorites.json", in: root)
        let prefs = defaults()
        prefs.set("cmd+space", forKey: PaletteHotKey.defaultsKey)
        let parts = try XCTUnwrap(SettingsArchive.Part.parse("commands, preferences"))
        let archive = try SettingsArchive.export(dataDirectory: root, defaults: prefs, parts: parts)
        XCTAssertEqual(Set(archive.files.keys), ["command-preferences.json"])
        XCTAssertEqual(archive.preferences.count, 1)
        XCTAssertNil(SettingsArchive.Part.parse("commands,secrets"))
    }
}

final class PrivateStoreTests: XCTestCase {
    func testASourceLineCarriesItsKeyAndTokenName() throws {
        let source = try XCTUnwrap(PluginStore.Source.parse("https://store.example.com/team/index.json#key=abc%2B%3D&auth=TEAM_STORE"))
        XCTAssertEqual(source.url.absoluteString, "https://store.example.com/team/index.json")
        XCTAssertEqual(source.publicKey, "abc+=")
        XCTAssertEqual(source.authSecret, "TEAM_STORE")
        XCTAssertEqual(source.configured, "https://store.example.com/team/index.json#key=abc%2B%3D&auth=TEAM_STORE")
        XCTAssertNil(PluginStore.Source.parse("http://store.example.com/index.json"), "https only")
        XCTAssertNil(PluginStore.Source.parse("https://store.example.com/index.json").flatMap(\.publicKey))
    }

    func testATokenGoesOnlyToItsStoresFolder() throws {
        let auth = StoreAuth()
        let index = try XCTUnwrap(URL(string: "https://store.example.com/team/index.json"))
        auth.set([index: "t0k"])
        XCTAssertEqual(auth.authorization(for: index), "Bearer t0k")
        XCTAssertEqual(auth.authorization(for: URL(string: "https://store.example.com/team/Dev/Tool.stackbarplugin")!), "Bearer t0k")
        XCTAssertNil(auth.authorization(for: URL(string: "https://store.example.com/other/x")!))
        XCTAssertNil(auth.authorization(for: URL(string: "https://evil.example.com/team/x")!))
        XCTAssertNil(auth.authorization(for: URL(string: "https://store.example.com:8443/team/x")!))
    }

    func testSourcesRegisterTheirTokens() {
        let sources = PluginStore.sources(userURLs: ["https://s.example.com/index.json#auth=S", "https://s.example.com/index.json"]) { $0 == "S" ? "v" : nil }
        XCTAssertEqual(sources.filter { !$0.isOfficial }.count, 1, "the same index once")
        XCTAssertEqual(StoreAuth.shared.authorization(for: URL(string: "https://s.example.com/a.stackbarplugin")!), "Bearer v")
        StoreAuth.shared.set([:])
    }
}
