import Foundation
import FluidProtocol

/// The authoring MCP server's tools: everything an agent needs to write a
/// plugin without a person in the loop. Write, build, read the diagnostics,
/// render, press things, read the logs, repeat.
///
/// Plugins stay running between calls (one session per file), so an event
/// followed by a render shows the new state. Rendering a file whose source
/// changed rebuilds and restarts it.
public final class AuthoringTools: MCPToolProvider, @unchecked Sendable {
    public typealias PNGRenderer = @Sendable (ViewNode, Surface) async -> Data?

    private let builder: PluginBuilder
    private let services: HostServices
    private let png: PNGRenderer?
    private let lock = NSLock()
    private var sessions: [String: PluginSession] = [:]

    public init(builder: PluginBuilder, services: HostServices, png: PNGRenderer? = nil) {
        self.builder = builder
        self.services = services
        self.png = png
    }

    public func tools() async -> [MCPTool] {
        let path = MCPTool.property("string", "Path to the plugin's .swift file")
        let surface = MCPTool.property("string", "Which surface", enumValues: Surface.allCases.map(\.rawValue))
        var formats = ["text", "json"]
        if png != nil { formats.append("png") }
        return [
            MCPTool(name: "fluid_docs", description: "The Fluid plugin authoring reference: plugin shape, every view, host services and capabilities. Read it before writing a plugin."),
            MCPTool(name: "fluid_new", description: "Create a new plugin file from the template. Fails if the file exists.", properties: [
                "path": path, "name": MCPTool.property("string", "Display name, e.g. \"PR Cockpit\""), "id": MCPTool.property("string", "Reverse-DNS id (optional)"),
            ], required: ["path", "name"]),
            MCPTool(name: "fluid_build", description: "Compile a plugin. Returns compiler diagnostics (file:line:col: error: ...) or the manifest summary.", properties: ["path": path], required: ["path"]),
            MCPTool(name: "fluid_render", description: "Build if needed, run the plugin, and show what a surface draws. Text output lists the action id of every control in {braces}.", properties: [
                "path": path, "surface": surface, "format": MCPTool.property("string", "Output format", enumValues: formats),
            ], required: ["path"]),
            MCPTool(name: "fluid_send_event", description: "Press a control by action id (from fluid_render), then return the new panel and menu bar. Fields take value as text, toggles true/false, sliders a number.", properties: [
                "path": path, "action": MCPTool.property("string", "Action id, e.g. button/Refresh"), "value": MCPTool.property("string", "Optional value"),
            ], required: ["path", "action"]),
            MCPTool(name: "fluid_refresh", description: "Run the plugin's refresh() now and return the new render.", properties: ["path": path], required: ["path"]),
            MCPTool(name: "fluid_call_tool", description: "Call one of the plugin's agent tools.", properties: [
                "path": path, "name": MCPTool.property("string", "Tool name"), "arguments": MCPTool.property("object", "Tool arguments"),
            ], required: ["path", "name"]),
            MCPTool(name: "fluid_simulate_copy", description: "Pretend the user copied text in another app (the simulated clipboard), fire the plugin's clipboard trigger, and return the new render. For plugins with the .clipboard trigger.", properties: [
                "path": path, "text": MCPTool.property("string", "What was copied"), "app": MCPTool.property("string", "The app it was copied from (default Safari)"),
                "concealed": MCPTool.property("boolean", "Marked as a password by the copying app"),
            ], required: ["path", "text"]),
            MCPTool(name: "fluid_logs", description: "Recent log lines from the plugin: its errors, warnings and stray prints.", properties: [
                "path": path, "lines": MCPTool.property("number", "How many (default 50)"),
            ], required: ["path"]),
            MCPTool(name: "fluid_stop", description: "Stop a running plugin.", properties: ["path": path], required: ["path"]),
        ]
    }

    public func call(_ name: String, arguments: [String: JSONValue]) async -> MCPToolResult {
        if name == "fluid_docs" { return .text(AuthoringGuide.text) }
        guard let path = arguments["path"]?.string, !path.isEmpty else { return .text("path is required", isError: true) }
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
        do {
            switch name {
            case "fluid_new":
                return try create(url, name: arguments["name"]?.string ?? url.deletingPathExtension().lastPathComponent, id: arguments["id"]?.string)
            case "fluid_build":
                return try await build(url)
            case "fluid_render":
                let session = session(for: url)
                try await session.ensureRunning()
                let surface = arguments["surface"]?.string.flatMap(Surface.init(rawValue:))
                return await render(session, surfaces: surface.map { [$0] } ?? [.menuBar, .panel], format: arguments["format"]?.string ?? "text")
            case "fluid_send_event":
                guard let action = arguments["action"]?.string else { return .text("action is required", isError: true) }
                let session = session(for: url)
                if await !session.isRunning { try await session.ensureRunning() }
                try await session.event(ActionID(action), value: Self.eventValue(arguments["value"], for: action))
                return await render(session, surfaces: [.menuBar, .panel], format: "text")
            case "fluid_refresh":
                let session = session(for: url)
                try await session.ensureRunning()
                try await session.refresh()
                return await render(session, surfaces: [.menuBar, .panel], format: "text")
            case "fluid_call_tool":
                guard let tool = arguments["name"]?.string else { return .text("name is required", isError: true) }
                let session = session(for: url)
                try await session.ensureRunning()
                let toolArguments = (arguments["arguments"]?.object ?? [:]).compactMapValues(\.eventValue)
                let result = try await session.callTool(tool, arguments: toolArguments)
                return .text(result.text, isError: result.isError)
            case "fluid_simulate_copy":
                guard let system = services.platform.system as? SimulatedSystem else { return .text("the clipboard is only simulated in fluidctl", isError: true) }
                let session = session(for: url)
                try await session.ensureRunning()
                let app = arguments["app"]?.string ?? "Safari"
                system.simulateCopy(arguments["text"]?.string ?? "", app: SystemStatus.App(id: "app.\(app.lowercased().filter(\.isLetter))", name: app), concealed: arguments["concealed"]?.bool ?? false)
                try await session.trigger(.clipboard)
                return await render(session, surfaces: [.menuBar, .panel], format: "text")
            case "fluid_logs":
                let count = Int(arguments["lines"]?.number ?? 50)
                let logs = await existing(url)?.logs(last: count) ?? []
                return .text(logs.isEmpty ? "(no log lines; is the plugin running? use fluid_render first)" : logs.joined(separator: "\n"))
            case "fluid_stop":
                await existing(url)?.stop()
                lock.withLock { sessions[url.path] = nil }
                return .text("stopped")
            default:
                return .text("unknown tool \(name)", isError: true)
            }
        } catch let failure as PluginBuilder.Failure {
            return .text("Build failed:\n" + failure.description, isError: true)
        } catch {
            return .text("\(error)", isError: true)
        }
    }

