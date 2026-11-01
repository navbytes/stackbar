import Foundation
import StackbarProtocol

/// The authoring MCP server's tools: everything an agent needs to write a
/// plugin without a person in the loop. Write, build, read the diagnostics,
/// render, press things, read the logs, repeat.
///
/// Plugins stay running between calls (one session per file), so an event
/// followed by a render shows the new state. Rendering a file whose source
/// changed rebuilds and restarts it.
public final class AuthoringTools: MCPToolProvider, @unchecked Sendable {
    /// Draws a surface; the closure it gets loads the remote images the
    /// tree names, fetched beforehand.
    public typealias PNGRenderer = @Sendable (ViewNode, Surface, @escaping @Sendable (String) -> Data?) async -> Data?

    private let loader: PluginLoader
    private let services: HostServices
    private let png: PNGRenderer?
    private let lock = NSLock()
    private var sessions: [String: PluginSession] = [:]
    /// The command view each file has open, so events inside it render it.
    private var openViews: [String: Int] = [:]

    public init(loader: PluginLoader, services: HostServices, png: PNGRenderer? = nil) {
        self.loader = loader
        self.services = services
        self.png = png
    }

    public func tools() async -> [MCPTool] {
        let path = MCPTool.property("string", "Path to the plugin's .swift file")
        let surface = MCPTool.property("string", "Which surface", enumValues: Surface.allCases.map(\.rawValue))
        var formats = ["text", "json"]
        if png != nil { formats.append("png") }
        return [
            MCPTool(name: "stackbar_docs", description: "The Stackbar plugin authoring reference: plugin shape, every view, host services and capabilities. Read it before writing a plugin."),
            MCPTool(name: "stackbar_new", description: "Create a new plugin file from the template. Fails if the file exists.", properties: [
                "path": path, "name": MCPTool.property("string", "Display name, e.g. \"PR Cockpit\""), "id": MCPTool.property("string", "Reverse-DNS id (optional)"),
            ], required: ["path", "name"]),
            MCPTool(name: "stackbar_build", description: "Compile a plugin. Returns compiler diagnostics (file:line:col: error: ...) or the manifest summary.", properties: ["path": path], required: ["path"]),
            MCPTool(name: "stackbar_render", description: "Build if needed, run the plugin, and show what a surface draws. Text output lists the action id of every control in {braces}.", properties: [
                "path": path, "surface": surface, "format": MCPTool.property("string", "Output format", enumValues: formats),
            ], required: ["path"]),
            MCPTool(name: "stackbar_send_event", description: "Press a control by action id (from stackbar_render), then return the new panel and menu bar. Fields take value as text, toggles true/false, sliders a number.", properties: [
                "path": path, "action": MCPTool.property("string", "Action id, e.g. button/Refresh"), "value": MCPTool.property("string", "Optional value"),
            ], required: ["path", "action"]),
            MCPTool(name: "stackbar_refresh", description: "Run the plugin's refresh() now and return the new render.", properties: ["path": path], required: ["path"]),
            MCPTool(name: "stackbar_call_tool", description: "Call one of the plugin's agent tools.", properties: [
                "path": path, "name": MCPTool.property("string", "Tool name"), "arguments": MCPTool.property("object", "Tool arguments"),
            ], required: ["path", "name"]),
            MCPTool(name: "stackbar_simulate_copy", description: "Pretend the user copied text in another app (the simulated clipboard), fire the plugin's clipboard trigger, and return the new render. For plugins with the .clipboard trigger.", properties: [
                "path": path, "text": MCPTool.property("string", "What was copied"), "app": MCPTool.property("string", "The app it was copied from (default Safari)"),
                "concealed": MCPTool.property("boolean", "Marked as a password by the copying app"),
            ], required: ["path", "text"]),
            MCPTool(name: "stackbar_list_commands", description: "List the plugin's commands: id, run or view, title and arguments.", properties: ["path": path], required: ["path"]),
            MCPTool(name: "stackbar_run_command", description: "Run one of the plugin's run commands and return its result (message, open, copy, paste or failure).", properties: [
                "path": path, "command": MCPTool.property("string", "Command id"), "arguments": MCPTool.property("object", "Argument values by name"),
                "selected_text": MCPTool.property("string", "Pretend this text is selected in the user's app (plugins with .context)"),
                "frontmost_app": MCPTool.property("string", "Pretend this app is frontmost, as bundle id or name (default Safari)"),
            ], required: ["path", "command"]),
            MCPTool(name: "stackbar_render_command", description: "Open one of the plugin's view commands with a query and show its view, with action ids in {braces}. stackbar_send_event then presses things inside it; submit a form with value as an object of field values.", properties: [
                "path": path, "command": MCPTool.property("string", "Command id"), "query": MCPTool.property("string", "What the user typed (default empty)"),
                "arguments": MCPTool.property("object", "Argument values by name"), "format": MCPTool.property("string", "Output format", enumValues: ["text", "json"]),
                "selected_text": MCPTool.property("string", "Pretend this text is selected in the user's app (plugins with .context)"),
                "frontmost_app": MCPTool.property("string", "Pretend this app is frontmost, as bundle id or name (default Safari)"),
            ], required: ["path", "command"]),
            MCPTool(name: "stackbar_logs", description: "Recent log lines from the plugin: its errors, warnings and stray prints.", properties: [
                "path": path, "lines": MCPTool.property("number", "How many (default 50)"),
            ], required: ["path"]),
            MCPTool(name: "stackbar_stop", description: "Stop a running plugin.", properties: ["path": path], required: ["path"]),
        ]
    }

