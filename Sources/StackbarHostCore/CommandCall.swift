import Foundation

/// `stackbarctl call`: one command for the running app to start, sent over
/// `StackbarPaths.commandSocket` as a line of JSON, answered with a `Reply`.
/// The app treats it like a `stackbar://commands/…` link: a run command
/// needs the user's "Links may run it" (it asks the first time), and a
/// view opens in the palette.
public struct CommandCall: Codable, Equatable, Sendable {
    /// A plugin id or its last part (`pr-cockpit`).
    public var plugin: String
    public var command: String
    public var arguments: [String: String]

    public init(plugin: String, command: String, arguments: [String: String] = [:]) {
        self.plugin = plugin
        self.command = command
        self.arguments = arguments
    }

    public struct Reply: Codable, Equatable, Sendable {
        public var message: String?
        public var isError: Bool

        public init(message: String?, isError: Bool) {
            self.message = message
            self.isError = isError
        }
    }

    /// The installed command the call names, by full plugin id or the
    /// id's last part.
    public func entry(in registry: CommandRegistry) -> CommandRegistry.Entry? {
        let wanted = plugin.lowercased()
        let entries = registry.entries.filter { $0.spec.id == command }
        return entries.first { $0.pluginID.lowercased() == wanted }
            ?? entries.first { $0.pluginID.split(separator: ".").last.map { $0.lowercased() == wanted } ?? false }
    }

    /// `--arg name=value` pairs from a command line.
    public static func arguments(from words: [String]) -> [String: String]? {
        var result: [String: String] = [:]
        var index = 0
        while index < words.count {
            if words[index] == "--arg" {
                guard index + 1 < words.count, let equals = words[index + 1].firstIndex(of: "=") else { return nil }
                let pair = words[index + 1]
                result[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }
}
