import Foundation
import XCTest
@testable import StackbarHostCore
import StackbarKit
import StackbarProtocol

/// The shared components pass the style lint in every theme, so a plugin
/// built from them starts clean.
@MainActor
final class DesignLintTests: XCTestCase {
    func testEveryComponentLintsCleanInEveryTheme() async {
        for (name, theme) in Theme.all {
            let view: ViewContent = [
                PanelHeader("Title", subtitle: "Subtitle", symbol: "star", theme: theme) {
                    IconButton("arrow.clockwise", label: "Refresh", theme: theme) {}
                },
                HeroCard(theme: theme) { Metric("25:00", caption: "Focus") },
                Card("Card", detail: "3") {
                    StatTile("Plain", value: "12", caption: "caption", symbol: "star", theme: theme)
                    StatTile("Emphasized", value: "12", caption: "caption", theme: theme, emphasized: true)
                    Meter("Meter", reading: "3 of 4", value: 0.75, theme: theme)
                },
                StatTile("Emphasized", value: "12", theme: theme, emphasized: true),
                Pill("Pill", symbol: "star", theme: theme),
                Banner("Banner", theme: theme),
                EmptyState("Empty", symbol: "star", message: "Message", theme: theme) {
                    ActionButton("Prominent", theme: theme, prominent: true) {}
                    ActionButton("Plain", theme: theme) {}
                },
                Chip("Selected", theme: theme, selected: true) {},
                Chip("Unselected", theme: theme) {},
                IconButton("plus", label: "Tinted", theme: theme, prominence: .tinted) {},
                IconButton("plus", label: "Filled", theme: theme, prominence: .filled) {},
            ]
            let nodes = view.resolve(in: RenderContext())
            let warnings = StyleLint.warnings(.stack(axis: .vertical, children: nodes))
            XCTAssertEqual(warnings, [], name)
        }
    }
}