    public func call(_ name: String, arguments: [String: JSONValue]) async -> MCPToolResult {
        if name == "stackbar_docs" { return .text(AuthoringGuide.text) }
        guard let path = arguments["path"]?.string, !path.isEmpty else { return .text("path is required", isError: true) }
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
        do {
            switch name {
            case "stackbar_new":
                return try create(url, name: arguments["name"]?.string ?? url.deletingPathExtension().lastPathComponent, id: arguments["id"]?.string)
            case "stackbar_build":
                return try await build(url)
            case "stackbar_render":
                let session = session(for: url)
                try await session.ensureRunning()
                let surface = arguments["surface"]?.string.flatMap(Surface.init(rawValue:))
                return await render(session, surfaces: surface.map { [$0] } ?? [.menuBar, .panel], format: arguments["format"]?.string ?? "text")
            case "stackbar_send_event":
                guard let action = arguments["action"]?.string else { return .text("action is required", isError: true) }
                let session = session(for: url)
                if await !session.isRunning { try await session.ensureRunning() }
                try await session.event(ActionID(action), value: Self.eventValue(arguments["value"], for: action))
                if let open = lock.withLock({ openViews[url.path] }), action.hasPrefix("view/\(open)/") {
                    return await renderCommandView(session, open, format: "text")
                }
                return await render(session, surfaces: [.menuBar, .panel], format: "text")
            case "stackbar_refresh":
                let session = session(for: url)
                try await session.ensureRunning()
                try await session.refresh()
                return await render(session, surfaces: [.menuBar, .panel], format: "text")
            case "stackbar_call_tool":
                guard let tool = arguments["name"]?.string else { return .text("name is required", isError: true) }
                let session = session(for: url)
                try await session.ensureRunning()
                let toolArguments = (arguments["arguments"]?.object ?? [:]).compactMapValues(\.eventValue)
                let result = try await session.callTool(tool, arguments: toolArguments)
                return .text(result.text, isError: result.isError)
            case "stackbar_simulate_copy":
                guard let system = services.platform.system as? SimulatedSystem else { return .text("the clipboard is only simulated in stackbarctl", isError: true) }
                let session = session(for: url)
                try await session.ensureRunning()
                let app = arguments["app"]?.string ?? "Safari"
                system.simulateCopy(arguments["text"]?.string ?? "", app: SystemStatus.App(id: "app.\(app.lowercased().filter(\.isLetter))", name: app), concealed: arguments["concealed"]?.bool ?? false)
                try await session.trigger(.clipboard)
                return await render(session, surfaces: [.menuBar, .panel], format: "text")
            case "stackbar_list_commands":
                let session = session(for: url)
                try await session.ensureRunning()
                let commands = await session.commands()
                return .text(commands.isEmpty ? "(no commands; add a `var commands: [Command]` to the plugin)" : commands.map(Self.describe).joined(separator: "\n"))
            case "stackbar_run_command":
                guard let command = arguments["command"]?.string else { return .text("command is required", isError: true) }
                let session = session(for: url)
                try await session.ensureRunning()
                let result = try await session.runCommand(command, arguments: Self.strings(arguments["arguments"]), context: await context(arguments))
                return Self.describe(result)
            case "stackbar_render_command":
                guard let command = arguments["command"]?.string else { return .text("command is required", isError: true) }
                let session = session(for: url)
                try await session.ensureRunning()
                if let previous = lock.withLock({ openViews[url.path] }) { await session.closeView(previous) }
                let query = CommandQuery(text: arguments["query"]?.string ?? "", arguments: Self.strings(arguments["arguments"]))
                let opened = try await session.openView(command, query: query, context: await context(arguments))
                lock.withLock { openViews[url.path] = opened.session }
                return await renderCommandView(session, opened.session, format: arguments["format"]?.string ?? "text")
            case "stackbar_logs":
                let count = Int(arguments["lines"]?.number ?? 50)
                let logs = await existing(url)?.logs(last: count) ?? []
                return .text(logs.isEmpty ? "(no log lines; is the plugin running? use stackbar_render first)" : logs.joined(separator: "\n"))
            case "stackbar_stop":
                await existing(url)?.stop()
                lock.withLock {
                    sessions[url.path] = nil
                    openViews[url.path] = nil
                }
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
        return .text("Created \(url.path). Edit it, then call stackbar_build.")
    }

    private func build(_ url: URL) async throws -> MCPToolResult {
        guard url.pathExtension == "swift" else { return .text("the path must end in .swift", isError: true) }
        let loader = loader
        let output = try await Task.detached { try loader.helper(for: url) }.value
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
            let manifest = await session.manifest
            let images = services.images
            for surface in wanted {
                guard let node = views[surface] else { continue }
                if let manifest { await images.load(node, pluginID: manifest.id, allowedHosts: manifest.networkHosts) }
                guard let data = await png(node, surface, { images.data(for: $0) }) else { continue }
                content.append(.text(surface.rawValue))
                content.append(.image(data, mimeType: "image/png"))
            }
            return content.isEmpty ? .text("nothing rendered", isError: true) : MCPToolResult(content)
        default:
            var text = wanted.map { surface in
                "== \(surface.rawValue) ==\n" + (views[surface].map { TreeTextRenderer.render($0) } ?? "(nothing rendered)")
            }.joined(separator: "\n")
            if wanted.contains(.menuBar), let click = await session.menuBarClick() {
                text += "\n(click: \(click.title) {\(click.action)})"
            }
            let commands = await session.commands()
            if !commands.isEmpty { text += "\n== commands ==\n" + commands.map(Self.describe).joined(separator: "\n") }
            let tools = await session.tools()
            if !tools.isEmpty { text += "\n== tools ==\n" + tools.map { "\($0.name): \($0.description)" }.joined(separator: "\n") }
            text += await Self.problems(session, views: wanted.compactMap { views[$0] })
            return .text(text)
        }
    }

    private func renderCommandView(_ session: PluginSession, _ id: Int, format: String) async -> MCPToolResult {
        guard let root = await session.commandView(id) else {
            let problems = await session.logs(last: 10).filter { $0.hasPrefix("[error]") || $0.hasPrefix("[warning]") }
            return .text("the view did not render" + (problems.isEmpty ? "" : ":\n" + problems.joined(separator: "\n")), isError: true)
        }
        if format == "json" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return .text((try? encoder.encode(root)).map { String(decoding: $0, as: UTF8.self) } ?? "{}")
        }
        let text = "== command view ==\n" + TreeTextRenderer.render(root) + (await Self.problems(session, views: [root]))
        return .text(text)
    }

