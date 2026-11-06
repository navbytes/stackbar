import Foundation

/// A key with its modifiers, as plugins and settings spell it: `cmd+shift+k`,
/// `ctrl+option+space`, `⌘⇧V`, `cmd+return`. The one place that reads a
/// shortcut: manifest hotkeys (`HotKeySpec`), row action shortcuts, the
/// palette's keys and the keycaps Settings and ⌘K draw.
public struct KeyCombo: Hashable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable {
        // In the order macOS draws them: ⌃⌥⇧⌘.
        case control, option, shift, command

        public var glyph: String {
            switch self {
            case .control: return "⌃"
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }
    }

    public enum Key: Hashable, Sendable {
        /// A letter, digit or punctuation mark, lowercased.
        case character(Character)
        case `return`, delete, forwardDelete, escape, space, tab, up, down, left, right
        /// F1 to F12.
        case function(Int)

        /// The key as a spec writes it: `k`, `return`, `f5`.
        public var name: String {
            switch self {
            case .character(let character): return String(character)
            case .return: return "return"
            case .delete: return "delete"
            case .forwardDelete: return "forwarddelete"
            case .escape: return "escape"
            case .space: return "space"
            case .tab: return "tab"
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"
            case .function(let number): return "f\(number)"
            }
        }

        public var glyph: String {
            switch self {
            case .character(let character): return String(character).uppercased()
            case .return: return "↩"
            case .delete: return "⌫"
            case .forwardDelete: return "⌦"
            case .escape: return "⎋"
            case .space: return "Space"
            case .tab: return "⇥"
            case .up: return "↑"
            case .down: return "↓"
            case .left: return "←"
            case .right: return "→"
            case .function(let number): return "F\(number)"
            }
        }
    }

    public var modifiers: Set<Modifier>
    public var key: Key

    public init(_ key: Key, modifiers: Set<Modifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Reads `cmd+shift+k`, `⌘+⇧+K` or `⌘⇧K`; nil for anything else, such as
    /// a misspelt modifier (`shft`), two keys, or no key.
    public init?(_ spec: String) {
        let lowered = spec.lowercased().trimmingCharacters(in: .whitespaces)
        // `⌘⇧K` written without pluses: each glyph is a part.
        let parts: [String]
        if !lowered.contains("+"), lowered.count > 1, lowered.unicodeScalars.contains(where: { Self.glyphModifiers[String($0)] != nil }) {
            parts = lowered.map(String.init)
        } else {
            parts = lowered.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var modifiers: Set<Modifier> = []
        var key: Key?
        for part in parts {
            if let modifier = Self.modifierNames[part] ?? Self.glyphModifiers[part] {
                guard modifiers.insert(modifier).inserted else { return nil }
                continue
            }
            guard key == nil, let named = Self.key(part) else { return nil }
            key = named
        }
        guard let key else { return nil }
        self.init(key, modifiers: modifiers)
    }

    /// The spec in one spelling: modifiers in ⌃⌥⇧⌘ order, then the key
    /// (`ctrl+shift+cmd+k`).
    public var spec: String {
        let names: [Modifier: String] = [.control: "ctrl", .option: "option", .shift: "shift", .command: "cmd"]
        return (Modifier.allCases.filter(modifiers.contains).compactMap { names[$0] } + [key.name]).joined(separator: "+")
    }

    /// `⇧⌘K`, as menus draw it.
    public var glyphs: String {
        Modifier.allCases.filter(modifiers.contains).map(\.glyph).joined() + key.glyph
    }

    /// `glyphs` for a spec, or the spec as written when it isn't one.
    public static func glyphs(_ spec: String) -> String {
        KeyCombo(spec)?.glyphs ?? spec
    }

    /// Whether it can be a system-wide hotkey: ⌘, ⌃ or ⌥ with a letter,
    /// digit, space or F1 to F12.
    public var isHotKey: Bool {
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return false }
        switch key {
        case .character(let character): return character.isASCII && (character.isLetter || character.isNumber)
        case .space, .function: return true
        default: return false
        }
    }

    private static let modifierNames: [String: Modifier] = [
        "cmd": .command, "command": .command, "ctrl": .control, "control": .control,
        "opt": .option, "option": .option, "alt": .option, "shift": .shift,
    ]

    private static let glyphModifiers: [String: Modifier] = ["⌘": .command, "⌃": .control, "⌥": .option, "⇧": .shift]

    private static func key(_ part: String) -> Key? {
        switch part {
        case "return", "enter", "↩": return .return
        case "delete", "backspace", "⌫": return .delete
        case "forwarddelete", "⌦": return .forwardDelete
        case "escape", "esc", "⎋": return .escape
        case "space": return .space
        case "tab", "⇥": return .tab
        case "up", "↑": return .up
        case "down", "↓": return .down
        case "left", "←": return .left
        case "right", "→": return .right
        default:
            if part.count >= 2, part.hasPrefix("f"), let number = Int(part.dropFirst()), (1...12).contains(number) { return .function(number) }
            guard part.count == 1, let character = part.first, !character.isWhitespace else { return nil }
            return .character(character)
        }
    }
}
