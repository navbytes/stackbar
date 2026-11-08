import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Protocol 23: the clock node the host keeps current, and live sliders.
final class ProtocolTwentyThreeTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")
    /// Sunday 8 November 2026, 09:05:07 UTC.
    private let moment = Date(timeIntervalSince1970: 1_794_128_707)

    func testAClockReadsItsPatternInItsZone() {
        XCTAssertEqual(ClockFace(pattern: "EEE d MMM HH:mm", timeZone: "UTC").string(at: moment, locale: posix), "Sun 8 Nov 09:05")
        XCTAssertEqual(ClockFace(pattern: "h:mm:ss a", timeZone: "Asia/Tokyo").string(at: moment, locale: posix), "6:05:07 PM")
    }

    func testOnlyAnUnquotedSecondsFieldTicksEverySecond() {
        XCTAssertTrue(ClockFace(pattern: "HH:mm:ss").showsSeconds)
        XCTAssertFalse(ClockFace(pattern: "HH:mm").showsSeconds)
        XCTAssertFalse(ClockFace(pattern: "HH:mm 'ist'").showsSeconds, "quoted letters are text")
    }

    func testTheWidestReadingsCoverEveryWeekdayAndMonth() {
        let weekdays = Set(ClockFace(pattern: "EEE", timeZone: "UTC").widestReadings(locale: posix))
        XCTAssertEqual(weekdays, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        let months = Set(ClockFace(pattern: "MMMM", timeZone: "UTC").widestReadings(locale: posix))
        XCTAssertEqual(months.count, 12)
        XCTAssertTrue(Set(ClockFace(pattern: "h:mm a", timeZone: "UTC").widestReadings(locale: posix)).contains("10:58 AM"))
    }

    func testTheAgentReadsAClockAsTheTimeNow() {
        let node = ViewNode.clock(ClockFace(pattern: "HH:mm", timeZone: "UTC"))
        XCTAssertEqual(TreeTextRenderer.render(node, now: moment), "09:05")
        XCTAssertFalse(node.isBlankInMenuBar, "a clock shows in the menu bar")
        XCTAssertEqual(SurfaceParity.Kind(node), .clock)
    }

    func testLiveIsOptionalOnTheWire() throws {
        let old = #"{"slider":{"title":"Volume","value":0.5,"min":0,"max":1,"action":"slider/Volume"}}"#
        let decoded = try JSONDecoder().decode(ViewNode.self, from: Data(old.utf8))
        guard case .slider(_, _, _, _, _, _, let live) = decoded else { return XCTFail("a slider") }
        XCTAssertNil(live, "a slider from an older plugin sends on release")
        let liveNode = ViewNode.slider(title: "Shift", value: 0, min: -12, max: 12, step: 0.5, action: "slider/shift", live: true)
        XCTAssertEqual(try JSONDecoder().decode(ViewNode.self, from: JSONEncoder().encode(liveNode)), liveNode)
        XCTAssertTrue(TreeTextRenderer.render(liveNode).contains("live"))
    }
}
