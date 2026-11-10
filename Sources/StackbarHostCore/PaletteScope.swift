import Foundation
import StackbarProtocol

/// Searching inside one plugin from the palette, as Spotlight on macOS 26
/// searches inside an app: type the plugin's name, press Tab, and what you
/// type next goes only to that plugin, under a chip with its name. Esc, or
/// Delete in the empty field, leaves.
///
/// Tab enters only from a row that stands for the plugin's search: its root
/// search command, or its "Open" row when it has one. From any other row Tab
/// still hands the text to Ask AI (`PaletteTabTarget`).
public enum PaletteScope {
    /// The root-search command Tab on `entry` searches inside: the command
    /// itself, or for a plugin's "Open" row its first root-search command.
    /// Nil when the row has none, or the user disabled it. Whether it is on
    /// for the main search doesn't matter, as with an alias.
    public static func target(of entry: PaletteIndex.Entry, commands: [CommandRegistry.Entry],
                              preference: (CommandKey) -> CommandPreference) -> CommandRegistry.Entry? {
        switch entry.kind {
        case .command:
            guard let key = entry.commandKey, let command = commands.first(where: { $0.key == key }),
                  RootSearchGate.searches(command.spec, preference: preference(key)) else { return nil }
            return command
        case .showPanel:
            return commands.first { $0.pluginID == entry.pluginID && RootSearchGate.searches($0.spec, preference: preference($0.key)) }
        default:
            return nil
        }
    }

    /// What the search field asks for while it searches inside `command`.
    public static func prompt(_ command: CommandRegistry.Entry) -> String {
        "Search \(command.pluginName)"
    }
}
