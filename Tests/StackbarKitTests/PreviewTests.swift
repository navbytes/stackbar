import XCTest
@testable import StackbarKit

@MainActor
final class Previewed: StackbarPlugin {
    static let manifest = Manifest(id: "test.previewed", name: "Previewed", surfaces: [.menuBar], triggers: [.launch])
    static let previews: [PreviewScene<Previewed>] = [
        PreviewScene("hero", "Three things") { $0.items = ["a", "b", "c"] },
        PreviewScene("broken", "Fails", surface: .window) { _ in throw Boom() },
    ]

    var items: [String] = []
    var refreshes = 0

    func refresh() async throws {
        refreshes += 1
        items = []
    }

    var menuBar: ViewContent { Label("\(items.count)", symbol: "number") }
}

@MainActor
final class PreviewTests: XCTestCase {
    func testSpecsListNamesAndTitlesInOrder() {
        XCTAssertEqual(Previewed.previewSpecs, [PreviewSpec(name: "hero", title: "Three things"), PreviewSpec(name: "broken", title: "Fails", surface: .window)])
        XCTAssertEqual(Counter.previewSpecs, [], "a plugin without previews has none")
    }

    func testAPreviewSetsUpAfterHelloAndTriggersNeverRefresh() async {
        let outbox = Outbox()
        let plugin = Previewed()
        let runtime = PluginRuntime(plugin: plugin, preview: "hero", send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
        XCTAssertEqual(outbox.take(), [
            .ready(protocolVersion: StackbarProtocolVersion.current),
            .render(surface: .menuBar, root: .label("3", symbol: "number", role: .primary)),
            .settled,
        ])
        await runtime.handle(.trigger(reason: .launch))
        await runtime.handle(.trigger(reason: .interval))
        XCTAssertEqual(plugin.refreshes, 0)
        XCTAssertEqual(plugin.items, ["a", "b", "c"])
        XCTAssertEqual(outbox.take(), [.settled, .settled], "the scene stays as the preview set it up")
    }

    func testWithoutAPreviewTriggersRefreshAsBefore() async {
        let plugin = Previewed()
        let runtime = PluginRuntime(plugin: plugin, send: Outbox().send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
        await runtime.handle(.trigger(reason: .launch))
        XCTAssertEqual(plugin.refreshes, 1)
    }

    func testAnUnknownOrFailingPreviewIsLogged() async {
        for (name, expected) in [("nope", "no preview named \"nope\"; this plugin has hero, broken"), ("broken", "preview broken failed")] {
            let outbox = Outbox()
            let runtime = PluginRuntime(plugin: Previewed(), preview: name, send: outbox.send)
            await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar]))
            let logs = outbox.take().compactMap { message -> String? in
                if case .log(.error, let text) = message { return text } else { return nil }
            }
            XCTAssertEqual(logs.count, 1)
            XCTAssertTrue(logs[0].contains(expected), logs[0])
        }
    }
}

@MainActor
final class Remembering: StackbarPlugin {
    static let manifest = Manifest(id: "test.remembering", name: "Remembering", surfaces: [.menuBar])
    static let previews: [PreviewScene<Remembering>] = [PreviewScene("hero", "Seven") { $0.saved = 7 }]
    @Stored("saved") var saved = 0
    var menuBar: ViewContent { Text("\(saved)") }
}

extension PreviewTests {
    func testAPreviewIgnoresAndNeverWritesRealStoredValues() async {
        let outbox = Outbox()
        let runtime = PluginRuntime(plugin: Remembering(), preview: "hero", send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 1, surfaces: [.menuBar], storage: ["saved": "99", "other": "1"]))
        XCTAssertEqual(Stackbar.storage.keys, ["saved"], "the real snapshot is not loaded")
        XCTAssertEqual(Stackbar.storage.value("saved", as: Int.self), 7)
        XCTAssertFalse(outbox.take().contains { if case .request = $0 { return true } else { return false } }, "nothing is saved to the host")
        Stackbar.storage.isScratch = false
        Stackbar.storage.load([:])
    }
}
