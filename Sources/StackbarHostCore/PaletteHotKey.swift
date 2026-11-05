import Foundation
import StackbarProtocol

/// The palette's own hotkey, which the user picks in Settings or the welcome
/// window. Stored as a hotkey spec (`ctrl+option+space`).
public enum PaletteHotKey {
    public static let defaultsKey = "paletteHotKey"
    /// Free on every Mac, so it is where the palette starts.
    public static let standard = "ctrl+option+space"
    /// Where Raycast and Alfred users want it, once Spotlight lets go.
    public static let spotlight = "cmd+space"

    /// The stored spec when it is a hotkey the palette can use; the standard
    /// one otherwise.
    public static func spec(stored: String?) -> String {
        guard let stored, HotKeySpec(stored) != nil else { return standard }
        return stored
    }

    /// The hotkeys to register: the chosen one, plus the standard one while
    /// Spotlight still holds ⌘Space, so the palette is never unreachable.
    public static func registered(_ spec: String, spotlightHoldsCommandSpace: Bool) -> [String] {
        let chosen = self.spec(stored: spec)
        guard spotlightHoldsCommandSpace, HotKeySpec(chosen) == HotKeySpec(spotlight) else { return [chosen] }
        return [chosen, standard]
    }
}

/// Spotlight's own shortcut, read from the `com.apple.symbolichotkeys`
/// preferences: "Show Spotlight search" is symbolic hot key 64. Stackbar can
/// only read it; the user turns it off in System Settings.
public enum SpotlightShortcut {
    /// Keyboard › Keyboard Shortcuts, where Spotlight's shortcuts are.
    public static let settingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"

    /// Whether Spotlight answers ⌘Space, from the `AppleSymbolicHotKeys`
    /// dictionary. Missing entries mean macOS's default: on, ⌘Space.
    public static func holdsCommandSpace(_ symbolicHotKeys: [String: Any]?) -> Bool {
        guard let entry = symbolicHotKeys?["64"] as? [String: Any] else { return true }
        if let enabled = entry["enabled"] as? Bool, !enabled { return false }
        if let enabled = entry["enabled"] as? Int, enabled == 0 { return false }
        guard let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [Int], parameters.count >= 3 else { return true }
        // 49 is the space bar's key code, 1048576 (1 << 20) the ⌘ flag alone.
        return parameters[1] == 49 && parameters[2] == 1_048_576
    }
}
