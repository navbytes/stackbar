import Foundation
import XCTest
@testable import FluidHostCore
import FluidProtocol

final class BackoffPolicyTests: XCTestCase {
    func testDelaysGrowThenGiveUp() {
        let policy = BackoffPolicy(initialDelay: 1, multiplier: 2, maxDelay: 5, maxConsecutiveFailures: 4)
        XCTAssertNil(policy.delay(afterFailures: 0))
        XCTAssertEqual(policy.delay(afterFailures: 1), 1)
        XCTAssertEqual(policy.delay(afterFailures: 2), 2)
        XCTAssertEqual(policy.delay(afterFailures: 3), 4)
        XCTAssertEqual(policy.delay(afterFailures: 4), 5, "capped at maxDelay")
        XCTAssertNil(policy.delay(afterFailures: 5), "gives up after maxConsecutiveFailures")
    }
}

final class SandboxEntitlementsTests: XCTestCase {
    func testCapabilitiesMapToEntitlements() throws {
        let quiet = Manifest(id: "a.quiet", name: "Quiet")
        XCTAssertEqual(SandboxEntitlements.entitlements(for: quiet), ["com.apple.security.app-sandbox": true])
        XCTAssertEqual(SandboxEntitlements.summary(for: quiet), ["No network, files, commands or secrets."])

        let busy = Manifest(id: "a.busy", name: "Busy", capabilities: [.network("api.github.com"), .files(paths: ["~/Notes"]), .secret(name: "TOKEN")])
        XCTAssertEqual(SandboxEntitlements.entitlements(for: busy), [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.network.client": true,
            "com.apple.security.files.user-selected.read-write": true,
        ])
        let plist = try SandboxEntitlements.propertyList(for: busy)
        let decoded = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Bool]
        XCTAssertEqual(decoded, SandboxEntitlements.entitlements(for: busy))
        XCTAssertEqual(SandboxEntitlements.summary(for: busy).first, "Connects to api.github.com")
    }
}

final class TreeTextRendererTests: XCTestCase {
    func testRendersControlsWithTheirActionIDs() {
        let tree = ViewNode.stack(axis: .vertical, children: [
            .text("Clock", style: .title),
            .progress(value: 0.5, label: "Day"),
            .toggle(title: "24h", isOn: true, action: "toggle/24h"),
            .list(searchable: true, children: [
                .row(RowNode(key: "1", title: "Fix bug", subtitle: "vee #1", accessories: [.badge("Ready", role: .success)], actions: [ActionRef(id: "row/1/Open", title: "Open", shortcut: "cmd+return")])),
            ]),
            .button(title: "Clear", role: .critical, action: "button/Clear"),
        ])
        XCTAssertEqual(TreeTextRenderer.render(tree), """
        # Clock
        Day [#####.....] 50%
        [x] 24h  {toggle/24h}
        List (searchable)
          * Fix bug - vee #1  [Ready] (success)  <Open (cmd+return)  {row/1/Open}>
        (Clear) (critical)  {button/Clear}
        """)
    }
}

final class PluginBuilderTests: XCTestCase {
    func testParsesCompilerDiagnostics() {
        let log = """
        Building for production...
        /tmp/x/Sources/Plugin/Plugin.swift:12:9: error: cannot find 'foo' in scope
        /tmp/x/Sources/Plugin/Plugin.swift:12:9: error: cannot find 'foo' in scope
        /tmp/x/Sources/Plugin/Plugin.swift:3:1: warning: unused variable 'x'
        error: fatalError
        """
        let diagnostics = PluginBuilder.parseDiagnostics(log)
        XCTAssertEqual(diagnostics, [
            BuildDiagnostic(file: "/tmp/x/Sources/Plugin/Plugin.swift", line: 12, column: 9, severity: .error, message: "cannot find 'foo' in scope"),
            BuildDiagnostic(file: "/tmp/x/Sources/Plugin/Plugin.swift", line: 3, column: 1, severity: .warning, message: "unused variable 'x'"),
        ])
    }

