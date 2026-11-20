import XCTest
@testable import StackbarHostCore

/// Keys that reach the palette's window with no field holding the keyboard
/// still move, run and type (the arrows that did nothing until Tab).
final class PaletteStrayKeyTests: XCTestCase {
    private typealias Key = PaletteStrayKey

    private func key(_ code: UInt16, _ modifiers: Key.Modifiers = [], _ characters: String? = nil, columns: Int? = nil) -> Key? {
        Key(keyCode: code, modifiers: modifiers, characters: characters, columns: columns)
    }

    func testArrowsMoveALineOrAGridRow() {
        XCTAssertEqual(key(Key.KeyCode.down, [], "\u{F701}"), .move(1))
        XCTAssertEqual(key(Key.KeyCode.up, [], "\u{F700}"), .move(-1))
        XCTAssertEqual(key(Key.KeyCode.down, [], "\u{F701}", columns: 8), .move(8))
        XCTAssertEqual(key(Key.KeyCode.right, [], "\u{F703}", columns: 8), .move(1))
        XCTAssertEqual(key(Key.KeyCode.left, [], "\u{F702}", columns: 8), .move(-1))
        // Shift doesn't stop an arrow, as in the field.
        XCTAssertEqual(key(Key.KeyCode.down, .shift, "\u{F701}"), .move(1))
    }

    func testLeftAndRightOutsideAGridAreLeftAlone() {
        XCTAssertNil(key(Key.KeyCode.left, [], "\u{F702}"))
        XCTAssertNil(key(Key.KeyCode.right, [], "\u{F703}"))
    }

    func testShortcutsAreLeftAlone() {
        XCTAssertNil(key(Key.KeyCode.down, .command, "\u{F701}"))
        XCTAssertNil(key(Key.KeyCode.up, .option, "\u{F700}"))
        XCTAssertNil(key(Key.KeyCode.returnKey, .command, "\r"))
        XCTAssertNil(key(40, .command, "k"))
        XCTAssertNil(key(0, .option, "a"))
    }

    func testReturnSubmits() {
        XCTAssertEqual(key(Key.KeyCode.returnKey, [], "\r"), .submit)
        XCTAssertEqual(key(Key.KeyCode.keypadEnter, [], "\u{03}"), .submit)
    }

    func testEmacsAndVimMoves() {
        XCTAssertEqual(key(45, .control, "n"), .move(1))
        XCTAssertEqual(key(38, .control, "j"), .move(1))
        XCTAssertEqual(key(35, .control, "p"), .move(-1))
        XCTAssertEqual(key(40, .control, "k"), .move(-1))
        XCTAssertEqual(key(45, .control, "n", columns: 6), .move(6))
        XCTAssertNil(key(0, .control, "a"))
    }

    func testTypingGoesToTheSearch() {
        XCTAssertEqual(key(0, [], "a"), .type("a"))
        XCTAssertEqual(key(0, .shift, "A"), .type("A"))
        XCTAssertEqual(key(49, [], " "), .type(" "))
    }

    func testEscTabDeleteAndFunctionKeysAreLeftAlone() {
        XCTAssertNil(key(53, [], "\u{1B}"))
        XCTAssertNil(key(48, [], "\t"))
        XCTAssertNil(key(51, [], "\u{7F}"))
        XCTAssertNil(key(122, [], "\u{F704}"))
        XCTAssertNil(key(0, [], nil))
        XCTAssertNil(key(0, [], ""))
    }
}
