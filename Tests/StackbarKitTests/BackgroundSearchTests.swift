import Foundation
import XCTest
@testable import StackbarKit

/// A plugin whose view search waits on the host (a secret), so a test decides
/// when each search's "network" answers.
@MainActor
final class SlowSearcher: StackbarPlugin {
    static let manifest = Manifest(id: "test.slowsearch", name: "Slow Search", surfaces: [.panel])

    var items = ["one"]
    var queries: [String] = []
    var cancelled = 0
    var picked: [String] = []

    var panel: ViewContent { Text("Slow") }

    var commands: [Command] {
        Command("find", title: "Find")
            .view(search: { invocation in
                self.queries.append(invocation.text)
                do {
                    let answer = try await Stackbar.secret("S") ?? ""
                    self.items = answer.split(separator: ",").map(String.init)
                } catch is CancellationError {
                    self.cancelled += 1
                    throw CancellationError()
                }
            }) { _ in
                List(self.items) { item in
                    Row(item, key: item).action("Pick") { self.picked.append(item) }
                }
            }
    }
}

@MainActor
final class BackgroundSearchTests: XCTestCase {
    private var outbox = Outbox()

    override func setUp() async throws {
        outbox = Outbox()
        HostClient.shared.configure(send: outbox.send)
    }

    override func tearDown() async throws {
        HostClient.shared.failAll("test over")
    }

    private func start() async -> (SlowSearcher, PluginRuntime) {
        let plugin = SlowSearcher()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.panel]))
        _ = outbox.take()
        return (plugin, runtime)
    }

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

    private func views(_ messages: [PluginMessage]) -> [(seq: Int, titles: [String])] {
        messages.compactMap { message in
            guard case .view(_, let seq, let root) = message else { return nil }
            guard case .list(_, let rows) = root else { return (seq, []) }
            return (seq, rows.compactMap { if case .row(let row) = $0 { return row.title } else { return nil } })
        }
    }

    func testAClickDuringASlowSearchIsHandledAtOnceAndTheSearchSettlesWhenItEnds() async throws {
        let (plugin, runtime) = await start()
        await runtime.handle(.openView(session: 1, command: "find", query: CommandQuery(text: ""), seq: 1, context: nil))
        var seen: [PluginMessage] = []
        let found1 = await nextSecretRequest(&seen)
        let first = try XCTUnwrap(found1)
        XCTAssertTrue(views(seen).isEmpty, "nothing answers the open before its search")
        HostClient.shared.resolve(id: first, result: .value("one,two"))
        await runtime.waitForRefreshes()
        let opened = outbox.take()
        XCTAssertEqual(views(opened).map(\.seq), [1])
        XCTAssertEqual(views(opened).first?.titles, ["one", "two"])
        XCTAssertEqual(settles(opened), 1)

        // A new query whose search waits on the host...
        await runtime.handle(.updateView(session: 1, query: CommandQuery(text: "t"), seq: 2))
        seen = []
        let found2 = await nextSecretRequest(&seen)
        let second = try XCTUnwrap(found2)
        XCTAssertEqual(settles(seen), 0, "the update is not done yet")

        // ...doesn't hold up a click, which answers under the last answered seq.
        await runtime.handle(.event(action: "view/1/row/two/Pick", value: nil))
        XCTAssertEqual(plugin.picked, ["two"])
        let clicked = outbox.take()
        XCTAssertEqual(views(clicked).map(\.seq), [1], "the host must not take this as the answer to seq 2")
        XCTAssertEqual(settles(clicked), 1, "the click settles on its own")

        HostClient.shared.resolve(id: second, result: .value("three"))
        await runtime.waitForRefreshes()
        let answered = outbox.take()
        XCTAssertEqual(views(answered).map(\.seq), [2])
        XCTAssertEqual(views(answered).first?.titles, ["three"])
        XCTAssertEqual(settles(answered), 1)
    }

    func testANewerQueryCancelsTheSearchItReplacesAndOwesBothSettles() async throws {
        let (plugin, runtime) = await start()
        await runtime.handle(.openView(session: 1, command: "find", query: CommandQuery(text: "a"), seq: 1, context: nil))
        var seen: [PluginMessage] = []
        let found3 = await nextSecretRequest(&seen)
        _ = try XCTUnwrap(found3)

        await runtime.handle(.updateView(session: 1, query: CommandQuery(text: "ab"), seq: 2))
        seen = []
        let found4 = await nextSecretRequest(&seen)
        let second = try XCTUnwrap(found4)
        XCTAssertEqual(plugin.cancelled, 1)
        XCTAssertEqual(plugin.queries, ["a", "ab"], "the newer search runs once the old one has wound down")

        HostClient.shared.resolve(id: second, result: .value("abc"))
        await runtime.waitForRefreshes()
        let answered = seen + outbox.take()
        XCTAssertEqual(views(answered).map(\.seq), [2], "the cancelled search never answers")
        XCTAssertEqual(settles(answered), 2)
    }

    func testClosingAViewCancelsItsSearch() async throws {
        let (plugin, runtime) = await start()
        await runtime.handle(.openView(session: 4, command: "find", query: CommandQuery(text: ""), seq: 1, context: nil))
        var seen: [PluginMessage] = []
        let found5 = await nextSecretRequest(&seen)
        _ = try XCTUnwrap(found5)

        await runtime.handle(.closeView(session: 4))
        await runtime.waitForRefreshes()
        let after = seen + outbox.take()
        XCTAssertEqual(plugin.cancelled, 1)
        XCTAssertTrue(views(after).isEmpty)
        XCTAssertEqual(settles(after), 2, "the close and the cancelled open both settle")
        XCTAssertFalse(after.contains { if case .log(.error, _) = $0 { return true } else { return false } }, "a cancel is not a failure")
    }
}
