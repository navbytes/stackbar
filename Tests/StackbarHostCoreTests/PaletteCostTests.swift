import Foundation
import StackbarProtocol
@testable import StackbarHostCore
import XCTest

/// The palette's per-keystroke work: what is kept between reads, and what is
/// computed once. The palette's body reads the root several times a pass.
@MainActor
final class PaletteCostTests: XCTestCase {
    private func command(_ id: String, _ title: String, plugin: String = "gh") -> CommandRegistry.Entry {
        CommandRegistry.Entry(pluginID: plugin, pluginName: plugin.capitalized, spec: CommandSpec(id: id, title: title, kind: .run))
    }

    private func index() -> PaletteIndex {
        var index = PaletteIndex()
        index.setCommands([command("a", "Open Pull Requests"), command("b", "Open Issues")], preferences: [:])
        return index
    }

    func testTheRootIsBuiltOnceForUnchangedInputs() {
        var cache = PaletteRootCache()
        var builds = 0
        let index = index()
        func root(_ key: PaletteRootCache.Key) -> PaletteRoot {
            cache.root(for: key) {
                builds += 1
                return PaletteRoot.build(query: key.query, index: index, ranker: PaletteRanker(query: key.query))
            }
        }
        let key = PaletteRootCache.Key(query: "open", index: index.revision, memory: 0, store: 0, rows: 0)
        let first = root(key)
        for _ in 0..<50 { XCTAssertEqual(root(key), first) }
        XCTAssertEqual(builds, 1, "fifty more reads of the same inputs build nothing")

        var changed = key
        changed.rows = 1
        _ = root(changed)
        changed.memory = 1
        _ = root(changed)
        changed.store = 2
        _ = root(changed)
        changed.query = "open i"
        _ = root(changed)
        changed.index += 1
        _ = root(changed)
        XCTAssertEqual(builds, 6, "each input that moves builds once")

        cache.clear()
        _ = root(changed)
        XCTAssertEqual(builds, 7)
    }

    private func command(_ id: String) -> CommandRegistry.Entry {
        CommandRegistry.Entry(pluginID: "dev.t.\(id)", pluginName: id, spec: CommandSpec(id: id, title: id, kind: .view, rootSearch: true))
    }

    private let accepts: (CommandRegistry.Entry, String) -> Bool = { RootSearchGate.accepts($0, text: $1, preference: CommandPreference(inRootSearch: true)) }

    func testRowsStampMovesOnlyWhenWhatIsShownChanges() async {
        let session = RootSearchSession<FakeRootView>(budget: RootSearchBudget())
        let apps = command("apps")
        let open: RootSearchSession<FakeRootView>.Opener = { entry, text in FakeRootView(entry, query: text) }
        session.feed("sl", commands: [apps], accepts: accepts, canOpen: { _ in true }, open: open)
        for _ in 0..<5 { await Task.yield() }
        let view = session.views[apps.key]!
        view.answer(["Slack", "Slides"])
        _ = session.rows()
        let settled = session.rowsStamp
        for _ in 0..<20 { _ = session.rows() }
        XCTAssertEqual(session.rowsStamp, settled, "reading again, unchanged, leaves the stamp alone")

        view.answer(["Slack"])
        _ = session.rows()
        XCTAssertNotEqual(session.rowsStamp, settled, "a new answer moves it")
        let answered = session.rowsStamp
        view.isStopped = true
        _ = session.rows()
        XCTAssertNotEqual(session.rowsStamp, answered, "a view that stops leaves the root")
    }

    func testAPluginThatNeverAnswersIsBenched() async {
        var clock = Date(timeIntervalSince1970: 0)
        let session = RootSearchSession<FakeRootView>(budget: RootSearchBudget(limit: 0.4, strikes: 2, bench: 600), now: { clock })
        let hung = command("hung")
        let open: RootSearchSession<FakeRootView>.Opener = { entry, text in FakeRootView(entry, query: text) }
        session.feed("sl", commands: [hung], accepts: accepts, canOpen: { _ in true }, open: open)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNotNil(session.views[hung.key])
        // It never answers; each new text finds the last one still waiting.
        for typed in ["sla", "slac", "slack"] {
            clock = clock.addingTimeInterval(1)
            session.feed(typed, commands: [hung], accepts: accepts, canOpen: { _ in true }, open: open)
        }
        XCTAssertTrue(session.budget.isBenched(hung.key, now: clock), "waits longer than the limit, twice, bench it")
        session.feed("slack!", commands: [hung], accepts: accepts, canOpen: { _ in true }, open: open)
        XCTAssertTrue(session.views.isEmpty, "and its view closes")
    }

