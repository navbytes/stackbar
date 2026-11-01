import Foundation
import XCTest
@testable import StackbarKit

/// Collects what a runtime sends, from any thread.
final class Outbox: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [PluginMessage] = []

    var send: PluginRuntime.Send { { message in self.lock.withLock { self.messages.append(message) } } }

    func take() -> [PluginMessage] {
        lock.withLock {
            defer { messages.removeAll() }
            return messages
        }
    }
}

struct Boom: Error {}

@MainActor
final class Counter: StackbarPlugin {
    static let manifest = Manifest(id: "test.counter", name: "Counter", surfaces: [.menuBar, .panel])

    var count = 0
    var refreshes = 0
    var shouldFail = false
    var enabled = false
    var items = ["a", "b"]

    func refresh() async throws {
        if shouldFail { throw Boom() }
        refreshes += 1
    }

    var menuBar: ViewContent {
        Label("\(count)", symbol: "number")
    }

    var panel: ViewContent {
        Text("Count").style(.headline)
        Button("Add") { self.count += 1 }
        Toggle("Enabled", isOn: enabled) { self.enabled = $0 }
        if count > 2 {
            Text("big").role(.warning)
        }
        List(items) { item in
            Row(item, key: "item-\(item)").badge("new").action("Remove") { self.items.removeAll { $0 == item } }
        }
    }
}

@MainActor
final class StackbarKitTests: XCTestCase {
    func testDSLResolvesToTheExpectedTree() {
        let plugin = Counter()
        let context = RenderContext()
        let nodes = plugin.panel.resolve(in: context)
        XCTAssertEqual(nodes.count, 4)
        XCTAssertEqual(nodes[0], .text("Count", style: .headline, role: .primary))
        XCTAssertEqual(nodes[1], .button(title: "Add", symbol: nil, role: .primary, action: "button/Add"))
        XCTAssertEqual(nodes[2], .toggle(title: "Enabled", isOn: false, action: "toggle/Enabled"))
        guard case .list(false, let rows) = nodes[3] else { return XCTFail("expected a list") }
        XCTAssertEqual(rows, [
            .row(RowNode(key: "item-a", title: "a", accessories: [.badge("new", role: .secondary)], actions: [ActionRef(id: "row/item-a/Remove", title: "Remove")])),
            .row(RowNode(key: "item-b", title: "b", accessories: [.badge("new", role: .secondary)], actions: [ActionRef(id: "row/item-b/Remove", title: "Remove")])),
        ])
        XCTAssertEqual(Set(context.handlers.keys), ["button/Add", "toggle/Enabled", "row/item-a/Remove", "row/item-b/Remove"])
    }

    func testDuplicateActionNamesGetSuffixesInsteadOfReplacingHandlers() {
        let context = RenderContext()
        let first = context.register("button/Go") { _ in }
        let second = context.register("button/Go") { _ in }
        XCTAssertEqual(first, "button/Go")
        XCTAssertEqual(second, "button/Go#2")
    }

    func testHelloAnswersReadyThenRendersOnlyOfferedSurfaces() async {
        let outbox = Outbox()
        let runtime = PluginRuntime(plugin: Counter(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
        XCTAssertEqual(outbox.take(), [
            .ready(protocolVersion: StackbarProtocolVersion.current),
            .render(surface: .menuBar, root: .label("0", symbol: "number", role: .primary)),
            .settled,
        ])
    }

    func testEventsRunHandlersAndOnlyChangedSurfacesAreResent() async throws {
        let outbox = Outbox()
        let plugin = Counter()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar, .panel]))
        _ = outbox.take()

        await runtime.handle(.trigger(reason: .interval))
        XCTAssertEqual(plugin.refreshes, 1)
        XCTAssertEqual(outbox.take(), [.settled], "an unchanged render is not sent again")

        await runtime.handle(.event(action: "button/Add", value: nil))
        XCTAssertEqual(plugin.count, 1)
        let sent = outbox.take()
        XCTAssertEqual(sent.count, 2, "the panel did not change, so only the menu bar is resent")
        XCTAssertEqual(sent.first, .render(surface: .menuBar, root: .label("1", symbol: "number", role: .primary)))

