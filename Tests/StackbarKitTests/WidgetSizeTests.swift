import Foundation
import XCTest
@testable import StackbarKit

/// A plugin that draws its widget differently for each desktop size.
@MainActor
final class SizedWidget: StackbarPlugin {
    static let manifest = Manifest(id: "test.sized", name: "Sized", surfaces: [.panel, .widget])

    var count = 0

    var panel: ViewContent { Text("Panel") }
    var widget: ViewContent { Text("Default \(count)") }

    func widget(_ size: WidgetSize) -> ViewContent {
        switch size {
        case .small: Text("Small \(count)")
        case .medium: widget
        case .large: VStack { Text("Large \(count)"); Button("Add") { self.count += 1 } }
        }
    }
}

@MainActor
final class WidgetSizeTests: XCTestCase {
    private var outbox = Outbox()

    override func setUp() async throws {
        outbox = Outbox()
        HostClient.shared.configure(send: outbox.send)
    }

    private func sized(_ messages: [PluginMessage]) -> [WidgetSize: ViewNode] {
        var found: [WidgetSize: ViewNode] = [:]
        for case .renderWidget(let size, let root) in messages { found[size] = root }
        return found
    }

    func testAHostThatNamesNoSizesGetsOneTree() async {
        let runtime = PluginRuntime(plugin: SizedWidget(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: 30, surfaces: [.panel, .widget]))
        let sent = outbox.take()
        XCTAssertTrue(sent.contains(.render(surface: .widget, root: .text("Default 0"))))
        XCTAssertTrue(sized(sent).isEmpty, "a host before protocol 31 never sees renderWidget")
    }

    func testEachSizeNamedInHelloGetsItsTree() async {
        let runtime = PluginRuntime(plugin: SizedWidget(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.panel, .widget], widgetSizes: [.small, .medium]))
        let trees = sized(outbox.take())
        XCTAssertEqual(trees[.small], .text("Small 0"))
        XCTAssertEqual(trees[.medium], .text("Default 0"))
        XCTAssertNil(trees[.large], "not asked for")
    }

    func testSizesChangeAndOnlyChangedTreesAreSent() async throws {
        let runtime = PluginRuntime(plugin: SizedWidget(), send: outbox.send)
        await runtime.handle(.hello(protocolVersion: StackbarProtocolVersion.current, surfaces: [.panel, .widget], widgetSizes: [.small]))
        _ = outbox.take()
        await runtime.handle(.widgetSizes([.small, .large]))
        let trees = sized(outbox.take())
        XCTAssertNil(trees[.small], "unchanged since it was sent")
        let large = try XCTUnwrap(trees[.large])
        // A button in the large widget acts like any other.
        let add = try XCTUnwrap(large.actions.first)
        await runtime.handle(.event(action: add, value: nil))
        let after = sized(outbox.take())
        XCTAssertEqual(after[.small], .text("Small 1"))
        XCTAssertEqual(after[.large]?.children.first, .text("Large 1"))
    }

    func testHelloWithoutSizesDecodesAndOldHelloIgnoresThem() throws {
        // A host before 31 sends no `widgetSizes`; a plugin before 31 ignores the key.
        let old = #"{"hello":{"protocolVersion":30,"surfaces":["widget"],"storage":{}}}"#
        let decoded = try JSONDecoder().decode(HostMessage.self, from: Data(old.utf8))
        XCTAssertEqual(decoded, .hello(protocolVersion: 30, surfaces: [.widget], storage: [:], widgetSizes: nil))
        let new = try JSONEncoder().encode(HostMessage.hello(protocolVersion: 31, surfaces: [.widget], widgetSizes: [.small]))
        XCTAssertTrue(String(decoding: new, as: UTF8.self).contains("small"))
    }
}
