import Foundation
import StackbarProtocol

/// The runtime MCP gateway: running plugins' `AgentTool`s, plus a way to read
/// any plugin's panel, offered to agents as one MCP server.
///
/// Tool names are `<plugin>__<tool>`, where `<plugin>` is the last part of the
/// plugin's id (`io.navbytes.stackbar.example.pr-cockpit` → `pr_cockpit`), so an agent can
/// ask "what's blocking my release?" across PR Cockpit's and CI's data at once.
public final class RuntimeTools: MCPToolProvider, Sendable {
    public typealias Directory = @Sendable () async -> [PluginSupervisor]

    private let directory: Directory

    public init(directory: @escaping Directory) {
        self.directory = directory
    }

    public func tools() async -> [MCPTool] {
        var result = [
            MCPTool(name: "stackbar_plugins", description: "List the running Stackbar plugins with their state, summary and tools."),
            MCPTool(name: "stackbar_read", description: "Read what a plugin's panel currently shows, as text.", properties: [
                "plugin": MCPTool.property("string", "Plugin id or short name, from stackbar_plugins"),
            ], required: ["plugin"]),
        ]
        for supervisor in await directory() {
            let prefix = Self.shortName(supervisor.manifest.id)
            for tool in await supervisor.tools {
                var properties: [String: JSONValue] = [:]
                for parameter in tool.parameters {
                    properties[parameter.name] = MCPTool.property(parameter.kind.rawValue, parameter.description)
                }
                result.append(MCPTool(
                    name: "\(prefix)__\(tool.name)",
                    description: "[\(supervisor.manifest.name)] \(tool.description)",
                    properties: properties,
                    required: tool.parameters.filter(\.required).map(\.name)
                ))
            }
        }
        return result
    }

    public func call(_ name: String, arguments: [String: JSONValue]) async -> MCPToolResult {
        let plugins = await directory()
        switch name {
        case "stackbar_plugins":
            var lines: [String] = []
            for supervisor in plugins {
                let manifest = supervisor.manifest
                let tools = await supervisor.tools.map(\.name)
                lines.append("\(Self.shortName(manifest.id)) — \(manifest.name) (\(manifest.id)), \(await supervisor.state)" + (manifest.summary.map { ": \($0)" } ?? ""))
                if !tools.isEmpty { lines.append("  tools: " + tools.map { "\(Self.shortName(manifest.id))__\($0)" }.joined(separator: ", ")) }
            }
            return .text(lines.isEmpty ? "No plugins are running." : lines.joined(separator: "\n"))
        case "stackbar_read":
            guard let wanted = arguments["plugin"]?.string, let supervisor = Self.find(wanted, in: plugins) else {
                return .text("no running plugin matches \(arguments["plugin"]?.string ?? "")", isError: true)
            }
            let views = await supervisor.views
            guard let node = views[.panel] ?? views[.window] ?? views[.menuBar] else { return .text("\(supervisor.manifest.name) has not rendered anything yet") }
            return .text(TreeTextRenderer.render(node, showActions: false))
        default:
            let parts = name.components(separatedBy: "__")
            guard parts.count == 2, let supervisor = Self.find(parts[0], in: plugins) else {
                return .text("unknown tool \(name); call stackbar_plugins to see what is available", isError: true)
            }
            let result = await supervisor.callTool(parts[1], arguments: arguments.compactMapValues(\.eventValue))
            return .text(result.text, isError: result.isError)
        }
    }

    static func shortName(_ id: String) -> String {
        String(id.split(separator: ".").last ?? Substring(id)).replacingOccurrences(of: "-", with: "_")
    }

    static func find(_ name: String, in plugins: [PluginSupervisor]) -> PluginSupervisor? {
        plugins.first { $0.manifest.id == name } ?? plugins.first { shortName($0.manifest.id) == name }
    }
}