        await runtime.handle(.event(action: "toggle/Enabled", value: .bool(true)))
        XCTAssertTrue(plugin.enabled)
        await runtime.handle(.event(action: "row/item-a/Remove", value: nil))
        XCTAssertEqual(plugin.items, ["b"])
    }

    func testFailuresAreLoggedNotFatal() async {
        let outbox = Outbox()
        let plugin = Counter()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
        _ = outbox.take()

        plugin.shouldFail = true
        let afterTrigger = await runtime.handle(.trigger(reason: .manual))
        XCTAssertTrue(afterTrigger)
        guard case .log(.error, let message) = outbox.take().first else { return XCTFail("expected an error log") }
        XCTAssertTrue(message.contains("refresh failed"))

        let afterEvent = await runtime.handle(.event(action: "button/Missing", value: nil))
        XCTAssertTrue(afterEvent)
        XCTAssertEqual(outbox.take(), [.log(level: .warning, message: "no handler for action button/Missing"), .settled])
    }

    func testVisibilityResendsTheSurfaceAndShutdownStops() async {
        let outbox = Outbox()
        let runtime = PluginRuntime(plugin: Counter(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
        _ = outbox.take()
        await runtime.handle(.visibility(surface: .menuBar, visible: true))
        XCTAssertEqual(outbox.take().count, 2)
        let keepGoing = await runtime.handle(.shutdown)
        XCTAssertFalse(keepGoing)
    }

    func testNewVocabularyResolvesAndRoutesValues() async {
        final class Inputs: StackbarPlugin {
            static let manifest = Manifest(id: "test.inputs", name: "Inputs", surfaces: [.panel])
            var query = ""
            var choice: String? = "a"
            var volume = 0.5
            var panel: ViewContent {
                LabeledContent("Build", value: "green").role(.success)
                Chart("Load", values: [1, 3, .infinity], kind: .bar)
                TextField("Search", text: query) { self.query = $0 }
                Picker("Mode", options: ["a", "b"], selection: choice) { self.choice = $0 }
                Slider("Volume", value: volume, in: 0...1) { self.volume = $0 }
                Link("Docs", url: "https://example.com")
                ContentUnavailableView("Nothing", symbol: "tray", message: "All clear")
            }
            required init() {}
        }
        let outbox = Outbox()
        let plugin = Inputs()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 2, surfaces: [.panel]))
        guard case .render(.panel, .stack(.vertical, _, _, let nodes)) = outbox.take()[1] else { return XCTFail("expected a panel stack") }
        XCTAssertEqual(nodes[0], .labeled(label: "Build", value: "green", role: .success))
        XCTAssertEqual(nodes[1], .chart(values: [1, 3, 0], kind: .bar, label: "Load", role: .accent), "non-finite values become 0")
        XCTAssertEqual(nodes[5], .link(title: "Docs", url: "https://example.com"))
        XCTAssertEqual(ViewNode.stack(axis: .vertical, children: nodes).actions, ["field/Search", "picker/Mode", "slider/Volume"])

        await runtime.handle(.event(action: "field/Search", value: .text("stackbar")))
        await runtime.handle(.event(action: "picker/Mode", value: .text("b")))
        await runtime.handle(.event(action: "picker/Mode", value: .text("not an option")))
        await runtime.handle(.event(action: "slider/Volume", value: .number(7)))
        XCTAssertEqual(plugin.query, "stackbar")
        XCTAssertEqual(plugin.choice, "b")
        XCTAssertEqual(plugin.volume, 1, "slider values are clamped to the range")
    }

    func testStoredValuesComeFromHelloAndWritesGoToTheHost() async {
        final class Saver: StackbarPlugin {
            static let manifest = Manifest(id: "test.saver", name: "Saver", surfaces: [.menuBar])
            @Stored("count") var count = 0
            var menuBar: ViewContent { Button("Bump") { self.count += 1 } }
            required init() {}
        }
        let outbox = Outbox()
        HostClient.shared.configure(send: outbox.send)
        let runtime = PluginRuntime(plugin: Saver(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 2, surfaces: [.menuBar], storage: ["count": "41"]))
        _ = outbox.take()
        await runtime.handle(.event(action: "button/Bump", value: nil))
        let sent = outbox.take()
        guard case .request(let id, .storageSet("count", "42")) = sent.first else { return XCTFail("expected a storage write, got \(sent)") }
        XCTAssertEqual(Stackbar.storage.value("count", as: Int.self), 42)
        XCTAssertTrue(HostClient.shared.resolve(id: id, result: .ok))
    }

    func testHostCallsResolveOutOfBandAndToolsAreListed() async {
        final class Caller: StackbarPlugin {
            static let manifest = Manifest(id: "test.caller", name: "Caller", surfaces: [.menuBar])
            var secret: String?
            var menuBar: ViewContent { Text(secret ?? "none") }
            var tools: [AgentTool] {
                AgentTool("greet", description: "Says hi", parameters: [ToolParameter("name")]) { arguments in "hi \(arguments.string("name") ?? "")" }
            }
            func refresh() async throws { secret = try await Stackbar.secret("S") }
            required init() {}
        }
        let outbox = Outbox()
        HostClient.shared.configure(send: outbox.send)
        let runtime = PluginRuntime(plugin: Caller(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 2, surfaces: [.menuBar]))
        XCTAssertEqual(outbox.take().filter { if case .tools = $0 { return true } else { return false } }, [.tools([ToolSpec(name: "greet", description: "Says hi", parameters: [ToolParameter("name")])])])

        // The refresh awaits the host; the answer arrives from another thread.
        let refresh = Task { await runtime.handle(.trigger(reason: .manual)) }
        var request: Int?
        for _ in 0..<200 where request == nil {
            try? await Task.sleep(for: .milliseconds(5))
            if case .request(let id, .secret("S"))? = outbox.take().first { request = id }
        }
        guard let request else { return XCTFail("no secret request") }
        HostClient.shared.resolve(id: request, result: .value("shh"))
        _ = await refresh.value
        XCTAssertTrue(outbox.take().contains(.render(surface: .menuBar, root: .text("shh", style: .body, role: .primary))))

        await runtime.handle(.callTool(id: 9, name: "greet", arguments: ["name": .text("Naveen")]))
        XCTAssertTrue(outbox.take().contains(.toolResult(id: 9, text: "hi Naveen", isError: false)))
    }
}
