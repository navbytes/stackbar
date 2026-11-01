import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class Copies: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    func add(_ text: String) { lock.withLock { texts.append(text) } }
    var all: [String] { lock.withLock { texts } }
}

final class CommandRegistryTests: XCTestCase {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("file.json")
    }

    func testCommandKeysParseAndEncodeAsStrings() throws {
        let key = try XCTUnwrap(CommandKey("dev.navbytes.pr-cockpit/search"))
        XCTAssertEqual(key.pluginID, "dev.navbytes.pr-cockpit")
        XCTAssertEqual(key.commandID, "search")
        XCTAssertNil(CommandKey("no-slash"))
        XCTAssertNil(CommandKey("/search"))
        XCTAssertNil(CommandKey("plugin/Bad Id"))
        let encoded = try JSONEncoder().encode([key: 1])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"dev.navbytes.pr-cockpit\/search":1}"#)
        XCTAssertEqual(try JSONDecoder().decode([CommandKey: Int].self, from: encoded), [key: 1])
    }

    func testRegistryDropsBadCommandsAndPersists() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let registry = CommandRegistry(file: file)
        let changes = Copies()
        registry.onChange = { changes.add("changed") }
        let problems = registry.update(pluginID: "a", pluginName: "A", specs: [
            CommandSpec(id: "one", title: "One"),
            CommandSpec(id: "one", title: "Again"),
            CommandSpec(id: "Bad", title: "Bad"),
            CommandSpec(id: "two", title: "Two", kind: .view),
        ])
        XCTAssertEqual(problems.count, 2)
        XCTAssertEqual(registry.entries.map(\.key.description), ["a/one", "a/two"])
        registry.update(pluginID: "a", pluginName: "A", specs: [CommandSpec(id: "one", title: "One"), CommandSpec(id: "two", title: "Two", kind: .view)])
        XCTAssertEqual(changes.all.count, 1, "an unchanged list is not a change")
        registry.update(pluginID: "b", pluginName: "B", specs: [CommandSpec(id: "x", title: "X")])
        registry.setOrder(["b", "a"])
        XCTAssertEqual(registry.entries.map(\.key.description), ["b/x", "a/one", "a/two"])

        let reloaded = CommandRegistry(file: file)
        XCTAssertEqual(reloaded.entry(CommandKey(pluginID: "a", commandID: "two"))?.spec.kind, .view)
        XCTAssertEqual(reloaded.commands(for: "b").map(\.id), ["x"])

        reloaded.retain(only: ["a"])
        XCTAssertEqual(reloaded.entries.map(\.pluginID), ["a", "a"])
        reloaded.remove(pluginID: "a")
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    func testPreferencesCheckAliasesAndHotkeys() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let preferences = CommandPreferences(file: file)
        let first = CommandKey(pluginID: "a", commandID: "one")
        let second = CommandKey(pluginID: "a", commandID: "two")
        try preferences.set(CommandPreference(alias: " GH ", hotkey: "cmd+shift+p"), for: first)
        XCTAssertEqual(preferences[first].alias, "gh")
        XCTAssertEqual(preferences.command(forAlias: "GH"), first)

        XCTAssertThrowsError(try preferences.set(CommandPreference(alias: "gh"), for: second)) { error in
            XCTAssertEqual(error as? CommandPreferences.Problem, .aliasTaken("gh", by: first))
        }
        XCTAssertThrowsError(try preferences.set(CommandPreference(alias: "two words"), for: second))
        XCTAssertThrowsError(try preferences.set(CommandPreference(hotkey: "shift+p"), for: second))
        XCTAssertThrowsError(try preferences.set(CommandPreference(hotkey: "shift+cmd+p"), for: second)) { error in
            XCTAssertEqual(error as? CommandPreferences.Problem, .hotkeyTaken("shift+cmd+p", by: "a/one"))
        }
        XCTAssertThrowsError(try preferences.set(CommandPreference(hotkey: "ctrl+option+space"), for: second, otherHotkeys: ["ctrl+option+space": "the palette"])) { error in
            XCTAssertEqual(error as? CommandPreferences.Problem, .hotkeyTaken("ctrl+option+space", by: "the palette"))
        }
        // Setting the same command again keeps its own alias and hotkey.
        try preferences.set(CommandPreference(alias: "gh", hotkey: "cmd+shift+p", linksAllowed: true), for: first)

        let reloaded = CommandPreferences(file: file)
        XCTAssertEqual(reloaded[first], CommandPreference(alias: "gh", hotkey: "cmd+shift+p", linksAllowed: true))
        XCTAssertEqual(reloaded[second], .default)
        reloaded.retain(only: [second])
        XCTAssertTrue(reloaded.all.isEmpty)
    }

    func testUsageDecaysWithAHalfLife() {
        final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 0) }
        let clock = Clock()
        let usage = PaletteUsage(file: nil) { clock.now }
        usage.record("x")
        usage.record("x")
        XCTAssertEqual(usage.score("x"), 2, accuracy: 0.001)
        clock.now = clock.now.addingTimeInterval(PaletteUsage.halfLife)
        XCTAssertEqual(usage.score("x"), 1, accuracy: 0.001)
        XCTAssertEqual(usage.score("never"), 0)
    }
}

