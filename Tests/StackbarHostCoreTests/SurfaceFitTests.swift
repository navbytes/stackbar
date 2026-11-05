import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Root search gates and budget, opt-in agent tools, widget presses and
/// empty menu bars (openspec surface-fit, protocol 17).
final class SurfaceFitTests: XCTestCase {
    private func view(_ id: String, pattern: String? = nil, fallback: Bool = false) -> CommandSpec {
        CommandSpec(id: id, title: id, kind: .view, rootSearch: true, fallback: fallback, rootPattern: pattern)
    }

    func testRootPatternMustMatchTheWholeText() {
        let issue = view("issue", pattern: #"[A-Za-z][A-Za-z0-9]*-\d+"#)
        XCTAssertTrue(RootSearchGate.accepts(issue, text: "ABC-123"))
        XCTAssertTrue(RootSearchGate.accepts(issue, text: "abc-1"))
        XCTAssertFalse(RootSearchGate.accepts(issue, text: "ABC-123 fix"), "the whole text, not a part")
        XCTAssertFalse(RootSearchGate.accepts(issue, text: "safari"))
        XCTAssertTrue(RootSearchGate.accepts(view("apps"), text: "anything"), "no pattern takes any text")
        XCTAssertFalse(RootSearchGate.accepts(view("bad", pattern: "(["), text: "x"), "a broken pattern takes nothing")
    }

    func testTheUserCanTurnRootSearchAndFallbacksOff() {
        let apps = view("apps")
        XCTAssertFalse(RootSearchGate.accepts(apps, text: "saf", preference: CommandPreference(inRootSearch: false)))
        XCTAssertFalse(RootSearchGate.accepts(apps, text: "saf", preference: CommandPreference(enabled: false)))
        var run = CommandSpec(id: "add", title: "Add", fallback: true)
        XCTAssertTrue(RootSearchGate.offersFallback(run))
        XCTAssertFalse(RootSearchGate.offersFallback(run, preference: CommandPreference(inRootSearch: false)))
        run.fallback = false
        XCTAssertFalse(RootSearchGate.offersFallback(run))
        XCTAssertFalse(RootSearchGate.accepts(CommandSpec(id: "r", title: "R", rootSearch: true), text: "x"), "only views search")
    }

    func testPreferencesSavedBeforeRootSearchStillLoad() throws {
        let old = #"{"enabled":false,"showInSpotlight":true,"linksAllowed":false,"alias":"gh"}"#
        let decoded = try JSONDecoder().decode(CommandPreference.self, from: Data(old.utf8))
        XCTAssertEqual(decoded, CommandPreference(alias: "gh", enabled: false))
        XCTAssertTrue(decoded.inRootSearch)
    }

    func testRootPatternsAreValidatedAndOptional() throws {
        XCTAssertEqual(view("ok", pattern: #"\d+"#).problems, [])
        XCTAssertEqual(view("bad", pattern: "([").problems.count, 1)
        XCTAssertEqual(CommandSpec(id: "run", title: "Run", rootPattern: "x").problems.count, 1, "a pattern needs root search")
        let old = #"{"id":"a","title":"A","kind":"view","rootSearch":true}"#
        XCTAssertNil(try JSONDecoder().decode(CommandSpec.self, from: Data(old.utf8)).rootPattern)
        let spec = view("issue", pattern: #"\d+"#)
        XCTAssertEqual(try JSONDecoder().decode(CommandSpec.self, from: JSONEncoder().encode(spec)), spec)
    }

    func testASlowRootSearchSitsOutAndOneQuickAnswerClearsItsStrikes() {
        let budget = RootSearchBudget(limit: 0.4, strikes: 3, bench: 600)
        let key = CommandKey(pluginID: "p", commandID: "search")
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(budget.record(key, took: 0.9, now: now))
        XCTAssertFalse(budget.record(key, took: 0.9, now: now))
        XCTAssertFalse(budget.record(key, took: 0.1, now: now), "a quick answer resets")
        XCTAssertFalse(budget.record(key, took: 0.9, now: now))
        XCTAssertFalse(budget.record(key, took: 0.9, now: now))
        XCTAssertTrue(budget.record(key, took: 0.9, now: now))
        XCTAssertTrue(budget.isBenched(key, now: now.addingTimeInterval(599)))
        XCTAssertFalse(budget.isBenched(key, now: now.addingTimeInterval(601)))
        budget.record(key, took: 0.9, now: now)
        budget.record(key, took: 0.9, now: now)
        budget.record(key, took: 0.9, now: now)
        budget.forget(pluginID: "p")
        XCTAssertFalse(budget.isBenched(key, now: now), "a restart starts over")
    }

    private func entry(_ title: String) -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: "p." + title, pluginName: "P", title: title, kind: .action(ActionID(title), value: nil))
    }

    func testPatternSectionsLeadThenTheBestMatch() {
        let jira = PaletteSection(title: "Jira", entries: [entry("Fix login")], leads: true)
        let files = PaletteSection(title: "Files", entries: [entry("ABC-123 notes.txt")])
        let apps = PaletteSection(title: "Applications", entries: [entry("Activity Monitor")])
        let ranked = PaletteSection.rank([apps, files, jira], query: "ABC-123")
        XCTAssertEqual(ranked.leads.map(\.title), ["Jira", "Files"], "a pattern match first, then a prefix match")
        XCTAssertEqual(ranked.follows.map(\.title), ["Applications"])
        let sections = PaletteSection.group([], query: "ABC-123", plugins: [apps, files, jira]) { _ in false }
        XCTAssertEqual(sections.map(\.title), ["Jira", "Files", "Applications"])
    }

    func testFollowingSectionsGoBestMatchFirst() {
        let weak = PaletteSection(title: "Weak", entries: [entry("Xylophone notes")])
        let strong = PaletteSection(title: "Strong", entries: [entry("Mynotes")])
        let none = PaletteSection(title: "None", entries: [entry("42")])
        XCTAssertEqual(PaletteSection.rank([none, weak, strong], query: "notes").follows.map(\.title), ["Strong", "Weak", "None"])
    }

    func testOptInToolsStayOffUntilAllowed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("consent-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("agent-tools.json")
        let specs = [ToolSpec(name: "recent_clips", description: "", optIn: true), ToolSpec(name: "count", description: "")]
        let consent = AgentConsent(file: file)
        XCTAssertFalse(consent.allows(pluginID: "clip", tool: "recent_clips", specs: specs))
        XCTAssertTrue(consent.allows(pluginID: "clip", tool: "count", specs: specs))
        XCTAssertFalse(consent.allows(pluginID: "clip", tool: AgentConsent.panel, specs: specs), "an opt-in tool keeps the panel private")
        XCTAssertTrue(consent.allows(pluginID: "other", tool: AgentConsent.panel, specs: [specs[1]]))
        consent.set(true, pluginID: "clip", tool: "recent_clips", specs: specs)
        consent.set(false, pluginID: "clip", tool: "count", specs: specs)
        let reloaded = AgentConsent(file: file)
        XCTAssertTrue(reloaded.allows(pluginID: "clip", tool: "recent_clips", specs: specs))
        XCTAssertFalse(reloaded.allows(pluginID: "clip", tool: "count", specs: specs))
        reloaded.set(true, pluginID: "clip", tool: "count", specs: specs)
        XCTAssertTrue(AgentConsent(file: file).allows(pluginID: "clip", tool: "count", specs: specs), "back to the default")
    }

    func testToolSpecsWithoutOptInStillDecode() throws {
        let old = #"{"name":"count","description":"How many","parameters":[]}"#
        XCTAssertFalse(try JSONDecoder().decode(ToolSpec.self, from: Data(old.utf8)).optIn)
        let private_ = ToolSpec(name: "clips", description: "x", optIn: true)
        XCTAssertEqual(try JSONDecoder().decode(ToolSpec.self, from: JSONEncoder().encode(private_)), private_)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(ToolSpec(name: "a", description: "b")), as: UTF8.self).contains("optIn"))
    }

