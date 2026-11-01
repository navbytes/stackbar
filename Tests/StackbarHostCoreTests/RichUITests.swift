import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Agent text and style lint for the protocol 11 vocabulary.
final class RichUITests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testAgentTextReadsTheNewNodes() {
        let session = TimeRange(start: start, end: start.addingTimeInterval(25 * 60))
        let tree = ViewNode.stack(axis: .vertical, alignment: .center, children: [
            .picker(title: "Mode", options: ["Focus", "Break"], selection: "Focus", style: .segmented, action: "picker/Mode"),
            .timer(session).styled(Style(font: FontSpec(size: 64, weight: .heavy))),
            .stack(axis: .depth, children: [
                .shape(ShapeNode(.circle, stroke: .hex("#00000014"), lineWidth: 6)),
                .progress(value: 0, style: .ring(lineWidth: 6), timing: session),
                .tappable(.image(.symbol("play.fill")), action: "button/start").styled(Style(accessibilityLabel: "Start")),
            ]),
            .stack(axis: .horizontal, children: [.spacer(), .tappable(.stack(axis: .horizontal, children: [.image(.symbol("tag")), .text("Deep Work")]), action: "button/tag")]),
        ])
        XCTAssertEqual(TreeTextRenderer.render(tree, now: start.addingTimeInterval(5 * 60)), """
        Mode: *Focus* | Break  {picker/Mode}
        20:00
        [##........] 20%
        (Start)  {button/start}
        (Deep Work)  {button/tag}
        """)
    }

    func testLintFlagsLowContrastAndUnnamedButtons() {
        let readable = ViewNode.text("25").styled(Style(foreground: .hex("#1A1A1A"), background: Fill(.hex("#FFF4EA"))))
        XCTAssertEqual(StyleLint.warnings(readable), [])

        let faint = ViewNode.text("Break").styled(Style(foreground: .hex("#AAAAAA", dark: "#555555"), background: Fill(.hex("#FFFFFF", dark: "#000000"))))
        let warnings = StyleLint.warnings(faint)
        XCTAssertEqual(warnings.count, 2, "\(warnings)")
        XCTAssertTrue(warnings[0].hasPrefix("low contrast 2.3:1 for #AAAAAA on #FFFFFF in light mode"), warnings[0])
        XCTAssertTrue(warnings[1].contains("in dark mode"), warnings[1])

        let inherited = ViewNode.stack(axis: .vertical, children: [ViewNode.text("Hi").styled(Style(background: Fill(.hex("#FFFFFF"))))]).styled(Style(foreground: .hex("#DDDDDD")))
        XCTAssertEqual(StyleLint.warnings(inherited).count, 3, "an outer foreground counts against an inner background, and the panel")

        // A see-through background is seen against what is behind it.
        let wash = ViewNode.text("Failing").styled(Style(foreground: .hex("#A81E23", dark: "#ED9496"), background: Fill(.hex("#D92D3324", dark: "#DD2F3438"))))
        XCTAssertEqual(StyleLint.warnings(wash), [], "\(StyleLint.warnings(wash))")
        let onCream = ViewNode.text("Focus").styled(Style(foreground: .hex("#FFFFFF"), background: Fill(.hex("#00000000")))).styled(Style(background: Fill(.hex("#F7E7D9"))))
        XCTAssertEqual(StyleLint.warnings(onCream).count, 2, "clear over cream is cream, in both modes: \(StyleLint.warnings(onCream))")
        XCTAssertTrue(StyleLint.warnings(onCream)[0].contains("on #F7E7D9"))

        let unnamed = ViewNode.tappable(.image(.symbol("gearshape")), action: "button/settings")
        XCTAssertEqual(StyleLint.warnings(unnamed), ["button {button/settings} has no text; give it .accessibilityLabel(...)"])
        XCTAssertEqual(StyleLint.warnings(.tappable(.image(.symbol("gearshape")).styled(Style(accessibilityLabel: "Settings")), action: "button/settings")), [])
        XCTAssertEqual(StyleLint.warnings(unnamed.styled(Style(accessibilityLabel: "Settings"))), [], "a label outside the button names it too")
    }
}
