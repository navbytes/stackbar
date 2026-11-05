import XCTest
import StackbarProtocol
@testable import StackbarHostCore

final class PaletteHotKeyTests: XCTestCase {
    func testStoredSpecFallsBackToTheStandardOne() {
        XCTAssertEqual(PaletteHotKey.spec(stored: nil), "ctrl+option+space")
        XCTAssertEqual(PaletteHotKey.spec(stored: "space"), "ctrl+option+space")
        XCTAssertEqual(PaletteHotKey.spec(stored: "cmd+space"), "cmd+space")
        XCTAssertEqual(PaletteHotKey.spec(stored: "cmd+shift+p"), "cmd+shift+p")
    }

    func testCommandSpaceKeepsTheStandardHotKeyWhileSpotlightHoldsIt() {
        XCTAssertEqual(PaletteHotKey.registered("cmd+space", spotlightHoldsCommandSpace: true), ["cmd+space", "ctrl+option+space"])
        XCTAssertEqual(PaletteHotKey.registered("cmd+space", spotlightHoldsCommandSpace: false), ["cmd+space"])
        XCTAssertEqual(PaletteHotKey.registered("command+space", spotlightHoldsCommandSpace: true), ["command+space", "ctrl+option+space"])
        XCTAssertEqual(PaletteHotKey.registered("cmd+shift+p", spotlightHoldsCommandSpace: true), ["cmd+shift+p"])
    }

    func testSpotlightShortcutIsOnByDefault() {
        XCTAssertTrue(SpotlightShortcut.holdsCommandSpace(nil))
        XCTAssertTrue(SpotlightShortcut.holdsCommandSpace(["65": ["enabled": true]]))
    }

    func testSpotlightShortcutTurnedOffOrMoved() {
        let on: [String: Any] = ["64": ["enabled": 1, "value": ["parameters": [32, 49, 1_048_576], "type": "standard"]]]
        let off: [String: Any] = ["64": ["enabled": 0, "value": ["parameters": [32, 49, 1_048_576], "type": "standard"]]]
        let offBool: [String: Any] = ["64": ["enabled": false]]
        let moved: [String: Any] = ["64": ["enabled": 1, "value": ["parameters": [32, 49, 1_572_864], "type": "standard"]]]
        XCTAssertTrue(SpotlightShortcut.holdsCommandSpace(on))
        XCTAssertFalse(SpotlightShortcut.holdsCommandSpace(off))
        XCTAssertFalse(SpotlightShortcut.holdsCommandSpace(offBool))
        XCTAssertFalse(SpotlightShortcut.holdsCommandSpace(moved))
    }
}
