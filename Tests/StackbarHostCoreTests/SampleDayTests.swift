import Foundation
import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class SampleDayTests: XCTestCase {
    private let calendar = Calendar.current

    private func at(hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: Date()))!
    }

    func testMorningKeepsEveryMeetingToday() {
        let now = at(hour: 10, minute: 0)
        let events = SimulatedSystem.sampleDay(now: now)
        let today = calendar.startOfDay(for: now)
        XCTAssertEqual(events.count, 5)
        for event in events where !event.isAllDay {
            XCTAssertEqual(calendar.startOfDay(for: event.start), today, event.title)
        }
        XCTAssertTrue(events.contains { $0.start < now && $0.end > now }, "a meeting is on now")
    }

    /// A render at 23:08 put the design review at 23:33–00:03, so Up Next
    /// listed it under both Today and Tomorrow.
    func testLateEveningMovesLaterMeetingsToTomorrowMorning() {
        let now = at(hour: 23, minute: 8)
        let events = SimulatedSystem.sampleDay(now: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        for event in events where !event.isAllDay {
            XCTAssertEqual(calendar.startOfDay(for: event.start), calendar.startOfDay(for: event.end.addingTimeInterval(-1)), "\(event.title) spans two days")
        }
        XCTAssertTrue(events.contains { $0.title == "Stand-up" && $0.start < now && $0.end > now })
        let moved = events.filter { $0.start >= tomorrow }.sorted { $0.start < $1.start }
        XCTAssertEqual(moved.map(\.title), ["Design review: onboarding", "Budget sync", "1:1 with Lee"])
        XCTAssertEqual(calendar.component(.hour, from: moved[0].start), 9)
        XCTAssertEqual(moved[0].end.timeIntervalSince(moved[0].start), 30 * 60)
        XCTAssertEqual(events.first { $0.isAllDay }?.end, tomorrow)
    }
}
