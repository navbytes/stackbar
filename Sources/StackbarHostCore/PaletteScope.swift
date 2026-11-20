import Foundation
import StackbarProtocol

/// Searching inside one plugin from the palette, as Spotlight on macOS 26
/// searches inside an app: type the plugin's name, press Tab, and what you
/// type next goes only to that plugin, under a chip with its name. Esc, or
/// Delete in the empty field, leaves.
///
/// Tab enters only from a row that stands for the plugin's search: its root
/// search command, or its "Open" row when it has one. Any other command that
/// opens something of its own, a view (Search Pull Requests) or argument
/// fields, Tab opens, as Return does. From any other row Tab still hands the
/// text to Ask AI (`PaletteTabTarget`).
public enum PaletteScope {
    /// What Tab does on a row of the main search.
    public enum Tab: Equatable, Sendable {
        /// Searches inside the plugin, under a chip with its name.
        case search(CommandRegistry.Entry)
        /// Opens the command: its view, with its own search field, or its
        /// argument fields.
        case open(CommandRegistry.Entry)
    }

    /// What Tab on `entry` does, or nil to leave Tab to the fallback.
    public static func tab(on entry: PaletteIndex.Entry, commands: [CommandRegistry.Entry],
                           preference: (CommandKey) -> CommandPreference) -> Tab? {
        if let command = target(of: entry, commands: commands, preference: preference) { return .search(command) }
        guard case .command = entry.kind, let key = entry.commandKey, preference(key).enabled,
              let command = commands.first(where: { $0.key == key }) else { return nil }
        // A run command with nothing to fill in just runs: that is Return's.
        guard command.spec.kind == .view || !command.spec.arguments.isEmpty else { return nil }
        return .open(command)
    }

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