final class PaletteCommandTests: XCTestCase {
    private func index(preferences: [CommandKey: CommandPreference] = [:]) -> PaletteIndex {
        let registry = CommandRegistry(file: nil)
        registry.update(pluginID: "gh", pluginName: "PR Cockpit", specs: [
            CommandSpec(id: "search", title: "Search Pull Requests", keywords: ["github"], kind: .view),
            CommandSpec(id: "refresh", title: "Refresh Reviews"),
            CommandSpec(id: "hidden", title: "Hidden Thing"),
        ])
        var index = PaletteIndex()
        index.update(pluginID: "clock", pluginName: "Clock", panel: .list(children: [
            .row(RowNode(key: "x", title: "Refresh Clock", actions: [ActionRef(id: "row/x/Refresh", title: "Refresh")])),
        ]))
        index.setCommands(registry.entries, preferences: preferences)
        return index
    }

    func testCommandsAreFoundByTitleKeywordAndAlias() {
        let search = CommandKey(pluginID: "gh", commandID: "search")
        let index = index(preferences: [
            search: CommandPreference(alias: "pr"),
            CommandKey(pluginID: "gh", commandID: "hidden"): CommandPreference(enabled: false),
        ])
        XCTAssertFalse(index.all.contains { $0.title == "Hidden Thing" }, "disabled commands are left out")
        XCTAssertEqual(index.search("github").first?.commandKey, search)
        XCTAssertEqual(index.search("pr").first?.commandKey, search, "an exact alias wins")
        XCTAssertEqual(index.search("refresh").first?.commandKey, CommandKey(pluginID: "gh", commandID: "refresh"), "commands rank above panel entries")
        let match = index.aliasMatch("PR  react native ")
        XCTAssertEqual(match?.entry.commandKey, search)
        XCTAssertEqual(match?.rest, "react native")
        XCTAssertNil(index.aliasMatch("pr"))
        XCTAssertNil(index.aliasMatch("zz react"))
    }

    func testUsageLiftsWhatWasUsed() throws {
        let index = index()
        let usage = PaletteUsage(file: nil)
        let clock = try XCTUnwrap(index.search("refresh").first { $0.pluginID == "clock" })
        for _ in 0..<20 { usage.record(clock.id) }
        XCTAssertEqual(index.search("refresh", usage: usage).first?.id, clock.id)
        XCTAssertEqual(index.search("", usage: usage).first?.id, clock.id)
    }

    func testRowNavigateActionsBecomeEntries() {
        var index = PaletteIndex()
        let target = CommandTarget(command: "details", arguments: ["id": "7"])
        index.update(pluginID: "p", pluginName: "P", panel: .row(RowNode(key: "7", title: "Issue 7", actions: [ActionRef(id: "row/7/Details", title: "Details", navigate: target)])))
        XCTAssertEqual(index.entries.first?.kind, .navigate(target))
    }
}

final class CommandLinkAndViewStateTests: XCTestCase {
    func testLinksRoundTrip() throws {
        let link = try XCTUnwrap(CommandLink("stackbar://commands/dev.navbytes.pr-cockpit/search?repo=a%2Fb&q=fix%20it"))
        XCTAssertEqual(link.key, CommandKey(pluginID: "dev.navbytes.pr-cockpit", commandID: "search"))
        XCTAssertEqual(link.arguments, ["repo": "a/b", "q": "fix it"])
        XCTAssertEqual(CommandLink(link.url), link)
        XCTAssertNil(CommandLink("https://commands/a/b"))
        XCTAssertNil(CommandLink("stackbar://settings/a/b"))
        XCTAssertNil(CommandLink("stackbar://commands/a"))
        XCTAssertNil(CommandLink("stackbar://commands/a/Bad"))
    }

