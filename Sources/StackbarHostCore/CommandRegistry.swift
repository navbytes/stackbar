import Foundation
import StackbarProtocol

/// Names one command across all plugins: `dev.navbytes.pr-cockpit/search`.
public struct CommandKey: Hashable, Codable, Sendable, CustomStringConvertible, Comparable {
    public var pluginID: String
    public var commandID: String

    public init(pluginID: String, commandID: String) {
        self.pluginID = pluginID
        self.commandID = commandID
    }

    /// Parses `plugin-id/command-id`.
    public init?(_ text: String) {
        guard let slash = text.lastIndex(of: "/") else { return nil }
        let plugin = String(text[..<slash])
        let command = String(text[text.index(after: slash)...])
        guard !plugin.isEmpty, CommandSpec.isValidID(command) else { return nil }
        self.init(pluginID: plugin, commandID: command)
    }

    public var description: String { "\(pluginID)/\(commandID)" }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = CommandKey(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a command key: \(text)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func < (lhs: CommandKey, rhs: CommandKey) -> Bool { lhs.description < rhs.description }
}

/// Every installed plugin's last-known commands, saved to disk so they can
/// be searched, indexed, given aliases and hotkeys, and started while their
/// plugin is restarting or not yet running.
///
/// Thread-safe; `onChange` runs after every change that altered something.
public final class CommandRegistry: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var pluginID: String
        public var pluginName: String
        public var spec: CommandSpec

        public var key: CommandKey { CommandKey(pluginID: pluginID, commandID: spec.id) }

        public init(pluginID: String, pluginName: String, spec: CommandSpec) {
            self.pluginID = pluginID
            self.pluginName = pluginName
            self.spec = spec
        }
    }

    private struct Plugin: Codable {
        var name: String
        var commands: [CommandSpec]
    }

    private let file: URL?
    private let lock = NSLock()
    private var plugins: [String: Plugin] = [:]
    private var order: [String] = []
    public var onChange: (@Sendable () -> Void)?

    /// `file` nil keeps everything in memory (for tests and `stackbarctl`).
    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: Plugin].self, from: data) {
            plugins = saved
            order = saved.keys.sorted()
        }
    }

    /// The valid commands among `specs` and a line for each one dropped.
    public static func validate(_ specs: [CommandSpec]) -> (valid: [CommandSpec], problems: [String]) {
        var valid: [CommandSpec] = []
        var problems: [String] = []
        var seen = Set<String>()
        for spec in specs {
            let issues = spec.problems
            if !issues.isEmpty {
                problems += issues
            } else if !seen.insert(spec.id).inserted {
                problems.append("two commands use the id \(spec.id); the second is ignored")
            } else if valid.count >= CommandSpec.maxCommands {
                problems.append("more than \(CommandSpec.maxCommands) commands; the rest are ignored")
                break
            } else {
                valid.append(spec)
            }
        }
        return (valid, problems)
    }

    /// Replaces one plugin's commands. Returns the problems with dropped ones.
    @discardableResult
    public func update(pluginID: String, pluginName: String, specs: [CommandSpec]) -> [String] {
        let (valid, problems) = Self.validate(specs)
        let changed: Bool = lock.withLock {
            let next = Plugin(name: pluginName, commands: valid)
            if let current = plugins[pluginID], current.name == next.name, current.commands == next.commands { return false }
            if plugins[pluginID] == nil { order.append(pluginID) }
            plugins[pluginID] = next
            return true
        }
        if changed { save(); onChange?() }
        return problems
    }

    /// Keeps the plugins in the order the app lists them.
    public func setOrder(_ pluginIDs: [String]) {
        lock.withLock { order = pluginIDs + order.filter { !pluginIDs.contains($0) } }
    }

    /// Forgets a plugin (it was uninstalled).
    public func remove(pluginID: String) {
        let removed: Bool = lock.withLock {
            order.removeAll { $0 == pluginID }
            return plugins.removeValue(forKey: pluginID) != nil
        }
        if removed { save(); onChange?() }
    }

    /// Forgets every plugin not in `pluginIDs` (left over from an uninstall
    /// while the app was not running).
    public func retain(only pluginIDs: Set<String>) {
        let removed: Bool = lock.withLock {
            let gone = plugins.keys.filter { !pluginIDs.contains($0) }
            for id in gone { plugins[id] = nil }
            order.removeAll { !pluginIDs.contains($0) }
            return !gone.isEmpty
        }
        if removed { save(); onChange?() }
    }

    public var entries: [Entry] {
        lock.withLock {
            order.flatMap { id -> [Entry] in
                guard let plugin = plugins[id] else { return [] }
                return plugin.commands.map { Entry(pluginID: id, pluginName: plugin.name, spec: $0) }
            }
        }
    }

    public func entry(_ key: CommandKey) -> Entry? {
        lock.withLock {
            guard let plugin = plugins[key.pluginID], let spec = plugin.commands.first(where: { $0.id == key.commandID }) else { return nil }
            return Entry(pluginID: key.pluginID, pluginName: plugin.name, spec: spec)
        }
    }

    public func commands(for pluginID: String) -> [CommandSpec] {
        lock.withLock { plugins[pluginID]?.commands ?? [] }
    }

    private func save() {
        guard let file else { return }
        let snapshot = lock.withLock { plugins }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

extension CommandKey: CodingKeyRepresentable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public var codingKey: CodingKey { Key(stringValue: description) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(codingKey.stringValue)
    }
}
