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
        XCTAssertTrue(root.canPin(section!.entries[0]), "an app is pinned as a snapshot found again by its title")
    }

    func testAPinnedPluginRowShowsFromItsSnapshotWithNothingTyped() {
        let apps = command("apps", "Applications", plugin: "apps", kind: .view, rootSection: "Applications")
        let typed = build("saf", index([]), plugins: [rows(apps, ["Safari"])])
        let safari = typed.entries[0]
        let snapshot = typed.snapshot(safari)
        XCTAssertEqual(snapshot?.query, "Safari")
        XCTAssertEqual(snapshot?.id, safari.learnID, "pinned and used under one id")
        let memory = PaletteMemory(directory: nil)
        XCTAssertTrue(memory.toggleFavorite(safari, row: snapshot))
        XCTAssertTrue(memory.isFavorite(safari), "the live row knows it is pinned")

        let empty = PaletteRoot.build(query: "", index: index([]), ranker: PaletteRanker(query: ""), favorites: memory.favorites.ids,
                                      remembered: memory.favoriteEntries(in: []))
        XCTAssertEqual(empty.sections.first?.kind, .favorites)
        let pinned = empty.entries[0]
        XCTAssertEqual(pinned.kind, .remembered(command: "apps", rowKey: "safari", query: "Safari"))
        XCTAssertEqual(pinned.id, safari.learnID)
        XCTAssertTrue(empty.canPin(pinned))
        XCTAssertTrue(memory.isFavorite(pinned), "and so does its snapshot")
    }

    func testARowAnsweringTheTextsShapeIsNotKept() {
        let calc = CommandRegistry.Entry(pluginID: "calc", pluginName: "Calc",
                                         spec: CommandSpec(id: "calc", title: "Calculator", kind: .view, rootSearch: true, rootPattern: "^[0-9]"))
        let root = build("2+2", index([]), plugins: [rows(calc, ["4"])])
        let answer = root.entries[0]
        XCTAssertFalse(root.canPin(answer))
        XCTAssertNil(root.snapshot(answer))
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

    func testTabHandsTextToAskAIUnlessAnotherFallbackIsChosen() {
        let web = command("web", "Search the Web", plugin: "web", arguments: [ArgumentSpec("q")], fallback: true)
        let ask = command("ask", "Ask AI", plugin: "io.navbytes.stackbar.plugins.ask-ai", arguments: [ArgumentSpec("prompt")], fallback: true)
        XCTAssertNil(PaletteTabTarget.command(saved: nil, fallbacks: [web]), "no Ask AI, no hand-off: Tab moves focus")
        XCTAssertEqual(PaletteTabTarget.command(saved: nil, fallbacks: [web, ask])?.key, ask.key)
        XCTAssertEqual(PaletteTabTarget.command(saved: "web/web", fallbacks: [web, ask])?.key, web.key)
        XCTAssertEqual(PaletteTabTarget.command(saved: "gone/cmd", fallbacks: [web, ask])?.key, ask.key, "a removed choice goes back to the default")
        XCTAssertNil(PaletteTabTarget.command(saved: PaletteTabTarget.off, fallbacks: [web, ask]))

        let root = build("why is the sky blue", index([]), fallbacks: [web, ask])
        let line = PaletteTabTarget.entry(for: ask, in: root)
        XCTAssertEqual(line?.title, "Ask AI")
        XCTAssertEqual(line.map { root.role(of: $0) }, .fallback)
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