    func testCacheKeysAndNames() {
        XCTAssertEqual(PluginBuilder.cacheKey(Data("a".utf8)), PluginBuilder.cacheKey(Data("a".utf8)))
        XCTAssertNotEqual(PluginBuilder.cacheKey(Data("a".utf8)), PluginBuilder.cacheKey(Data("b".utf8)))
        XCTAssertEqual(PluginBuilder.sanitizedName("my plugin.v2"), "my-plugin-v2")
        let manifest = PluginBuilder.manifest(fluidPackage: URL(fileURLWithPath: "/src/Fluid"), targets: ["Clock_ab"])
        XCTAssertTrue(manifest.contains(#".package(path: "/src/Fluid")"#))
        XCTAssertTrue(manifest.contains(#".executableTarget(name: "Clock_ab", dependencies: [.product(name: "FluidKit", package: "fluid")], path: "Sources/Clock_ab")"#))
        XCTAssertEqual(PluginBuilder.targetName("my plugin", key: "1f"), "myplugin_1f")
        XCTAssertEqual(PluginBuilder.targetName("3d", key: "1f"), "Plugin3d_1f")
    }

    /// Compiles real plugins with SwiftPM. Slow (it builds FluidKit), so it
    /// runs only when FLUID_BUILD_TESTS=1.
    func testBuildsAPluginAndMapsErrorsBackToItsSource() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FLUID_BUILD_TESTS"] == "1", "set FLUID_BUILD_TESTS=1 to compile plugins")
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("fluid-build-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let builder = PluginBuilder(fluidPackage: package, cacheRoot: work.appendingPathComponent("cache"), configuration: "debug")

        let good = work.appendingPathComponent("Hello.swift")
        try """
        import FluidKit
        @main final class Hello: FluidPlugin {
            static let manifest = Manifest(id: "test.hello", name: "Hello")
            var menuBar: ViewContent { Text("hello") }
        }
        """.write(to: good, atomically: true, encoding: .utf8)
        let first = try builder.build(source: good)
        XCTAssertFalse(first.cached)
        XCTAssertEqual(try PluginProcess.readManifest(executable: first.binary).id, "test.hello")
        XCTAssertTrue(try builder.build(source: good).cached)

        // A second plugin reuses the workspace's compiled FluidKit.
        let other = work.appendingPathComponent("Other.swift")
        try String(contentsOf: good, encoding: .utf8).replacingOccurrences(of: "test.hello", with: "test.other").write(to: other, atomically: true, encoding: .utf8)
        let started = Date()
        let second = try builder.build(source: other)
        XCTAssertEqual(try PluginProcess.readManifest(executable: second.binary).id, "test.other")
        XCTAssertLessThan(Date().timeIntervalSince(started), 60)

        let bad = work.appendingPathComponent("Broken.swift")
        try """
        import FluidKit
        @main final class Broken: FluidPlugin {
            static let manifest = Manifest(id: "test.broken", name: "Broken")
            var menuBar: ViewContent { Text(missingValue) }
        }
        """.write(to: bad, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try builder.build(source: bad)) { error in
            let diagnostics = (error as? PluginBuilder.Failure)?.diagnostics ?? []
            XCTAssertTrue(diagnostics.contains { $0.file == bad.path && $0.line == 4 && $0.severity == .error }, "\(diagnostics)")
        }
    }
}

/// Drives the real example and fixture plugins as child processes.
final class PluginSupervisorTests: XCTestCase {
    static var productsDirectory: URL {
        #if os(macOS)
        if let bundle = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        #endif
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }

    static func helper(_ name: String) -> URL { productsDirectory.appendingPathComponent(name) }

    func testReadsTheManifestFromTheHelper() throws {
        let manifest = try PluginProcess.readManifest(executable: Self.helper("ClockPlugin"))
        XCTAssertEqual(manifest.id, "dev.fluid.example.clock")
        XCTAssertEqual(manifest.refreshInterval, 1)
    }

    func testRendersBothSurfacesAndHandlesEvents() async throws {
        let log = Log()
        let supervisor = try PluginSupervisor.make(executable: Self.helper("FixturePlugin"), onUpdate: log.add)
        await supervisor.start()
        let startup = supervisor.startupMessageCount
        let started = await waitUntil { await supervisor.settledCount >= startup }
        XCTAssertTrue(started)
        let running = await supervisor.state
        XCTAssertEqual(running, .running)
        var views = await supervisor.views
        XCTAssertEqual(views[.menuBar], .text("count 0", style: .body, role: .primary))
        XCTAssertNotNil(views[.panel])

        await supervisor.event("button/Increment")
        await supervisor.event("button/Print")
        let handled = await waitUntil { await supervisor.settledCount >= startup + 2 }
        XCTAssertTrue(handled)
        views = await supervisor.views
        XCTAssertEqual(views[.menuBar], .text("count 11", style: .body, role: .primary), "a stray print must not corrupt the protocol")
        let sawPrint = await waitUntil(5) { log.all.contains("stray output from plugin code") }
        XCTAssertTrue(sawPrint, "plugin stdout is redirected to the log: \(log.all)")

        await supervisor.stop()
        let stopped = await supervisor.state
        XCTAssertEqual(stopped, .stopped)
    }

    func testRestartsACrashedPluginAndKeepsTheLastTree() async throws {
        let fast = BackoffPolicy(initialDelay: 0.05, multiplier: 1, maxDelay: 0.05, maxConsecutiveFailures: 3)
        let supervisor = try PluginSupervisor.make(executable: Self.helper("FixturePlugin"), policy: fast)
        await supervisor.start()
        let startup = supervisor.startupMessageCount
        _ = await waitUntil { await supervisor.settledCount >= startup }

        await supervisor.event("button/Increment")
        _ = await waitUntil { await supervisor.views[.menuBar] == .text("count 1", style: .body, role: .primary) }
        await supervisor.event("button/Crash")
        let restarted = await waitUntil { await supervisor.restarts == 1 }
        XCTAssertTrue(restarted)
        let back = await waitUntil {
            let state = await supervisor.state
            let settled = await supervisor.settledCount
            return state == .running && settled >= startup
        }
        XCTAssertTrue(back)
        let views = await supervisor.views
        XCTAssertEqual(views[.menuBar], .text("count 0", style: .body, role: .primary), "a restarted plugin starts from fresh state and re-renders")
        await supervisor.stop()
    }

    func testGivesUpAfterTooManyCrashes() async throws {
        let fast = BackoffPolicy(initialDelay: 0.05, multiplier: 1, maxDelay: 0.05, maxConsecutiveFailures: 2)
        let supervisor = try PluginSupervisor.make(executable: Self.helper("FixturePlugin"), policy: fast)
        await supervisor.start()
        for _ in 0..<3 {
            _ = await waitUntil { await supervisor.state == .running }
            await supervisor.event("button/Crash")
            _ = await waitUntil(5) {
                switch await supervisor.state {
                case .restarting, .failed: return true
                default: return false
                }
            }
        }
        let failed = await waitUntil {
            if case .failed = await supervisor.state { return true }
            return false
        }
        XCTAssertTrue(failed)
        await supervisor.stop()
    }

    func testHostServicesStorageSecretsHTTPToolsAndTopics() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try LoopbackServer { _ in .text("pong") }
        defer { server.stop() }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore(["FIXTURE_SECRET": "s3cret"]))
        let fast = BackoffPolicy(initialDelay: 0.05, multiplier: 1, maxDelay: 0.05, maxConsecutiveFailures: 3)
        let supervisor = try PluginSupervisor.make(executable: Self.helper("FixturePlugin"), policy: fast, services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        func panelText() async -> String { await supervisor.views[.panel].map { TreeTextRenderer.render($0) } ?? "" }
        func waitForPanel(_ text: String) async -> Bool { await waitUntil(10) { await panelText().contains(text) } }

        await supervisor.event("button/Save")
        let saved = await waitForPanel("saved 1")
        XCTAssertTrue(saved)
        let stored = await services.storage.snapshot(for: "dev.fluid.test.fixture")
        XCTAssertEqual(stored["saved"], "1")

        await supervisor.event("button/Secret")
        let secret = await waitForPanel("status secret s3cret")
        let secretText = await panelText()
        XCTAssertTrue(secret, secretText)
        await supervisor.event("button/Undeclared secret")
        let refused = await waitForPanel("status refused")
        XCTAssertTrue(refused)

        await supervisor.event("field/URL", value: .text("\(server.baseURL)/ping"))
        let fetched = await waitForPanel("status http 200 pong")
        let fetchedText = await panelText()
        XCTAssertTrue(fetched, fetchedText)

        let tools = await supervisor.tools.map(\.name)
        XCTAssertEqual(tools, ["count", "add"])
        let added = await supervisor.callTool("add", arguments: ["amount": .number(5)])
        XCTAssertEqual(added.text, "now 5")
        XCTAssertFalse(added.isError)
        let missing = await supervisor.callTool("add")
        XCTAssertTrue(missing.isError, "required arguments are checked")
        let unknown = await supervisor.callTool("nope")
        XCTAssertTrue(unknown.isError)

        try await services.bus.publish("fixture.inbox", payload: "hello", from: "dev.test.sender")
        let topic = await waitForPanel("status topic fixture.inbox hello from dev.test.sender")
        let topicText = await panelText()
        XCTAssertTrue(topic, topicText)

        // Saved values survive a crash; ordinary state does not.
        await supervisor.event("button/Crash")
        _ = await waitUntil { await supervisor.restarts == 1 }
        let survived = await waitForPanel("saved 1")
        XCTAssertTrue(survived)
        await supervisor.stop()
        let listeners = await services.bus.listeners(of: "fixture.inbox")
        XCTAssertEqual(listeners, [], "a stopped plugin stops listening")
    }

    func testAPluginsChildrenDieWithIt() async throws {
        let fast = BackoffPolicy(initialDelay: 0.05, multiplier: 1, maxDelay: 0.05, maxConsecutiveFailures: 3)
        let supervisor = try PluginSupervisor.make(executable: Self.helper("FixturePlugin"), policy: fast)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        func panelText() async -> String { await supervisor.views[.panel].map { TreeTextRenderer.render($0) } ?? "" }

        // A crashed helper's `Process` children are re-parented before the host
        // hears of it (see PluginProcess), so a stop is what is checked here.
        await supervisor.event("button/Spawn")
        let spawned = await waitUntil(10) { await panelText().contains("status child ") }
        XCTAssertTrue(spawned)
        let text = await panelText()
        let digits = text.components(separatedBy: "status child ").last?.prefix { $0.isNumber } ?? ""
        let pid = try XCTUnwrap(Int32(digits))
        XCTAssertTrue(Self.isAlive(pid))

        await supervisor.stop()
        let gone = await waitUntil(10) { !Self.isAlive(pid) }
        XCTAssertTrue(gone, "a plugin's child outlived it")
    }

    /// True if `pid` exists and is not a zombie waiting for a reaper.
    static func isAlive(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 else { return false }
        #if os(Linux)
        if let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
           let close = stat.lastIndex(of: ")") {
            return !stat[close...].hasPrefix(") Z")
        }
        #endif
        return true
    }
}
