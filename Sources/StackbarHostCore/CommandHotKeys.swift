import Foundation
import StackbarProtocol

/// Which system-wide shortcut opens which command.
public enum CommandHotKeys {
    /// The user's own hotkey for each enabled command, or, for the command a
    /// manifest names in `hotkeyCommand`, the manifest's `hotkey` while the
    /// user hasn't set one. `manifests` are by plugin id.
    public static func wanted(entries: [CommandRegistry.Entry], preference: (CommandKey) -> CommandPreference, manifests: [String: Manifest]) -> [CommandKey: String] {
        var wanted: [CommandKey: String] = [:]
        for entry in entries {
            let saved = preference(entry.key)
            guard saved.enabled else { continue }
            if let hotkey = saved.hotkey, !hotkey.isEmpty {
                wanted[entry.key] = hotkey
            } else if let hotkey = pluginHotKey(for: entry, in: manifests) {
                wanted[entry.key] = hotkey
            }
        }
        return wanted
    }

    /// The manifest hotkey that opens this command, if the manifest gives
    /// its hotkey to a command and this is the one.
    public static func pluginHotKey(for entry: CommandRegistry.Entry, in manifests: [String: Manifest]) -> String? {
        guard let manifest = manifests[entry.pluginID], manifest.hotkeyCommand == entry.spec.id else { return nil }
        return manifest.hotkey
    }

    /// Whether the manifest's hotkey toggles the panel: it has one and
    /// hasn't given it to a command.
    public static func opensPanel(_ manifest: Manifest?) -> Bool {
        manifest?.hotkey != nil && manifest?.hotkeyCommand == nil
    }
}
