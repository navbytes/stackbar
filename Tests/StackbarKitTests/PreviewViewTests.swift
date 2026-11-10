import Foundation
import XCTest
@testable import StackbarKit

/// Protocol 29: a view in a row's preview.
@MainActor
final class PreviewViewTests: XCTestCase {
    override func setUp() async throws {
        Stackbar.hostProtocol = nil
    }

    private func preview(_ row: Row, in context: RenderContext = RenderContext()) -> RowPreview? {
        guard case .row(let node) = row.resolve(in: context).first else { return nil }
        return node.preview
    }

    func testAViewTravelsWithItsTextAndCaption() async {
        let row = Row("#42 Fix login", key: "pr/42").preview(text: "2 checks failing", caption: "navbytes/app") {
            PreviewDetail("Checks", symbol: "checkmark.seal", theme: .critical) {
                Metadata("Status", pill: "2 failing", theme: .critical)
                Metadata("Updated", "3m ago")
            }
        }
        let shown = preview(row)
        XCTAssertEqual(shown?.text, "2 checks failing", "search and older hosts keep the words")
        XCTAssertEqual(shown?.caption, "navbytes/app")
        let view = try? XCTUnwrap(shown?.view)
        XCTAssertNotNil(view)
        XCTAssertEqual(view, shown?.shownView, "well under the budget, the host draws it")
        XCTAssertTrue(view?.rows.isEmpty ?? false)
        XCTAssertTrue(TreeTextRendererProbe.texts(in: view).contains("2 failing"))
    }

    func testSeveralTopLevelViewsStackAndOneStaysAsIs() async {
        let one = preview(Row("a").preview(text: "a") { Text("only") })
        XCTAssertEqual(one?.view, .text("only"))
        let two = preview(Row("b").preview(text: "b") {
            Text("first")
            Text("second")
        })
        XCTAssertEqual(two?.view, .stack(axis: .vertical, spacing: 8, children: [.text("first"), .text("second")]))
    }

    func testOlderHostsGetTheTextOnly() async {
        Stackbar.hostProtocol = 28
        let shown = preview(Row("a").preview(text: "words", caption: "c") { Text("view") })
        XCTAssertEqual(shown, RowPreview(text: "words", caption: "c"))
    }

    func testAViewOverTheBudgetIsDroppedWithOneWarning() async {
        let big = Row("big", key: "big").preview(text: "many") {
            ForEach(0..<(RowPreview.maxViewNodes + 1)) { index in Text("\(index)") }
        }
        let context = RenderContext()
        XCTAssertNil(preview(big, in: context)?.view)
        XCTAssertEqual(preview(big, in: context)?.text, "many")
        XCTAssertEqual(context.warnings.count, 1, "said once, not every render")
        XCTAssertTrue(context.warnings.first?.contains("row big") ?? false)
    }

    func testTheHostDropsAnOversizedViewItself() async {
        let huge = ViewNode.stack(axis: .vertical, children: Array(repeating: .divider, count: RowPreview.maxViewNodes))
        XCTAssertEqual(huge.nodeCount, RowPreview.maxViewNodes + 1)
        XCTAssertNil(RowPreview(text: "t", view: huge).shownView)
        XCTAssertEqual(RowPreview(text: "t", view: .divider).shownView, .divider)
    }

    func testOldPreviewsDecodeAndNewOnesRoundTrip() throws {
        let old = try JSONDecoder().decode(RowPreview.self, from: Data(#"{"text":"hi","caption":"c"}"#.utf8))
        XCTAssertEqual(old, RowPreview(text: "hi", caption: "c"))
        let new = RowPreview(text: "hi", view: .badge("ok", role: .success))
        XCTAssertEqual(try JSONDecoder().decode(RowPreview.self, from: JSONEncoder().encode(new)), new)
    }

    func testARowsPreviewCountsTowardsItsNodes() async {
        let row = ViewNode.row(RowNode(key: "k", title: "t", accessories: [.badge("1")], preview: RowPreview(view: .stack(axis: .vertical, children: [.divider]))))
        XCTAssertEqual(row.nodeCount, 4)
    }
}

/// The text nodes in a tree, to look for words without spelling out styles.
private enum TreeTextRendererProbe {
    static func texts(in node: ViewNode?) -> [String] {
        guard let node else { return [] }
        if case .text(let string, _, _) = node { return [string] }
        return node.children.flatMap(texts(in:))
    }
}