    func testWidgetPressesAreReadOnceAndStaleOnesDropped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("presses-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = WidgetActionInbox(directory: directory)
        let now = Date()
        try inbox.post(WidgetAction(pluginID: "music", action: "next", pressedAt: now.addingTimeInterval(-1)))
        try inbox.post(WidgetAction(pluginID: "awake", action: "toggle", value: .bool(true), pressedAt: now))
        try inbox.post(WidgetAction(pluginID: "old", action: "x", pressedAt: now.addingTimeInterval(-600)))
        let drained = inbox.drain(now: now)
        XCTAssertEqual(drained.map(\.pluginID), ["music", "awake"], "oldest first, stale dropped")
        XCTAssertEqual(drained.last?.value, .bool(true))
        XCTAssertEqual(inbox.drain(now: now), [], "each press is read once")
    }

    func testOnlyContentWithNoNodesIsNothing() {
        XCTAssertTrue(ViewNode.stack(axis: .horizontal, children: []).isNothing)
        XCTAssertTrue(ViewNode.stack(axis: .horizontal, children: [.stack(axis: .vertical, children: [])]).isNothing)
        XCTAssertFalse(ViewNode.label("", symbol: "command").isNothing)
        XCTAssertFalse(ViewNode.stack(axis: .horizontal, children: [.divider]).isNothing, "panel-only nodes show the plugin's name instead")
    }

    func testWidgetControlsActInTheLedger() {
        XCTAssertTrue(SurfaceParity.treatment(.button, on: .widget).contains("sends the action"))
        XCTAssertEqual(SurfaceParity.treatment(.slider, on: .widget), "Drawn disabled")
    }
}

final class AgentConsentGatewayTests: XCTestCase {
    func testTurnedOffToolsAreNotListedOrCallable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gateway-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let supervisor = try PluginSupervisor.make(executable: PluginSupervisorTests.helper("FixturePlugin"))
        await supervisor.start()
        _ = await waitUntil { await supervisor.tools.count == 2 }
        let consent = AgentConsent(file: directory.appendingPathComponent("agent-tools.json"))
        let specs = await supervisor.tools
        consent.set(false, pluginID: supervisor.manifest.id, tool: "add", specs: specs)
        consent.set(false, pluginID: supervisor.manifest.id, tool: AgentConsent.panel, specs: specs)
        let tools = RuntimeTools(consent: consent) { [supervisor] }
        let listed = await tools.tools().map(\.name)
        XCTAssertEqual(listed, ["stackbar_plugins", "stackbar_read", "fixture__count"])
        let added = await tools.call("fixture__add", arguments: ["amount": 4])
        XCTAssertTrue(added.isError)
        let read = await tools.call("stackbar_read", arguments: ["plugin": "fixture"])
        XCTAssertTrue(read.isError)
        await supervisor.stop()
    }
}
