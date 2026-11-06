import XCTest
@testable import StackbarHostCore
import StackbarProtocol

/// Bugs found reviewing the palette's ranking (11-06).
final class PaletteRankingTests: XCTestCase {
    func testAPluginNameRanksBelowATitleThatMatches() {
        var index = PaletteIndex()
        index.update(pluginID: "gh", pluginName: "GitHub", panel: .stack(axis: .vertical, children: [
            .button(title: "Open Inbox", action: "button/inbox"),
            .button(title: "Refresh", action: "button/refresh"),
        ]))
        index.update(pluginID: "dev", pluginName: "Dev Tools", panel: .button(title: "Reset Git Cache", action: "button/reset"))
        let found = index.search("git")
        XCTAssertEqual(found.first?.title, "Reset Git Cache")
        XCTAssertEqual(found.count, 3, "the plugin's own rows are still found by its name")
    }

    func testLettersInOrderNeverBeatTheWholeText() throws {
        let exact = try XCTUnwrap(TextMatch.score("abcdefghijklmnopqrst", in: "abcdefghijklmnopqrst"))
        let scattered = try XCTUnwrap(TextMatch.score("abcdefghijklmnopqrst", in: "a-bcdefghijklmnopqrst"))
        XCTAssertGreaterThan(exact, scattered)
        let contains = try XCTUnwrap(TextMatch.score("hub", in: "GitHub"))
        XCTAssertGreaterThan(contains, scattered)
    }

    func testTiesKeepTheIndexOrder() {
        var index = PaletteIndex()
        index.update(pluginID: "p", pluginName: "P", panel: .stack(axis: .vertical, children: [
            .button(title: "Copy A", action: "button/a"),
            .button(title: "Copy B", action: "button/b"),
            .button(title: "Copy C", action: "button/c"),
        ]))
        for _ in 0..<5 {
            XCTAssertEqual(index.search("copy").map(\.title), ["Copy A", "Copy B", "Copy C"])
        }
    }

    func testAnAliasAfterLeadingSpaces() {
        let registry = CommandRegistry(file: nil)
        registry.update(pluginID: "gh", pluginName: "PR Cockpit", specs: [CommandSpec(id: "search", title: "Search Pull Requests", kind: .view)])
        var index = PaletteIndex()
        index.setCommands(registry.entries, preferences: [CommandKey(pluginID: "gh", commandID: "search"): CommandPreference(alias: "gh")])
        XCTAssertEqual(index.aliasMatch("  gh react")?.rest, "react")
    }
}
