import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// The rules `HostServices.handle` applies to more than one call: what may
/// be opened, what a notification or an alert carries, and how long notes
/// may be.
final class HostServicesRulesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private final class Opened: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [String] = []
        private var withApp: [String] = []
        var plain: [String] { lock.withLock { urls } }
        var chosen: [String] { lock.withLock { withApp } }
        func open(_ url: URL) { lock.withLock { urls.append(url.absoluteString) } }
        func openIn(_ url: URL, _ app: String) throws {
            if app == "missing" { throw SystemServiceError("missing is not installed") }
            lock.withLock { withApp.append("\(app) \(url.absoluteString)") }
        }
    }

    private func services(_ opened: Opened = Opened(), notify: NotificationRecorder = NotificationRecorder(), alert: NotificationRecorder = NotificationRecorder(),
                          system: SimulatedSystem = SimulatedSystem()) -> HostServices {
        HostServices.local(directory: directory.appendingPathComponent("home"), secrets: MemorySecretStore([:]),
                           platform: .init(notify: notify.record, alert: alert.record, open: { opened.open($0) }, openWith: { try opened.openIn($0, $1) }, system: system))
    }

    // MARK: Opening

    private func makeProgram() throws -> URL {
        let program = directory.appendingPathComponent("tool")
        try Data("#!/bin/sh\n".utf8).write(to: program)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        return program
    }

    func testOpenAndOpenURLFollowTheSameRules() async throws {
        let opened = Opened()
        let services = services(opened)
        let plain = Manifest(id: "dev.test.plain", name: "Plain")
        let files = Manifest(id: "dev.test.files", name: "Files", capabilities: [.openURLs(schemes: ["*"])])
        let program = try makeProgram()

        for call: HostCall in [.openURL("https://example.com/a"), .open(url: "https://example.com/a", app: nil)] {
            guard case .ok = await services.handle(call, for: plain) else { return XCTFail("\(call) opens") }
        }
        XCTAssertEqual(opened.plain, ["https://example.com/a", "https://example.com/a"])

        for call: HostCall in [.openURL("slack://open"), .open(url: "slack://open", app: nil), .open(url: "slack://open", app: "com.tinyspeck.slackmacgap"),
                               .openURL(directory.path), .open(url: directory.path, app: nil), .openURL("not a url"), .open(url: "not a url", app: nil)] {
            guard case .failure = await services.handle(call, for: plain) else { return XCTFail("\(call) is refused without the capability") }
        }

        for call: HostCall in [.openURL(program.path), .open(url: program.path, app: nil)] {
            guard case .failure(let message) = await services.handle(call, for: files) else { return XCTFail("\(call): a program needs an app") }
            XCTAssertEqual(message, "\(program.path) is a program; open it with an app chosen explicitly")
        }
        XCTAssertEqual(opened.plain.count, 2, "nothing refused was opened")
        XCTAssertTrue(opened.chosen.isEmpty)
    }

    func testOpenWithAnAppGoesToThatAppAndSaysWhenItIsMissing() async throws {
        let opened = Opened()
        let services = services(opened)
        let files = Manifest(id: "dev.test.files", name: "Files", capabilities: [.openURLs(schemes: ["*"])])
        let program = try makeProgram()

        guard case .ok = await services.handle(.open(url: "https://example.com", app: "com.apple.Safari"), for: files) else { return XCTFail("opens in the app") }
        guard case .ok = await services.handle(.open(url: program.path, app: "com.apple.Terminal"), for: files) else { return XCTFail("a program opens in a chosen app") }
        XCTAssertEqual(opened.chosen, ["com.apple.Safari https://example.com", "com.apple.Terminal \(URL(fileURLWithPath: program.path).absoluteString)"])
        XCTAssertTrue(opened.plain.isEmpty)

        guard case .failure(let message) = await services.handle(.open(url: "https://example.com", app: "missing"), for: files) else { return XCTFail("the app is missing") }
        XCTAssertEqual(message, "missing is not installed")
    }

    // MARK: Notifications and alerts

    func testNotificationsAndAlertsAreCutAndCheckedAlike() async {
        let (notified, alerted) = (NotificationRecorder(), NotificationRecorder())
        let services = services(notify: notified, alert: alerted)
        let manifest = Manifest(id: "dev.test.notify", name: "Notify", capabilities: [])
        let title = String(repeating: "t", count: 250)
        let body = String(repeating: "b", count: 1200)
        let buttons = (1...4).map { NotificationAction(String(repeating: "\($0)", count: 50), url: "https://example.com/\($0)") }

        guard case .ok = await services.handle(.notify(title: title, body: body, actions: buttons), for: manifest) else { return XCTFail("notify") }
        guard case .ok = await services.handle(.alert(title: title, body: body, actions: buttons), for: manifest) else { return XCTFail("alert") }
        XCTAssertEqual(notified.all.count, 1)
        XCTAssertEqual(notified.all, alerted.all, "an alert carries what the notification would")
        let posted = notified.all[0]
        XCTAssertEqual(posted.pluginID, "dev.test.notify")
        XCTAssertEqual(posted.pluginName, "Notify")
        XCTAssertEqual(posted.title.count, 200)
        XCTAssertEqual(posted.body?.count, 1000)
        XCTAssertEqual(posted.actions.map(\.title.count), [40, 40, 40], "three buttons, titles cut to 40")
        XCTAssertEqual(posted.actions.map(\.url), ["https://example.com/1", "https://example.com/2", "https://example.com/3"])

        // Each plugin has its own budget of alerts, so the next calls come from others.
        let second = Manifest(id: "dev.test.second", name: "Second")
        guard case .ok = await services.handle(.notify(title: "plain", body: nil, actions: nil), for: second) else { return XCTFail("no buttons") }
        XCTAssertEqual(notified.all.last, HostNotification(pluginID: "dev.test.second", pluginName: "Second", title: "plain"))

        let bad = [NotificationAction("Run", url: "file:///bin/sh")]
        let expected = "button \"Run\" opens file:///bin/sh; only https, http, mailto, tel and meeting app URLs can be opened"
        for call: HostCall in [.notify(title: "x", body: nil, actions: bad), .alert(title: "x", body: nil, actions: bad)] {
            guard case .failure(let message) = await services.handle(call, for: Manifest(id: "dev.test.third", name: "Third")) else { return XCTFail("\(call) has a button that opens a file") }
            XCTAssertEqual(message, expected)
        }
        XCTAssertEqual(notified.all.count, 2)
        XCTAssertEqual(alerted.all.count, 1)
    }

    // MARK: Notes

    func testNotesAreCutTo4000CharactersGoingOutAndComingIn() async throws {
        let long = String(repeating: "n", count: 5000)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let system = SimulatedSystem(events: [CalendarEvent(id: "e", title: "Review", start: start, end: start.addingTimeInterval(3600), notes: long)])
        let services = services(system: system)
        let manifest = Manifest(id: "dev.test.notes", name: "Notes", capabilities: [.calendar, .reminders])

        let listed = await services.handle(.calendarEvents(from: start.addingTimeInterval(-60), to: start.addingTimeInterval(7200)), for: manifest)
        let events = try XCTUnwrap(HostReplies.calendarEvents.decode(listed))
        XCTAssertEqual(events.map { $0.notes?.count }, [4000])

        let answer = await services.handle(.saveReminder(Reminder(title: "Long", notes: long), fields: nil), for: manifest)
        let saved = try XCTUnwrap(HostReplies.saveReminder.decode(answer))
        XCTAssertEqual(saved.notes?.count, 4000, "cut before it is saved")
        XCTAssertEqual(system.simulatedReminders.reminders.first { $0.id == saved.id }?.notes?.count, 4000)

        var state = system.simulatedReminders
        state.reminders = [Reminder(id: "r", list: state.lists.first?.id ?? "", title: "Kept elsewhere", notes: long)]
        system.simulate(reminders: state)
        let all = await services.handle(.reminders(ReminderQuery()), for: manifest)
        let read = try XCTUnwrap(HostReplies.reminders.decode(all))
        XCTAssertEqual(read.map { $0.notes?.count }, [4000], "cut on the way to the plugin")
    }

    // MARK: Files

    func testAFileTooLargeToSaveIsRefused() async {
        let services = services()
        let manifest = Manifest(id: "dev.test.files", name: "Files", capabilities: [.files(paths: [])])
        let big = Data(count: ChosenFile.maxBytes + 1)
        guard case .failure(let message) = await services.handle(.saveFile(name: "a.bin", data: big), for: manifest) else { return XCTFail("too large") }
        XCTAssertEqual(message, "files saved this way are at most 5 MB")
    }
}
