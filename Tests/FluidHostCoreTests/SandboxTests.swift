#if os(macOS)
import Foundation
import XCTest
@testable import FluidHostCore
import FluidProtocol

/// Proves on a real Mac that a helper signed by `PluginBuilder.sign` runs in
/// the App Sandbox: the protocol still works, files outside the plugin's
/// declared paths can't be read, and a plugin without `.network` can't open
/// a connection itself. Runs on the self-hosted Mac runner (FLUID_BUILD_TESTS).
final class SandboxTests: XCTestCase {
    static let probe = """
    import FluidKit
    import Foundation
    #if canImport(FoundationNetworking)
    import FoundationNetworking
    #endif

    @main final class Probe: FluidPlugin {
        static let manifest = Manifest(id: "dev.fluid.test.sandbox-probe", name: "Probe", capabilities: [CAPABILITIES])
        var menuBar: ViewContent { Text("probe") }
        var tools: [AgentTool] {
            AgentTool("read", description: "Reads a file", parameters: [ToolParameter("path", .string)]) { arguments in
                do { return "read " + (try String(contentsOfFile: arguments.string("path") ?? "", encoding: .utf8)) } catch { return "denied" }
            }
            AgentTool("write", description: "Writes a file", parameters: [ToolParameter("path", .string)]) { arguments in
                do { try "x".write(toFile: arguments.string("path") ?? "", atomically: false, encoding: .utf8); return "wrote" } catch { return "denied" }
            }
            AgentTool("connect", description: "Connects to a URL", parameters: [ToolParameter("url", .string)]) { arguments in
                do {
                    let (data, _) = try await URLSession.shared.data(from: URL(string: arguments.string("url") ?? "")!)
                    return "connected " + String(decoding: data, as: UTF8.self)
                } catch { return "denied" }
            }
        }
    }
    """

    func testASignedHelperIsSandboxed() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FLUID_BUILD_TESTS"] == "1", "set FLUID_BUILD_TESTS=1 to compile plugins")
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("fluid-sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let secretFile = home.appendingPathComponent(".fluid-sandbox-probe-\(UUID().uuidString)")
        try "private".write(to: secretFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: secretFile) }
        let allowedDir = home.appendingPathComponent(".fluid-sandbox-allowed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: allowedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: allowedDir) }
        try "shared".write(to: allowedDir.appendingPathComponent("in.txt"), atomically: true, encoding: .utf8)
        let server = try LoopbackServer { _ in .text("pong") }
        defer { server.stop() }

        let builder = PluginBuilder(fluidPackage: package, cacheRoot: work.appendingPathComponent("cache"), configuration: "debug")
        let source = work.appendingPathComponent("Probe.swift")
        try Self.probe.replacingOccurrences(of: "CAPABILITIES", with: ".files(paths: [\"~/\(allowedDir.lastPathComponent)\"])").write(to: source, atomically: true, encoding: .utf8)
        let binary = try builder.build(source: source).binary
        let manifest = try PluginProcess.readManifest(executable: binary)

        func run(_ executable: URL, _ body: (PluginSupervisor) async -> Void) async {
            let supervisor = PluginSupervisor(executable: executable, manifest: manifest)
            await supervisor.start()
            let ready = await waitUntil(20) {
                let state = await supervisor.state
                let settled = await supervisor.settledCount
                return state == .running && settled >= 1
            }
            XCTAssertTrue(ready, "the helper starts and speaks the protocol")
            await body(supervisor)
            await supervisor.stop()
        }

        // Unsigned: the probe really can read the file, so "denied" below means the sandbox.
        await run(binary) { supervisor in
            let read = await supervisor.callTool("read", arguments: ["path": .text(secretFile.path)])
            XCTAssertEqual(read.text, "read private")
        }

        let sandboxed = try builder.sign(binary: binary, manifest: manifest)
        XCTAssertEqual(try builder.sign(binary: binary, manifest: manifest), sandboxed, "an unchanged helper is not signed again")
        await run(sandboxed) { supervisor in
            let outside = await supervisor.callTool("read", arguments: ["path": .text(secretFile.path)])
            XCTAssertEqual(outside.text, "denied", "a sandboxed helper can't read the user's files")
            let inside = await supervisor.callTool("read", arguments: ["path": .text(allowedDir.appendingPathComponent("in.txt").path)])
            XCTAssertEqual(inside.text, "read shared", "declared .files paths stay readable")
            let write = await supervisor.callTool("write", arguments: ["path": .text(allowedDir.appendingPathComponent("out.txt").path)])
            XCTAssertEqual(write.text, "wrote", "and writable")
            let connect = await supervisor.callTool("connect", arguments: ["url": .text("\(server.baseURL)/ping")])
            XCTAssertEqual(connect.text, "denied", "no .network, no connections of its own")
        }
    }
}
#endif