    /// Style warnings for the rendered views and the plugin's recent errors,
    /// as sections to append to a text render.
    private static func problems(_ session: PluginSession, views: [ViewNode]) async -> String {
        var text = ""
        let style = views.flatMap(StyleLint.warnings)
        if !style.isEmpty { text += "\n== style problems ==\n" + style.joined(separator: "\n") }
        let warnings = await session.logs(last: 10).filter { $0.hasPrefix("[error]") || $0.hasPrefix("[warning]") }
        if !warnings.isEmpty { text += "\n== recent problems ==\n" + warnings.joined(separator: "\n") }
        return text
    }

    static func describe(_ spec: CommandSpec) -> String {
        var line = "\(spec.id) (\(spec.kind.rawValue)): \(spec.title)"
        if let subtitle = spec.subtitle { line += " - \(subtitle)" }
        if !spec.arguments.isEmpty {
            line += " [" + spec.arguments.map { argument in
                var text = argument.name
                if !argument.required || argument.defaultValue != nil { text += "?" }
                if let options = argument.options { text += " one of " + options.joined(separator: "|") }
                if let value = argument.defaultValue { text += " = \(value)" }
                return text
            }.joined(separator: ", ") + "]"
        }
        if !spec.keywords.isEmpty { line += " keywords: " + spec.keywords.joined(separator: ", ") }
        if spec.exposure == .stackbarOnly { line += " (Stackbar only)" }
        return line
    }

