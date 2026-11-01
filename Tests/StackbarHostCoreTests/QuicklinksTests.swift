import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class QuicklinksTests: XCTestCase {
    final class Opened: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [(url: String, app: String?)] = []
        func add(_ url: URL, _ app: String?) { lock.withLock { list.append((url.absoluteString, app)) } }
        var all: [(url: String, app: String?)] { lock.withLock { list } }
    }

    private var directory: URL!
    private let system = SimulatedSystem()
    private let opened = Opened()

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func session() async throws -> PluginSession {
        let opened = opened
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(
            open: { opened.add($0, nil) },
            openWith: { url, app in opened.add(url, app) },
            system: system
        ))
        let session = PluginSession(source: PluginSupervisorTests.helper("QuicklinksPlugin"), loader: PluginLoader(builder: nil, sandbox: false), services: services)
        try await session.ensureRunning()
        return session
    }

    private static let raycastExport = """
    [
      {"name": "GitHub Search", "link": "https://github.com/search?q={argument name=\\"query\\"}&type={argument name=\\"type\\" default=\\"code\\"}", "openWith": "Google Chrome"},
      {"name": "Temp", "link": "/tmp"},
      {"name": "Translate", "link": "translate.google.com/?text={selection}"},
      {"name": "Temp", "link": "/tmp"},
      {"name": "Too many", "link": "{argument name=a}{argument name=b}{argument name=c}{argument name=d}"},
      {"name": "Notes", "link": "https://notes.example.com/{date format=\\"yyyy-MM-dd\\"}", "openWith": "Nonexistent Browser"}
    ]
    """

    private func importSample(_ session: PluginSession) async throws -> CommandResult {
        system.simulate(chosenFile: ChosenFile(name: "quicklinks.json", data: Data(Self.raycastExport.utf8)))
        return try await session.runCommand("import")
    }

    private func command(_ session: PluginSession, titled title: String) async throws -> CommandSpec {
        let found = await session.commands().first { $0.title == title }
        return try XCTUnwrap(found, "no command \(title)")
    }

    func testImportingARaycastExport() async throws {
        let session = try await session()
        let result = try await importSample(session)
        guard case .message(let message?) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(message.hasPrefix("Imported 4, skipped 1 duplicate, skipped 1 that didn't parse"), message)
        XCTAssertTrue(message.contains("Nonexistent Browser, which isn't installed"), message)

        // Importing again skips them all.
        let again = try await importSample(session)
        guard case .message(let second?) = again else { return XCTFail("\(again)") }
        XCTAssertTrue(second.hasPrefix("Imported 0, skipped 5 duplicates"), second)
        await session.stop()
    }

    func testEachQuicklinkIsACommandWithItsArguments() async throws {
        let session = try await session()
        _ = try await importSample(session)
        let search = try await command(session, titled: "GitHub Search")
        XCTAssertTrue(search.id.hasPrefix("ql-"))
        XCTAssertEqual(search.arguments.map(\.name), ["query", "type"])
        XCTAssertEqual(search.arguments.map(\.required), [true, false])
        XCTAssertTrue(search.keywords.contains("github.com"))

        let result = try await session.runCommand(search.id, arguments: ["query": "swift actors"])
        XCTAssertEqual(result, .open(url: "https://github.com/search?q=swift%20actors&type=code", app: "com.google.Chrome"))

        let missing = try await session.runCommand(search.id)
        guard case .failure(let message) = missing else { return XCTFail("\(missing)") }
        XCTAssertTrue(message.contains("needs query"), message)

        let temp = try await command(session, titled: "Temp")
        let tempResult = try await session.runCommand(temp.id)
        XCTAssertEqual(tempResult, .open(url: "/tmp", app: nil))

        let translate = try await command(session, titled: "Translate")
        let context = InvocationContext(frontmostApp: .init(bundleID: "com.apple.Safari", name: "Safari"), selectedText: "bonjour à tous")
        let translated = try await session.runCommand(translate.id, context: context)
        XCTAssertEqual(translated, .open(url: "https://translate.google.com/?text=bonjour%20%C3%A0%20tous", app: nil))
        await session.stop()
    }

    func testCreatingAndEditingWithTheForm() async throws {
        let session = try await session()
        let opened = try await session.openView("create")
        let submit = ActionID("view/\(opened.session)/form/new")
        // Invalid: no name, and a placeholder typo.
        try await session.event(submit, value: .fields(["name": .text(""), "link": .text("https://x.com/{clipbaord}")]))
        let errors = TreeTextRenderer.render(await session.commandView(opened.session) ?? .empty(title: ""))
        XCTAssertTrue(errors.contains("Give it a name"), errors)
        XCTAssertTrue(errors.contains("{clipbaord} is not a placeholder"), errors)
        let none = await session.commands().allSatisfy { !$0.id.hasPrefix("ql-") }
        XCTAssertTrue(none)

        try await session.event(submit, value: .fields(["name": .text("Search Docs"), "link": .text("docs.example.com/?q={argument}"), "tags": .text("work, docs"), "app": .text("")]))
        let created = try await command(session, titled: "Search Docs")
        XCTAssertEqual(created.arguments.map(\.name), ["argument"])
        XCTAssertTrue(created.keywords.contains("work"))
        let ran = try await session.runCommand(created.id, arguments: ["argument": "a+b"])
        XCTAssertEqual(ran, .open(url: "https://docs.example.com/?q=a%2Bb", app: nil))
        await session.closeView(opened.session)

        // Editing keeps the id, so aliases and hotkeys still point at it.
        let uuid = String(created.id.dropFirst(3)).uppercased()
        let edit = try await session.openView("create", query: CommandQuery(arguments: ["id": uuid]))
        try await session.event(ActionID("view/\(edit.session)/form/\(uuid)"), value: .fields(["name": .text("Docs Search"), "link": .text("https://docs.example.com/?q={argument}"), "tags": .text(""), "app": .text("com.apple.Safari")]))
        let edited = try await command(session, titled: "Docs Search")
        XCTAssertEqual(edited.id, created.id)
        let ranEdited = try await session.runCommand(edited.id, arguments: ["argument": "x"])
        XCTAssertEqual(ranEdited, .open(url: "https://docs.example.com/?q=x", app: "com.apple.Safari"))
        await session.stop()
    }

    func testExportRoundTrips() async throws {
        let session = try await session()
        _ = try await importSample(session)
        let result = try await session.runCommand("export")
        guard case .message(let message?) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(message, "Exported 4 to /Users/you/Downloads/Quicklinks.json")
        let saved = try XCTUnwrap(system.saved.last)
        let items = try JSONDecoder().decode([[String: String]].self, from: saved.data)
        XCTAssertEqual(Set(items.compactMap { $0["name"] }), ["GitHub Search", "Temp", "Translate", "Notes"])
        XCTAssertEqual(items.first { $0["name"] == "GitHub Search" }?["openWith"], "com.google.Chrome")
        await session.stop()
    }

    func testSearchListsRowsWithActions() async throws {
        let session = try await session()
        _ = try await importSample(session)
        let opened = try await session.openView("search")
        let text = TreeTextRenderer.render(try XCTUnwrap(opened.root))
        XCTAssertTrue(text.contains("GitHub Search"), text)
        XCTAssertTrue(text.contains("Copy Link"), text)
        XCTAssertTrue(text.contains("Edit"), text)
        await session.stop()
    }
}
