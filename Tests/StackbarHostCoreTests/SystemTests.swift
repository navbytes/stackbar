import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// The clipboard, power and calendar services, and the plugins built on them.
final class SystemServicesTests: XCTestCase {
    private func services(_ system: SimulatedSystem) -> (HostServices, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system)), directory)
    }

    func testSystemCallsNeedTheirCapabilities() async throws {
        let system = SimulatedSystem()
        let (services, directory) = services(system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        for call: HostCall in [.clipboardRead, .clipboardWrite(.text("x")), .paste(.text("x")), .keepAwake(KeepAwakeRequest()), .systemStatus, .calendarEvents(from: Date(), to: Date().addingTimeInterval(60))] {
            guard case .failure(let message) = await services.handle(call, for: bare) else { return XCTFail("\(call) went through without a capability") }
            XCTAssertTrue(message.contains("to the manifest's capabilities"), message)
        }
        guard case .ok = await services.handle(.keepAwake(nil), for: bare) else { return XCTFail("letting go never needs a capability") }

        let granted = Manifest(id: "dev.test.all", name: "All", capabilities: [.clipboard, .power, .calendar])
        system.simulateCopy("secret", concealed: true)
        guard case .value(let json?) = await services.handle(.clipboardRead, for: granted) else { return XCTFail("no clipboard") }
        let item = try SystemCodec.decode(ClipboardItem.self, from: json)
        XCTAssertTrue(item.concealed)
        XCTAssertNil(item.text, "a concealed item's content never leaves the host")

        guard case .ok = await services.handle(.keepAwake(KeepAwakeRequest(display: false, reason: "tests")), for: granted) else { return XCTFail("keepAwake failed") }
        XCTAssertEqual(system.keptAwake["dev.test.all"], KeepAwakeRequest(display: false, reason: "All: tests"), "the reason names the plugin")
        services.release(pluginID: "dev.test.all")
        XCTAssertTrue(system.keptAwake.isEmpty)

        guard case .failure = await services.handle(.calendarEvents(from: Date(), to: Date().addingTimeInterval(40 * 86400)), for: granted) else { return XCTFail("ranges are capped") }
        guard case .value(let events?) = await services.handle(.calendarEvents(from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(86400)), for: granted) else { return XCTFail("no events") }
        XCTAssertFalse(try SystemCodec.decode([CalendarEvent].self, from: events).isEmpty)
    }

    func testImageStoreDedupesAndPrunes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardImageStore(directory: directory, limit: 2)
        let first = try store.save(Data("one".utf8))
        XCTAssertEqual(try store.save(Data("one".utf8)), first)
        _ = try store.save(Data("two".utf8))
        _ = try store.save(Data("three".utf8))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 2)
        XCTAssertNil(store.data(for: "../secrets"), "ids are hex only")
    }

    func testClipboardHistoryRecordsCopiesAndSkipsPasswords() async throws {
        let system = SimulatedSystem()
        let (services, directory) = services(system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try PluginProcess.readManifest(executable: PluginSupervisorTests.helper("ClipboardPlugin"))
        let supervisor = PluginSupervisor(executable: PluginSupervisorTests.helper("ClipboardPlugin"), manifest: manifest, services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        func panel() async -> String { await supervisor.views[.panel].map { TreeTextRenderer.render($0) } ?? "" }

        // The host polls twice a second, like other clipboard managers, so
        // copies further apart than that are each recorded.
        func copy(_ text: String, app: SystemStatus.App? = SystemStatus.App(id: "com.apple.Safari", name: "Safari"), concealed: Bool = false, formatted: Bool = false) async {
            let before = await supervisor.settledCount
            system.simulateCopy(text, app: app, concealed: concealed, formatted: formatted)
            _ = await waitUntil(5) { await supervisor.settledCount > before }
        }
        await copy("first thing")
        await copy("https://example.com/page")
        let recorded = await waitUntil(10) { await panel().contains("https://example.com/page") }
        XCTAssertTrue(recorded, "the clipboard trigger fires on a copy")
        await copy("hunter2", concealed: true)
        await copy("from a password manager", app: SystemStatus.App(id: "com.1password.1password", name: "1Password"))
        await copy("last thing")
        _ = await waitUntil(10) { await panel().contains("last thing") }
        var text = await panel()
        XCTAssertFalse(text.contains("hunter2"))
        XCTAssertFalse(text.contains("password manager"), "ignored apps are skipped")

        guard let row = await supervisor.views[.panel]?.rows.first(where: { $0.title == "first thing" }) else { return XCTFail("no row:\n\(text)") }
        let count = await supervisor.settledCount
        await supervisor.event(ActionID("row/\(row.key)/Paste"))
        _ = await waitUntil { await supervisor.settledCount > count }
        XCTAssertEqual(system.pasted, [.text("first thing")])
        let moved = await waitUntil(10) { await supervisor.views[.panel]?.rows.first?.title == "first thing" }
        text = await panel()
        XCTAssertTrue(moved, "a pasted item moves to the top:\n\(text)")

        // Formatted text is pasted back as it was copied, or as plain text on request.
        await copy("**bold**", formatted: true)
        _ = await waitUntil(10) { await supervisor.views[.panel]?.rows.first?.title == "**bold**" }
        guard let rich = await supervisor.views[.panel]?.rows.first(where: { $0.title == "**bold**" }) else { return XCTFail("no formatted row") }
        XCTAssertTrue(rich.actions.map(\.title).contains("Paste as plain text"))
        await supervisor.event(ActionID("row/\(rich.key)/Paste"))
        _ = await waitUntil(5) { system.pasted.count == 2 }
        guard case .stored = system.pasted.last else { return XCTFail("formatted copies paste their stored original: \(system.pasted)") }
        await supervisor.event(ActionID("row/\(rich.key)/Paste as plain text"))
        _ = await waitUntil(5) { system.pasted.count == 3 }
        XCTAssertEqual(system.pasted.last, .text("**bold**"))
        await supervisor.stop()
    }

    func testStayAwakeHoldsAndReleasesTheAssertion() async throws {
        let system = SimulatedSystem()
        let (services, directory) = services(system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fast = BackoffPolicy(initialDelay: 0.05, multiplier: 1, maxDelay: 0.05, maxConsecutiveFailures: 3)
        let manifest = try PluginProcess.readManifest(executable: PluginSupervisorTests.helper("StayAwakePlugin"))
        let supervisor = PluginSupervisor(executable: PluginSupervisorTests.helper("StayAwakePlugin"), manifest: manifest, policy: fast, services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        XCTAssertTrue(system.keptAwake.isEmpty)

        await supervisor.event("row/for-60/Start")
        let held = await waitUntil(10) { system.keptAwake["io.navbytes.stackbar.stay-awake"] != nil }
        XCTAssertTrue(held)
        let result = await supervisor.callTool("awake_status")
        XCTAssertTrue(result.text.contains("left"), result.text)

        // A low battery ends the hold on the next refresh.
        system.simulate(status: SystemStatus(batteryLevel: 0.1, onACPower: false))
        await supervisor.refresh()
        let released = await waitUntil(10) { system.keptAwake.isEmpty }
        XCTAssertTrue(released, "the battery floor lets the Mac sleep")
        system.simulate(status: SystemStatus(batteryLevel: 0.9, onACPower: true))
        await supervisor.refresh()
        _ = await waitUntil(10) { !system.keptAwake.isEmpty }
        XCTAssertFalse(system.keptAwake.isEmpty, "the session resumes once the battery is fine")

        await supervisor.event("field/For a while, like 90m or 1h30", value: .text("1h30"))
        let custom = await waitUntil(10) {
            let status = await supervisor.callTool("awake_status").text
            return status.contains("1h 29m left") || status.contains("1h 30m left")
        }
        XCTAssertTrue(custom, "a typed duration starts a session")

        await supervisor.stop()
        XCTAssertTrue(system.keptAwake.isEmpty, "stopping a plugin releases its assertion")
    }

    func testUpNextFindsTheMeetingAndItsLink() async throws {
        let now = Date()
        let system = SimulatedSystem(events: [
            CalendarEvent(id: "a", title: "Planning", start: now.addingTimeInterval(600), end: now.addingTimeInterval(2400), notes: "Join Zoom Meeting\nhttps://acme.zoom.us/j/987654321?pwd=xyz.", calendar: "Work", participation: .accepted, attendees: 3),
            CalendarEvent(id: "b", title: "Declined thing", start: now.addingTimeInterval(300), end: now.addingTimeInterval(900), location: "https://meet.google.com/aaa-bbbb-ccc", calendar: "Work", participation: .declined),
        ])
        let (services, directory) = services(system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try PluginProcess.readManifest(executable: PluginSupervisorTests.helper("UpNextPlugin"))
        let supervisor = PluginSupervisor(executable: PluginSupervisorTests.helper("UpNextPlugin"), manifest: manifest, services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        let menu = await supervisor.views[.menuBar].map { TreeTextRenderer.render($0) } ?? ""
        XCTAssertTrue(menu.contains("Planning · in 10m"), menu)
        let next = await supervisor.callTool("next_meeting")
        XCTAssertTrue(next.text.contains("https://acme.zoom.us/j/987654321?pwd=xyz"), "trailing punctuation is trimmed: \(next.text)")
        XCTAssertTrue(next.text.contains("Zoom"))
        let menuRows = await supervisor.views[.panel]?.rows.map(\.title) ?? []
        XCTAssertEqual(menuRows.first, "Planning", "the next meeting is the first row, so Return joins it: \(menuRows)")
        await supervisor.stop()
    }
}

final class SettingsSurfaceTests: XCTestCase {
    /// Preferences live on the settings surface, not in the panel, and their
    /// controls still work from there.
    func testBundledPluginsKeepPreferencesOutOfThePanel() async throws {
        let cases: [(plugin: String, preference: String)] = [
            ("ClipboardPlugin", "Paste into the app on click"),
            ("StayAwakePlugin", "Pause in Low Power Mode"),
            ("UpNextPlugin", "Open the call when it starts"),
            ("PRCockpitPlugin", "Include drafts to review"),
        ]
        for (plugin, preference) in cases {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: SimulatedSystem()))
            let executable = PluginSupervisorTests.helper(plugin)
            let manifest = try PluginProcess.readManifest(executable: executable)
            XCTAssertTrue(manifest.surfaces.contains(.settings), plugin)
            let supervisor = PluginSupervisor(executable: executable, manifest: manifest, services: services)
            await supervisor.start()
            _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
            let panel = await supervisor.views[.panel].map { TreeTextRenderer.render($0) } ?? ""
            let settings = await supervisor.views[.settings].map { TreeTextRenderer.render($0) } ?? ""
            XCTAssertFalse(panel.contains(preference), "\(plugin)'s panel still has \(preference)")
            XCTAssertTrue(settings.contains(preference), "\(plugin)'s settings lack \(preference): \(settings)")
            await supervisor.stop()
        }
    }
}

final class OpenURLTests: XCTestCase {
    func testMeetingAppSchemesOpenButOthersDont() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]))
        let manifest = Manifest(id: "dev.test.open", name: "Open")
        for url in ["https://example.com", "zoommtg://acme.zoom.us/join?action=join&confno=1", "msteams:/l/meetup-join/x"] {
            guard case .ok = await services.handle(.openURL(url), for: manifest) else { return XCTFail("\(url) should open") }
        }
        for url in ["file:///etc/passwd", "javascript:alert(1)", "x-apple.systempreferences:"] {
            guard case .failure = await services.handle(.openURL(url), for: manifest) else { return XCTFail("\(url) must not open") }
        }
    }
}
