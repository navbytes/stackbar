import Foundation
import StackbarProtocol

/// Which plugin tools agents may use, as the user set them in Settings →
/// Agents. Saved in the data directory, so it survives plugin updates.
///
/// A tool is allowed unless the user turned it off, or the plugin marked it
/// `optIn` and the user hasn't turned it on. `stackbar_read` (a plugin's
/// panel as text) follows the same rule under the name `panel`, and is
/// opt-in for a plugin with any opt-in tool: a panel shows the same data.
public final class AgentConsent: @unchecked Sendable {
    /// The pseudo-tool that stands for reading a plugin's panel.
    public static let panel = "panel"

    private let file: URL?
    private let lock = NSLock()
    /// The user's choices by plugin id, then tool name.
    private var saved: [String: [String: Bool]] = [:]
    public var onChange: (@Sendable () -> Void)?

    public init(file: URL?) {
        self.file = file
        saved = JSONFile.read(from: file) ?? [:]
    }

    /// Whether agents may call `tool` of a plugin whose tools are `specs`.
    public func allows(pluginID: String, tool: String, specs: [ToolSpec]) -> Bool {
        if let choice = lock.withLock({ saved[pluginID]?[tool] }) { return choice }
        return !Self.isOptIn(tool, specs: specs)
    }

    /// What applies when the user hasn't chosen.
    public static func isOptIn(_ tool: String, specs: [ToolSpec]) -> Bool {
        if tool == panel { return specs.contains(where: \.optIn) }
        return specs.first { $0.name == tool }?.optIn ?? false
    }

    /// Records the user's choice; one that matches the default is forgotten,
    /// so a later change to the plugin's default still applies.
    public func set(_ allowed: Bool, pluginID: String, tool: String, specs: [ToolSpec]) {
        lock.withLock {
            var tools = saved[pluginID] ?? [:]
            tools[tool] = allowed == !Self.isOptIn(tool, specs: specs) ? nil : allowed
            saved[pluginID] = tools.isEmpty ? nil : tools
        }
        save()
        onChange?()
    }

    private func save() {
        guard let file else { return }
        try? JSONFile.write(lock.withLock { saved }, to: file)
    }
}
