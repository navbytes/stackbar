import Foundation
import StackbarProtocol

/// Tab in the palette's root hands what you typed to one fallback command,
/// as Raycast's Tab hands it to Quick AI. Which one is a setting; left unset
/// it is Ask AI's when that plugin is installed, and nothing otherwise, so
/// Tab keeps moving focus as it always has.
public enum PaletteTabTarget {
    public static let defaultsKey = "paletteTabCommand"
    /// Saved when the user turned Tab's hand-off off.
    public static let off = "off"
    /// The default, when installed.
    public static let preferred = CommandKey(pluginID: "io.navbytes.stackbar.plugins.ask-ai", commandID: "ask")

    /// The fallback Tab hands text to, or nil for none.
    public static func command(saved: String?, fallbacks: [CommandRegistry.Entry]) -> CommandRegistry.Entry? {
        if saved == off { return nil }
        if let saved, let key = CommandKey(saved), let chosen = fallbacks.first(where: { $0.key == key }) { return chosen }
        return fallbacks.first { $0.key == preferred }
    }

    /// That command's line in the root built for the typed text.
    public static func entry(for command: CommandRegistry.Entry, in root: PaletteRoot) -> PaletteIndex.Entry? {
        let lines = root.entries.filter { entry in
            guard entry.pluginID == command.pluginID, case .command(let spec) = entry.kind else { return false }
            return spec.id == command.spec.id
        }
        return lines.first { root.role(of: $0) == .fallback } ?? lines.first
    }
}
