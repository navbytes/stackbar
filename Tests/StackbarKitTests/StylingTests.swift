import Foundation
import XCTest
@testable import StackbarKit

private let orange = Paint.hex("#F28C38", dark: "#FF9F4F")

@MainActor
final class StylingTests: XCTestCase {
    func testModifiersFoldInOrderAndWrapWhenTheyMust() async {
        let nodes = Text("25").padding(6).background(orange, in: .capsule).padding(2).resolve(in: RenderContext())
        XCTAssertEqual(nodes, [
            .styled(.styled(.text("25"), style: Style(padding: EdgeInsets(6), background: Fill(orange, in: .capsule))), style: Style(padding: EdgeInsets(2))),
        ])
        let font = Text("x").font(size: 64, weight: .heavy).foreground(orange).resolve(in: RenderContext())
        XCTAssertEqual(font, [.styled(.text("x"), style: Style(font: FontSpec(size: 64, weight: .heavy), foreground: orange))])
    }

    func testCustomControlsResolve() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = TimeRange(start: start, end: start.addingTimeInterval(1500))
        var started = 0
        let context = RenderContext()
        let view: ViewContent = [
            ZStack {
                Circle().stroke(.hex("#00000014"), lineWidth: 6)
                ProgressBar(timing: session, style: .ring(lineWidth: 6)).foreground(orange)
                Button(key: "start", action: { started += 1 }) {
                    Image(systemName: "play.fill").font(size: 26).frame(width: 72, height: 72).background(orange, in: .circle)
                }
                .accessibilityLabel("Start")
            },
            TimerText(session),
            HStack(alignment: .center) { Spacer(); RoundedRectangle(cornerRadius: 12).fill(orange) },
            Picker("Mode", options: ["Focus", "Break"], selection: "Focus", style: .segmented) { _ in },
            Button(action: {}) { Image(systemName: "tag"); Text("Deep Work") },
        ]
        let nodes = view.resolve(in: context)
        XCTAssertEqual(nodes[0], .stack(axis: .depth, children: [
            .shape(ShapeNode(.circle, stroke: .hex("#00000014"), lineWidth: 6)),
            .styled(.progress(value: 0, style: .ring(lineWidth: 6), timing: session), style: Style(foreground: orange)),
            .styled(.tappable(.styled(.image(.symbol("play.fill")), style: Style(font: FontSpec(size: 26), frame: Frame(width: 72, height: 72), background: Fill(orange, in: .circle))), action: "button/start"), style: Style(accessibilityLabel: "Start")),
        ]))
        XCTAssertEqual(nodes[1], .timer(session))
        XCTAssertEqual(nodes[2], .stack(axis: .horizontal, alignment: .center, children: [.spacer(), .shape(ShapeNode(.roundedRectangle(cornerRadius: 12), fill: orange))]))
        XCTAssertEqual(nodes[3], .picker(title: "Mode", options: ["Focus", "Break"], selection: "Focus", style: .segmented, action: "picker/Mode"))
        XCTAssertEqual(nodes[4], .tappable(.stack(axis: .horizontal, children: [.image(.symbol("tag")), .text("Deep Work")]), action: "button/Deep Work"), "a text label names the action")
        XCTAssertEqual(Set(context.handlers.keys), ["button/start", "picker/Mode", "button/Deep Work"])
    }
}
