import XCTest
@testable import StackbarProtocol

final class StyleTests: XCTestCase {
    func testFoldingKeepsSwiftUIOrder() {
        let padded = Style(padding: EdgeInsets(8))
        let filled = Style(background: Fill(.hex("#FFFFFF")))
        XCTAssertEqual(padded.folding(filled), Style(padding: EdgeInsets(8), background: Fill(.hex("#FFFFFF"))), "background after padding fits one style")
        XCTAssertNil(filled.folding(padded), "padding after a background needs its own node")
        XCTAssertNil(padded.folding(padded), "a second padding needs its own node")
    }

    func testEnvironmentFieldsKeepTheInnerValue() {
        let inner = Style(font: FontSpec(size: 12), padding: EdgeInsets(4))
        let outer = Style(font: FontSpec(size: 40), foreground: .role(.accent), padding: nil)
        let folded = inner.folding(outer)
        XCTAssertEqual(folded?.font?.size, 12)
        XCTAssertEqual(folded?.foreground, .role(.accent))
    }

    func testStyledNodesFoldOrWrap() {
        let text = ViewNode.text("Hi")
        let once = text.styled(Style(padding: EdgeInsets(4))).styled(Style(background: Fill(.hex("#000000"))))
        XCTAssertEqual(once, .styled(text, style: Style(padding: EdgeInsets(4), background: Fill(.hex("#000000")))))
        let twice = once.styled(Style(padding: EdgeInsets(2)))
        XCTAssertEqual(twice, .styled(once, style: Style(padding: EdgeInsets(2))))
    }

    func testHexColorsAndContrast() throws {
        let orange = try XCTUnwrap(HexColor.components("#F28C38"))
        XCTAssertEqual(orange.red, 242.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(orange.alpha, 1)
        XCTAssertEqual(try XCTUnwrap(HexColor.components("#00000080")).alpha, 128.0 / 255, accuracy: 0.0001)
        XCTAssertNil(HexColor.components("orange"))
        XCTAssertNil(HexColor.components("#FFF"))
        XCTAssertEqual(try XCTUnwrap(HexColor.contrast("#000000", "#FFFFFF")), 21, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(HexColor.contrast("#777777", "#FFFFFF")), 4.48, accuracy: 0.01)
        XCTAssertEqual(HexColor("#111111", dark: "#EEEEEE").hex(dark: true), "#EEEEEE")
        XCTAssertEqual(HexColor("#111111").hex(dark: true), "#111111")
    }

    func testTimeRangeFractionAndClock() {
        let start = Date(timeIntervalSince1970: 1_000)
        let range = TimeRange(start: start, end: start.addingTimeInterval(25 * 60))
        XCTAssertEqual(range.fraction(at: start.addingTimeInterval(75)), 0.05, accuracy: 0.0001)
        XCTAssertEqual(range.fraction(at: start.addingTimeInterval(-5)), 0)
        XCTAssertEqual(range.fraction(at: start.addingTimeInterval(9_999)), 1)
        XCTAssertEqual(range.clock(at: start.addingTimeInterval(0.5), countsDown: true), "25:00")
        XCTAssertEqual(range.clock(at: start.addingTimeInterval(61), countsDown: true), "23:59")
        XCTAssertEqual(range.clock(at: start.addingTimeInterval(61), countsDown: false), "1:01")
        XCTAssertEqual(range.clock(at: start.addingTimeInterval(9_999), countsDown: true), "0:00")
        let long = TimeRange(start: start, end: start.addingTimeInterval(2 * 3600))
        XCTAssertEqual(long.clock(at: start, countsDown: true), "2:00:00")
        XCTAssertEqual(TimeRange(start: start, end: start.addingTimeInterval(-10)).end, start, "an end before the start is clamped")
    }

    func testNewNodesRoundTripAndOldJSONStillDecodes() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let tree = ViewNode.stack(axis: .depth, alignment: .center, children: [
            .shape(ShapeNode(.circle, stroke: .gradient(["#F28C38", "#FFB36B"]), lineWidth: 6)),
            .progress(value: 0, style: .ring(lineWidth: 6), timing: TimeRange(start: start, end: start.addingTimeInterval(60))),
            .tappable(.image(.symbol("play.fill")).styled(Style(font: FontSpec(size: 26), background: Fill(.hex("#F28C38"), in: .circle))), action: "button/start"),
            .timer(TimeRange(start: start, end: start.addingTimeInterval(60))),
            .spacer(),
            .picker(title: "Mode", options: ["Focus", "Break"], selection: "Focus", style: .segmented, action: "picker/Mode"),
        ])
        XCTAssertEqual(try LineCodec.decode(ViewNode.self, from: try LineCodec.encode(tree)), tree)

        let old = Data(#"{"stack":{"axis":"vertical","children":[{"progress":{"value":1,"total":2,"role":"accent"}}]}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ViewNode.self, from: old), .stack(axis: .vertical, children: [.progress(value: 1, total: 2)]), "protocol 10 trees still decode")
    }

    func testChildrenActionsTextAndLimits() {
        let button = ViewNode.tappable(.stack(axis: .horizontal, children: [.image(.symbol("tag")), .text("Deep Work")]), action: "button/tag")
        let tree = ViewNode.stack(axis: .vertical, children: [button.styled(Style(padding: EdgeInsets(4))), .shape(ShapeNode(.circle)).styled(Style(accessibilityLabel: "Progress ring"))])
        XCTAssertEqual(tree.actions, ["button/tag"])
        XCTAssertEqual(button.plainText, "Deep Work")
        XCTAssertEqual(tree.plainText, "Deep Work Progress ring")
        XCTAssertEqual(tree.size.count, 8)
        XCTAssertEqual(tree.size.depth, 5)
        XCTAssertNil(RenderLimits.violation(tree))

        let wide = ViewNode.stack(axis: .vertical, children: Array(repeating: .divider, count: RenderLimits.maxNodes))
        XCTAssertEqual(RenderLimits.violation(wide), "the view has 5001 nodes; at most 5000 are allowed")
        let deep = (0..<RenderLimits.maxDepth).reduce(ViewNode.divider) { node, _ in .styled(node, style: Style(opacity: 1)) }
        XCTAssertEqual(RenderLimits.violation(deep), "the view is 65 levels deep; at most 64 are allowed")
    }
}
