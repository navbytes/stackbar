import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// The main search lists commands, not panels; plugins answer in it only
/// with the user's yes; aliases scope a search; fallbacks are the user's
/// list (openspec palette-root-commands).
final class PaletteRootCommandsTests: XCTestCase {
    private func entry(_ plugin: String, _ spec: CommandSpec) -> CommandRegistry.Entry {
        CommandRegistry.Entry(pluginID: plugin, pluginName: plugin, spec: spec)
    }

    func testPanelEntriesStayOutOfTheMainSearch() {
        var index = PaletteIndex()
        index.update(pluginID: "docker", pluginName: "Docker", panel: .stack(axis: .vertical, children: [
            .button(title: "Remove Stopped Containers", action: "button/prune"),
            .toggle(title: "Group by Compose project", isOn: false, action: "toggle/group"),
        ]))
        index.setPanels([(pluginID: "docker", name: "Docker"), (pluginID: "music", name: "Music")])
        XCTAssertEqual(index.entries.count, 2, "still read from the panel")
        XCTAssertEqual(index.search("remove"), [])
        XCTAssertEqual(index.search("group"), [])
        XCTAssertEqual(index.search("docker").map(\.title), ["Open Docker"], "every plugin with a panel has its Open row")
        XCTAssertEqual(index.search("music").first?.kind, .showPanel)
        let sections = PaletteSection.group(index.search(""), query: "") { _ in false }
        XCTAssertFalse(sections.contains { $0.kind == .panelActions })
    }

