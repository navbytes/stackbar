import Foundation
import XCTest
@testable import StackbarKit

@MainActor
final class Finder: StackbarPlugin {
    static let manifest = Manifest(id: "test.finder", name: "Finder", surfaces: [.panel])

    var fruits = ["apple", "apricot", "banana", "cherry"]
    var found: [String] = []
    var searches = 0
    var saved: [String: EventValue] = [:]
    var nameError: String?
    var lastSource: InvocationSource?

    var panel: ViewContent {
        Text("Fruit")
    }

    var commands: [Command] {
        Command("count", title: "Count Fruit", symbol: "number") { invocation in
            self.lastSource = invocation.source
            return .message("\(self.fruits.count) fruit")
        }
        Command("add", title: "Add Fruit") { invocation in
            self.fruits.append(invocation["name"] ?? "")
            return .done
        }
        .argument("name", placeholder: "Fruit name")
        Command("greet", title: "Greet") { invocation in .message("Hello, \(invocation["who"] ?? "?")") }
            .argument("who", required: false, default: "world")
        Command("search", title: "Search Fruit", keywords: ["find"])
            .view(search: { invocation in
                self.searches += 1
                self.found = self.fruits.filter { invocation.text.isEmpty || $0.hasPrefix(invocation.text) }
            }) { _ in
                List(self.found) { fruit in
                    Row(fruit, key: fruit)
                        .action("Eat") { self.fruits.removeAll { $0 == fruit }; self.found.removeAll { $0 == fruit } }
                        .navigate("Details", to: "details", arguments: ["fruit": fruit])
                }
            }
        Command("details", title: "Fruit Details")
            .view { invocation in Text(invocation["fruit"] ?? "none") }
            .stackbarOnly()
        Command("new", title: "New Fruit")
            .view { _ in
                Form(submit: "Add") {
                    FormField.text("Name", name: "name", error: self.nameError)
                    FormField.toggle("Ripe", name: "ripe")
                } onSubmit: { values in
                    self.saved = values
                    self.nameError = (values.string("name") ?? "").isEmpty ? "Give it a name" : nil
                }
            }
        for fruit in fruits.prefix(2) {
            Command("eat-\(fruit)", title: "Eat \(fruit)") { _ in .copy(fruit) }
        }
    }
}