    func testAFastTypistDoesNotBenchAQuickPlugin() async {
        var clock = Date(timeIntervalSince1970: 0)
        let session = RootSearchSession<FakeRootView>(budget: RootSearchBudget(limit: 0.4, strikes: 2, bench: 600), now: { clock })
        let apps = command("apps")
        let open: RootSearchSession<FakeRootView>.Opener = { entry, text in FakeRootView(entry, query: text) }
        session.feed("sl", commands: [apps], accepts: accepts, canOpen: { _ in true }, open: open)
        for _ in 0..<5 { await Task.yield() }
        let view = session.views[apps.key]!
        for typed in ["sla", "slac", "slack", "slack "] {
            clock = clock.addingTimeInterval(0.1)
            session.feed(typed, commands: [apps], accepts: accepts, canOpen: { _ in true }, open: open)
            _ = view
        }
        XCTAssertFalse(session.budget.isBenched(apps.key, now: clock), "text typed within the limit of the last is not a slow answer")
    }

    func testRankingScoresEachRowOnceAndKeepsItsOrder() {
        func entry(_ title: String) -> PaletteIndex.Entry {
            PaletteIndex.Entry(pluginID: "p", pluginName: "P", title: title, kind: .action(ActionID("a/\(title)"), value: nil))
        }
        let ranker = PaletteRanker(query: "sl")
        let sections = [
            PaletteSection(title: "Apps", entries: [entry("Notes"), entry("Slack")]),
            PaletteSection(title: "Files", entries: [entry("Slides")], leads: true),
        ]
        let ranked = PaletteSection.rank(sections, results: [entry("Result")], ranker: ranker)
        XCTAssertEqual(ranked.map(\.title).first, "Files", "a pattern-led section leads")
        XCTAssertEqual(ranked.first { $0.kind == .topHit }?.entries.map(\.title), ["Slack"], "the best row is lifted out of its section")
        XCTAssertEqual(ranked.first { $0.title == "Apps" }?.entries.map(\.title), ["Notes"])
    }

    func testRootEntriesAreTheSectionsFlattened() {
        let root = PaletteRoot.build(query: "open", index: index(), ranker: PaletteRanker(query: "open"))
        XCTAssertEqual(root.entries, root.sections.flatMap(\.entries))
        XCTAssertFalse(root.entries.isEmpty)
    }

    func testStoreSuggestionsBreakTiesByStoreThenNameAndSkipReplacedPlugins() {
        func listing(_ id: String, _ name: String, replaces: [String]? = nil) -> PluginIndex.Entry {
            var entry = PluginIndex.Entry(id: id, name: name, version: "1.0.0", publisher: "n", bundle: "b", sha256: "0", capabilities: [])
            entry.replaces = replaces
            return entry
        }
        let first = PluginStore.Catalog(source: .init(url: URL(string: "https://one.example.com/index.json")!), index: PluginIndex(name: "One", plugins: [
            listing("dev.t.timer-b", "Timer B"), listing("dev.t.timer-a", "Timer A"), listing("dev.t.old-timer", "Old Timer"),
        ]))
        let second = PluginStore.Catalog(source: .init(url: URL(string: "https://two.example.com/index.json")!), index: PluginIndex(name: "Two", plugins: [
            listing("dev.t.timer-c", "Timer C", replaces: ["dev.t.old-timer"]),
        ]))
        let found = StoreListing.paletteSuggestions([first, second], query: "timer", installed: .init(), limit: 5)
        XCTAssertEqual(found.map(\.title), ["Timer A", "Timer B", "Timer C"], "the plugin another replaces is left out; ties go by store, then name")
    }
}
