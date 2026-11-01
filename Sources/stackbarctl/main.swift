import Foundation
import StackbarHostCore
import StackbarProtocol
#if canImport(StackbarUI) && os(macOS)
import StackbarUI
#endif

// stackbarctl — build, inspect and drive Stackbar plugins without the app, and serve
// them to agents over MCP.

let usage = """
usage:
  stackbarctl new <plugin.swift> [--name "Display Name"] [--id dev.example.x]
  stackbarctl build <plugin.swift>
  stackbarctl manifest <plugin.swift | helper>
  stackbarctl render <plugin.swift | helper> [--surface menuBar|panel|window|widget]
                  [--event <action-id>[=value]]... [--tool name[:json]] [--copy <text>]...
                  [--json] [--png <dir> [--dark]] [--verbose]
                  [--command <id> [--query <text>] [--arg name=value]...]
                  --command opens a view command; --event then presses things inside it
                  --copy pretends you copied text in another app (clipboard plugins);
                  the clipboard, battery and calendar are simulated (STACKBAR_CALENDAR=<events.json>)
  stackbarctl commands <plugin.swift | helper>        lists the plugin's commands
  stackbarctl run <plugin.swift | helper> <command> [--arg name=value]...
                                    runs a command and prints its result
                  render and run take --selected-text <text> and --frontmost-app <bundle id>
                  for plugins with .context (or STACKBAR_CONTEXT=<json>)
  stackbarctl mcp                      authoring MCP server on stdio (for coding agents)
  stackbarctl agent [<plugin>...]      runtime MCP gateway on stdio: bridges to the running
                                    app, or runs the given plugins itself when it isn't
  stackbarctl secret set|get|delete <NAME> [value]
  stackbarctl keygen [--key <file>]                   an Ed25519 publisher key (macOS)
  stackbarctl sign <plugin.swift> --publisher <name> [--key <file>] [-o <out.stackbarplugin>]
  stackbarctl verify <bundle.stackbarplugin>
  stackbarctl install <bundle.stackbarplugin | https://…> | --index <url> <plugin-id>
  stackbarctl index build <dir> [--name <name>] [--homepage <url>] [--revoked <file.json>] [--key <file>]
                                    writes <dir>/index.json from every bundle under <dir>;
                                    a subfolder is the category; --key signs it (macOS)
  stackbarctl index verify <index.json | https://…> --public-key <base64>
  stackbarctl index search <url> [query] [--public-key <base64>]
  stackbarctl index fetch <dir> [--index <url>] [--public-key <base64>]
                                    downloads the first-party plugins' signed bundles
                                    (the official store by default) for the app to carry
  stackbarctl docs                     the plugin authoring reference
  stackbarctl parity                   the surface parity ledger
  stackbarctl soak <plugin> [--minutes 10] [--interval 1] [--press] [--growth 15]
                                    runs a plugin under load and fails if its memory grows
  stackbarctl logs [-n <lines>]        the end of the host log (the app's and stackbarctl's)
  stackbarctl doctor                   checks the toolchain, StackbarKit and data directories
  stackbarctl version

A .swift path is built first (cached by content); anything else is run as an
already-built helper. On macOS, render, commands, run, mcp, agent and soak run
plugins in the App Sandbox their manifest allows, as the app does; --no-sandbox
runs them unsigned. STACKBAR_PACKAGE overrides where StackbarKit is found, and
STACKBAR_HOME where Stackbar keeps its data.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Plugins run in the App Sandbox, as the app runs them, unless
/// `--no-sandbox`. Only macOS has a sandbox to sign them into.
#if os(macOS)
let sandbox = !CommandLine.arguments.contains("--no-sandbox")
#else
let sandbox = false
#endif
let loader = PluginLoader(builder: PluginBuilder(stackbarPackage: StackbarPaths.stackbarPackage(), cacheRoot: StackbarPaths.buildCache), sandbox: sandbox)

/// stackbarctl runs plugins against a simulated clipboard, battery and calendar
/// (`STACKBAR_CALENDAR` points at a JSON file of events; otherwise a sample day).
let simulatedSystem = SimulatedSystem.fromEnvironment()

/// `--selected-text` and `--frontmost-app`: what the user is in, for
/// plugins granted `.context`.
func simulateContext(_ flag: String, _ value: String) {
    var context = simulatedSystem.currentContext
    if flag == "--selected-text" {
        context.selectedText = value
    } else {
        context.frontmostApp = value.contains(".") ? .init(bundleID: value, name: value.split(separator: ".").last.map(String.init) ?? value) : .init(bundleID: "", name: value)
    }
    simulatedSystem.simulate(context: context)
}

func makeServices() -> HostServices {
    HostServices(
        storage: StorageStore(directory: StackbarPaths.storageDirectory),
        secrets: StackbarPaths.defaultSecrets(),
        platform: .init(
            notify: { posted in
                let buttons = posted.actions.isEmpty ? "" : " [" + posted.actions.map { "\($0.title) → \($0.url)" }.joined(separator: ", ") + "]"
                note("[notify] \(posted.pluginName): \(posted.title)" + (posted.body.map { " — \($0)" } ?? "") + buttons)
            },
            alert: { posted in note("[alert] \(posted.pluginName): \(posted.title)" + (posted.body.map { " — \($0)" } ?? "") + " [" + posted.actions.map(\.title).joined(separator: ", ") + "]") },
            playSound: { sound in note("[sound] \(sound.rawValue)") },
            open: { url in note("[open] \(url.absoluteString)") },
            copy: { text in note("[copy] \(text.prefix(200))") },
            secretMissing: { _, name in note("[secret] \(name) is not set; run: stackbarctl secret set \(name) <value>") },
            system: simulatedSystem
        )
    )
}

func pngRenderer(dark: Bool = false) -> AuthoringTools.PNGRenderer? {
    #if canImport(StackbarUI) && os(macOS)
    return { node, surface in await MainActor.run { Snapshot.png(node, surface: surface, dark: dark) } }
    #else
    return nil
    #endif
}

func helper(for path: String) -> URL {
    do {
        let output = try loader.helper(for: URL(fileURLWithPath: path))
        if !output.cached { note("built \(output.binary.path)") }
        return output.binary
    } catch let failure as PluginBuilder.Failure {
        fail(failure.description)
    } catch {
        fail("build failed: \(error)")
    }
}

/// A plugin ready to supervise: built, checked and sandboxed like the app's.
func load(_ path: String) -> LoadedPlugin {
    do {
        return try loader.load(helper(for: path))
    } catch {
        fail("\(path): \(error)")
    }
}

func value(after flag: String, in options: [String], at index: inout Int) -> String {
    index += 1
    guard index < options.count else { fail("\(flag) needs a value\n\n\(usage)") }
    return options[index]
}

func render(_ path: String, options: [String]) async {
    var surfaces: [Surface] = [.menuBar, .panel]
    var steps: [(kind: String, name: String, value: String?)] = []
    var asJSON = false
    var pngDirectory: String?
    var dark = false
    var verbose = false
    var command: String?
    var query = ""
    var commandArguments: [String: JSONValue] = [:]
    var index = 0
    while index < options.count {
        switch options[index] {
        case "--surface":
            let name = value(after: "--surface", in: options, at: &index)
            guard let surface = Surface(rawValue: name) else { fail("unknown surface \(name)") }
            surfaces = [surface]
        case "--event":
            let spec = value(after: "--event", in: options, at: &index)
            let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
            steps.append(("event", parts[0], parts.count > 1 ? parts[1] : nil))
        case "--tool":
            let spec = value(after: "--tool", in: options, at: &index)
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            steps.append(("tool", parts[0], parts.count > 1 ? parts[1] : nil))
        case "--copy":
            steps.append(("copy", value(after: "--copy", in: options, at: &index), nil))
        case "--json": asJSON = true
        case "--png": pngDirectory = value(after: "--png", in: options, at: &index)
        case "--dark": dark = true
        case "--verbose": verbose = true
        case "--command": command = value(after: "--command", in: options, at: &index)
        case "--query": query = value(after: "--query", in: options, at: &index)
        case "--selected-text", "--frontmost-app":
            simulateContext(options[index], value(after: options[index], in: options, at: &index))
        case "--arg":
            let parts = value(after: "--arg", in: options, at: &index).split(separator: "=", maxSplits: 1).map(String.init)
            commandArguments[parts[0]] = .string(parts.count > 1 ? parts[1] : "")
        default: fail(usage)
        }
        index += 1
    }

    let tools = AuthoringTools(loader: loader, services: makeServices(), png: pngRenderer(dark: dark))
    func run(_ name: String, _ arguments: [String: JSONValue]) async -> MCPToolResult {
        var arguments = arguments
        arguments["path"] = .string(path)
        let result = await tools.call(name, arguments: arguments)
        if result.isError {
            if verbose, case .text(let logs) = await tools.call("stackbar_logs", arguments: ["path": .string(path)]).content.first { note(logs) }
            await tools.stopAll()
            fail(result.content.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined(separator: "\n"))
        }
        return result
    }

    _ = await run("stackbar_render", ["format": "json"])
    // The command view opens after the copies, tools and panel events
    // before its first event, so it shows what they did.
    var viewText: String?
    var viewOpened = false
    func openView() async {
        guard let command, !viewOpened else { return }
        viewOpened = true
        let opened = await run("stackbar_render_command", ["command": .string(command), "query": .string(query), "arguments": .object(commandArguments), "format": .string(asJSON ? "json" : "text")])
        if case .text(let text) = opened.content.first { viewText = text }
    }
    for step in steps {
        if step.kind == "event", step.name.hasPrefix("view/") { await openView() }
        if step.kind == "event" {
            let value: JSONValue = step.value.map { text in
                text.hasPrefix("{") ? (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .string(text) : .string(text)
            } ?? .null
            let result = await run("stackbar_send_event", ["action": .string(step.name), "value": value])
            if command != nil, step.name.hasPrefix("view/"), case .text(let text) = result.content.first { viewText = text }
        } else if step.kind == "copy" {
            _ = await run("stackbar_simulate_copy", ["text": .string(step.name)])
        } else {
            let arguments = step.value.flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) } ?? [:]
            let result = await run("stackbar_call_tool", ["name": .string(step.name), "arguments": arguments])
            if case .text(let text) = result.content.first { print("== tool \(step.name) ==\n\(text)") }
        }
    }
    await openView()
    if let viewText {
        print(viewText)
    } else if let pngDirectory {
        let result = await run("stackbar_render", ["format": "png", "surface": surfaces.count == 1 ? .string(surfaces[0].rawValue) : .null])
        try? FileManager.default.createDirectory(atPath: pngDirectory, withIntermediateDirectories: true)
        var label = "surface"
        for item in result.content {
            switch item {
            case .text(let text): label = text
            case .image(let data, _):
                let file = URL(fileURLWithPath: pngDirectory).appendingPathComponent("\(label).png")
                try? data.write(to: file)
                print(file.path)
            }
        }
    } else {
        let result = await run("stackbar_render", ["format": asJSON ? "json" : "text", "surface": surfaces.count == 1 ? .string(surfaces[0].rawValue) : .null])
        if case .text(let text) = result.content.first { print(text) }
    }
    if verbose, case .text(let logs) = await tools.call("stackbar_logs", arguments: ["path": .string(path)]).content.first { note(logs) }
    await tools.stopAll()
}

func flag(_ name: String, in options: [String]) -> String? {
    guard let index = options.firstIndex(of: name), index + 1 < options.count else { return nil }
    return options[index + 1]
}

let arguments = CommandLine.arguments.dropFirst().filter { $0 != "--no-sandbox" }
guard let command = arguments.first else { fail(usage) }
let rest = Array(arguments.dropFirst())

switch command {
case "docs":
    print(AuthoringGuide.text)
case "parity":
    print(SurfaceParity.ledger())
case "version", "--version":
    print("stackbarctl \(StackbarVersion.current), protocol \(StackbarProtocolVersion.current)")
case "soak":
    guard let path = rest.first else { fail(usage) }
    let minutes = flag("--minutes", in: rest).flatMap(Double.init) ?? 10
    let soak = Soak(
        duration: minutes * 60,
        interval: flag("--interval", in: rest).flatMap(Double.init) ?? 1,
        pressEvents: rest.contains("--press"),
        allowedGrowth: (flag("--growth", in: rest).flatMap(Double.init) ?? 15) / 100
    )
    let plugin = load(path)
    let supervisor = PluginSupervisor(executable: plugin.binary, manifest: plugin.manifest, services: makeServices()) { update in
        if case .log(let level, let message) = update, level != .debug { note("[\(level.rawValue)] \(message)") }
    }
    note("soaking \(plugin.manifest.name) for \(minutes) minutes")
    let report = await soak.run(supervisor) { tick, bytes in
        if tick % 30 == 0 { note(String(format: "tick %d: %.1f MB", tick, Double(bytes) / 1_048_576)) }
    }
    print(report)
    exit(report.passed ? 0 : 1)
case "logs":
    let count = flag("-n", in: rest).flatMap(Int.init) ?? 100
    print("\(HostLog.shared.file.path)\n")
    for line in HostLog.shared.tail(count) { print(line) }
case "doctor":
    var healthy = true
    func check(_ name: String, _ problem: String?) {
        if let problem {
            healthy = false
            print("✗ \(name): \(problem)")
        } else {
            print("✓ \(name)")
        }
    }
    check("Swift toolchain", PluginBuilder.toolchainProblem())
    let package = StackbarPaths.stackbarPackage()
    check("StackbarKit at \(package.path)", FileManager.default.fileExists(atPath: package.appendingPathComponent("Package.swift").path) ? nil : "no Package.swift there; set STACKBAR_PACKAGE")
    for directory in [StackbarPaths.dataDirectory, StackbarPaths.cacheDirectory] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        check("writable \(directory.path)", FileManager.default.isWritableFile(atPath: directory.path) ? nil : "not writable")
    }
    exit(healthy ? 0 : 1)
case "mcp":
    let tools = AuthoringTools(loader: loader, services: makeServices(), png: pngRenderer())
    let server = MCPServer(name: "stackbar-authoring", version: StackbarVersion.current, instructions: "Tools for writing Stackbar plugins: call stackbar_docs first, then stackbar_new/stackbar_build/stackbar_render/stackbar_send_event.", provider: tools)
    await server.serveStdio()
    await tools.stopAll()
case "agent":
    if rest.isEmpty {
        do {
            try UnixSocket.bridgeStdio(to: StackbarPaths.agentSocket.path)
        } catch {
            fail("\(error)\nStart Stackbar, or pass plugin files to run them here: stackbarctl agent <plugin.swift>...")
        }
    } else {
        let services = makeServices()
        var supervisors: [PluginSupervisor] = []
        for path in rest {
            let plugin = load(path)
            let supervisor = PluginSupervisor(executable: plugin.binary, manifest: plugin.manifest, services: services)
            await supervisor.start()
            supervisors.append(supervisor)
        }
        let running = supervisors
        let server = MCPServer(name: "stackbar", version: StackbarVersion.current, instructions: "Tools from running Stackbar plugins. Call stackbar_plugins to see them.", provider: RuntimeTools { running })
        await server.serveStdio()
        for supervisor in supervisors { await supervisor.stop() }
    }
case "keygen":
    let keyFile = URL(fileURLWithPath: flag("--key", in: rest) ?? StackbarPaths.dataDirectory.appendingPathComponent("publisher.key").path)
    if FileManager.default.fileExists(atPath: keyFile.path) { fail("\(keyFile.path) already exists") }
    do {
        let key = try Signing.generateKey()
        try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try key.privateKey.base64EncodedString().write(to: keyFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        print("private key: \(keyFile.path)\npublic key: \(key.publicKey.base64EncodedString())")
    } catch {
        fail("\(error)")
    }
case "sign":
    guard let path = rest.first, let publisher = flag("--publisher", in: rest) else { fail(usage) }
    let keyFile = flag("--key", in: rest) ?? StackbarPaths.dataDirectory.appendingPathComponent("publisher.key").path
    do {
        guard let key = Data(base64Encoded: try String(contentsOfFile: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("\(keyFile) is not a key; run stackbarctl keygen") }
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let manifest = try PluginProcess.readManifest(executable: helper(for: path))
        let bundle = try Signing.bundle(source: source, manifest: manifest, publisherName: publisher, privateKey: key)
        let out = URL(fileURLWithPath: flag("-o", in: rest) ?? (PluginBuilder.sanitizedName(manifest.id) + "." + PluginBundle.fileExtension))
        try bundle.encoded().write(to: out)
        print(out.path)
    } catch {
        fail("\(error)")
    }
case "verify":
    guard let path = rest.first else { fail(usage) }
    do {
        let bundle = try PluginBundle.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        try bundle.verify()
        print("valid: \(bundle.manifest.name) \(bundle.manifest.version) (\(bundle.manifest.id)), signed by \(bundle.publisher.name)")
        for line in SandboxEntitlements.summary(for: bundle.manifest) { print("- \(line)") }
    } catch {
        fail("\(error)")
    }
case "install":
    let installer = PluginInstaller(pluginsDirectory: StackbarPaths.pluginsDirectory, publishers: PublisherStore(file: StackbarPaths.publishersFile), recordFile: StackbarPaths.dataDirectory.appendingPathComponent("installed.json"))
    do {
        let bundle: PluginBundle
        if let index = flag("--index", in: rest) {
            guard let id = rest.last, id != index, let url = URL(string: index) else { fail(usage) }
            let catalog = try await PluginIndex.fetch(url)
            guard let entry = catalog.plugins.filter({ $0.id == id }).max(by: { $1.isNewer(than: $0.version) }) else { fail("\(id) is not in \(catalog.name)") }
            try catalog.checkInstallable(entry)
            bundle = try await PluginIndex.bundle(for: entry, indexURL: url)
        } else if let target = rest.first, target.hasPrefix("https://"), let url = URL(string: target) {
            bundle = try PluginBundle.decode(try await PluginIndex.download(url))
        } else if let target = rest.first {
            bundle = try PluginBundle.decode(Data(contentsOf: URL(fileURLWithPath: target)))
        } else {
            fail(usage)
        }
        let file = try installer.install(bundle)
        let built = try PluginProcess.readManifest(executable: helper(for: file.path))
        try installer.confirm(built, matches: bundle, file: file)
        print("installed \(bundle.manifest.name) \(bundle.manifest.version) to \(file.path)")
        for line in SandboxEntitlements.summary(for: bundle.manifest) { print("- \(line)") }
        print("Stackbar asks you to approve these the first time it runs the plugin.")
    } catch {
        fail("\(error)")
    }
case "index":
    guard rest.count >= 2 else { fail(usage) }
    do {
        switch rest[0] {
        case "build":
            let directory = URL(fileURLWithPath: rest[1])
            let revoked = try flag("--revoked", in: rest).map { try JSONDecoder().decode([PluginIndex.Revocation].self, from: Data(contentsOf: URL(fileURLWithPath: $0))) }
            var index = try PluginIndex.build(name: flag("--name", in: rest) ?? directory.lastPathComponent, root: directory, homepage: flag("--homepage", in: rest), revoked: revoked)
            if let keyFile = flag("--key", in: rest) {
                guard let key = Data(base64Encoded: try String(contentsOfFile: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("\(keyFile) is not a key; run stackbarctl keygen") }
                index = try index.signed(privateKey: key)
            }
            let out = directory.appendingPathComponent("index.json")
            try index.encoded().write(to: out)
            print("\(out.path): \(index.plugins.count) plugins" + (index.signature == nil ? ", unsigned" : ", signed"))
        case "verify":
            guard let key = flag("--public-key", in: rest) else { fail(usage) }
            let url = rest[1].hasPrefix("https://") ? URL(string: rest[1]) : URL(fileURLWithPath: rest[1])
            guard let url else { fail(usage) }
            let index = try await PluginIndex.fetch(url, publicKey: key)
            print("valid: \(index.name), \(index.plugins.count) plugins, \(index.revoked?.count ?? 0) revoked")
        case "fetch":
            let directory = URL(fileURLWithPath: rest[1])
            let key = flag("--public-key", in: rest) ?? OfficialIndex.publicKey
            guard let url = URL(string: flag("--index", in: rest) ?? OfficialIndex.url.absoluteString) else { fail(usage) }
            let index = try await PluginIndex.fetch(url, publicKey: key)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var fetched = 0
            for id in BundledStore.pluginIDs.sorted() {
                guard let entry = index.plugins.filter({ $0.id == id && $0.requiredStackbar() == nil }).max(by: { $1.isNewer(than: $0.version) }) else {
                    print("not in \(index.name) for Stackbar \(StackbarVersion.current): \(id)")
                    continue
                }
                try index.checkInstallable(entry)
                let bundle = try await PluginIndex.bundle(for: entry, indexURL: url)
                try bundle.verify()
                guard bundle.publisher.publicKey == key else { fail("\(id) is not signed by the index's key") }
                try bundle.encoded().write(to: directory.appendingPathComponent("\(id)-\(bundle.manifest.version).\(PluginBundle.fileExtension)"))
                print("fetched \(bundle.manifest.name) \(bundle.manifest.version)")
                fetched += 1
            }
            print("\(directory.path): \(fetched) bundles")
        case "search":
            guard let url = URL(string: rest[1]) else { fail(usage) }
            let index = try await PluginIndex.fetch(url, publicKey: flag("--public-key", in: rest))
            let query = rest.count > 2 && !rest[2].hasPrefix("--") ? rest[2] : ""
            for entry in index.search(query) {
                let needs = entry.requiredStackbar().map { " (needs Stackbar \($0))" } ?? ""
            print("\(entry.id)  \(entry.name) \(entry.version) by \(entry.publisher)\(needs)" + (entry.summary.map { " — \($0)" } ?? ""))
            }
        default:
            fail(usage)
        }
    } catch {
        fail("\(error)")
    }
case "new":
    guard let path = rest.first else { fail(usage) }
    let url = URL(fileURLWithPath: path)
    let name = flag("--name", in: rest) ?? url.deletingPathExtension().lastPathComponent
    if FileManager.default.fileExists(atPath: url.path) { fail("\(path) already exists") }
    do {
        try PluginTemplate.source(name: name, id: flag("--id", in: rest)).write(to: url, atomically: true, encoding: .utf8)
        print(url.path)
    } catch {
        fail("\(error)")
    }
case "build":
    guard let path = rest.first else { fail(usage) }
    print(helper(for: path).path)
case "manifest":
    guard let path = rest.first else { fail(usage) }
    do {
        let manifest = try PluginProcess.readManifest(executable: helper(for: path))
        print("\(manifest.name) \(manifest.version) (\(manifest.id))")
        if let summary = manifest.summary { print(summary) }
        print("surfaces: " + manifest.surfaces.map(\.rawValue).joined(separator: ", "))
        for line in SandboxEntitlements.summary(for: manifest) { print("- \(line)") }
        for problem in manifest.problems { print("! \(problem)") }
    } catch {
        fail("\(error)")
    }
case "commands", "run":
    guard let path = rest.first else { fail(usage) }
    let tools = AuthoringTools(loader: loader, services: makeServices(), png: nil)
    var callArguments: [String: JSONValue] = ["path": .string(path)]
    var toolName = "stackbar_list_commands"
    if command == "run" {
        guard rest.count >= 2 else { fail(usage) }
        toolName = "stackbar_run_command"
        callArguments["command"] = .string(rest[1])
        var values: [String: JSONValue] = [:]
        var index = 2
        while index < rest.count {
            switch rest[index] {
            case "--arg":
                let parts = value(after: "--arg", in: rest, at: &index).split(separator: "=", maxSplits: 1).map(String.init)
                values[parts[0]] = .string(parts.count > 1 ? parts[1] : "")
            case "--selected-text", "--frontmost-app":
                simulateContext(rest[index], value(after: rest[index], in: rest, at: &index))
            default:
                fail(usage)
            }
            index += 1
        }
        callArguments["arguments"] = .object(values)
    }
    let result = await tools.call(toolName, arguments: callArguments)
    await tools.stopAll()
    let text = result.content.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined(separator: "\n")
    if result.isError { fail(text) }
    print(text)
case "render":
    guard let path = rest.first else { fail(usage) }
    await render(path, options: Array(rest.dropFirst()))
case "secret":
    guard rest.count >= 2 else { fail(usage) }
    let store = StackbarPaths.defaultSecrets()
    do {
        switch rest[0] {
        case "set":
            let secretValue = rest.count > 2 ? rest[2] : (readLine(strippingNewline: true) ?? "")
            try store.setSecret(secretValue, for: rest[1])
            print("saved \(rest[1])")
        case "get":
            print(try store.secret(rest[1]) ?? "")
        case "delete":
            try store.setSecret(nil, for: rest[1])
            print("deleted \(rest[1])")
        default:
            fail(usage)
        }
    } catch {
        fail("\(error)")
    }
default:
    fail(usage)
}