@MainActor
final class CommandTests: XCTestCase {
    private func start() async -> (Finder, PluginRuntime, Outbox) {
        let plugin = Finder()
        let outbox = Outbox()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.panel]))
        return (plugin, runtime, outbox)
    }

    private func commandList(_ messages: [PluginMessage]) -> [CommandSpec]? {
        for case .commands(let specs) in messages { return specs }
        return nil
    }

    private func result(_ messages: [PluginMessage], id: Int) -> CommandResult? {
        for case .commandResult(let got, let result) in messages where got == id { return result }
        return nil
    }

    private func views(_ messages: [PluginMessage]) -> [(session: Int, seq: Int, root: ViewNode)] {
        messages.compactMap { if case .view(let session, let seq, let root) = $0 { return (session, seq, root) } else { return nil } }
    }

    func testCommandsAreSentAfterReadyAndWhenTheyChange() async {
        let (plugin, runtime, outbox) = await start()
        let specs = commandList(outbox.take())
        XCTAssertEqual(specs?.map(\.id), ["count", "add", "greet", "search", "details", "new", "eat-apple", "eat-apricot"])
        XCTAssertEqual(specs?.first { $0.id == "search" }?.kind, .view)
        XCTAssertEqual(specs?.first { $0.id == "search" }?.keywords, ["find"])
        XCTAssertEqual(specs?.first { $0.id == "details" }?.exposure, .stackbarOnly)
        XCTAssertEqual(specs?.first { $0.id == "add" }?.arguments, [ArgumentSpec("name", placeholder: "Fruit name")])

        runtime.render()
        XCTAssertNil(commandList(outbox.take()), "an unchanged list is not sent again")

        plugin.fruits.insert("kiwi", at: 0)
        runtime.render()
        XCTAssertEqual(commandList(outbox.take())?.suffix(2).map(\.id), ["eat-kiwi", "eat-apple"])
    }

    func testRunCommandAnswersWithItsResultAndFillsDefaults() async {
        let (plugin, runtime, outbox) = await start()
        _ = outbox.take()
        await runtime.handle(.runCommand(id: 1, command: "count", arguments: [:], source: .hotkey, context: nil))
        XCTAssertEqual(result(outbox.take(), id: 1), .message("4 fruit"))
        XCTAssertEqual(plugin.lastSource, .hotkey)

        await runtime.handle(.runCommand(id: 2, command: "greet", arguments: [:], source: .palette, context: nil))
        XCTAssertEqual(result(outbox.take(), id: 2), .message("Hello, world"))

        await runtime.handle(.runCommand(id: 3, command: "add", arguments: [:], source: .palette, context: nil))
        XCTAssertEqual(result(outbox.take(), id: 3), .failure("Add Fruit needs Fruit name"))

        await runtime.handle(.runCommand(id: 4, command: "add", arguments: ["name": "fig"], source: .palette, context: nil))
        XCTAssertEqual(result(outbox.take(), id: 4), .message(nil))
        XCTAssertEqual(plugin.fruits.last, "fig")

        await runtime.handle(.runCommand(id: 5, command: "nope", arguments: [:], source: .palette, context: nil))
        XCTAssertEqual(result(outbox.take(), id: 5), .failure("no command named nope"))
        await runtime.handle(.runCommand(id: 6, command: "search", arguments: [:], source: .palette, context: nil))
        XCTAssertEqual(result(outbox.take(), id: 6), .failure("Search Fruit opens a view; it can't be run"))
    }

    func testViewsFollowTheQueryAndEchoTheirSeq() async throws {
        let (plugin, runtime, outbox) = await start()
        _ = outbox.take()
        await runtime.handle(.openView(session: 7, command: "search", query: CommandQuery(text: "ap"), seq: 1, context: nil))
        var sent = views(outbox.take())
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].session, 7)
        XCTAssertEqual(sent[0].seq, 1)
        guard case .list(_, let rows) = sent[0].root else { return XCTFail("expected a list") }
        XCTAssertEqual(rows.count, 2)
        guard case .row(let apple) = rows[0] else { return XCTFail("expected a row") }
        XCTAssertEqual(apple.actions[0].id, "view/7/row/apple/Eat")
        XCTAssertEqual(apple.actions[1].navigate, CommandTarget(command: "details", arguments: ["fruit": "apple"]))

        // Same tree for a new query is still sent, so the host can clear "Searching…".
        await runtime.handle(.updateView(session: 7, query: CommandQuery(text: "ap"), seq: 2))
        sent = views(outbox.take())
        XCTAssertEqual(sent.map(\.seq), [2])

        // An action inside the view reaches its handler and re-renders the view.
        await runtime.handle(.event(action: "view/7/row/apple/Eat", value: nil))
        sent = views(outbox.take())
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(plugin.fruits.contains("apple"))
        guard case .list(_, let left) = sent[0].root, case .row(let only)? = left.first else { return XCTFail("expected a list") }
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(only.title, "apricot")

        await runtime.handle(.closeView(session: 7))
        await runtime.handle(.event(action: "view/7/row/apricot/Eat", value: nil))
        XCTAssertTrue(plugin.fruits.contains("apricot"), "a closed view's handlers are gone")
        XCTAssertEqual(plugin.searches, 2)
    }

    func testFormsSubmitEveryFieldAndShowErrors() async throws {
        let (plugin, runtime, outbox) = await start()
        _ = outbox.take()
        await runtime.handle(.openView(session: 1, command: "new", query: CommandQuery(), seq: 1, context: nil))
        guard case .form(let form) = views(outbox.take()).first?.root else { return XCTFail("expected a form") }
        XCTAssertEqual(form.fields.map(\.name), ["name", "ripe"])
        XCTAssertEqual(form.submitTitle, "Add")
        XCTAssertEqual(form.action, "view/1/form/Add")

        await runtime.handle(.event(action: form.action, value: .fields(["name": .text(""), "ripe": .bool(true)])))
        XCTAssertEqual(plugin.saved["ripe"], .bool(true))
        guard case .form(let again) = views(outbox.take()).first?.root else { return XCTFail("expected the form again") }
        XCTAssertEqual(again.fields[0].error, "Give it a name")

        // A view action always answers with its view, even when nothing changed.
        await runtime.handle(.event(action: form.action, value: .fields(["name": .text("fig")])))
        guard case .form(let fixed) = views(outbox.take()).first?.root else { return XCTFail("expected the form") }
        XCTAssertNil(fixed.fields[0].error)
        await runtime.handle(.event(action: form.action, value: .fields(["name": .text("fig")])))
        XCTAssertEqual(views(outbox.take()).count, 1)
    }

    func testEventValueFieldsRoundTripThroughJSON() throws {
        let value = EventValue.fields(["name": .text("fig"), "ripe": .bool(true), "nested": .fields(["n": .number(2)])])
        let message = HostMessage.event(action: "view/1/form/Add", value: value)
        XCTAssertEqual(try LineCodec.decode(HostMessage.self, from: LineCodec.encode(message).dropLast()), message)
    }

    func testCommandSpecProblems() {
        XCTAssertEqual(CommandSpec(id: "ok-1", title: "OK").problems, [])
        XCTAssertFalse(CommandSpec(id: "Bad Id", title: "x").problems.isEmpty)
        XCTAssertFalse(CommandSpec(id: "x", title: " ").problems.isEmpty)
        let four = (1...4).map { ArgumentSpec("a\($0)") }
        XCTAssertFalse(CommandSpec(id: "x", title: "X", arguments: four).problems.isEmpty)
        XCTAssertFalse(CommandSpec(id: "x", title: "X", arguments: [ArgumentSpec("a"), ArgumentSpec("a")]).problems.isEmpty)
    }
}
