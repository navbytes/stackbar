import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Protocol 29: a view in a row's preview.
final class ProtocolTwentyNineTests: XCTestCase {
    func testRenderShowsAPreviewViewUnderItsRowWithoutActionIDs() {
        let view = ViewNode.stack(axis: .vertical, children: [
            .labeled(label: "Status", value: "2 failing", role: .critical),
            .button(title: "Re-run", action: "rerun"),
        ])
        let row = ViewNode.row(RowNode(key: "pr", title: "#42 Fix login", preview: RowPreview(text: "2 failing", view: view)))
        XCTAssertEqual(TreeTextRenderer.render(.list(searchable: true, children: [row])), """
        List (searchable)
          * #42 Fix login
            Preview
              Status: 2 failing (critical)
              (Re-run)
        """)
    }

    func testRenderSaysWhenAPreviewViewIsOverBudget() {
        let big = ViewNode.stack(axis: .vertical, children: Array(repeating: .divider, count: RowPreview.maxViewNodes))
        let row = ViewNode.row(RowNode(key: "k", title: "Big", preview: RowPreview(text: "t", view: big)))
        XCTAssertTrue(TreeTextRenderer.render(row).contains("Preview (over 150 nodes: the text shows)"))
    }

    func testTextOnlyPreviewsRenderAsBefore() {
        let row = ViewNode.row(RowNode(key: "k", title: "Plain", preview: RowPreview(text: "words")))
        XCTAssertEqual(TreeTextRenderer.render(row), "* Plain")
    }
}
