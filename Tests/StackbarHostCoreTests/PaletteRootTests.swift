import StackbarHostCore
import StackbarProtocol
import XCTest

final class PaletteRootTests: XCTestCase {
    private func command(_ id: String, _ title: String, plugin: String = "gh", kind: CommandSpec.Kind = .run, arguments: [ArgumentSpec] = [],
                         rootSection: String? = nil, fallback: Bool = false) -> CommandRegistry.Entry {
        CommandRegistry.Entry(pluginID: plugin, pluginName: plugin.capitalized,
                              spec: CommandSpec(id: id, title: title, kind: kind, arguments: arguments, rootSearch: rootSection != nil, rootSection: rootSection, fallback: fallback))
    }

    private func index(_ commands: [CommandRegistry.Entry], aliases: [String: String] = [:]) -> PaletteIndex {
        var index = PaletteIndex()
        var preferences: [CommandKey: CommandPreference] = [:]
        for (id, alias) in aliases { preferences[CommandKey(pluginID: "gh", commandID: id)] = CommandPreference(alias: alias) }
        index.setCommands(commands, preferences: preferences)
        return index
    }

    private func build(_ query: String, _ index: PaletteIndex, store: [PaletteIndex.Entry] = [], plugins: [PaletteRoot.PluginRows] = [],
                       fallbacks: [CommandRegistry.Entry] = [], favorites: [String] = []) -> PaletteRoot {
        PaletteRoot.build(query: query, index: index, ranker: PaletteRanker(query: query), favorites: favorites, store: store, plugins: plugins, fallbacks: fallbacks)
    }

    private func rows(_ command: CommandRegistry.Entry, _ titles: [String]) -> PaletteRoot.PluginRows {
        PaletteRoot.PluginRows(command: command, rows: titles.map { title in
            RowNode(key: title.lowercased(), title: title, actions: [ActionRef(id: ActionID("open-\(title)"), title: "Open App", shortcut: "cmd+o")])
        })
    }

    func testAnAliasPutsItsCommandFirst() {
        let search = command("search", "Search Pull Requests", arguments: [ArgumentSpec("q")])
        let index = index([command("desk", "GitHub Desktop"), search], aliases: ["search": "gh"])
        let root = build("gh react", index, plugins: [rows(command("apps", "Applications", plugin: "apps", kind: .view, rootSection: "Applications"), ["GitHub Desktop"])])
        XCTAssertEqual(root.sections.first?.kind, .results)
        XCTAssertEqual(root.entries.first?.title, "Search Pull Requests")
        XCTAssertEqual(root.input(for: root.entries[0], query: "gh react", index: index), "react")
    }

    func testAnotherCommandsWholeNameBeatsTheAlias() {
        let index = index([command("cockpit", "pr cockpit"), command("search", "Search Pull Requests")], aliases: ["search": "pr"])
        XCTAssertEqual(build("pr cockpit", index).entries.first?.title, "pr cockpit")
    }

    func testPluginRowsAreLimitedRenamedAndKnowTheirView() {
        let apps = command("apps", "Applications", plugin: "apps", kind: .view, rootSection: "Results")
        let root = build("sa", index([]), plugins: [rows(apps, ["Safari", "Sandbox", "Savings", "Saturn"])])
        let section = root.sections.first { $0.kind == .plugin }
        XCTAssertEqual(section?.title, "Results — Apps", "a fixed heading is never reused")
        XCTAssertEqual(section?.entries.count, PaletteRoot.pluginRowLimit)
        let row = root.pluginRow(section!.entries[0])
        XCTAssertEqual(row?.command, apps.key)
        XCTAssertEqual(row?.rowKey, "safari")
        XCTAssertEqual(root.primaryTitle(section!.entries[0]), "Open App")
        XCTAssertFalse(root.canPin(section!.entries[0]))
    }

    func testFallbacksGetTheWholeTextAndCantBePinned() {
        let web = command("web", "Search the Web", plugin: "web", arguments: [ArgumentSpec("q")], fallback: true)
        let index = index([])
        let root = build("cheap flights", index, fallbacks: [web])
        let entry = root.sections.first { $0.kind == .fallback }!.entries[0]
        XCTAssertEqual(root.role(of: entry), .fallback)
        XCTAssertEqual(root.input(for: entry, query: "cheap flights", index: index), "cheap flights")
        XCTAssertFalse(root.canPin(entry))
        XCTAssertTrue(build("", index, fallbacks: [web]).sections.isEmpty, "nothing typed, nothing to fall back on")
    }

    func testStoreSuggestionsShowInTheStoreAndDontLearn() {
        let suggestion = PaletteIndex.Entry(pluginID: "dev.timer", pluginName: "Store", title: "Timers", kind: .open(StoreLink(pluginID: "dev.timer").url.absoluteString))
        let root = build("timers", index([]), store: [suggestion])
        XCTAssertEqual(root.role(of: suggestion), .storeSuggestion)
        XCTAssertEqual(root.primaryTitle(suggestion), "Show in Store")
        XCTAssertFalse(root.learns(suggestion))
        XCTAssertFalse(root.canPin(suggestion))
    }

    func testResultsCanBePinnedAndLeadWhenFavourite() {
        let index = index([command("one", "One"), command("two", "Two", arguments: [ArgumentSpec("x")])])
        let root = build("", index, favorites: ["gh/two"])
        XCTAssertEqual(root.sections.map(\.kind), [.favorites, .commands])
        let two = root.entries[0]
        XCTAssertTrue(root.canPin(two))
        XCTAssertTrue(root.learns(two))
        XCTAssertEqual(root.primaryTitle(two), "Open", "a command with arguments opens its fields")
        XCTAssertEqual(root.primaryTitle(root.entries[1]), "Run")
        XCTAssertEqual(root.input(for: two, query: "", index: index), "")
    }
}
