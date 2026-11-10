import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class ListSelectionTests: XCTestCase {
    func testStartsOnTheFirstLineAndStopsAtTheEnds() {
        var selection = ListSelection()
        let ids = ["a", "b", "c"]
        XCTAssertEqual(selection.selected(in: ids, query: ""), "a")
        selection.move(1, in: ids, query: "")
        XCTAssertEqual(selection.selected(in: ids, query: ""), "b")
        selection.move(5, in: ids, query: "")
        XCTAssertEqual(selection.index(in: ids, query: ""), 2)
        selection.move(-9, in: ids, query: "")
        XCTAssertEqual(selection.selected(in: ids, query: ""), "a")
        selection.move(1, in: [], query: "")
        XCTAssertEqual(selection.selected(in: [], query: ""), nil)
    }

    /// The reported bug: after typing, Down must go from the first match to
    /// the second, whatever was selected before and however far down.
    func testTypingStartsAgainOnTheFirstMatch() {
        var selection = ListSelection()
        let all = (1...10).map { "item\($0)" }
        for _ in 0..<7 { selection.move(1, in: all, query: "") }
        XCTAssertEqual(selection.selected(in: all, query: ""), "item8")
        let matches = ["item1", "item10"]
        XCTAssertEqual(selection.selected(in: matches, query: "item1"), "item1", "a new query highlights its first match")
        selection.move(1, in: matches, query: "item1")
        XCTAssertEqual(selection.selected(in: matches, query: "item1"), "item10", "one press moves one line")
    }

    func testKeepsItsLineWhenTheListReorders() {
        var selection = ListSelection()
        selection.move(1, in: ["a", "b", "c"], query: "x")
        XCTAssertEqual(selection.selected(in: ["c", "a", "b"], query: "x"), "b")
        selection.move(1, in: ["c", "a", "b"], query: "x")
        XCTAssertEqual(selection.selected(in: ["c", "a", "b"], query: "x"), "b", "already the last line")
        XCTAssertEqual(selection.selected(in: ["c", "a"], query: "x"), "c", "gone: the first line")
        selection.reset()
        XCTAssertEqual(selection.selected(in: ["c", "a", "b"], query: "x"), "c")
    }
}

final class PaletteIndexStabilityTests: XCTestCase {
    private func buttons(_ titles: [String]) -> ViewNode {
        .stack(axis: .vertical, children: titles.map { .button(title: $0, action: ActionID("button/\($0)")) })
    }

    func testAPluginThatReRendersKeepsItsPlace() {
        var index = PaletteIndex()
        index.update(pluginID: "a", pluginName: "A", panel: buttons(["One", "Two"]))
        index.update(pluginID: "b", pluginName: "B", panel: buttons(["Three"]))
        let revision = index.revision
        XCTAssertFalse(index.update(pluginID: "a", pluginName: "A", panel: buttons(["One", "Two"])), "same affordances: no change")
        XCTAssertEqual(index.revision, revision)
        XCTAssertTrue(index.update(pluginID: "a", pluginName: "A", panel: buttons(["One", "Two", "Four"])))
        XCTAssertGreaterThan(index.revision, revision)
        XCTAssertEqual(index.entries.map(\.title), ["One", "Two", "Four", "Three"], "a's entries stay ahead of b's")
        XCTAssertEqual(index.searchPanels("").map(\.title), ["One", "Two", "Four", "Three"])
    }

    func testSearchListsEachEntryOnce() {
        var index = PaletteIndex()
        index.update(pluginID: "a", pluginName: "A", panel: .stack(axis: .vertical, children: [
            .link(title: "Docs", url: "https://example.com"),
            .link(title: "Docs", url: "https://example.com"),
        ]))
        XCTAssertEqual(index.searchPanels("docs").count, 1)
        XCTAssertEqual(index.searchPanels("").count, 1)
    }
}
