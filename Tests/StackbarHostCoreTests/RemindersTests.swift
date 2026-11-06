import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Reminders through the host: the capability, field-level saves, and the
/// trigger.
final class RemindersTests: XCTestCase {
    private func services(_ system: SimulatedSystem) -> (HostServices, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (HostServices.local(directory: directory, secrets: MemorySecretStore([:]), platform: .init(system: system)), directory)
    }

    private let granted = Manifest(id: "dev.test.todo", name: "Todo", capabilities: [.reminders])

    /// The value a call answered with, as its reply type reads it.
    private func value<T>(_ reply: HostReply<T>, _ result: HostResult) throws -> T {
        try XCTUnwrap(reply.decode(result), "expected a value, got \(result)")
    }

    func testCallsNeedTheCapability() async {
        let (services, directory) = services(SimulatedSystem())
        defer { try? FileManager.default.removeItem(at: directory) }
        let bare = Manifest(id: "dev.test.bare", name: "Bare")
        for call: HostCall in [.reminderAccess(ask: false), .reminderLists, .reminders(ReminderQuery()), .saveReminder(Reminder(title: "x"), fields: nil), .deleteReminder(id: "x"), .createReminderList(title: "x", color: nil)] {
            guard case .failure(let message) = await services.handle(call, for: bare) else { return XCTFail("\(call) went through without .reminders") }
            XCTAssertTrue(message.contains("to the manifest's capabilities"), message)
        }
        XCTAssertEqual(SandboxEntitlements.entitlements(for: granted), ["com.apple.security.app-sandbox": true], "the helper itself never touches EventKit")
        XCTAssertEqual(Capability.reminders.summary, "Reads and changes your reminders")
        XCTAssertEqual(SettingsPresentation.Access(.reminders), .reminders)
        XCTAssertEqual(SettingsPresentation.Access(summary: Capability.reminders.summary), .reminders)
    }

    func testAddReadSaveFieldsAndDelete() async throws {
        let system = SimulatedSystem()
        let (services, directory) = services(system)
        defer { try? FileManager.default.removeItem(at: directory) }

        let lists = try value(HostReplies.reminderLists, await services.handle(.reminderLists, for: granted))
        XCTAssertEqual(lists.map(\.title), ["Reminders", "Groceries"])
        let home = try value(HostReplies.createReminderList, await services.handle(.createReminderList(title: "  Home ", color: "#FF2D55"), for: granted))
        XCTAssertEqual(home.title, "Home")
        guard case .failure = await services.handle(.createReminderList(title: " ", color: nil), for: granted) else { return XCTFail("a list needs a title") }

        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let added = try value(HostReplies.saveReminder, await services.handle(.saveReminder(Reminder(title: "Call mum", due: due, dueHasTime: true, priority: .high), fields: nil), for: granted))
        XCTAssertFalse(added.id.isEmpty)
        XCTAssertEqual(added.list, "list-1", "a reminder with no list goes to the default one")

        // The phone moves the date; the Mac then renames it, sending only the title.
        var onPhone = added
        onPhone.due = due.addingTimeInterval(86400)
        _ = try await system.saveReminder(onPhone, fields: [.due])
        var stale = added
        stale.title = "Call mum back"
        let renamed = try value(HostReplies.saveReminder, await services.handle(.saveReminder(stale, fields: [.title]), for: granted))
        XCTAssertEqual(renamed.title, "Call mum back")
        XCTAssertEqual(renamed.due, due.addingTimeInterval(86400), "a field the Mac didn't send keeps the phone's change")

        var done = renamed
        done.completed = due
        _ = try value(HostReplies.saveReminder, await services.handle(.saveReminder(done, fields: [.completed]), for: granted))
        let open = try value(HostReplies.reminders, await services.handle(.reminders(ReminderQuery()), for: granted))
        XCTAssertTrue(open.isEmpty, "completed reminders are left out unless asked for")
        let recent = try value(HostReplies.reminders, await services.handle(.reminders(ReminderQuery(completedSince: due.addingTimeInterval(-60))), for: granted))
        XCTAssertEqual(recent.map(\.title), ["Call mum back"])
        let elsewhere = try value(HostReplies.reminders, await services.handle(.reminders(ReminderQuery(lists: [home.id], completedSince: .distantPast)), for: granted))
        XCTAssertTrue(elsewhere.isEmpty)

        guard case .ok = await services.handle(.deleteReminder(id: added.id), for: granted) else { return XCTFail("delete failed") }
        XCTAssertTrue(system.simulatedReminders.reminders.isEmpty)
        guard case .failure(let message) = await services.handle(.saveReminder(renamed, fields: [.title]), for: granted) else { return XCTFail("saving a deleted reminder fails") }
        XCTAssertTrue(message.contains("deleted"), message)
    }

    func testAccessCanBeDeclined() async throws {
        let system = SimulatedSystem()
        system.simulate(reminders: SimulatedReminders(access: .notDetermined, grantWhenAsked: false))
        let (services, directory) = services(system)
        defer { try? FileManager.default.removeItem(at: directory) }
        let checked = try value(HostReplies.reminderAccess, await services.handle(.reminderAccess(ask: false), for: granted))
        XCTAssertEqual(checked, .notDetermined, "checking doesn't ask")
        let asked = try value(HostReplies.reminderAccess, await services.handle(.reminderAccess(ask: true), for: granted))
        XCTAssertEqual(asked, .denied)
        guard case .failure(let message) = await services.handle(.reminderLists, for: granted) else { return XCTFail("declined access fails") }
        XCTAssertTrue(message.contains("System Settings"), message)
    }

    func testUnsupportedSystemHasNoReminders() async {
        let system = UnsupportedSystem()
        let access = await system.reminderAccess(ask: true)
        XCTAssertEqual(access, .unavailable)
    }

    func testFieldsApplyOneByOne() {
        let base = Reminder(id: "r1", list: "a", title: "Old", notes: "n", priority: .low)
        let change = Reminder(id: "r1", list: "", title: "New", notes: nil, due: Date(timeIntervalSince1970: 0), dueHasTime: true, priority: .high, recurrence: .weekdays)
        let merged = base.applying(change, fields: [.title, .list, .due])
        XCTAssertEqual(merged.title, "New")
        XCTAssertEqual(merged.list, "a", "an empty list never moves a reminder")
        XCTAssertEqual(merged.notes, "n")
        XCTAssertEqual(merged.priority, .low)
        XCTAssertTrue(merged.dueHasTime)
        XCTAssertNil(merged.recurrence)
        XCTAssertEqual(base.applying(change, fields: nil).recurrence, .weekdays)
    }

    func testRemindersRoundTrip() throws {
        let reminder = Reminder(id: "r", externalID: "x", list: "l", title: "T", notes: "N", due: Date(timeIntervalSince1970: 1_800_000_000), dueHasTime: false, priority: .medium, completed: nil, recurrence: ReminderRecurrence(.monthly, interval: 2), alarm: Date(timeIntervalSince1970: 1_800_000_100), url: "https://example.com")
        XCTAssertEqual(try SystemCodec.decode(Reminder.self, from: SystemCodec.encode(reminder)), reminder)
        let call = PluginMessage.request(id: 3, call: .saveReminder(reminder, fields: [.title, .due]))
        XCTAssertEqual(try JSONDecoder().decode(PluginMessage.self, from: JSONEncoder().encode(call)), call)
    }
}