    /// Stops every running plugin (when the server shuts down).
    public func stopAll() async {
        let all = lock.withLock { Array(sessions.values) }
        for session in all { await session.stop() }
    }

    private func create(_ url: URL, name: String, id: String?) throws -> MCPToolResult {
        guard url.pathExtension == "swift" else { return .text("the path must end in .swift", isError: true) }
        guard !FileManager.default.fileExists(atPath: url.path) else { return .text("\(url.path) already exists", isError: true) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PluginTemplate.source(name: name, id: id).write(to: url, atomically: true, encoding: .utf8)
        return .text("Created \(url.path). Edit it, then call fluid_build.")
    }

    private func build(_ url: URL) async throws -> MCPToolResult {
        let builder = builder
        let output = try await Task.detached { try builder.build(source: url) }.value
        let manifest = try PluginProcess.readManifest(executable: output.binary)
        var lines = ["Built \(manifest.name) \(manifest.version) (\(manifest.id))" + (output.cached ? ", unchanged since the last build" : "")]
        lines.append("surfaces: " + manifest.surfaces.map(\.rawValue).joined(separator: ", "))
        lines += SandboxEntitlements.summary(for: manifest).map { "- " + $0 }
        let problems = manifest.problems
        if !problems.isEmpty { lines.append("Manifest problems:\n- " + problems.joined(separator: "\n- ")) }
        return .text(lines.joined(separator: "\n"), isError: !problems.isEmpty)
    }

    private func render(_ session: PluginSession, surfaces: [Surface], format: String) async -> MCPToolResult {
        let views = await session.views()
        let declared = await session.manifest?.surfaces ?? []
        let wanted = surfaces.filter(declared.contains)
        switch format {
        case "json":
            let byName = Dictionary(uniqueKeysWithValues: wanted.compactMap { surface in views[surface].map { (surface.rawValue, $0) } })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return .text((try? encoder.encode(byName)).map { String(decoding: $0, as: UTF8.self) } ?? "{}")
        case "png":
            guard let png else { return .text("PNG rendering needs macOS", isError: true) }
            var content: [MCPToolResult.Content] = []
            for surface in wanted {
                guard let node = views[surface], let data = await png(node, surface) else { continue }
                content.append(.text(surface.rawValue))
                content.append(.image(data, mimeType: "image/png"))
            }
            return content.isEmpty ? .text("nothing rendered", isError: true) : MCPToolResult(content)
        default:
            var text = wanted.map { surface in
                "== \(surface.rawValue) ==\n" + (views[surface].map { TreeTextRenderer.render($0) } ?? "(nothing rendered)")
            }.joined(separator: "\n")
            let tools = await session.tools()
            if !tools.isEmpty { text += "\n== tools ==\n" + tools.map { "\($0.name): \($0.description)" }.joined(separator: "\n") }
            let warnings = await session.logs(last: 10).filter { $0.hasPrefix("[error]") || $0.hasPrefix("[warning]") }
            if !warnings.isEmpty { text += "\n== recent problems ==\n" + warnings.joined(separator: "\n") }
            return .text(text)
        }
    }

    private func session(for url: URL) -> PluginSession {
        lock.withLock {
            if let session = sessions[url.path] { return session }
            let session = PluginSession(source: url, builder: builder, services: services)
            sessions[url.path] = session
            return session
        }
    }

    private func existing(_ url: URL) -> PluginSession? {
        lock.withLock { sessions[url.path] }
    }

    /// The value an action expects, from whatever JSON the agent sent: a
    /// number for sliders, a Bool for toggles, text for everything else.
    static func eventValue(_ value: JSONValue?, for action: String) -> EventValue? {
        guard let value else { return nil }
        if action.hasPrefix("slider/") {
            return value.number.map(EventValue.number) ?? value.string.flatMap(Double.init).map(EventValue.number)
        }
        if action.hasPrefix("toggle/") {
            return value.bool.map(EventValue.bool) ?? value.string.flatMap(Bool.init).map(EventValue.bool)
        }
        switch value {
        case .string(let text): return .text(text)
        case .number(let number): return .text(number.rounded() == number ? String(Int(number)) : String(number))
        case .bool(let flag): return .text(String(flag))
        case .null, .array, .object: return nil
        }
    }
}
