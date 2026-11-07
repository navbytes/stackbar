import Foundation
import StackbarProtocol
@testable import StackbarHostCore
import XCTest

final class PaletteMemoryTests: XCTestCase {
    private func command(_ id: String, plugin: String = "dev.t.p") -> PaletteIndex.Entry {
        PaletteIndex.Entry(pluginID: plugin, pluginName: "P", title: id, kind: .command(CommandSpec(id: id, title: id)))
    }

    private func row(_ key: String) -> PaletteIndex.Entry {
        var entry = PaletteIndex.Entry(pluginID: "dev.t.apps", pluginName: "Apps", title: key, kind: .action(ActionID("a-\(UUID())"), value: nil))
        entry.rankKey = "dev.t.apps|row|search|\(key)"
        return entry
    }

    func testAChoiceTeachesUseAndThePickUnderOneID() {
        let memory = PaletteMemory(directory: nil)
        let slack = row("slack")
        memory.chose(slack, query: "s")
        XCTAssertGreaterThan(memory.usage.score(slack.learnID), 0)
        XCTAssertEqual(memory.picks.weights(for: "s").keys.sorted(), [slack.learnID])
        XCTAssertTrue(memory.isRecent(slack))

        let inside = row("mail")
        memory.chose(inside, query: nil)
        XCTAssertEqual(memory.picks.weights(for: "mail"), [:], "nothing typed at the root")
        XCTAssertGreaterThan(memory.usage.score(inside.learnID), 0)

        let run = command("run")
        memory.chose(run, query: "ru")
        XCTAssertEqual(memory.picks.weights(for: "ru").keys.sorted(), [run.learnID])
        XCTAssertEqual(memory.usage.score(run.learnID), 0, "a command's use is counted when it runs, not twice")
    }

    func testAHotkeyRunCountsForTheCommandsRow() {
        let memory = PaletteMemory(directory: nil)
        let entry = command("run")
        memory.used(CommandKey(pluginID: "dev.t.p", commandID: "run"))
        XCTAssertGreaterThan(memory.usage.score(entry.learnID), 0, "a hotkey run and a palette run are one id")
    }

    func testChangesBumpTheRevisionButLearningDoesNot() {
        let memory = PaletteMemory(directory: nil)
        let entry = command("run")
        let start = memory.revision
        memory.chose(entry, query: "r")
        XCTAssertEqual(memory.revision, start)
        memory.forget(entry)
        XCTAssertEqual(memory.revision, start + 1)
        XCTAssertEqual(memory.usage.score(entry.learnID), 0)
        XCTAssertEqual(memory.picks.weights(for: "r"), [:])
        memory.toggleFavorite(entry)
        XCTAssertTrue(memory.isFavorite(entry))
        memory.chose(entry, query: "r")
        memory.clear()
        XCTAssertEqual(memory.revision, start + 3, "a clear reaches the palette's cache")
        XCTAssertEqual(memory.usage.score(entry.learnID), 0)
        XCTAssertTrue(memory.isFavorite(entry), "pins stay")
        memory.handOver(from: "dev.t.p", to: "dev.t.q")
        XCTAssertEqual(memory.revision, start + 4)
        XCTAssertEqual(memory.favorites.ids, ["dev.t.q/run"])
    }

    func testCarriedIDs() {
        let all: (String) -> Bool = { _ in true }
        XCTAssertEqual(PaletteMemory.carried("a/run", from: "a", to: "b", carries: all), "b/run")
        XCTAssertEqual(PaletteMemory.carried("a|row|search|x|y", from: "a", to: "b", carries: { $0 == "search" }), "b|row|search|x|y")
        XCTAssertNil(PaletteMemory.carried("a|row|other|x", from: "a", to: "b", carries: { $0 == "search" }))
        XCTAssertNil(PaletteMemory.carried("a|panel", from: "a", to: "b", carries: all))
        XCTAssertNil(PaletteMemory.carried("ab/run", from: "a", to: "b", carries: all), "another plugin whose id starts the same")
    }
}
