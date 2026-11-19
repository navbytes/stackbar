import Foundation
import XCTest
@testable import StackbarKit

/// A plugin whose view shows a cached list fetched from the host (a secret),
/// so a test decides when each fetch answers.
@MainActor
final class CachedLister: StackbarPlugin {
    static let manifest = Manifest(id: "test.cached", name: "Cached", surfaces: [.panel])

    var items: [String] = []
    var fetches = 0

    var panel: ViewContent { Text("Cached") }

    var commands: [Command] {
        Command("list", title: "List")
            .view(search: { _ in
                try await Stackbar.cached("items", maxAge: 0.05) {
                    self.fetches += 1
                    self.items = (try await Stackbar.secret("S") ?? "").split(separator: ",").map(String.init)
                }
            }) { _ in
                List(searchable: true) {
                    ForEach(self.items) { item in Row(item, key: item).keywords(["kw-" + item]) }
                }
            }
    }
}

@MainActor
final class CachedTests: XCTestCase {
    private var outbox = Outbox()

    override func setUp() async throws {
        outbox = Outbox()
        HostClient.shared.configure(send: outbox.send)
        Stackbar.invalidateCache()
    }

    override func tearDown() async throws {
        HostClient.shared.failAll("test over")
        Stackbar.invalidateCache()
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

    private func views(_ messages: [PluginMessage]) -> [(seq: Int, rows: [RowNode], loading: Bool?)] {
        messages.compactMap { message in
            guard case .view(_, let seq, let root, let loading) = message else { return nil }
            return (seq, root.rows, loading)
        }
    }

    func testOnlyTheFirstOpenWaitsAndAStaleValueReloadsBehindWithTheLoadingFlag() async throws {
        let plugin = CachedLister()
        let runtime = PluginRuntime(plugin: plugin, send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.panel]))
        _ = outbox.take()

        // First open: nothing cached, so the search waits for the fetch.
        await runtime.handle(.openView(session: 1, command: "list", query: CommandQuery(), seq: 1, context: nil))
        var seen: [PluginMessage] = []
        let firstFound = await nextSecretRequest(&seen)
        HostClient.shared.resolve(id: try XCTUnwrap(firstFound), result: .value("a,b"))
        await runtime.waitForRefreshes()
        let opened = views(seen + outbox.take())
        XCTAssertEqual(opened.map(\.seq), [1])
        XCTAssertEqual(opened.first?.rows.map(\.title), ["a", "b"])
        XCTAssertEqual(opened.first?.rows.first?.keywords, ["kw-a"])
        XCTAssertNil(opened.first?.loading, "not loading: nothing runs behind it")

        // Stale now: the next query answers from the cache at once...
        try await Task.sleep(for: .milliseconds(80))
        await runtime.handle(.updateView(session: 1, query: CommandQuery(text: "a"), seq: 2))
        seen = []
        let secondFound = await nextSecretRequest(&seen)
        let second = try XCTUnwrap(secondFound)
        await runtime.waitForRefreshes()
        let answered = views(seen + outbox.take())
        XCTAssertTrue(answered.contains { $0.seq == 2 && $0.rows.map(\.title) == ["a", "b"] && $0.loading == true },
                      "answered from the cache, with the loading bar on while it reloads")
        XCTAssertTrue(Stackbar.isUpdating)

        // ...and the reload lands as a redraw with the bar off.
        HostClient.shared.resolve(id: second, result: .value("a,b,c"))
        for _ in 0..<200 where Stackbar.isUpdating { try await Task.sleep(for: .milliseconds(5)) }
        let landed = views(outbox.take())
        XCTAssertEqual(landed.last?.rows.map(\.title), ["a", "b", "c"])
        XCTAssertNil(landed.last?.loading)
        XCTAssertEqual(plugin.fetches, 2)
    }

    func testCallersShareOneFetchAndAFailedFirstFetchThrows() async throws {
        let counter = CachedLister()
        let first = Task { @MainActor in
            try await Stackbar.cached("n", maxAge: 60) { () async throws -> Int in
                counter.fetches += 1
                try await Task.sleep(for: .milliseconds(30))
                return 7
            }
        }
        await Task.yield()
        let second = Task { @MainActor in
            try await Stackbar.cached("n", maxAge: 60) { () async throws -> Int in
                counter.fetches += 1
                return 8
            }
        }
        let answers = try await [first.value, second.value]
        XCTAssertEqual(answers, [7, 7])
        XCTAssertEqual(counter.fetches, 1)
        XCTAssertEqual(Stackbar.cachedValue("n", as: Int.self), 7)

        do {
            _ = try await Stackbar.cached("broken", maxAge: 60) { () async throws -> Int in throw Boom() }
            XCTFail("a first fetch that fails throws")
        } catch is Boom {}
        XCTAssertNil(Stackbar.cachedValue("broken", as: Int.self))

        Stackbar.invalidateCache("n")
        XCTAssertNil(Stackbar.cachedValue("n", as: Int.self))
    }
}
