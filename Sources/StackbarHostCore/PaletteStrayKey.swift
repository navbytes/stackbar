import Foundation

/// A key press that reached the palette's window with no field to take it.
/// SwiftUI only hands keys to the palette while one of its fields holds the
/// keyboard; when none does (a field that went away, a focus write SwiftUI
/// dropped), the arrows went nowhere until Tab put a field back in charge.
/// The window catches such a key and the palette still does what it meant.
public enum PaletteStrayKey: Equatable, Sendable {
    /// Up, Down, or Left and Right in a grid: moves the highlight by this many.
    case move(Int)
    /// Return: what Return on the highlighted line does.
    case submit
    /// Plain typing: goes on the end of the search text.
    case type(String)

    /// The modifier keys that change what a key means here.
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Mac virtual key codes (Carbon's kVK_*), which stay the same on
    /// every keyboard layout.
    public enum KeyCode {
        public static let returnKey: UInt16 = 36
        public static let keypadEnter: UInt16 = 76
        public static let left: UInt16 = 123
        public static let right: UInt16 = 124
        public static let down: UInt16 = 125
        public static let up: UInt16 = 126
    }

    /// What `keyCode` with `modifiers` means to the palette, or nil to leave
    /// the key alone (Esc, Tab and shortcuts take their usual way).
    /// `characters` is the key's text ignoring modifiers, but with Shift.
    /// `columns` is the grid's width when a grid list is showing.
    public init?(keyCode: UInt16, modifiers: Modifiers, characters: String?, columns: Int?) {
        let line = columns ?? 1
        let plain = modifiers.isDisjoint(with: [.command, .option, .control])
        switch keyCode {
        case KeyCode.down where plain: self = .move(line)
        case KeyCode.up where plain: self = .move(-line)
        case KeyCode.right where plain && columns != nil: self = .move(1)
        case KeyCode.left where plain && columns != nil: self = .move(-1)
        case KeyCode.returnKey where plain, KeyCode.keypadEnter where plain: self = .submit
        default:
            // ⌃N/⌃J down and ⌃P/⌃K up, as the palette's own keys do.
            if modifiers == .control {
                switch characters?.lowercased() {
                case "n", "j": self = .move(line)
                case "p", "k": self = .move(-line)
                default: return nil
                }
                return
            }
            guard plain, let characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy(Self.isTypeable) else { return nil }
            self = .type(characters)
        }
    }

    /// Printable text: not a control character, and not one of the private
    /// use characters AppKit gives arrows and function keys.
    private static func isTypeable(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .control { return false }
        if (0xF700...0xF8FF).contains(scalar.value) { return false }
        return true
    }
}
