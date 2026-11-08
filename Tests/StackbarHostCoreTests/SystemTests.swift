import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// The clipboard, power and calendar services, and how they reach a plugin.
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
        let store = ClipboardImageStore(directory: directory, limit: 2, pruneEvery: 1)
        let first = try store.save(Data("one".utf8))
        XCTAssertEqual(try store.save(Data("one".utf8)), first)
        _ = try store.save(Data("two".utf8))
        _ = try store.save(Data("three".utf8))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 2)
        XCTAssertNil(store.data(for: "../secrets"), "ids are hex only")
    }

    func testCalendarEventIDsKeepAnAtSignInTheIdentifier() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let id = CalendarEventID.make(identifier: "040000008200E0@example.com", start: start)
        XCTAssertEqual(id, "040000008200E0@example.com@1700000000")
        let split = CalendarEventID.split(id)
        XCTAssertEqual(split.identifier, "040000008200E0@example.com", "the start is after the last @")
        XCTAssertEqual(split.start, 1_700_000_000)
        XCTAssertEqual(CalendarEventID.split("ABC-123").identifier, "ABC-123")
        XCTAssertNil(CalendarEventID.split("ABC-123").start)
        XCTAssertEqual(CalendarEventID.split("someone@example.com").identifier, "someone@example.com", "no start: the whole id")
    }

    func testImageStorePrunesOnTheFirstSaveThenEveryFewSaves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Left over from an earlier launch, older than anything saved now.
        for index in 0..<3 {
            let file = directory.appendingPathComponent("old\(index).bin")
            try Data("old \(index)".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: file.path)
        }
        let store = ClipboardImageStore(directory: directory, limit: 2, pruneEvery: 3)
        func count() throws -> Int { try FileManager.default.contentsOfDirectory(atPath: directory.path).count }

        let first = try store.save(Data("one".utf8))
        XCTAssertEqual(try count(), 2, "the first save prunes what an earlier launch left")
        XCTAssertNotNil(store.data(for: first), "the newest is kept")
        _ = try store.save(Data("two".utf8))
        _ = try store.save(Data("three".utf8))
        XCTAssertEqual(try count(), 4, "the saves in between don't list the folder")
        _ = try store.save(Data("four".utf8))
        XCTAssertEqual(try count(), 2, "every third save prunes again")
    }

    /// The SystemFixture plugin, started and settled.
    private func fixture(_ services: HostServices) async throws -> PluginSupervisor {
        let executable = PluginSupervisorTests.helper("SystemFixturePlugin")
        let supervisor = PluginSupervisor(executable: executable, manifest: try PluginProcess.readManifest(executable: executable), services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        return supervisor
    }

    func testTheClipboardTriggerFiresAndRowsPasteWhatWasCopied() async throws {
        let system = SimulatedSystem()
        let (services, directory) = services(system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let supervisor = try await fixture(services)
        func rows() async -> [RowNode] { await supervisor.views[.panel]?.rows ?? [] }

        system.simulateCopy("first thing")
        let recorded = await waitUntil(10) { await rows().map(\.title) == ["first thing"] }
        XCTAssertTrue(recorded, "the clipboard trigger fires on a copy")
        system.simulateCopy("hunter2", concealed: true)
        system.simulateCopy("**bold**", formatted: true)
        _ = await waitUntil(10) { await rows().first?.title == "**bold**" }
        let titles = await rows().map(\.title)
        XCTAssertFalse(titles.contains("hunter2"), "a concealed copy never shows its text: \(titles)")

        guard let plain = await rows().first(where: { $0.title == "first thing" }), let rich = await rows().first(where: { $0.title == "**bold**" }) else { return XCTFail("rows: \(titles)") }
        await supervisor.event(ActionID("row/\(plain.key)/Paste"))
        _ = await waitUntil(5) { system.pasted.count == 1 }
        XCTAssertEqual(system.pasted, [.text("first thing")])
        await supervisor.event(ActionID("row/\(rich.key)/Paste"))
        _ = await waitUntil(5) { system.pasted.count == 2 }
        guard case .stored = system.pasted.last else { return XCTFail("a formatted copy pastes the host's stored original: \(system.pasted)") }
        await supervisor.stop()
    }

    func testCalendarEventsReachThePlugin() async throws {
        let now = Date()
        let system = SimulatedSystem(events: [
            CalendarEvent(id: "a", title: "Planning", start: now.addingTimeInterval(600), end: now.addingTimeInterval(2400), calendar: "Work", participation: .accepted, attendees: 3),
        ])
        let (services, directory) = services(system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let supervisor = try await fixture(services)
        let menu = await supervisor.views[.menuBar].map { TreeTextRenderer.render($0) } ?? ""
        XCTAssertEqual(menu, "Planning")
        await supervisor.stop()
    }
}

final class SettingsSurfaceTests: XCTestCase {
    /// Preferences live on the settings surface, not in the panel, and their
    /// controls still work from there.
    func testPreferencesStayOutOfThePanelAndWorkFromSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: SimulatedSystem()))
        let executable = PluginSupervisorTests.helper("SystemFixturePlugin")
        let manifest = try PluginProcess.readManifest(executable: executable)
        XCTAssertTrue(manifest.surfaces.contains(.settings))
        let supervisor = PluginSupervisor(executable: executable, manifest: manifest, services: services)
        await supervisor.start()
        _ = await waitUntil { await supervisor.settledCount >= supervisor.startupMessageCount }
        let panel = await supervisor.views[.panel].map { TreeTextRenderer.render($0) } ?? ""
        XCTAssertFalse(panel.contains("Compact rows"), panel)
        func toggle() async -> (isOn: Bool, action: ActionID)? {
            func find(_ node: ViewNode) -> (isOn: Bool, action: ActionID)? {
                if case .toggle("Compact rows", let isOn, let action) = node { return (isOn, action) }
                return node.children.lazy.compactMap(find).first
            }
            return await supervisor.views[.settings].flatMap(find)
        }
        guard let off = await toggle(), !off.isOn else { return XCTFail("the settings surface has the preference") }
        let before = await supervisor.settledCount
        await supervisor.event(off.action, value: .bool(true))
        _ = await waitUntil { await supervisor.settledCount > before }
        let on = await toggle()
        XCTAssertEqual(on?.isOn, true, "the toggle works from settings")
        await supervisor.stop()
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

    /// `Stackbar.open(url)` follows the manifest like `open(_:with:)`: a
    /// declared scheme opens, and with "*" a folder does, but not a program.
    func testOpenURLHonoursDeclaredSchemesAndPaths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = HostServices.local(directory: directory.appendingPathComponent("home"), secrets: MemorySecretStore([:]))

        let panes = Manifest(id: "dev.test.panes", name: "Panes", capabilities: [.openURLs(schemes: ["x-apple.systempreferences"])])
        guard case .ok = await services.handle(.openURL("x-apple.systempreferences:com.apple.Network-Settings.extension"), for: panes) else { return XCTFail("a declared scheme opens") }
        guard case .failure = await services.handle(.openURL(directory.path), for: panes) else { return XCTFail("a path needs \"*\"") }

        let files = Manifest(id: "dev.test.files", name: "Files", capabilities: [.openURLs(schemes: ["*"])])
        guard case .ok = await services.handle(.openURL(directory.path), for: files) else { return XCTFail("a folder opens with \"*\"") }
        let program = directory.appendingPathComponent("tool")
        FileManager.default.createFile(atPath: program.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        guard case .failure = await services.handle(.openURL(program.path), for: files) else { return XCTFail("a program needs an app chosen explicitly") }
    }

    /// stackbarctl keeps plugins' saved values out of the app's own folder
    /// unless asked, or unless STACKBAR_HOME moves everything.
    func testToolStorageIsScratchByDefault() {
        let scratch = StackbarPaths.toolStorageDirectory(realStorage: false, environment: [:])
        XCTAssertNotEqual(scratch.standardizedFileURL, StackbarPaths.storageDirectory.standardizedFileURL)
        XCTAssertTrue(scratch.path.hasSuffix("stackbarctl/Storage"))
        XCTAssertEqual(StackbarPaths.toolStorageDirectory(realStorage: true, environment: [:]), StackbarPaths.storageDirectory)
        XCTAssertEqual(StackbarPaths.toolStorageDirectory(realStorage: false, environment: ["STACKBAR_HOME": "/tmp/x"]), StackbarPaths.storageDirectory)
    }
}
