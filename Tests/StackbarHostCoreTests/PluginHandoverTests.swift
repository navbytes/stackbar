import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class PluginHandoverTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("handover-" + UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func key(_ plugin: String, _ command: String) -> CommandKey { CommandKey(pluginID: plugin, commandID: command) }

    func testManifestChecksWhatItReplaces() {
        XCTAssertEqual(Manifest(id: "dev.t.windows", name: "W", replaces: ["dev.t.layouts"]).problems, [])
        XCTAssertEqual(Manifest(id: "dev.t.windows", name: "W", replaces: ["dev.t.windows"]).problems, ["a plugin can't replace itself"])
        XCTAssertEqual(Manifest(id: "dev.t.windows", name: "W", replaces: ["layouts"]).problems.count, 1)
    }

    func testManifestWithoutReplacesStillDecodes() throws {
        let encoded = try JSONEncoder().encode(Manifest(id: "dev.t.a", name: "A"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("replaces"), "older apps see the same manifest as before")
        XCTAssertNil(try JSONDecoder().decode(Manifest.self, from: encoded).replaces)
    }

    func testMovesHotkeysAliasesUsageAndFavouritesOnce() throws {
        let preferences = CommandPreferences(file: directory.appendingPathComponent("prefs.json"))
        let memory = PaletteMemory(directory: nil)
        let usage = memory.usage
        let favorites = memory.favorites
        try preferences.set(CommandPreference(alias: "lh", hotkey: "ctrl+option+l"), for: key("dev.t.layouts", "left-half"))
        try preferences.set(CommandPreference(hotkey: "ctrl+option+m"), for: key("dev.t.layouts", "maximize"))
        try preferences.set(CommandPreference(alias: "mine"), for: key("dev.t.windows", "maximize"))
        try preferences.set(CommandPreference(alias: "other"), for: key("dev.t.other", "x"))
        usage.record("dev.t.layouts/left-half")
        usage.record("dev.t.layouts|panel")
        favorites.toggle("dev.t.layouts/left-half")
        favorites.toggle("dev.t.other/x")
        memory.picks.record(query: "lh", id: "dev.t.layouts/left-half")
        memory.picks.record(query: "le", id: "dev.t.layouts|row|left-half|screen-2")
        memory.picks.record(query: "zz", id: "dev.t.layouts|row|gone|a")

        let handover = PluginHandover(file: directory.appendingPathComponent("handovers.json"))
        let manifest = Manifest(id: "dev.t.windows", name: "Windows", replaces: ["dev.t.layouts", "dev.t.layouts"])
        XCTAssertEqual(handover.pending(for: manifest), ["dev.t.layouts"])

        try preferences.set(CommandPreference(hotkey: "ctrl+option+z"), for: key("dev.t.layouts", "restore"))
        try preferences.set(CommandPreference(hotkey: "ctrl+option+g"), for: key("dev.t.layouts", "gone"))
        let commands = ["left-half": "Left Half", "maximize": "Maximize", "restore": "Restore Window Layout"]
        let oldTitles = ["left-half": "Left Half", "maximize": "Maximize", "restore": "Restore", "gone": "Gone"]
        let moved = handover.hand(from: "dev.t.layouts", to: "dev.t.windows", commands: commands, oldTitles: oldTitles,
                                  preferences: preferences, memory: memory)
        XCTAssertEqual(moved, [key("dev.t.windows", "left-half")], "maximize already had the new plugin's own preference")
        XCTAssertNil(preferences[key("dev.t.windows", "restore")].hotkey, "same id, different command: it stays behind")
        XCTAssertEqual(preferences[key("dev.t.layouts", "restore")].hotkey, "ctrl+option+z")
        XCTAssertEqual(preferences[key("dev.t.layouts", "gone")].hotkey, "ctrl+option+g", "a command the new plugin doesn't have stays behind")
        XCTAssertEqual(preferences[key("dev.t.windows", "left-half")].hotkey, "ctrl+option+l")
        XCTAssertEqual(preferences[key("dev.t.windows", "left-half")].alias, "lh")
        XCTAssertEqual(preferences[key("dev.t.windows", "maximize")].alias, "mine")
        XCTAssertNil(preferences[key("dev.t.windows", "maximize")].hotkey)
        XCTAssertEqual(preferences[key("dev.t.layouts", "left-half")], .default, "the old command keeps nothing, so its hotkey isn't registered twice")
        XCTAssertEqual(preferences.command(forAlias: "other"), key("dev.t.other", "x"))
        XCTAssertGreaterThan(usage.score("dev.t.windows/left-half"), 0)
        XCTAssertEqual(usage.score("dev.t.layouts/left-half"), 0)
        XCTAssertGreaterThan(usage.score("dev.t.layouts|panel"), 0, "only commands carry over")
        XCTAssertEqual(favorites.ids, ["dev.t.windows/left-half", "dev.t.other/x"])
        XCTAssertEqual(memory.picks.weights(for: "lh").keys.sorted(), ["dev.t.windows/left-half"], "what the ranker learned moves too")
        XCTAssertEqual(memory.picks.weights(for: "le").keys.sorted(), ["dev.t.windows|row|left-half|screen-2"], "and a command's root rows")
        XCTAssertEqual(memory.picks.weights(for: "zz").keys.sorted(), ["dev.t.layouts|row|gone|a"], "a row of a command that doesn't carry stays")

        XCTAssertEqual(handover.pending(for: manifest), [])
        XCTAssertEqual(handover.replacement(of: "dev.t.layouts"), "dev.t.windows")
        let reloaded = PluginHandover(file: directory.appendingPathComponent("handovers.json"))
        XCTAssertEqual(reloaded.pending(for: manifest), [], "remembered across launches")
        XCTAssertEqual(CommandPreferences(file: directory.appendingPathComponent("prefs.json"))[key("dev.t.windows", "left-half")].alias, "lh")
    }

    func testStoreHidesAReplacedPluginUnlessInstalled() {
        func entry(_ id: String, replaces: [String]? = nil) -> PluginIndex.Entry {
            PluginIndex.Entry(id: id, name: String(id.split(separator: ".").last!), version: "1.0.0", publisher: "navbytes", bundle: "b", sha256: "0",
                              capabilities: [], category: "Productivity", replaces: replaces)
        }
        let catalog = PluginStore.Catalog(source: .init(url: OfficialIndex.url, isOfficial: true), index: PluginIndex(name: "O", plugins: [
            entry("dev.t.layouts"), entry("dev.t.windows", replaces: ["dev.t.layouts"]), entry("dev.t.zebra"),
        ]))
        XCTAssertEqual(StoreListing.all([catalog], running: "1.0.0").map(\.entry.name), ["windows", "zebra"])
        XCTAssertEqual(StoreListing.replacedIDs([catalog], running: "1.0.0")["dev.t.layouts"]?.id, "dev.t.windows")
        let installed = StoreListing.Installed(versions: ["dev.t.layouts": "1.0.0"])
        XCTAssertEqual(StoreListing.items([catalog], filter: .installed, installed: installed, running: "1.0.0").map(\.entry.name), ["layouts"],
                       "still listed where it is installed, so it can be uninstalled")
        XCTAssertNil(StoreListing.featured([catalog], installed: installed, running: "1.0.0").flatMap { $0.entry.id == "dev.t.layouts" ? $0 : nil })
    }
}