    func testViewStateKeepsOneQueryInFlightAndDropsStaleTrees() {
        var state = ViewSessionState(session: 1, query: CommandQuery(text: ""))
        XCTAssertEqual(state.open(), .open(seq: 1, query: CommandQuery(text: "")))
        XCTAssertNil(state.change(CommandQuery(text: "a")), "one in flight already")
        XCTAssertNil(state.change(CommandQuery(text: "ab")))
        XCTAssertTrue(state.isSearching)
        let first = state.received(seq: 1, root: .text("1", style: .body, role: .primary))
        XCTAssertTrue(first.show)
        XCTAssertEqual(first.next, .update(seq: 2, query: CommandQuery(text: "ab")), "only the newest pending query is sent")
        XCTAssertTrue(state.isSearching)
        let second = state.received(seq: 2, root: .text("2", style: .body, role: .primary))
        XCTAssertTrue(second.show)
        XCTAssertNil(second.next)
        XCTAssertFalse(state.isSearching)
        XCTAssertFalse(state.received(seq: 1, root: .text("old", style: .body, role: .primary)).show, "older trees are dropped")
        XCTAssertNil(state.change(CommandQuery(text: "ab")), "the same query sends nothing")
        XCTAssertEqual(state.change(CommandQuery(text: "abc")), .update(seq: 3, query: CommandQuery(text: "abc")))
    }

    func testOpenAllowsSafeSchemesAndDeclaredOnes() throws {
        let plain = Manifest(id: "p", name: "P")
        XCTAssertNoThrow(try HostServices.openTarget("https://example.com", granted: plain).get())
        XCTAssertNoThrow(try HostServices.openTarget("mailto:a@b.c", granted: plain).get())
        XCTAssertThrowsError(try HostServices.openTarget("slack://open", granted: plain).get())
        XCTAssertThrowsError(try HostServices.openTarget("/tmp", granted: plain).get())
        XCTAssertThrowsError(try HostServices.openTarget("not a url", granted: plain).get())

        let slack = Manifest(id: "p", name: "P", capabilities: [.openURLs(schemes: ["Slack"])])
        XCTAssertNoThrow(try HostServices.openTarget("slack://open", granted: slack).get())
        let anything = Manifest(id: "p", name: "P", capabilities: [.openURLs(schemes: ["*"])])
        XCTAssertNoThrow(try HostServices.openTarget("raycast://x", granted: anything).get())
        XCTAssertEqual(try HostServices.openTarget("/tmp", granted: anything).get().path, "/tmp")
        XCTAssertThrowsError(try HostServices.openTarget("/does/not/exist/\(UUID())", granted: anything).get())
    }

    func testProgramsAreRecognised() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("run.sh")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        let note = directory.appendingPathComponent("note.txt")
        try Data("hi".utf8).write(to: note)
        XCTAssertFalse(HostServices.isProgram(script))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        XCTAssertTrue(HostServices.isProgram(script))
        XCTAssertFalse(HostServices.isProgram(note))
        XCTAssertFalse(HostServices.isProgram(directory))
        XCTAssertTrue(HostServices.isProgram(URL(fileURLWithPath: "/Applications/Safari.app")))
    }
}

