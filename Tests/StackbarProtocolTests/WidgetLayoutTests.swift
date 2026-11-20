import XCTest
@testable import StackbarProtocol

final class WidgetLayoutTests: XCTestCase {
    private let cover = ViewNode.image(.url("https://example.com/cover.jpg", placeholder: "music.note"))
    private let fill = ViewNode.shape(ShapeNode(.rectangle, fill: .color(HexColor("#203040"))))

    func testPlainTreeKeepsTheStandardBackground() {
        let layers = ViewNode.text("hi").widgetLayers
        XCTAssertEqual(layers, WidgetLayers(background: [], content: .text("hi"), edgeToEdge: false))
    }

    /// A `Backdrop`: a framed, clipped depth stack opening with a fill and a
    /// blurred image. The widget is the card, so the frame and clip go and
    /// the fill and image fill the widget.
    func testBackdropFillsTheWidget() {
        let blurred = ViewNode.styled(cover, style: Style(blur: 30, opacity: 0.9))
        let content = ViewNode.styled(.text("Song"), style: Style(padding: EdgeInsets(16)))
        let card = ViewNode.stack(axis: .depth, children: [fill, blurred, content])
            .styled(Style(frame: Frame(height: 131, fillWidth: true), clip: .roundedRectangle(cornerRadius: 14)))
        let layers = card.widgetLayers
        XCTAssertEqual(layers.background, [fill, blurred])
        XCTAssertEqual(layers.content, content)
        XCTAssertTrue(layers.edgeToEdge, "the content pads itself")
    }

    func testBackdropCarriesTextStylingToItsLayers() {
        let style = Style(foreground: .role(.success), frame: Frame(height: 100))
        let layers = ViewNode.stack(axis: .depth, children: [fill, .text("x")]).styled(style).widgetLayers
        XCTAssertEqual(layers.content, .styled(.text("x"), style: Style(foreground: .role(.success))))
        XCTAssertEqual(layers.background, [.styled(fill, style: Style(foreground: .role(.success)))])
    }

    func testStyledBackgroundFillsTheWidgetAndKeepsPadding() {
        let gradient = Paint.linearGradient(colors: [HexColor("#ff0000"), HexColor("#0000ff")], angle: 90)
        let root = ViewNode.text("Hello").styled(Style(padding: EdgeInsets(8), background: Fill(gradient, in: .roundedRectangle(cornerRadius: 12)), clip: .roundedRectangle(cornerRadius: 12)))
        let layers = root.widgetLayers
        XCTAssertEqual(layers.background, [.shape(ShapeNode(.rectangle, fill: gradient))])
        XCTAssertEqual(layers.content, .styled(.text("Hello"), style: Style(padding: EdgeInsets(8))))
        XCTAssertFalse(layers.edgeToEdge)
    }

    func testStacksThatAreNotBackdropsStayAsTheyAre() {
        let onlyLayers = ViewNode.stack(axis: .depth, children: [fill, cover])
        XCTAssertEqual(onlyLayers.widgetLayers.content, onlyLayers, "nothing over the layers: it is the content")
        let contentFirst = ViewNode.stack(axis: .depth, children: [.text("x"), fill])
        XCTAssertEqual(contentFirst.widgetLayers.content, contentFirst)
        let faded = ViewNode.stack(axis: .depth, children: [fill, .text("x")]).styled(Style(opacity: 0.5))
        XCTAssertEqual(faded.widgetLayers.content, faded, "a faded card is drawn as the author made it")
    }

    func testChangesWithTime() {
        XCTAssertFalse(ViewNode.text("x").changesWithTime)
        XCTAssertTrue(ViewNode.stack(axis: .vertical, children: [.clock(ClockFace(pattern: "HH:mm"))]).changesWithTime)
        let timing = TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60))
        XCTAssertTrue(ViewNode.progress(value: 0, timing: timing).styled(Style(opacity: 1)).changesWithTime)
        XCTAssertFalse(ViewNode.progress(value: 0.5).changesWithTime)
        XCTAssertTrue(ViewNode.row(RowNode(key: "a", title: "A", accessories: [.progress(value: 0, timing: timing)])).changesWithTime)
    }

    func testRowsBySize() {
        XCTAssertLessThan(WidgetSize.small.maxRows, WidgetSize.medium.maxRows)
        XCTAssertLessThan(WidgetSize.medium.maxRows, WidgetSize.large.maxRows)
    }
}
