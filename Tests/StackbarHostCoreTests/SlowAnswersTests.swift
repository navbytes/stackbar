import Foundation
import XCTest
@testable import StackbarHostCore

final class SlowAnswersTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testAQuickAnswerIsNotLogged() {
        var answers = SlowAnswers()
        answers.opened(session: 1, command: "tabs", seq: 1, at: start)
        XCTAssertNil(answers.answered(session: 1, seq: 1, at: start.addingTimeInterval(0.4)))
    }

    func testASlowOpenNamesItsCommandAndTime() {
        var answers = SlowAnswers()
        answers.opened(session: 1, command: "tabs", seq: 1, at: start)
        XCTAssertEqual(answers.answered(session: 1, seq: 1, at: start.addingTimeInterval(2.5)), "slow: tabs took 2.50s to answer the palette")
        // Answered once: a redraw after it is not another slow answer.
        XCTAssertNil(answers.answered(session: 1, seq: 1, at: start.addingTimeInterval(9)))
    }

    /// The wait runs from the first unanswered query: typing on while the
    /// plugin is busy doesn't restart the clock.
    func testTypingOnDuringASlowSearchKeepsTheFirstQuerysClock() {
        var answers = SlowAnswers()
        answers.opened(session: 1, command: "tabs", seq: 1, at: start)
        XCTAssertNil(answers.answered(session: 1, seq: 1, at: start.addingTimeInterval(0.1)))
        answers.updated(session: 1, seq: 2, at: start.addingTimeInterval(1))
        answers.updated(session: 1, seq: 3, at: start.addingTimeInterval(1.5))
        XCTAssertNil(answers.answered(session: 1, seq: 1, at: start.addingTimeInterval(3)), "an older answer doesn't answer a newer query")
        XCTAssertEqual(answers.answered(session: 1, seq: 3, at: start.addingTimeInterval(3)), "slow: tabs took 2.00s to answer the palette")
    }

    func testAClosedViewForgetsItsQuery() {
        var answers = SlowAnswers()
        answers.opened(session: 1, command: "tabs", seq: 1, at: start)
        answers.closed(session: 1)
        XCTAssertNil(answers.answered(session: 1, seq: 1, at: start.addingTimeInterval(5)))
        answers.updated(session: 1, seq: 2, at: start)
        XCTAssertNil(answers.answered(session: 1, seq: 2, at: start.addingTimeInterval(5)), "an update for a closed view has no command")
    }

    func testOnlyNotableRunsAreLogged() {
        func record(duration: Double = 0.1, status: Int32 = 0, timedOut: Bool = false, cancelled: Bool = false) -> CommandRunGate.Record {
            CommandRunGate.Record(path: "/usr/bin/osascript", arguments: 2, status: status, duration: duration, stdoutBytes: 0, stderrBytes: 0, timedOut: timedOut, cancelled: cancelled, at: Date())
        }
        XCTAssertFalse(CommandRunGate.isNotable(record()))
        XCTAssertTrue(CommandRunGate.isNotable(record(duration: 1.2)))
        XCTAssertTrue(CommandRunGate.isNotable(record(status: 1)))
        XCTAssertTrue(CommandRunGate.isNotable(record(timedOut: true)))
        XCTAssertTrue(CommandRunGate.isNotable(record(cancelled: true)))
    }
}
