import XCTest
@testable import StackbarKit

@MainActor
final class Previewed: StackbarPlugin {
    static let manifest = Manifest(id: "test.previewed", name: "Previewed", surfaces: [.menuBar], triggers: [.launch])
    static let previews: [Preview<Previewed>] = [
        Preview("hero", "Three things") { $0.items = ["a", "b", "c"] },
        Preview("broken", "Fails") { _ in throw Boom() },
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
        XCTAssertEqual(Previewed.previewSpecs, [PreviewSpec(name: "hero", title: "Three things"), PreviewSpec(name: "broken", title: "Fails")])
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
