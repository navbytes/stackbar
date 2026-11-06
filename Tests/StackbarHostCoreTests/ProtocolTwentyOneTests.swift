import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Protocol 21: adding calendar events, opening a terminal, reading text in
/// images and on screen, sensors, and notification buttons that run a
/// plugin's own command.
final class ProtocolTwentyOneTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func services(_ system: SimulatedSystem, notify: NotificationRecorder? = nil) -> HostServices {
        if let notify {
            return HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(notify: notify.record, system: system))
        }
        return HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system))
    }

    /// The value a call answered with, as its reply type reads it.
    private func value<T>(_ reply: HostReply<T>, _ result: HostResult) throws -> T {
        try XCTUnwrap(reply.decode(result), "expected a value, got \(result)")
    }

    func testEachCallNeedsItsCapability() async {
        let services = services(SimulatedSystem())
        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        let calls: [(HostCall, String)] = [
            (.saveCalendarEvent(CalendarEventDraft(title: "x", start: Date(), end: Date())), "calendarWrite"),
            (.writableCalendars, "calendarWrite"),
            (.openInTerminal(command: ["ls"], title: nil), "terminal"),
            (.recognizeText(imageID: "abc", languages: nil), "clipboard"),
            (.captureScreenText(languages: nil), "screenText"),
            (.sensors, "sensors"),
        ]
        for (call, capability) in calls {
            guard case .failure(let message) = await services.handle(call, for: bare) else { return XCTFail("\(call) went through without .\(capability)") }
            XCTAssertTrue(message.contains(capability), message)
        }
        // Reading a calendar is not enough to write one.
        let reader = Manifest(id: "dev.test.read", name: "Read", capabilities: [.calendar])
        guard case .failure = await services.handle(.writableCalendars, for: reader) else { return XCTFail(".calendar doesn't add events") }
        for capability: Capability in [.calendarWrite, .terminal, .screenText, .sensors] {
            XCTAssertEqual(SandboxEntitlements.entitlements(for: Manifest(id: "dev.test.e", name: "E", capabilities: [capability])), ["com.apple.security.app-sandbox": true], "the host does \(capability) for the helper")
            XCTAssertFalse(capability.summary.isEmpty)
        }
    }

    func testAddsAndChangesCalendarEvents() async throws {
        let system = SimulatedSystem()
        let services = services(system)
        let manifest = Manifest(id: "dev.test.cal", name: "Cal", capabilities: [.calendar, .calendarWrite])
        let calendars = try value(HostReplies.writableCalendars, await services.handle(.writableCalendars, for: manifest))
        XCTAssertEqual(calendars.map(\.title), ["Work", "Home"])
        XCTAssertEqual(calendars.first(where: \.isDefault)?.id, "work")

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let added = try value(HostReplies.saveCalendarEvent, await services.handle(.saveCalendarEvent(CalendarEventDraft(title: "Lunch", start: start, end: start + 3600, calendarID: "home", alertMinutes: 10)), for: manifest))
        XCTAssertEqual(added.calendar, "Home")
        XCTAssertFalse(added.id.isEmpty)
        var moved = CalendarEventDraft(id: added.id, title: "Lunch with Sam", start: start + 1800, end: start + 5400, calendarID: "home")
        let changed = try value(HostReplies.saveCalendarEvent, await services.handle(.saveCalendarEvent(moved), for: manifest))
        XCTAssertEqual(changed.id, added.id)
        XCTAssertEqual(changed.title, "Lunch with Sam")
        let listed = try value(HostReplies.calendarEvents, await services.handle(.calendarEvents(from: start, to: start + 86400), for: manifest))
        XCTAssertEqual(listed.filter { $0.id == added.id }.map(\.start), [start + 1800])

        moved.end = moved.start - 60
        guard case .failure(let backwards) = await services.handle(.saveCalendarEvent(moved), for: manifest) else { return XCTFail("an event can't end before it starts") }
        XCTAssertTrue(backwards.contains("before it starts"), backwards)
        guard case .failure = await services.handle(.saveCalendarEvent(CalendarEventDraft(title: "  ", start: start, end: start)), for: manifest) else { return XCTFail("an event needs a title") }
        guard case .failure = await services.handle(.saveCalendarEvent(CalendarEventDraft(title: "x", start: start, end: start, calendarID: "nope")), for: manifest) else { return XCTFail("an unknown calendar is refused") }
    }

    func testTerminalCommandsAreWordsNotShellAndRateLimited() async {
        let system = SimulatedSystem()
        let services = services(system)
        let manifest = Manifest(id: "dev.test.term", name: "Term", capabilities: [.terminal])
        let opened = await services.handle(.openInTerminal(command: ["docker", "exec", "-it", "web; rm -rf ~", "sh"], title: "web"), for: manifest)
        XCTAssertEqual(opened, .ok)
        XCTAssertEqual(system.terminalCommands, [["docker", "exec", "-it", "web; rm -rf ~", "sh"]])
        for bad in [[], [" "], ["echo", "two\nlines"], Array(repeating: "x", count: 65)] {
            guard case .failure = await services.handle(.openInTerminal(command: bad, title: nil), for: manifest) else { return XCTFail("\(bad) is refused") }
        }
        for _ in 0..<4 { _ = await services.handle(.openInTerminal(command: ["top"], title: nil), for: manifest) }
        guard case .failure(let message) = await services.handle(.openInTerminal(command: ["top"], title: nil), for: manifest) else { return XCTFail("at most 5 a minute") }
        XCTAssertTrue(message.contains("5 a minute"), message)
    }

    func testReadsTextInKeptImagesAndOnScreen() async throws {
        let system = SimulatedSystem()
        let services = services(system)
        system.simulate(text: RecognizedText(lines: [.init(text: "Invoice 42", confidence: 0.99), .init(text: "Total $10", confidence: 0.8)]), inImage: "abc123")
        let clipboard = Manifest(id: "dev.test.clip", name: "Clip", capabilities: [.clipboard])
        let text = try value(HostReplies.recognizedText, await services.handle(.recognizeText(imageID: "abc123", languages: ["en-US"]), for: clipboard))
        XCTAssertEqual(text.text, "Invoice 42\nTotal $10")
        guard case .failure = await services.handle(.recognizeText(imageID: "missing", languages: nil), for: clipboard) else { return XCTFail("an unknown image fails") }

        let screen = Manifest(id: "dev.test.screen", name: "Screen", capabilities: [.screenText])
        let read = try value(HostReplies.recognizedText, await services.handle(.captureScreenText(languages: nil), for: screen))
        XCTAssertEqual(read.text, "Bonjour tout le monde")
        system.simulate(screenText: nil)
        let cancelled = await services.handle(.captureScreenText(languages: nil), for: screen)
        XCTAssertEqual(cancelled, .value(nil), "Esc answers nothing")
    }

    func testSensors() async throws {
        let system = SimulatedSystem()
        let services = services(system)
        let manifest = Manifest(id: "dev.test.sensors", name: "Sensors", capabilities: [.sensors])
        let readings = try value(HostReplies.sensors, await services.handle(.sensors, for: manifest))
        XCTAssertEqual(readings.filter { $0.kind == .temperature }.map(\.id), ["cpu", "gpu", "battery"])
        XCTAssertEqual(readings.first { $0.kind == .fan }?.maximum, 4900)
    }

    func testNotificationButtonsCanRunTheirPluginsCommands() async {
        let recorder = NotificationRecorder()
        let services = services(SimulatedSystem(), notify: recorder)
        let manifest = Manifest(id: "dev.test.timer", name: "Timer")
        let buttons = [NotificationAction("Start Break", command: "break"), NotificationAction("+5 min", command: "start", arguments: ["minutes": "5"])]
        guard case .ok = await services.handle(.notify(title: "Focus done", body: nil, actions: buttons), for: manifest) else { return XCTFail("command buttons are fine") }
        XCTAssertEqual(recorder.all.first?.actions, buttons)
        let bad = [NotificationAction("Bad", command: "not a command!")]
        guard case .failure = await services.handle(.notify(title: "x", body: nil, actions: bad), for: manifest) else { return XCTFail("a command id is checked") }
        let long = [NotificationAction("Long", command: "go", arguments: ["text": String(repeating: "a", count: 501)])]
        guard case .failure = await services.handle(.notify(title: "x", body: nil, actions: long), for: manifest) else { return XCTFail("arguments are capped") }
    }

    func testOldPluginsStillDecodeURLButtons() throws {
        let old = Data(#"{"title":"Join","url":"https://meet.google.com/x"}"#.utf8)
        let decoded = try JSONDecoder().decode(NotificationAction.self, from: old)
        XCTAssertEqual(decoded, NotificationAction("Join", url: "https://meet.google.com/x"))
        XCTAssertNil(decoded.command)
    }
}
