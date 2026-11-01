import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

/// The host's side of commands, on CommandFixture: file panels, open-with,
/// pasting with the clipboard restored, forms, views of rows and storage
/// grants. Quicklinks' and Snippets' own behaviour is tested in
/// navbytes/stackbar-plugins.
final class CommandFixtureTests: XCTestCase {
    final class Opened: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [(url: String, app: String?)] = []
        func add(_ url: URL, _ app: String?) { lock.withLock { list.append((url.absoluteString, app)) } }
        var all: [(url: String, app: String?)] { lock.withLock { list } }
    }

    private var directory: URL!
    private let system = SimulatedSystem()
    private let opened = Opened()
    private let copies = Copies()

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        system.restoreDelay = .milliseconds(20)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private var services: HostServices {
        let opened = opened
        return HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(
            open: { opened.add($0, nil) },
            openWith: { url, app in opened.add(url, app) },
            copy: copies.add,
            system: system
        ))
    }

    private static let executable = PluginSupervisorTests.helper("CommandFixturePlugin")

    private func session() async throws -> PluginSession {
        let session = PluginSession(source: Self.executable, loader: PluginLoader(builder: nil, sandbox: false), services: services)
        try await session.ensureRunning()
        return session
    }

    private func importLinks(_ json: String, run: () async throws -> CommandResult) async throws {
        system.simulate(chosenFile: ChosenFile(name: "links.json", data: Data(json.utf8)))
        let result = try await run()
        XCTAssertEqual(result, .message("Imported links.json"), "the chosen file reaches the plugin")
    }

    func testCommandResultsOpenWithTheChosenAppAndPasteWithTheClipboardBack() async throws {
        let services = services
        let registry = CommandRegistry(file: nil)
        let supervisor = try PluginSupervisor.make(executable: Self.executable, services: services) { update in
            if case .commands(let specs) = update { registry.update(pluginID: "fixture", pluginName: "Command Fixture", specs: specs) }
        }
        let runner = CommandRunner(registry: registry, services: services, timeout: 10) { id in id == "fixture" ? .supervisor(supervisor) : nil }
        await supervisor.start()
        _ = await waitUntil { registry.entries.count == 5 }
        func key(_ id: String) -> CommandKey { CommandKey(pluginID: "fixture", commandID: id) }

        system.simulate(chosenFile: ChosenFile(name: "links.json", data: Data(#"[{"name": "Search", "url": "https://example.com/?q=x", "app": "Google Chrome"}, {"name": "Temp", "url": "/tmp"}]"#.utf8)))
        let imported = await runner.run(key("import"), source: .palette)
        XCTAssertEqual(imported, CommandRunner.Outcome(message: "Imported links.json", isError: false))
        let listed = await waitUntil { registry.entries.count == 7 }
        XCTAssertTrue(listed, "commands added at run time reach the registry")

        var outcome = await runner.run(key("link-0"), source: .hotkey)
        XCTAssertFalse(outcome.isError, "\(outcome)")
        outcome = await runner.run(key("link-1"), source: .palette)
        XCTAssertFalse(outcome.isError, "\(outcome)")
        // Foundation gives a directory URL a trailing slash; on macOS /tmp is
        // a symlink and gets none.
        XCTAssertEqual(opened.all.map { $0.url.hasSuffix("/") ? String($0.url.dropLast()) : $0.url }, ["https://example.com/?q=x", "file:///tmp"])
        XCTAssertEqual(opened.all.map(\.app), ["com.google.Chrome", nil], "the app the plugin resolved opens the link")

        system.simulateCopy("what the user had")
        outcome = await runner.run(key("greet"), arguments: ["name": "Zoë"], source: .hotkey)
        XCTAssertFalse(outcome.isError, "\(outcome)")
        XCTAssertEqual(system.pastes.last?.content, .text("Hello Zoë!"))
        XCTAssertEqual(system.pastes.last?.options, PasteOptions(restoreClipboard: true, cursorFromEnd: 1))
        let restored = await waitUntil { self.system.readClipboard()?.text == "what the user had" }
        XCTAssertTrue(restored, "the user's copy comes back")
        await supervisor.stop()
    }

    func testExportSavesThroughTheFilePanel() async throws {
        let session = try await session()
        try await importLinks(#"[{"name": "Search", "url": "https://example.com", "app": "Safari"}]"#) { try await session.runCommand("import") }
        let result = try await session.runCommand("export")
        XCTAssertEqual(result, .message("/Users/you/Downloads/links.json"))
        let saved = try XCTUnwrap(system.saved.last)
        XCTAssertEqual(saved.name, "links.json")
        let items = try JSONDecoder().decode([[String: String]].self, from: saved.data)
        XCTAssertEqual(items, [["name": "Search", "url": "https://example.com", "app": "com.apple.Safari"]])
        await session.stop()
    }

    func testAFormValidatesAndAViewListsRowsWithActions() async throws {
        let session = try await session()
        let form = try await session.openView("create")
        let submit = ActionID("view/\(form.session)/form/new")
        try await session.event(submit, value: .fields(["name": .text(""), "url": .text("example.com")]))
        func errors() async -> [String: String] {
            func find(_ node: ViewNode) -> FormNode? {
                if case .form(let form) = node { return form }
                return node.children.lazy.compactMap(find).first
            }
            let fields = await session.commandView(form.session).flatMap(find)?.fields ?? []
            return Dictionary(uniqueKeysWithValues: fields.compactMap { field in field.error.map { (field.name, $0) } })
        }
        let shown = await errors()
        XCTAssertEqual(shown, ["name": "Give it a name", "url": "Needs a scheme"], "the plugin's errors reach the form")
        try await session.event(submit, value: .fields(["name": .text("Docs"), "url": .text("https://docs.example.com")]))
        let cleared = await errors()
        XCTAssertEqual(cleared, [:])
        let created = await session.commands().contains { $0.id == "link-0" && $0.title == "Docs" }
        XCTAssertTrue(created, "a submitted form can add a command")
        await session.closeView(form.session)

        let search = try await session.openView("search")
        XCTAssertEqual(search.root?.rows.map(\.title), ["Docs"])
        let filtered = try await session.updateView(search.session, query: CommandQuery(text: "nothing"))
        XCTAssertEqual(filtered?.rows.count, 0, "the view follows the query")
        let all = try await session.updateView(search.session, query: CommandQuery(text: "doc"))
        let row = try XCTUnwrap(all?.rows.first)
        XCTAssertEqual(row.actions.map(\.title), ["Open", "Copy Link"])
        XCTAssertEqual(row.actions.first?.navigate, CommandTarget(command: "link-0"), "Open pushes the link's own command")
        try await session.event(row.actions[1].id)
        XCTAssertEqual(copies.all, ["https://docs.example.com"])
        await session.stop()
    }

    func testAStorageGrantHoldsMoreThanTheDefault() async throws {
        let big = String(repeating: "x", count: 1_500_000)
        var session = try await session()
        try await importLinks(#"[{"name": "Big", "url": "https://example.com/\#(big)"}]"#) { try await session.runCommand("import") }
        await session.stop()
        session = try await self.session()
        let kept = await session.commands().contains { $0.title == "Big" }
        XCTAssertTrue(kept, "1.5 MB is stored under a 4 MB grant and survives a restart")
        await session.stop()
    }
}
