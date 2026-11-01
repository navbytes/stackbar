import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Records what the host would post.
final class NotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var posted: [HostNotification] = []
    var all: [HostNotification] { lock.withLock { posted } }
    func record(_ note: HostNotification) { lock.withLock { posted.append(note) } }
}

final class ClickNotifyPreviewTests: XCTestCase {
    private let pluginID = "io.navbytes.stackbar.test.system"

    private func run(system: SimulatedSystem = SimulatedSystem(), recorder: NotificationRecorder = NotificationRecorder(), alerts: NotificationRecorder = NotificationRecorder()) async throws -> (PluginSupervisor, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(notify: recorder.record, alert: alerts.record, system: system))
        let executable = PluginSupervisorTests.helper("SystemFixturePlugin")
        let supervisor = PluginSupervisor(executable: executable, manifest: try PluginProcess.readManifest(executable: executable), services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        return (supervisor, directory)
    }

    private func press(_ supervisor: PluginSupervisor, _ action: ActionID) async {
        let before = await supervisor.settledCount
        await supervisor.event(action)
        _ = await waitUntil { await supervisor.settledCount > before }
    }

    func testAMenuBarClickRunsAndSwapsThePluginsAction() async throws {
        let system = SimulatedSystem()
        let (supervisor, directory) = try await run(system: system)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let click = await supervisor.menuBarClick else { return XCTFail("the fixture sets a click action") }
        XCTAssertEqual(click.title, "Keep awake")
        await press(supervisor, click.action)
        XCTAssertEqual(system.keptAwake[pluginID]?.reason, "System Fixture: clicked", "a click reaches the platform")
        let stop = await supervisor.menuBarClick
        XCTAssertEqual(stop?.title, "Let the Mac sleep", "the action follows the plugin's state")
        await press(supervisor, stop?.action ?? click.action)
        XCTAssertTrue(system.keptAwake.isEmpty, "a second click stops it")

        await press(supervisor, click.action)
        XCTAssertFalse(system.keptAwake.isEmpty)
        await supervisor.stop()
        XCTAssertTrue(system.keptAwake.isEmpty, "stopping a plugin releases its assertion")
    }

    func testNotificationButtonsReachThePlatform() async throws {
        let recorder = NotificationRecorder()
        let (supervisor, directory) = try await run(recorder: recorder)
        defer { try? FileManager.default.removeItem(at: directory) }
        await supervisor.event("button/Notify")
        let posted = await waitUntil(5) { !recorder.all.isEmpty }
        XCTAssertTrue(posted)
        XCTAssertEqual(recorder.all.first?.actions, [NotificationAction("Join", url: "https://meet.google.com/abc-defg-hij")])
        XCTAssertEqual(recorder.all.first?.pluginID, pluginID)
        await supervisor.stop()
    }

    func testNotificationButtonsMustOpenAllowedURLs() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = NotificationRecorder()
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(notify: recorder.record))
        let manifest = Manifest(id: "dev.test.notify", name: "Notify")
        guard case .failure = await services.handle(.notify(title: "Hi", body: nil, actions: [NotificationAction("Run", url: "file:///Applications/Calculator.app")]), for: manifest) else { return XCTFail("file URLs are refused") }
        let many = (1...5).map { NotificationAction("Open \($0)", url: "https://example.com/\($0)") }
        guard case .ok = await services.handle(.notify(title: "Hi", body: nil, actions: many), for: manifest) else { return XCTFail("https buttons are fine") }
        XCTAssertEqual(recorder.all.first?.actions.count, 3, "at most three buttons")
        XCTAssertEqual(recorder.all.first?.pluginID, "dev.test.notify")
    }
    func testAlertButtonsReachThePlatform() async throws {
        let alerts = NotificationRecorder()
        let (supervisor, directory) = try await run(alerts: alerts)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(alerts.all.isEmpty)
        await supervisor.event("button/Alert")
        let shown = await waitUntil(5) { !alerts.all.isEmpty }
        XCTAssertTrue(shown, "an alert covers the screen")
        XCTAssertEqual(alerts.all.first?.title, "Board call")
        XCTAssertEqual(alerts.all.first?.actions.map(\.title), ["Join", "Call in"])
        XCTAssertEqual(alerts.all.first?.actions.last?.url, "tel:+16465588656,,123456789%23", "a tel: button passes through as written")
        await supervisor.stop()
    }

    func testClipboardRowsCarryAPreview() async throws {
        let system = SimulatedSystem()
        let (supervisor, directory) = try await run(system: system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = await supervisor.settledCount
        let long = "func greet() {\n    print(\"hello\")\n}\n" + String(repeating: "// more\n", count: 20)
        system.simulateCopy(long)
        _ = await waitUntil(5) { await supervisor.settledCount > before }
        let found = await waitUntil(5) { await supervisor.views[.panel]?.rows.contains { $0.preview?.text?.contains("print(\"hello\")") == true } == true }
        XCTAssertTrue(found, "a row's preview reaches the host")
        let row = await supervisor.views[.panel]?.rows.first { $0.preview != nil }
        XCTAssertEqual(row?.preview?.caption, "24 lines")
        await supervisor.stop()
    }

    func testDonutsRenderAsNamedValues() {
        let text = TreeTextRenderer.render(.chart(values: [3, 1], kind: .donut, label: "Kinds", options: ChartOptions(labels: ["Text", "Links"])))
        XCTAssertEqual(text, "Kinds: Text 3 (75.0%), Links 1 (25.0%) (donut)")
        let heatmap = TreeTextRenderer.render(.chart(values: [0, 2_000_000, 5], kind: .heatmap, label: "Activity", options: ChartOptions(labels: ["Mon", "Tue", "Wed"], unit: " tokens")))
        XCTAssertTrue(heatmap.hasSuffix("(heatmap: 3 days, 2 active, busiest Tue 2M tokens)"), heatmap)
    }
}
