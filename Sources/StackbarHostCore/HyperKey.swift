import Foundation

/// Caps Lock as a Hyper key: held, it presses ⌃⌥⇧⌘ with whatever key comes
/// next; tapped alone, it can be Escape.
///
/// macOS can't make Caps Lock a modifier by itself, so Stackbar does it in
/// two steps, the way dedicated Hyper key apps do. `hidutil` remaps Caps Lock
/// to F18 (a key no keyboard has), and the app's keyboard listener turns F18
/// held into the four modifiers. The remap lasts until logout; Stackbar puts
/// it back when the setting is off or the app quits.
public enum HyperKey {
    public static let defaultsKey = "hyperKey"
    public static let escapeDefaultsKey = "hyperKeyEscape"

    /// HID usages (page 7, keyboard) as `hidutil` takes them.
    public static let capsLockUsage: UInt64 = 0x7_0000_0039
    public static let f18Usage: UInt64 = 0x7_0000_006D
    /// F18's virtual key code (kVK_F18) and Escape's (kVK_Escape).
    public static let f18KeyCode: Int64 = 0x4F
    public static let escapeKeyCode: Int64 = 0x35

    /// A press shorter than this, with no other key, is a tap.
    public static let tapLimit: TimeInterval = 0.3

    // MARK: The remap

    /// One `UserKeyMapping` entry.
    public struct Mapping: Equatable, Sendable {
        public var source: UInt64
        public var destination: UInt64
        public init(source: UInt64, destination: UInt64) {
            self.source = source
            self.destination = destination
        }
    }

    public static let ours = Mapping(source: capsLockUsage, destination: f18Usage)

    /// The mappings in `hidutil property --get UserKeyMapping`'s output, a
    /// property-list style dump; `(null)` or nothing is none.
    public static func mappings(fromHidutil output: String) -> [Mapping] {
        var result: [Mapping] = []
        var source: UInt64?
        var destination: UInt64?
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("HIDKeyboardModifierMappingSrc") { source = number(in: trimmed) }
            if trimmed.hasPrefix("HIDKeyboardModifierMappingDst") { destination = number(in: trimmed) }
            if let src = source, let dst = destination {
                result.append(Mapping(source: src, destination: dst))
                source = nil
                destination = nil
            }
        }
        return result
    }

    private static func number(in line: String) -> UInt64? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let value = line[line.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
        if value.hasPrefix("0x") { return UInt64(value.dropFirst(2), radix: 16) }
        return UInt64(value)
    }

    /// `current` with Caps Lock going to F18 (or not), keeping every other
    /// remap someone else made.
    public static func mappings(_ current: [Mapping], hyper on: Bool) -> [Mapping] {
        var kept = current.filter { $0.source != capsLockUsage || ($0 != ours && !on) }
        if on { kept.append(ours) }
        return kept
    }

    /// The JSON `hidutil property --set` takes for `mappings`.
    public static func hidutilJSON(_ mappings: [Mapping]) -> String {
        let entries = mappings.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.source),\"HIDKeyboardModifierMappingDst\":\($0.destination)}"
        }
        return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    }

    // MARK: Presses

    /// What the listener does with one key event, decided away from
    /// CoreGraphics so it can be tested.
    public struct State: Sendable {
        public enum Event: Equatable, Sendable {
            case keyDown(code: Int64, at: TimeInterval)
            case keyUp(code: Int64, at: TimeInterval)
        }

        public enum Output: Equatable, Sendable {
            /// Not ours: let it through as it is.
            case pass
            /// Drop it.
            case swallow
            /// Drop it and send it again with ⌃⌥⇧⌘ added.
            case withHyper
            /// Drop it and press Escape.
            case escape
        }

        public var escapeOnTap: Bool
        public private(set) var held = false
        private var pressedAt: TimeInterval = 0
        private var usedWithKey = false
        /// Keys pressed with Hyper, so their release gets it too even if
        /// Caps Lock came up first.
        private var hyperKeys: Set<Int64> = []

        public init(escapeOnTap: Bool) {
            self.escapeOnTap = escapeOnTap
        }

        public mutating func handle(_ event: Event) -> Output {
            switch event {
            case .keyDown(HyperKey.f18KeyCode, let time):
                if !held {
                    held = true
                    pressedAt = time
                    usedWithKey = false
                }
                return .swallow
            case .keyUp(HyperKey.f18KeyCode, let time):
                defer { held = false }
                guard held, escapeOnTap, !usedWithKey, time - pressedAt < HyperKey.tapLimit else { return .swallow }
                return .escape
            case .keyDown(let code, _):
                guard held else { return .pass }
                usedWithKey = true
                hyperKeys.insert(code)
                return .withHyper
            case .keyUp(let code, _):
                return hyperKeys.remove(code) != nil ? .withHyper : .pass
            }
        }

        /// The listener was paused by macOS: start over.
        public mutating func reset() {
            held = false
            usedWithKey = false
            hyperKeys = []
        }
    }
}
