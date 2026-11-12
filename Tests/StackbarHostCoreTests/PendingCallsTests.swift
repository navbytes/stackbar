import XCTest
@testable import StackbarHostCore

/// The table of calls waiting on a plugin: each is answered exactly once.
final class PendingCallsTests: XCTestCase {
    /// Holds the table the way the supervisor does: inside an actor.
    private actor Caller {
        var calls = PendingCalls<String>()

        /// Starts a call whose timeout answers after `timeout` seconds, and
        /// lets `started` act on it (answer it, fail it) once it waits.
        func call(timeout: Double = 60, started: @Sendable @escaping (Int) async -> Void = { _ in }) async -> String {
            let id = calls.newID()
            calls.setTimeout(Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                await self?.finish(id, "timed out")
            }, for: id)
            return await withCheckedContinuation { continuation in
                calls.wait(for: id, continuation)
                Task { await started(id) }
            }
        }

        @discardableResult
        func finish(_ id: Int, _ answer: String) -> Bool { calls.finish(id, with: answer) }
        func failAll(_ answer: String) { calls.failAll(with: answer) }
        var openTimeouts: Int { calls.openTimeouts }
        func newID() -> Int { calls.newID() }
    }

    func testIdsCountUpFromOne() async {
        let caller = Caller()
        let first = await caller.newID()
        let second = await caller.newID()
        XCTAssertEqual([first, second], [1, 2])
    }

    func testThePluginsAnswerEndsTheCallAndItsTimeout() async {
        let caller = Caller()
        let answer = await caller.call { id in await caller.finish(id, "done") }
        XCTAssertEqual(answer, "done")
        let open = await caller.openTimeouts
        XCTAssertEqual(open, 0, "an answered call leaves no timeout running")
    }

    func testASecondAnswerDoesNothing() async {
        let caller = Caller()
        let results = Results()
        let answer = await caller.call { id in
            await results.add(await caller.finish(id, "first"))
            await results.add(await caller.finish(id, "second"))
        }
        XCTAssertEqual(answer, "first")
        let finished = await waitUntil(5) { await results.all.count == 2 }
        XCTAssertTrue(finished)
        let all = await results.all
        XCTAssertEqual(all, [true, false], "the late answer finds nobody waiting")
    }

    func testACallThePluginNeverAnswersTimesOut() async {
        let caller = Caller()
        let answer = await caller.call(timeout: 0.05)
        XCTAssertEqual(answer, "timed out")
        let open = await caller.openTimeouts
        XCTAssertEqual(open, 0)
    }

    func testFailAllAnswersEveryWaitingCallAndCancelsItsTimeout() async {
        let caller = Caller()
        async let first = caller.call()
        async let second = caller.call()
        let waiting = await waitUntil(5) { await caller.openTimeouts == 2 }
        XCTAssertTrue(waiting)
        await caller.failAll("the plugin exited")
        let answers = await [first, second]
        XCTAssertEqual(answers, ["the plugin exited", "the plugin exited"])
        let open = await caller.openTimeouts
        XCTAssertEqual(open, 0)
        let next = await caller.newID()
        XCTAssertEqual(next, 3, "ids aren't reused after the plugin goes away")
        let late = await caller.finish(1, "late")
        XCTAssertFalse(late, "an answer that arrives after the exit is dropped")
    }

    private actor Results {
        var all: [Bool] = []
        func add(_ value: Bool) { all.append(value) }
    }
}
