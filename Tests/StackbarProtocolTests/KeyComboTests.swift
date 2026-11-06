import XCTest
@testable import StackbarProtocol

final class KeyComboTests: XCTestCase {
    func testEverySpellingReadsTheSame() {
        let expected = KeyCombo(.character("k"), modifiers: [.command, .shift])
        for spec in ["cmd+shift+k", "Shift+Command+K", "⌘+⇧+k", "⌘⇧K", " cmd + shift + k "] {
            XCTAssertEqual(KeyCombo(spec), expected, spec)
        }
        XCTAssertEqual(expected.spec, "shift+cmd+k")
        XCTAssertEqual(expected.glyphs, "⇧⌘K")
    }

    func testNamedKeys() {
        XCTAssertEqual(KeyCombo("cmd+return")?.key, .return)
        XCTAssertEqual(KeyCombo("enter")?.key, .return)
        XCTAssertEqual(KeyCombo("cmd+up")?.glyphs, "⌘↑")
        XCTAssertEqual(KeyCombo("ctrl+option+space")?.glyphs, "⌃⌥Space")
        XCTAssertEqual(KeyCombo("cmd+f5")?.key, .function(5))
        XCTAssertEqual(KeyCombo("cmd+1")?.key, .character("1"))
    }

    func testTyposAreNotShortcuts() {
        for spec in ["cmd+shft+k", "cmd+k+j", "cmd+", "", "cmd+cmd+k", "cmd+f13", "cmd+shift"] {
            XCTAssertNil(KeyCombo(spec), spec)
        }
        XCTAssertEqual(KeyCombo.glyphs("cmd+shft+k"), "cmd+shft+k", "shown as written when it can't be read")
    }

    func testHotKeysNeedACommandControlOrOptionAndAPlainKey() {
        XCTAssertTrue(KeyCombo("cmd+shift+v")!.isHotKey)
        XCTAssertTrue(KeyCombo("ctrl+f12")!.isHotKey)
        XCTAssertFalse(KeyCombo("shift+v")!.isHotKey)
        XCTAssertFalse(KeyCombo("cmd+return")!.isHotKey)
        XCTAssertFalse(KeyCombo("cmd+.")!.isHotKey)
        XCTAssertEqual(HotKeySpec("⌘⇧V")?.key, "v")
        XCTAssertEqual(HotKeySpec("option+space")?.modifiers, [.option])
        XCTAssertNil(HotKeySpec("cmd+up"))
    }
}
