import Foundation
import XCTest
@testable import StackbarKit

@MainActor
final class DesignTests: XCTestCase {
    /// The popover's material, and a card on it: what text is read against.
    private let backdrops = [(light: "#ECECEC", dark: "#2B2B2B"), (light: "#E2E2E2", dark: "#383838")]

    private func over(_ top: String, _ bottom: String) -> String {
        guard let color = HexColor.components(top), let under = HexColor.components(bottom) else { return top }
        func channel(_ a: Double, _ b: Double) -> String { String(format: "%02X", Int(((a * color.alpha + b * (1 - color.alpha)) * 255).rounded())) }
        return "#" + channel(color.red, under.red) + channel(color.green, under.green) + channel(color.blue, under.blue)
    }

    func testEveryAccentIsAThemeHue() {
        XCTAssertEqual(Accent.allCases.map(\.rawValue), Theme.all.map(\.name), "a manifest accent names exactly the Theme hues")
        XCTAssertEqual(Theme(.teal), .teal)
    }

    func testEveryThemeReadsAtFourAndAHalfToOne() async {
        for (name, theme) in Theme.all {
            for dark in [false, true] {
                let mode = dark ? "dark" : "light"
                let solid = theme.solid.hex(dark: dark)
                let onSolid = theme.onSolid.hex(dark: dark)
                XCTAssertGreaterThanOrEqual(HexColor.contrast(onSolid, solid) ?? 0, 4.5, "\(name) onSolid on solid, \(mode)")
                XCTAssertGreaterThanOrEqual(HexColor.contrast(onSolid, Theme.deepen(solid)) ?? 0, 4.5, "\(name) onSolid on the gradient's foot, \(mode)")
                for backdrop in backdrops {
                    let under = dark ? backdrop.dark : backdrop.light
                    let text = theme.text.hex(dark: dark)
                    XCTAssertGreaterThanOrEqual(HexColor.contrast(text, under) ?? 0, 4.5, "\(name) text on \(under), \(mode)")
                    let tint = over(theme.tint.hex(dark: dark), under)
                    XCTAssertGreaterThanOrEqual(HexColor.contrast(text, tint) ?? 0, 4.5, "\(name) text on its tint over \(under), \(mode)")
                }
            }
        }
    }

    func testComponentsResolveToStyledProtocolNodes() async {
        let context = RenderContext()
        var refreshed = 0
        let view: ViewContent = [
            PanelHeader("3 running", subtitle: "Updated just now", symbol: "shippingbox.fill", theme: .teal) {
                IconButton("arrow.clockwise", label: "Refresh", theme: .teal) { refreshed += 1 }
            },
            Card("Containers", detail: "8") { Text("web") },
            StatTile("Running", value: "3", symbol: "play.fill", theme: .green, emphasized: true),
            Metric("25:00", caption: "Focus"),
            Gauge(value: 0.4, theme: .blue) { Text("40%") },
            Meter("Memory", reading: "12 of 16 GB", value: 0.75, theme: .warning),
            Pill("Failing", symbol: "xmark", theme: .critical),
            Banner("Showing numbers from 5 min ago"),
            EmptyState("Nothing running", symbol: "shippingbox", message: "Start a container.", theme: .teal) {
                ActionButton("Try Again", symbol: "arrow.clockwise", theme: .teal, prominent: true) {}
            },
            Chip("All", theme: .indigo, selected: true) {},
        ]
        let nodes = view.resolve(in: context)
        XCTAssertEqual(nodes.count, 10)
        XCTAssertEqual(Set(context.handlers.keys), ["button/Refresh", "button/Try Again", "button/All"])
        // The icon button carries its label for VoiceOver and the agent.
        guard case .styled(_, let style) = nodes[0], case .stack(_, _, _, let header)? = Optional(nodes[0].unstyled) else {
            return XCTFail("header is a styled stack: \(nodes[0])")
        }
        XCTAssertEqual(style.frame?.fillWidth, true)
        XCTAssertTrue(header.contains { $0.plainText == "3 running Updated just now" || $0.plainText.contains("3 running") })
        XCTAssertTrue("\(nodes[0])".contains("accessibilityLabel: Optional(\"Refresh\")"))
    }

    func testDayBarMergesSegmentsAndPlacesNow() async {
        let runs = DayBar.runs([0.5...0.75, 0.2...0.3, 0.25...0.4, 1.2...1.5])
        XCTAssertEqual(runs.map(\.span), [0...0.2, 0.2...0.4, 0.4...0.5, 0.5...0.75, 0.75...1])
        XCTAssertEqual(runs.map(\.filled), [false, true, false, true, false])
        let nodes = DayBar([0.5...0.75], now: 0.25, theme: .red, width: 102).resolve(in: RenderContext())
        guard case .stack(_, _, _, let pieces)? = nodes.first?.unstyled else { return XCTFail("\(nodes)") }
        // empty to now, the marker, empty to the meeting, the meeting, empty.
        XCTAssertEqual(pieces.count, 5)
        let widths = pieces.compactMap { node -> Double? in
            if case .styled(_, let style) = node { return style.frame?.width }
            return nil
        }
        XCTAssertEqual(widths.reduce(0, +), 102, accuracy: 0.001)
        XCTAssertEqual(widths[1], 2)
    }

    func testTagChipsPutTheRestInAMenu() async {
        let context = RenderContext()
        var picked: [String?] = []
        _ = TagChips(["work", "docs", "home", "dev", "music", "misc"], selection: "music", theme: .cyan) { picked.append($0) }.resolve(in: context)
        XCTAssertEqual(Set(context.handlers.keys), ["button/tag/All", "button/tag/work", "button/tag/docs", "button/tag/home", "button/tag/dev", "picker/tag/More"])
    }

    func testTypographySetsTheWholeFont() async {
        XCTAssertEqual(Text("12").typography(.stat).resolve(in: RenderContext()), [
            .styled(.text("12"), style: Style(font: FontSpec(size: 20, weight: .semibold, design: .rounded, monospacedDigit: true))),
        ])
        XCTAssertEqual(Text("a").typography(.caption).resolve(in: RenderContext()), [
            .styled(.text("a"), style: Style(font: FontSpec(size: 11, weight: .regular, design: .default))),
        ])
    }
}

private extension ViewNode {
    var unstyled: ViewNode {
        if case .styled(let child, _) = self { return child.unstyled }
        return self
    }
}
