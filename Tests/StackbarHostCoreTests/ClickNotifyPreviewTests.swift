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
    private func run(_ plugin: String, system: SimulatedSystem = SimulatedSystem(), recorder: NotificationRecorder = NotificationRecorder()) async throws -> (PluginSupervisor, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(notify: recorder.record, system: system))
        let executable = PluginSupervisorTests.helper(plugin)
        let supervisor = PluginSupervisor(executable: executable, manifest: try PluginProcess.readManifest(executable: executable), services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        return (supervisor, directory)
    }

    func testClickingStayAwakesCupStartsAndStops() async throws {
        let system = SimulatedSystem()
        let (supervisor, directory) = try await run("StayAwakePlugin", system: system)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let click = await supervisor.menuBarClick else { return XCTFail("Stay Awake sets a click action") }
        XCTAssertTrue(click.title.contains("keep awake"), click.title)
        var before = await supervisor.settledCount
        await supervisor.event(click.action)
        _ = await waitUntil { await supervisor.settledCount > before }
        XCTAssertFalse(system.keptAwake.isEmpty, "a click starts a session")
        let stop = await supervisor.menuBarClick
        XCTAssertEqual(stop?.title, "Click to stop keeping awake")
        before = await supervisor.settledCount
        await supervisor.event(stop?.action ?? click.action)
        _ = await waitUntil { await supervisor.settledCount > before }
        XCTAssertTrue(system.keptAwake.isEmpty, "a second click stops it")
        await supervisor.stop()
    }

    func testUpNextReminderHasAJoinButton() async throws {
        let now = Date()
        let system = SimulatedSystem(events: [
            CalendarEvent(id: "soon", title: "Sync", start: now.addingTimeInterval(90), end: now.addingTimeInterval(1800), location: "https://meet.google.com/abc-defg-hij", calendar: "Work", participation: .accepted, attendees: 3),
        ])
        let recorder = NotificationRecorder()
        let (supervisor, directory) = try await run("UpNextPlugin", system: system, recorder: recorder)
        defer { try? FileManager.default.removeItem(at: directory) }
        let posted = await waitUntil(5) { !recorder.all.isEmpty }
        XCTAssertTrue(posted, "a meeting in 90 seconds is reminded about")
        XCTAssertEqual(recorder.all.first?.actions, [NotificationAction("Join", url: "https://meet.google.com/abc-defg-hij")])
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

    func testClipboardRowsCarryAPreview() async throws {
        let system = SimulatedSystem()
        let (supervisor, directory) = try await run("ClipboardPlugin", system: system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = await supervisor.settledCount
        let long = "func greet() {\n    print(\"hello\")\n}\n" + String(repeating: "// more\n", count: 20)
        system.simulateCopy(long)
        _ = await waitUntil(5) { await supervisor.settledCount > before }
        let found = await waitUntil(5) { await supervisor.views[.panel]?.rows.contains { $0.preview?.text?.contains("print(\"hello\")") == true } == true }
        XCTAssertTrue(found, "a long copy has its full text as a preview")
        let row = await supervisor.views[.panel]?.rows.first { $0.preview != nil }
        XCTAssertTrue(row?.preview?.caption?.contains("lines") == true, row?.preview?.caption ?? "no caption")
        await supervisor.stop()
    }

    func testPluginsDrawTheirCharts() async throws {
        let now = Date()
        let system = SimulatedSystem(events: [
            CalendarEvent(id: "a", title: "Planning", start: now.addingTimeInterval(600), end: now.addingTimeInterval(4200), calendar: "Work", participation: .accepted, attendees: 3),
            CalendarEvent(id: "b", title: "Overlapping", start: now.addingTimeInterval(2400), end: now.addingTimeInterval(6000), calendar: "Home", participation: .accepted, attendees: 2),
        ])
        let (upNext, upNextDirectory) = try await run("UpNextPlugin", system: system)
        defer { try? FileManager.default.removeItem(at: upNextDirectory) }
        let window = await upNext.views[.window].map { TreeTextRenderer.render($0) } ?? ""
        XCTAssertTrue(window.contains("Hours in meetings, next 7 days"), window)
        let panel = await upNext.views[.panel].map { TreeTextRenderer.render($0) } ?? ""
        // 10 min → 100 min overlapping 40 → 100 min: 1h 30m once, not 2h.
        XCTAssertTrue(panel.contains("1h 30m in meetings today") || !Calendar.current.isDate(now.addingTimeInterval(6000), inSameDayAs: now), panel)
        await upNext.stop()

        let (stayAwake, stayAwakeDirectory) = try await run("StayAwakePlugin")
        defer { try? FileManager.default.removeItem(at: stayAwakeDirectory) }
        let awake = await stayAwake.views[.panel].map { TreeTextRenderer.render($0) } ?? ""
        XCTAssertTrue(awake.contains("Hours awake") && awake.contains("(bar)"), awake)
        await stayAwake.stop()
    }

    func testDonutsRenderAsNamedValues() {
        let text = TreeTextRenderer.render(.chart(values: [3, 1], kind: .donut, label: "Kinds", options: ChartOptions(labels: ["Text", "Links"])))
        XCTAssertEqual(text, "Kinds: Text 3, Links 1 (donut)")
    }
}
