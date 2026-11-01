import Foundation
import XCTest
@testable import StackbarKit

@MainActor
final class ExpressiveDesignTests: XCTestCase {
    func testVividHeroReadsInEveryTheme() async {
        for (name, theme) in Theme.all {
            for dark in [false, true] {
                guard case .linearGradient(let colors, _) = theme.vivid else { return XCTFail("vivid is a gradient") }
                for stop in colors {
                    XCTAssertGreaterThanOrEqual(HexColor.contrast(theme.onSolid.hex(dark: dark), stop.hex(dark: dark)) ?? 0, 4.5, "\(name) vivid, dark: \(dark)")
                }
            }
        }
    }

    func testSkyPhasesFollowTheHour() async {
        XCTAssertEqual(Sky(hour: 3), .night)
        XCTAssertEqual(Sky(hour: 6.5), .dawn)
        XCTAssertEqual(Sky(hour: 12), .day)
        XCTAssertEqual(Sky(hour: 18), .dusk)
        XCTAssertEqual(Sky(hour: 23.9), .night)
        XCTAssertEqual(Sky(hour: 24 + 12), .day)
        XCTAssertEqual(Sky(hour: -1), .night)
        for sky in Sky.allCases {
            for color in [sky.colors.top, sky.colors.bottom] {
                XCTAssertGreaterThanOrEqual(HexColor.contrast("#FFFFFF", color) ?? 0, 4.5, sky.rawValue)
            }
        }
    }

    func testAvatarInitialsAndStackSummary() async {
        XCTAssertEqual(Avatar.initials("Ada Lovelace"), "AL")
        XCTAssertEqual(Avatar.initials("grace"), "G")
        XCTAssertEqual(Avatar.initials("linus-torvalds"), "LT")
        XCTAssertEqual(Avatar.initials("  "), "?")
        XCTAssertEqual(AvatarStack.summary(["Ada"], limit: 4), "Ada")
        XCTAssertEqual(AvatarStack.summary(["Ada", "Grace"], limit: 4), "Ada and Grace")
        XCTAssertEqual(AvatarStack.summary(["Ada", "Grace", "Ken", "Linus", "Rob"], limit: 3), "Ada, Grace, Ken and 2 more")
    }

    func testRingClusterNestsAndLabelsItsRings() async {
        let cluster = RingCluster([.init("CPU", value: 0.42, theme: .green), .init("Memory", value: 12, total: 16, theme: .blue), .init("Disk", value: 2, theme: .amber), .init("Extra", value: 0, theme: .red)], size: 100, lineWidth: 10, gap: 2)
        XCTAssertEqual([0, 1, 2].map(cluster.diameter), [100, 76, 52])
        let nodes = cluster.resolve(in: RenderContext())
        XCTAssertEqual(nodes.first?.plainText, "CPU 42%, Memory 75%, Disk 100%")
    }

    func testBackdropAndTilesUseTheNewVocabulary() async {
        var opened = 0
        let view: ViewContent = [
            Backdrop(imageURL: "https://is1-ssl.mzstatic.com/a.jpg", theme: .pink) { Text("Song") },
            Grid(columns: 2) {
                Tile("Docs", symbol: "doc", imageURL: "https://example.com/icon.png", theme: .cyan) { opened += 1 }
                Tile("Mail", symbol: "envelope", theme: .cyan)
            },
            Image(systemName: "waveform").symbolEffect(.variableColor).numericTransition(),
        ]
        let root = ViewNode.stack(axis: .vertical, children: view.resolve(in: RenderContext()))
        XCTAssertEqual(root.imageURLs, ["https://is1-ssl.mzstatic.com/a.jpg", "https://example.com/icon.png"])
        XCTAssertEqual(root.actions, [ActionID("button/Docs")])
        guard case .stack(_, _, _, let children) = root, case .grid(let columns, _, let cells) = children[1] else { return XCTFail("a grid") }
        XCTAssertEqual(columns, 2)
        XCTAssertEqual(cells.count, 2)
        guard case .styled(_, let style) = children[2] else { return XCTFail("styled symbol") }
        XCTAssertEqual(style.symbol?.effect, .variableColor)
        XCTAssertEqual(style.numericTransition, true)
    }

    func testThemePaintsCarryDarkVariants() async {
        let theme = Theme.blue
        guard case .angularGradient(let sweep, -90) = theme.sweep, case .radialGradient(let glow, _, _, _) = theme.glow else { return XCTFail("paint kinds") }
        XCTAssertEqual(sweep.last, theme.solid)
        XCTAssertNotNil(sweep.first?.dark)
        XCTAssertEqual(glow.map(\.light), ["#0A60C840", "#0A60C800"])
        XCTAssertEqual(Theme.lighten("#000000", 0.5), "#808080")
        XCTAssertEqual(theme.track, .color(HexColor("#0A60C82E", dark: "#5AA9FF38")))
    }
}