    static func describe(_ result: CommandResult) -> MCPToolResult {
        switch result {
        case .message(let message): return .text("message: " + (message ?? "(none)"))
        case .open(let url, let app): return .text("open: \(url)" + (app.map { " with \($0)" } ?? ""))
        case .copy(let text): return .text("copy: \(text)")
        case .paste(let text, let cursor): return .text("paste: \(text)" + (cursor > 0 ? " (cursor \(cursor) from the end)" : ""))
        case .failure(let message): return .text("failure: \(message)", isError: true)
        }
    }

    /// What the user is in for a command: the simulated system's context,
    /// with the tool call's `selected_text` and `frontmost_app` on top. The
    /// supervisor passes it on only to plugins granted `.context`.
    func context(_ arguments: [String: JSONValue]) async -> InvocationContext {
        var context = await services.platform.system.context()
        if let text = arguments["selected_text"]?.string { context.selectedText = InvocationContext.capped(text) }
        if let app = arguments["frontmost_app"]?.string, !app.isEmpty {
            context.frontmostApp = app.contains(".") ? .init(bundleID: app, name: app.split(separator: ".").last.map(String.init) ?? app) : .init(bundleID: "", name: app)
        }
        return context
    }

    static func strings(_ value: JSONValue?) -> [String: String] {
        (value?.object ?? [:]).compactMapValues { value in
            switch value {
            case .string(let text): return text
            case .number(let number): return number.rounded() == number ? String(Int(number)) : String(number)
            case .bool(let flag): return String(flag)
            case .null, .array, .object: return nil
            }
        }
    }

    private func session(for url: URL) -> PluginSession {
        lock.withLock {
            if let session = sessions[url.path] { return session }
            let session = PluginSession(source: url, loader: loader, services: services)
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
        case .object: return value.eventValue
        case .null, .array: return nil
        }
    }
}
