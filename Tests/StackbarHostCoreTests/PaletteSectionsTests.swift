import XCTest
@testable import StackbarHostCore
import StackbarProtocol

final class PaletteSectionsTests: XCTestCase {
    private func command(_ id: String) -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: "p", pluginName: "P", title: id, kind: .command(CommandSpec(id: id, title: id)))
    }

    private func action(_ id: String) -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: "p", pluginName: "P", title: id, kind: .action(ActionID(id), value: nil))
    }

    func testEmptyQueryGroupsRecentThenCommandsThenActions() {
        let results = [action("a1"), command("c1"), command("c2"), action("a2")]
        let sections = PaletteSection.group(results, query: "") { $0.title == "a1" }
        XCTAssertEqual(sections.map(\.title), ["Recent", "Commands", "Panel Actions"])
        XCTAssertEqual(sections.map { $0.entries.map(\.title) }, [["a1"], ["c1", "c2"], ["a2"]])
    }

    func testRecentIsCappedAndEmptyGroupsAreLeftOut() {
        let results = (1...4).map { command("c\($0)") }
        let sections = PaletteSection.group(results, query: " ", recentLimit: 2) { _ in true }
        XCTAssertEqual(sections.map(\.title), ["Recent", "Commands"])
        XCTAssertEqual(sections[0].entries.map(\.title), ["c1", "c2"])
    }

    func testATypedQueryKeepsOneRankedList() {
        let results = [action("a1"), command("c1")]
        let sections = PaletteSection.group(results, query: "x") { _ in true }
        XCTAssertEqual(sections, [PaletteSection(title: "Results", entries: results)])
        XCTAssertEqual(PaletteSection.group([], query: "x") { _ in true }, [])
    }
}
