import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class SnippetsTests: XCTestCase {
    private var directory: URL!
    private let system = SimulatedSystem()

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        system.restoreDelay = .milliseconds(20)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private var services: HostServices {
        HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system))
    }

    private func session() async throws -> PluginSession {
        let session = PluginSession(source: PluginSupervisorTests.helper("SnippetsPlugin"), loader: PluginLoader(builder: nil, sandbox: false), services: services)
        try await session.ensureRunning()
        return session
    }

    private static let raycastExport = """
    [
      {"name": "Signature", "text": "-- \\n{argument name=\\"who\\" default=\\"Nav\\"}", "keyword": ";sig"},
      {"name": "Reply", "text": "Hi {argument name=\\"name\\"},\\n\\n{cursor}\\n\\n{snippet name=\\"Signature\\"}", "keyword": ";re"},
      {"name": "Today", "text": "{date: yyyy-MM-dd} at {time: HH:mm}"},
      {"name": "Signature", "text": "-- \\n{argument name=\\"who\\" default=\\"Nav\\"}"},
      {"name": "Spaced", "text": "x", "keyword": "has space"},
      {"name": "Too many", "text": "{argument name=a}{argument name=b}{argument name=c}{argument name=d}"}
    ]
    """

    private func importSample(_ session: PluginSession) async throws -> String {
        system.simulate(chosenFile: ChosenFile(name: "snippets.json", data: Data(Self.raycastExport.utf8)))
        let result = try await session.runCommand("import")
        guard case .message(let message?) = result else { XCTFail("\(result)"); return "" }
        return message
    }

    private func command(_ session: PluginSession, titled title: String) async throws -> CommandSpec {
        let found = await session.commands().first { $0.title == title }
        return try XCTUnwrap(found, "no command \(title)")
    }

    func testImportingARaycastExport() async throws {
        let session = try await session()
        let message = try await importSample(session)
        XCTAssertTrue(message.hasPrefix("Imported 4, skipped 1 duplicate, skipped 1 that didn't parse"), message)
        XCTAssertTrue(message.contains("left out keywords already taken or not allowed: has space"), message)
        let again = try await importSample(session)
        XCTAssertTrue(again.hasPrefix("Imported 0, skipped 5 duplicates"), again)

        let today = try await command(session, titled: "Today")
        XCTAssertEqual(today.subtitle, #"{date format="yyyy-MM-dd"} at {time format="HH:mm"}"#, "the old shorthand is modernised")
        await session.stop()
    }

    func testEachSnippetPastesWithItsArgumentsAndCursor() async throws {
        let session = try await session()
        _ = try await importSample(session)
        let reply = try await command(session, titled: "Reply")
        XCTAssertTrue(reply.id.hasPrefix("sn-"))
        XCTAssertEqual(reply.arguments.map(\.name), ["name", "who"], "an included snippet's arguments are asked for too")
        XCTAssertEqual(reply.arguments.map(\.required), [true, false])
        XCTAssertTrue(reply.keywords.contains(";re"))

        let result = try await session.runCommand(reply.id, arguments: ["name": "Zoë"])
        let tail = "\n\n-- \nNav"
        XCTAssertEqual(result, .paste("Hi Zoë,\n\n" + tail, cursorFromEnd: tail.count))

        // Grapheme clusters, not UTF-16: one ← per character the user sees.
        let reply2 = try await session.runCommand(reply.id, arguments: ["name": "A", "who": "🇸🇬 e\u{301}"])
        guard case .paste(let text, let cursor) = reply2 else { return XCTFail("\(reply2)") }
        XCTAssertTrue(text.hasSuffix("🇸🇬 e\u{301}"))
        XCTAssertEqual(cursor, "\n\n-- \n🇸🇬 é".count)
        XCTAssertEqual(cursor, 9)

        let missing = try await session.runCommand(reply.id)
        guard case .failure(let message) = missing else { return XCTFail("\(missing)") }
        XCTAssertTrue(message.contains("needs name"), message)
        await session.stop()
    }

    func testRunningASnippetPastesAndRestoresTheClipboard() async throws {
        let services = services
        let registry = CommandRegistry(file: nil)
        let supervisor = try PluginSupervisor.make(executable: PluginSupervisorTests.helper("SnippetsPlugin"), services: services) { update in
            if case .commands(let specs) = update { registry.update(pluginID: "snippets", pluginName: "Snippets", specs: specs) }
        }
        let runner = CommandRunner(registry: registry, services: services, timeout: 10) { id in id == "snippets" ? .supervisor(supervisor) : nil }
        await supervisor.start()
        _ = await waitUntil { registry.entries.count == 4 }
        system.simulate(chosenFile: ChosenFile(name: "s.json", data: Data(#"[{"name": "Hello", "text": "Hello {clipboard | uppercase}{cursor}!"}]"#.utf8)))
        _ = await runner.run(CommandKey(pluginID: "snippets", commandID: "import"), source: .palette)
        let listed = await waitUntil { registry.entries.count == 5 }
        XCTAssertTrue(listed)
        let hello = try XCTUnwrap(registry.entries.first { $0.spec.title == "Hello" })

        system.simulateCopy("world")
        let outcome = await runner.run(hello.key, source: .hotkey)
        XCTAssertFalse(outcome.isError, "\(outcome)")
        XCTAssertEqual(system.pastes.last?.content, .text("Hello WORLD!"))
        XCTAssertEqual(system.pastes.last?.options, PasteOptions(restoreClipboard: true, cursorFromEnd: 1))
        let restored = await waitUntil { self.system.readClipboard()?.text == "world" }
        XCTAssertTrue(restored, "the user's copy comes back")
        await supervisor.stop()
    }

    func testTheFormValidates() async throws {
        let session = try await session()
        _ = try await importSample(session)
        let opened = try await session.openView("create")
        let submit = ActionID("view/\(opened.session)/form/new")
        func errors(_ fields: [String: String]) async throws -> String {
            try await session.event(submit, value: .fields(fields.mapValues { .text($0) }))
            return TreeTextRenderer.render(await session.commandView(opened.session) ?? .empty(title: ""))
        }
        var text = try await errors(["name": "", "text": "{cursor} and {cursor}", "keyword": "a b"])
        XCTAssertTrue(text.contains("Give it a name"), text)
        XCTAssertTrue(text.contains("Use {cursor} once"), text)
        XCTAssertTrue(text.contains("no spaces, quotes or backticks"), text)
        text = try await errors(["name": "Loop", "text": #"{snippet name="Loop"}"#])
        XCTAssertTrue(text.contains("can't include itself"), text)
        text = try await errors(["name": "Deep", "text": #"{snippet name="Reply"}"#])
        XCTAssertTrue(text.contains("one level deep"), text)
        text = try await errors(["name": "Typo", "text": "{clipbaord}"])
        XCTAssertTrue(text.contains("{clipbaord} is not a placeholder"), text)
        text = try await errors(["name": "Taken", "text": "x", "keyword": ";sig"])
        XCTAssertTrue(text.contains("Another snippet has the keyword ;sig"), text)

        _ = try await errors(["name": "Thanks", "text": "Thanks!\n{snippet name=\"Signature\"}", "keyword": ";ty", "tags": "email"])
        let created = try await command(session, titled: "Thanks")
        XCTAssertTrue(created.keywords.contains("email"))
        let ran = try await session.runCommand(created.id)
        XCTAssertEqual(ran, .paste("Thanks!\n-- \nNav", cursorFromEnd: 0))
        await session.stop()
    }

    func testSearchShowsAPreviewAndExportRoundTrips() async throws {
        let session = try await session()
        _ = try await importSample(session)
        let opened = try await session.openView("search")
        let root = try XCTUnwrap(opened.root)
        let text = TreeTextRenderer.render(root)
        XCTAssertTrue(text.contains("Reply"), text)
        XCTAssertTrue(text.contains("Copy"), text)
        let previews = root.rows.compactMap { $0.preview?.text }
        XCTAssertTrue(previews.contains("Hi ‹name›,\n\n\n\n-- \nNav"), "\(previews)")

        let result = try await session.runCommand("export")
        guard case .message(let message?) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(message, "Exported 4 to /Users/you/Downloads/Snippets.json")
        let saved = try XCTUnwrap(system.saved.last)
        let items = try JSONDecoder().decode([[String: String]].self, from: saved.data)
        XCTAssertEqual(items.first { $0["name"] == "Signature" }?["keyword"], ";sig")
        XCTAssertNil(items.first { $0["name"] == "Spaced" }?["keyword"])
        await session.stop()
    }
}
