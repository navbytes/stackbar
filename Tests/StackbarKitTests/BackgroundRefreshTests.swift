import Foundation
import XCTest
@testable import StackbarKit

/// A plugin whose refresh waits on the host (a secret), so a test decides
/// when each refresh's "network" answers.
@MainActor
final class SlowFetcher: StackbarPlugin {
    static let manifest = Manifest(id: "test.slow", name: "Slow", surfaces: [.menuBar, .panel])

    var tab = "Mine"
    var data = "none"
    var refreshes = 0
    var cancelled = 0
    var reasons: [TriggerReason?] = []
    var reasonSeenByClick: TriggerReason?? = .none
    var refreshingSeenByClick: Bool?

    required init() {}

    func refresh() async throws {
        refreshes += 1
        reasons.append(Stackbar.refreshReason)
        do {
            data = try await Stackbar.secret("S") ?? "nil"
        } catch is CancellationError {
            cancelled += 1
            throw CancellationError()
        }
    }

    var menuBar: ViewContent {
        Label(Stackbar.isRefreshing ? "busy" : data, symbol: "number")
    }

    var panel: ViewContent {
        Text(tab)
        Button("Other") {
            self.tab = "Other"
            self.reasonSeenByClick = .some(Stackbar.refreshReason)
            self.refreshingSeenByClick = Stackbar.isRefreshing
        }
        Button("Try Again") { try await Stackbar.refresh() }
    }
}

@MainActor
final class BackgroundRefreshTests: XCTestCase {
    private var outbox = Outbox()

    override func setUp() async throws {
        outbox = Outbox()
        HostClient.shared.configure(send: outbox.send)
    }

    override func tearDown() async throws {
        HostClient.shared.failAll("test over")
    }

    /// Waits for the plugin's next secret request and returns its id.
    private func nextSecretRequest(_ seen: inout [PluginMessage]) async -> Int? {
        for _ in 0..<400 {
            let new = outbox.take()
            seen += new
            for case .request(let id, .secret("S")) in new { return id }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    private func settles(_ messages: [PluginMessage]) -> Int {
        messages.filter { $0 == .settled }.count
    }

    func testAClickDuringASlowRefreshIsHandledAtOnceAndTheTriggerSettlesWhenItEnds() async throws {
        let plugin = SlowFetcher()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.menuBar, .panel]))
        _ = outbox.take()

        await runtime.handle(.trigger(reason: .interval))
        var seen: [PluginMessage] = []
        let request = await nextSecretRequest(&seen)
        XCTAssertNotNil(request)
        XCTAssertTrue(seen.contains(.render(surface: .menuBar, root: .label("busy", symbol: "number", role: .primary))), "a refresh draws when it starts, for spinners")
        XCTAssertEqual(settles(seen), 0, "the trigger is not done yet")

        // The click is handled while the refresh still waits on the host.
        await runtime.handle(.event(action: "button/Other", value: nil))
        XCTAssertEqual(plugin.tab, "Other")
        XCTAssertEqual(plugin.reasonSeenByClick, .some(nil), "a click doesn't see the refresh's reason")
        XCTAssertEqual(plugin.refreshingSeenByClick, true)
        XCTAssertEqual(settles(outbox.take()), 1, "the click settles on its own")