    func testOnlyCorePluginsAndPatternsAnswerByDefault() {
        let any = CommandSpec(id: "repos", title: "Repositories", kind: .view, rootSearch: true)
        let pattern = CommandSpec(id: "issue", title: "Issue", kind: .view, rootSearch: true, rootPattern: #"[A-Z]+-\d+"#)
        XCTAssertTrue(RootSearchGate.accepts(entry("io.navbytes.stackbar.plugins.applications", any), text: "saf"))
        XCTAssertFalse(RootSearchGate.accepts(entry("io.navbytes.stackbar.plugins.git-sync", any), text: "stackbar"), "free text: off until turned on")
        XCTAssertTrue(RootSearchGate.accepts(entry("io.navbytes.stackbar.plugins.git-sync", any), text: "stackbar", preference: CommandPreference(inRootSearch: true)))
        XCTAssertTrue(RootSearchGate.accepts(entry("jira", pattern), text: "ABC-12"))
        XCTAssertFalse(RootSearchGate.accepts(entry("jira", pattern), text: "ABC-12", preference: CommandPreference(inRootSearch: false)))
        XCTAssertTrue(RootSearchGate.searches(any, preference: CommandPreference(inRootSearch: false)), "an alias still reaches it")
        XCTAssertFalse(RootSearchGate.searches(any, preference: CommandPreference(enabled: false)))
    }

    func testTheMainSearchSwitchSavesAndOldFilesLoad() throws {
        let decode = { (json: String) in try JSONDecoder().decode(CommandPreference.self, from: Data(json.utf8)) }
        XCTAssertNil(try decode(#"{"alias":"gh","inRootSearch":true}"#).inRootSearch, "an old true was only the default")
        XCTAssertEqual(try decode(#"{"inRootSearch":false}"#).inRootSearch, false, "an old false was a choice")
        let on = CommandPreference(inRootSearch: true)
        XCTAssertEqual(try JSONDecoder().decode(CommandPreference.self, from: JSONEncoder().encode(on)), on)
        let unset = String(decoding: try JSONEncoder().encode(CommandPreference.default), as: UTF8.self)
        XCTAssertFalse(unset.contains("mainSearch"))
    }

    func testDefaultAliasesYieldToTheUserAndToEachOther() {
        var gs = CommandSpec(id: "repos", title: "Repositories", kind: .view, rootSearch: true)
        gs.defaultAlias = "gs"
        var other = CommandSpec(id: "search", title: "Search", kind: .view)
        other.defaultAlias = "gs"
        let registry = [entry("git", gs), entry("other", other), entry("pr", CommandSpec(id: "prs", title: "PRs", kind: .view))]
        let aliases = PaletteIndex.aliases(registry, preferences: [:])
        XCTAssertEqual(aliases[registry[0].key], "gs")
        XCTAssertNil(aliases[registry[1].key], "a default already taken is skipped")
        let mine = PaletteIndex.aliases(registry, preferences: [registry[2].key: CommandPreference(alias: "gs")])
        XCTAssertEqual(mine[registry[2].key], "gs", "the user's alias wins")
        XCTAssertNil(mine[registry[0].key])
        let cleared = PaletteIndex.aliases(registry, preferences: [registry[0].key: CommandPreference(alias: "")])
        XCTAssertNil(cleared[registry[0].key])
        XCTAssertEqual(cleared[registry[1].key], "gs", "the next default takes it")

        var index = PaletteIndex()
        index.setCommands(registry, preferences: [:])
        XCTAssertEqual(index.aliasMatch("gs stackbar")?.entry.commandKey, registry[0].key)
        XCTAssertEqual(index.aliasMatch("gs stackbar")?.rest, "stackbar")
    }

    func testAliasesMayBeSymbolsAndDefaultsAreChecked() throws {
        XCTAssertEqual(CommandPreference.normalizedAlias("#"), "#")
        XCTAssertNil(CommandPreference.normalizedAlias("two words"))
        var spec = CommandSpec(id: "a", title: "A")
        spec.defaultAlias = "gs"
        XCTAssertEqual(spec.problems, [])
        spec.defaultAlias = "#"
        XCTAssertEqual(spec.problems.count, 1, "symbols are the user's to pick")
        let preferences = CommandPreferences(file: nil)
        let key = CommandKey(pluginID: "a", commandID: "a")
        XCTAssertThrowsError(try preferences.set(CommandPreference(alias: "gs"), for: key, otherAliases: ["gs": CommandKey(pluginID: "b", commandID: "b")]))
        try preferences.set(CommandPreference(alias: ""), for: key)
        XCTAssertEqual(preferences[key].alias, "", "cleared, not back to the default")
        let decoded = try JSONDecoder().decode(CommandSpec.self, from: JSONEncoder().encode(CommandSpec(id: "a", title: "A", defaultAlias: "gs")))
        XCTAssertEqual(decoded.defaultAlias, "gs")
    }

    func testFallbacksAreTheUsersListInOrder() {
        let web = entry("io.navbytes.stackbar.quicklinks", CommandSpec(id: "web-search", title: "Search Google", fallback: true))
        let ask = entry("io.navbytes.stackbar.plugins.ask-ai", CommandSpec(id: "ask", title: "Ask AI", kind: .view, fallback: true))
        let todo = entry("io.navbytes.stackbar.plugins.todo", CommandSpec(id: "add", title: "Add a Todo", fallback: true))
        let available = [todo, web, ask]
        XCTAssertEqual(PaletteFallbacks.offered(available, chosen: nil) { _ in .default }.map(\.spec.title), ["Search Google", "Ask AI"])
        XCTAssertEqual(PaletteFallbacks.offered(available, chosen: nil) { $0 == ask.key ? CommandPreference(inRootSearch: false) : .default }.map(\.spec.title),
                       ["Search Google"], "one turned off before lists existed stays off")
        XCTAssertEqual(PaletteFallbacks.offered(available, chosen: [todo.key, web.key]) { _ in .default }.map(\.spec.title), ["Add a Todo", "Search Google"])
        XCTAssertEqual(PaletteFallbacks.offered([web], chosen: [ask.key, web.key]) { _ in .default }.map(\.spec.title), ["Search Google"], "a missing one is skipped")
    }

    func testAnAliasedSearchLeads() {
        let repos = entry("git", CommandSpec(id: "repos", title: "Repositories", kind: .view, rootSearch: true, rootSection: "Repositories"))
        let rows = PaletteRoot.PluginRows(command: repos, rows: [RowNode(key: "1", title: "stackbar", actions: [ActionRef(id: "row/1/Open", title: "Open")])])
        var index = PaletteIndex()
        index.setCommands([entry("x", CommandSpec(id: "stack", title: "Stack Overflow"))], preferences: [:])
        let plain = PaletteRoot.build(query: "gs stack", index: index, ranker: PaletteRanker(query: "gs stack"), plugins: [rows])
        let scoped = PaletteRoot.build(query: "gs stack", index: index, ranker: PaletteRanker(query: "gs stack"), plugins: [rows], scoped: repos.key)
        XCTAssertEqual(scoped.sections.first?.title, "Repositories")
        XCTAssertTrue(scoped.sections.first?.leads == true)
        XCTAssertFalse(plain.sections.first?.leads == true)
    }
}
