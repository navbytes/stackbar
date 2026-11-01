import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class PaletteIndexTests: XCTestCase {
    func testCollectsActionsAndRanksMatches() {
        var index = PaletteIndex()
        let panel = ViewNode.stack(axis: .vertical, children: [
            .button(title: "Refresh now", symbol: "arrow.clockwise", action: "button/Refresh now"),
            .toggle(title: "Notifications", isOn: true, action: "toggle/Notifications"),
            .list(children: [
                .row(RowNode(key: "1", title: "Fix login bug", subtitle: "web #12", actions: [ActionRef(id: "row/1/Open", title: "Open"), ActionRef(id: "row/1/Copy link", title: "Copy link")])),
            ]),
            .link(title: "Docs", url: "https://example.com"),
            .text("not an entry"),
        ])
        index.update(pluginID: "a", pluginName: "PRs", panel: panel)
        index.update(pluginID: "b", pluginName: "Clock", panel: .button(title: "Lap", action: "button/Lap"))
        XCTAssertEqual(index.entries.count, 6)
        XCTAssertEqual(index.search("fix").first?.title, "Fix login bug")
        XCTAssertEqual(index.search("rfn").first?.title, "Refresh now", "letters in order match")
        XCTAssertEqual(index.search("copy").first?.kind, .action("row/1/Copy link", value: nil))
        XCTAssertEqual(index.search("turn off").first?.kind, .action("toggle/Notifications", value: .bool(false)))
        XCTAssertEqual(index.search("clock").first?.title, "Lap", "the plugin name matches too")
        XCTAssertEqual(index.search("zzz"), [])
        index.update(pluginID: "a", pluginName: "PRs", panel: nil)
        XCTAssertEqual(index.entries.map(\.pluginID), ["b"])
    }

    func testListsWhatCanBePressedWithoutItsControl() {
        let target = CommandTarget(command: "details", arguments: ["id": "1"])
        let panel = ViewNode.stack(axis: .vertical, children: [
            .row(RowNode(key: "1", title: "Fix bug", actions: [ActionRef(id: "row/1/Details", title: "Details", navigate: target)])),
            .textField(placeholder: "Search", text: "", action: "field/Search"),
            .picker(title: "Mode", options: ["a"], selection: nil, action: "picker/Mode"),
            .slider(title: "Volume", value: 0, min: 0, max: 1, action: "slider/Volume"),
            .form(FormNode(fields: [], action: "form/Save")),
            .tappable(.stack(axis: .horizontal, children: [.text("Start"), .button(title: "Inner", action: "button/Inner")]), action: "button/Start"),
            .tappable(.image(.symbol("play.fill")), action: "button/Play"),
        ])
        let entries = PaletteIndex.entries(in: panel, pluginID: "p", pluginName: "P")
        XCTAssertEqual(entries.map(\.title), ["Fix bug", "Start Inner"], "no inputs, nothing inside a tappable, no tappable without words")
        XCTAssertEqual(entries.map(\.kind), [.navigate(target), .action("button/Start", value: nil)])
        XCTAssertEqual(entries.first?.subtitle, "Details")
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let snapshot = WidgetSnapshot(pluginID: "dev.x.y", name: "Y", node: .text("hi"), updatedAt: Date(timeIntervalSince1970: 1))
        try store.write(snapshot)
        XCTAssertEqual(store.read("dev.x.y"), snapshot)
        XCTAssertEqual(store.all(), [snapshot])
        store.remove("dev.x.y")
        XCTAssertNil(store.read("dev.x.y"))
    }
}

final class RuntimeGatewayTests: XCTestCase {
    func testExposesPluginToolsOverASocket() async throws {
        let directory = URL(fileURLWithPath: "/tmp").appendingPathComponent("stackbar-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let supervisor = try PluginSupervisor.make(executable: PluginSupervisorTests.helper("FixturePlugin"))
        await supervisor.start()
        _ = await waitUntil { await supervisor.tools.count == 2 }
        let tools = RuntimeTools { [supervisor] }
        let server = MCPServer(name: "stackbar", version: "test", provider: tools)
        let socket = try UnixSocketServer(path: directory.appendingPathComponent("agent.sock").path) { line in await server.handle(line: line) }
        defer { socket.stop() }

        let listed = await tools.tools().map(\.name)
        XCTAssertEqual(listed, ["stackbar_plugins", "stackbar_read", "fixture__count", "fixture__add"])
        let added = await tools.call("fixture__add", arguments: ["amount": 4])
        XCTAssertEqual(added, .text("now 4"))
        let read = await tools.call("stackbar_read", arguments: ["plugin": "fixture"])
        guard case .text(let panel)? = read.content.first else { return XCTFail() }
        XCTAssertTrue(panel.contains("(Increment)"), panel)
        let unknown = await tools.call("nope__x", arguments: [:])
        XCTAssertTrue(unknown.isError)

        // The same server, reached the way `stackbarctl agent` reaches the app.
        let reply = try Self.roundTrip(socket.path, #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"fixture__count"}}"#)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: reply)
        XCTAssertEqual(decoded["id"], 7)
        guard case .array(let content)? = decoded["result"]?["content"] else { return XCTFail(String(decoding: reply, as: UTF8.self)) }
        XCTAssertEqual(content.first?["text"], "4")
        await supervisor.stop()
    }

    /// Sends one line to a Unix socket and reads one line back.
    static func roundTrip(_ path: String, _ line: String) throws -> Data {
        #if canImport(Glibc)
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
        defer { close(fd) }
        var address = try UnixSocket.address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(connected, 0)
        UnixSocket.writeAll(Data((line + "\n").utf8), to: fd)
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !received.contains(0x0A) {
            let count = recv(fd, &chunk, chunk.count, 0)
            if count <= 0 { break }
            received.append(contentsOf: chunk[0..<count])
        }
        return received
    }
}

final class ShowcaseTests: XCTestCase {
    func testPomodoroTellsTodoAboutFocusOverTheBus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore())
        let todo = try PluginSupervisor.make(executable: PluginSupervisorTests.helper("TodoPlugin"), services: services)
        let pomodoro = try PluginSupervisor.make(executable: PluginSupervisorTests.helper("PomodoroPlugin"), services: services)
        await todo.start()
        await pomodoro.start()
        _ = await waitUntil {
            let first = await todo.state
            let second = await pomodoro.state
            return first == .running && second == .running
        }
        _ = await waitUntil { await services.bus.listeners(of: "focus.state") == ["io.navbytes.stackbar.example.todo"] }

        let added = await todo.callTool("add", arguments: ["title": .text("Write the README")])
        XCTAssertEqual(added.text, "Added \"Write the README\"")
        await pomodoro.event("button/Start focus")
        let focused = await waitUntil(10) {
            await todo.views[.panel].map { TreeTextRenderer.render($0).contains("Focus mode") } ?? false
        }
        XCTAssertTrue(focused, "Todo hears Pomodoro's focus.state")
        let status = await pomodoro.callTool("status")
        XCTAssertTrue(status.text.hasPrefix("focus,"), status.text)
        let stored = await services.storage.snapshot(for: "io.navbytes.stackbar.example.todo")
        XCTAssertTrue(stored["items"]?.contains("Write the README") == true)
        await todo.stop()
        await pomodoro.stop()
    }
}
