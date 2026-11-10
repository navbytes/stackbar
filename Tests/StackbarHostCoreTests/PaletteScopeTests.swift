import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// A plugin's name, then Tab, searches inside it (openspec palette-scope).
final class PaletteScopeTests: XCTestCase {
    private let search = CommandSpec(id: "repos", title: "Search Git Repos", kind: .view, rootSearch: true)
    private let sync = CommandSpec(id: "sync", title: "Sync All Repos", kind: .run)

    private var commands: [CommandRegistry.Entry] {
        [CommandRegistry.Entry(pluginID: "git", pluginName: "Git Sync", spec: sync),
         CommandRegistry.Entry(pluginID: "git", pluginName: "Git Sync", spec: search),
         CommandRegistry.Entry(pluginID: "docker", pluginName: "Docker", spec: CommandSpec(id: "ps", title: "Containers", kind: .view))]
    }

    private func row(_ entry: CommandRegistry.Entry) -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: entry.pluginID, pluginName: entry.pluginName, title: entry.spec.title, kind: .command(entry.spec))
    }

    private func open(_ plugin: String, _ name: String) -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: plugin, pluginName: name, title: "Open \(name)", kind: .showPanel)
    }

    func testTabEntersFromThePluginsSearchOrOpenRow() {
        let all = commands
        let target = { (entry: PaletteIndex.Entry, preference: CommandPreference) in
            PaletteScope.target(of: entry, commands: all) { _ in preference }?.key
        }
        XCTAssertEqual(target(row(all[1]), .default), all[1].key, "the search command itself")
        XCTAssertEqual(target(open("git", "Git Sync"), .default), all[1].key, "the Open row finds the plugin's search")
        XCTAssertNil(target(row(all[0]), .default), "another command of the plugin: Tab stays Ask AI")
        XCTAssertNil(target(open("docker", "Docker"), .default), "a plugin with no search")
        XCTAssertNil(target(row(all[2]), .default))
        XCTAssertEqual(target(row(all[1]), CommandPreference(inRootSearch: false)), all[1].key, "off for the main search still enters, as an alias does")
        XCTAssertNil(target(row(all[1]), CommandPreference(enabled: false)), "a disabled command doesn't")
        XCTAssertNil(target(PaletteIndex.Entry(pluginID: "git", pluginName: "Git Sync", title: "x", kind: .copy("x")), .default))
    }

    func testTheScopedRootListsOnlyThatPlugin() {
        let command = commands[1]
        let rows = (0..<60).map { RowNode(key: "\($0)", title: "repo \($0)", actions: [ActionRef(id: ActionID("row/\($0)/Open"), title: "Open")]) }
        let root = PaletteRoot.scoped(PaletteRoot.PluginRows(command: command, rows: rows))
        XCTAssertEqual(root.sections.count, 1)
        XCTAssertEqual(root.sections[0].title, "Git Sync")
        XCTAssertEqual(root.entries.count, PaletteRoot.scopedRowLimit, "more than the main search's three")
        XCTAssertEqual(root.pluginRow(root.entries[0])?.command, command.key, "Return runs the row in the plugin's view")
        XCTAssertEqual(root.primaryTitle(root.entries[0]), "Open")
        XCTAssertTrue(PaletteRoot.scoped(nil).sections.isEmpty, "not answered yet: nothing else creeps in")
        XCTAssertTrue(PaletteRoot.scoped(PaletteRoot.PluginRows(command: command, rows: [])).sections.isEmpty)
    }

    func testTheCacheKeepsTheMainSearchAndAPluginsApart() {
        var cache = PaletteRootCache()
        let main = PaletteRootCache.Key(query: "", index: 1, memory: 1, store: 0, rows: 1)
        var scoped = main
        scoped.scope = commands[1].key
        let first = cache.root(for: main) { PaletteRoot.scoped(nil) }
        var built = false
        _ = cache.root(for: scoped) { built = true; return first }
        XCTAssertTrue(built)
        XCTAssertEqual(PaletteScope.prompt(commands[1]), "Search Git Sync")
    }
}