final class CommandRunnerTests: XCTestCase {
    func testRunsCommandsOnARealPlugin() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copies = Copies()
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: HostServices.Platform(copy: copies.add))
        let registry = CommandRegistry(file: nil)
        let supervisor = try PluginSupervisor.make(executable: PluginSupervisorTests.helper("FixturePlugin"), services: services) { update in
            if case .commands(let specs) = update { registry.update(pluginID: "fixture", pluginName: "Fixture", specs: specs) }
        }
        let runner = CommandRunner(registry: registry, services: services, timeout: 1) { id in
            id == "fixture" ? .supervisor(supervisor) : id == "waiting" ? .unavailable("waiting for your approval") : nil
        }
        await supervisor.start()
        let listed = await waitUntil { registry.entries.count == 8 }
        XCTAssertTrue(listed, "commands reach the registry: \(registry.entries.map(\.key))")
        func key(_ id: String) -> CommandKey { CommandKey(pluginID: "fixture", commandID: id) }

        var outcome = await runner.run(key("bump"), source: .palette)
        XCTAssertEqual(outcome, CommandRunner.Outcome(message: "count 1", isError: false))
        outcome = await runner.run(key("bump"), arguments: ["by": "5"], source: .hotkey)
        XCTAssertEqual(outcome.message, "count 6")

        outcome = await runner.run(key("copy-count"), source: .palette)
        XCTAssertEqual(outcome, CommandRunner.Outcome(message: "Copied", isError: false))
        XCTAssertEqual(copies.all, ["6"])

        outcome = await runner.run(key("inside"), source: .link)
        XCTAssertTrue(outcome.isError)
        outcome = await runner.run(key("inside"), source: .palette)
        XCTAssertFalse(outcome.isError)
        outcome = await runner.run(key("echo"), source: .palette)
        XCTAssertEqual(outcome, .failure("Echo opens a view"))
        outcome = await runner.run(key("slow"), source: .palette)
        XCTAssertEqual(outcome, .failure("slow did not answer within 1 seconds"))
        outcome = await runner.run(key("missing"), source: .palette)
        XCTAssertTrue(outcome.isError)
        registry.update(pluginID: "waiting", pluginName: "Waiting", specs: [CommandSpec(id: "go", title: "Go")])
        outcome = await runner.run(CommandKey(pluginID: "waiting", commandID: "go"), source: .palette)
        XCTAssertEqual(outcome, .failure("waiting for your approval"))

        await supervisor.stop()
        outcome = await runner.run(key("bump"), source: .palette)
        XCTAssertEqual(outcome, .failure("Fixture is stopped"))
    }
}

final class CommandIndexingTests: XCTestCase {
    func testOnlyExposedCommandsAreIndexedAndDiffed() throws {
        let registry = CommandRegistry(file: nil)
        registry.update(pluginID: "gh", pluginName: "PR Cockpit", specs: [
            CommandSpec(id: "search", title: "Search Pull Requests", subtitle: "GitHub", keywords: ["github"], kind: .view),
            CommandSpec(id: "inside", title: "Inside", exposure: .stackbarOnly),
            CommandSpec(id: "off", title: "Switched Off"),
            CommandSpec(id: "hidden", title: "Not in Spotlight"),
        ])
        let preferences = CommandPreferences(file: nil)
        try preferences.set(CommandPreference(enabled: false), for: CommandKey(pluginID: "gh", commandID: "off"))
        try preferences.set(CommandPreference(showInSpotlight: false), for: CommandKey(pluginID: "gh", commandID: "hidden"))
        try preferences.set(CommandPreference(alias: "pr"), for: CommandKey(pluginID: "gh", commandID: "search"))
        let usage = PaletteUsage(file: nil)
        for _ in 0..<7 { usage.record("gh/search") }

        let items = CommandIndexing.items(registry: registry, preferences: preferences, usage: usage)
        XCTAssertEqual(items.map(\.id), ["gh/search"])
        XCTAssertEqual(items[0].summary, "PR Cockpit · GitHub")
        XCTAssertEqual(items[0].keywords, ["github", "PR Cockpit", "pr"])
        XCTAssertEqual(items[0].priority, 6)
        XCTAssertEqual(items[0].symbol, "list.bullet.rectangle")

        XCTAssertEqual(CommandIndexing.search("github", registry: registry, preferences: preferences, usage: usage).map(\.id), ["gh/search"])
        XCTAssertTrue(CommandIndexing.search("inside", registry: registry, preferences: preferences, usage: usage).isEmpty)

        var changed = items[0]
        changed.title = "Find Pull Requests"
        let added = CommandIndexItem(id: "gh/new", title: "New", summary: "PR Cockpit", symbol: "command", keywords: [], kind: .run, priority: 0)
        let gone = CommandIndexItem(id: "gh/gone", title: "Gone", summary: "PR Cockpit", symbol: "command", keywords: [], kind: .run, priority: 0)
        let diff = CommandIndexing.diff(from: items + [gone], to: [changed, added])
        XCTAssertEqual(diff.upsert.map(\.id), ["gh/search", "gh/new"])
        XCTAssertEqual(diff.delete, ["gh/gone"])
        XCTAssertTrue(CommandIndexing.diff(from: items, to: items).upsert.isEmpty)

        preferences.spotlightEnabled = false
        XCTAssertTrue(CommandIndexing.items(registry: registry, preferences: preferences, usage: usage).isEmpty)
    }
}
