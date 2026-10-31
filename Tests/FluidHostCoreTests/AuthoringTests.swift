import Foundation
import XCTest
@testable import FluidHostCore
import FluidProtocol

final class AuthoringTests: XCTestCase {
    func testLLMsTxtMatchesTheGuide() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("llms.txt")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(text, AuthoringGuide.text + "\n", "llms.txt is out of date; regenerate it with: swift run fluidctl docs > llms.txt")
    }

    func testTemplateNames() {
        XCTAssertEqual(PluginTemplate.typeName(for: "My PR list"), "MyPRList")
        XCTAssertEqual(PluginTemplate.typeName(for: "3d printer"), "Plugin3dPrinter")
        XCTAssertEqual(PluginTemplate.typeName(for: "!!"), "Plugin")
        XCTAssertTrue(PluginTemplate.source(name: "Hello \"World\"").contains("name: \"Hello 'World'\""))
    }

    func testEventValuesMatchTheControl() {
        XCTAssertEqual(AuthoringTools.eventValue(.string("4"), for: "slider/Volume"), .number(4))
        XCTAssertEqual(AuthoringTools.eventValue(.string("true"), for: "toggle/On"), .bool(true))
        XCTAssertEqual(AuthoringTools.eventValue(.number(42), for: "field/Search"), .text("42"))
        XCTAssertNil(AuthoringTools.eventValue(nil, for: "button/Go"))
    }

    func testMCPServerSpeaksJSONRPC() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tools = AuthoringTools(builder: PluginBuilder(fluidPackage: directory, cacheRoot: directory), services: .local(directory: directory, secrets: MemorySecretStore()))
        let server = MCPServer(name: "test", version: "1", provider: tools)
        func call(_ json: String) async throws -> JSONValue? {
            guard let reply = await server.handle(line: Data(json.utf8)) else { return nil }
            return try JSONDecoder().decode(JSONValue.self, from: reply)
        }

        let initialize = try await call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        XCTAssertEqual(initialize?["result"]?["protocolVersion"], "2025-03-26")
        let notification = try await call(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(notification, "notifications get no reply")
        let list = try await call(#"{"jsonrpc":"2.0","id":"two","method":"tools/list"}"#)
        XCTAssertEqual(list?["id"], "two")
        guard case .array(let listed)? = list?["result"]?["tools"] else { return XCTFail("no tools") }
        XCTAssertTrue(listed.contains { $0["name"] == "fluid_render" })
        let missing = try await call(#"{"jsonrpc":"2.0","id":3,"method":"nope"}"#)
        XCTAssertEqual(missing?["error"]?["code"], .number(-32601))
        let garbage = try await call("{not json")
        XCTAssertEqual(garbage?["error"]?["code"], .number(-32700))
    }

    func testAuthoringToolsDriveARunningPlugin() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tools = AuthoringTools(builder: PluginBuilder(fluidPackage: directory, cacheRoot: directory), services: .local(directory: directory, secrets: MemorySecretStore()))
        let helper = PluginSupervisorTests.helper("FixturePlugin").path
        func text(_ result: MCPToolResult) -> String { result.content.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined() }

        let rendered = await tools.call("fluid_render", arguments: ["path": .string(helper)])
        XCTAssertFalse(rendered.isError, text(rendered))
        XCTAssertTrue(text(rendered).contains("{button/Increment}"))
        XCTAssertTrue(text(rendered).contains("== tools ==\ncount: The current count"))

        let pressed = await tools.call("fluid_send_event", arguments: ["path": .string(helper), "action": "button/Increment"])
        XCTAssertTrue(text(pressed).contains("count 1"), text(pressed))
        let wrong = await tools.call("fluid_send_event", arguments: ["path": .string(helper), "action": "button/Nope"])
        XCTAssertTrue(wrong.isError)
        XCTAssertTrue(text(wrong).contains("button/Increment"), "the error lists what can be pressed")

        let tool = await tools.call("fluid_call_tool", arguments: ["path": .string(helper), "name": "add", "arguments": ["amount": 2]])
        XCTAssertEqual(text(tool), "now 3")
        let logs = await tools.call("fluid_logs", arguments: ["path": .string(helper)])
        XCTAssertTrue(text(logs).contains("[state] running"), text(logs))
        await tools.stopAll()
    }
}