        HostClient.shared.resolve(id: try XCTUnwrap(request), result: .value("fresh"))
        await runtime.waitForRefreshes()
        let after = outbox.take()
        XCTAssertTrue(after.contains(.render(surface: .menuBar, root: .label("fresh", symbol: "number", role: .primary))))
        XCTAssertEqual(settles(after), 1, "the trigger settles once its refresh is done")
        XCTAssertEqual(plugin.reasons, [.interval])
    }

    func testTriggersDuringARefreshFoldIntoOneFollowUpThatOwesEverySettle() async throws {
        let plugin = SlowFetcher()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.menuBar]))
        _ = outbox.take()

        await runtime.handle(.trigger(reason: .interval))
        var seen: [PluginMessage] = []
        let firstFound = await nextSecretRequest(&seen)
        let first = try XCTUnwrap(firstFound)
        await runtime.handle(.trigger(reason: .interval))
        await runtime.handle(.trigger(reason: .wake), absorbed: 2)
        XCTAssertEqual(plugin.refreshes, 1, "no second refresh while one runs")

        HostClient.shared.resolve(id: first, result: .value("one"))
        seen = []
        let secondFound = await nextSecretRequest(&seen)
        let second = try XCTUnwrap(secondFound)
        XCTAssertEqual(settles(seen), 1, "the first trigger settled when its refresh ended")
        HostClient.shared.resolve(id: second, result: .value("two"))
        await runtime.waitForRefreshes()
        XCTAssertEqual(settles(outbox.take()), 4, "the follow-up answers the three folded triggers and the two the mailbox folded")
        XCTAssertEqual(plugin.refreshes, 2)
        XCTAssertEqual(plugin.reasons, [.interval, .wake], "the follow-up carries the newest reason")
        XCTAssertEqual(plugin.data, "two")
    }

    func testStackbarRefreshCancelsTheRunningRefreshSoItsAnswerNeverLands() async throws {
        let plugin = SlowFetcher()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.menuBar, .panel]))
        _ = outbox.take()

        await runtime.handle(.trigger(reason: .interval))
        var seen: [PluginMessage] = []
        let staleFound = await nextSecretRequest(&seen)
        let stale = try XCTUnwrap(staleFound)

        let click = Task { await runtime.handle(.event(action: "button/Try Again", value: nil)) }
        seen = []
        let freshFound = await nextSecretRequest(&seen)
        let fresh = try XCTUnwrap(freshFound)
        XCTAssertEqual(plugin.cancelled, 1, "the old refresh's host call threw CancellationError")
        XCTAssertFalse(HostClient.shared.resolve(id: stale, result: .value("stale")), "nobody waits on the cancelled call")
        XCTAssertEqual(settles(seen), 0)

        HostClient.shared.resolve(id: fresh, result: .value("fresh"))
        _ = await click.value
        await runtime.waitForRefreshes()
        let after = seen + outbox.take()
        XCTAssertEqual(plugin.data, "fresh")
        XCTAssertEqual(plugin.reasons, [.interval, nil], "a refresh the plugin asks for has no reason")
        XCTAssertEqual(settles(after), 2, "the click and the replaced trigger")
        XCTAssertFalse(after.contains { if case .log(.error, _) = $0 { return true } else { return false } }, "a cancelled refresh is not an error")
    }

    func testAFailedStackbarRefreshThrowsToTheCaller() async throws {
        @MainActor final class Failing: StackbarPlugin {
            static let manifest = Manifest(id: "test.failing", name: "Failing", surfaces: [.menuBar])
            var caught: String?
            required init() {}
            func refresh() async throws { throw HostError("offline") }
            var menuBar: ViewContent {
                Button("Go") {
                    do { try await Stackbar.refresh() } catch { self.caught = "\(error)" }
                }
            }
        }
        let plugin = Failing()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.menuBar]))
        await runtime.handle(.event(action: "button/Go", value: nil))
        XCTAssertEqual(plugin.caught, "offline")
    }

    func testCancellingAHostCallStopsWaitingAndStopsARun() async throws {
        let task = Task { try await Stackbar.run("sleep", ["100"]) }
        var request: Int?
        for _ in 0..<400 where request == nil {
            for case .request(let id, .run) in outbox.take() { request = id }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let id = try XCTUnwrap(request)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {}
        XCTAssertTrue(outbox.take().contains(.request(id: id + 1, call: .cancelRun(id: id))), "the host is told to stop the process")
        XCTAssertEqual(HostClient.shared.openRequests, 1, "only the cancelRun waits for its .ok")
    }
}

@MainActor
final class NestedRefreshTests: XCTestCase {
    func testStackbarRefreshFromInsideARefreshReturnsInsteadOfWaitingOnItself() async {
        @MainActor final class Nested: StackbarPlugin {
            static let manifest = Manifest(id: "test.nested", name: "Nested", surfaces: [.menuBar])
            var refreshes = 0
            required init() {}
            func refresh() async throws {
                refreshes += 1
                try await Stackbar.refresh()
            }
            var menuBar: ViewContent { Text("\(refreshes)") }
        }
        let outbox = Outbox()
        let plugin = Nested()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.menuBar]))
        await runtime.handle(.trigger(reason: .manual))
        await runtime.waitForRefreshes()
        XCTAssertEqual(plugin.refreshes, 1)
    }
}
