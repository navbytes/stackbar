import Foundation
import FluidHostCore
import FluidProtocol
#if canImport(FluidUI) && os(macOS)
import FluidUI
#endif

// fluidctl — build, inspect and drive Fluid plugins without the app, and serve
// them to agents over MCP.

let usage = """
usage:
  fluidctl new <plugin.swift> [--name "Display Name"] [--id dev.example.x]
  fluidctl build <plugin.swift>
  fluidctl manifest <plugin.swift | helper>
  fluidctl render <plugin.swift | helper> [--surface menuBar|panel|window|widget]
                  [--event <action-id>[=value]]... [--tool name[:json]] [--json] [--png <dir>] [--verbose]
  fluidctl mcp                      authoring MCP server on stdio (for coding agents)
  fluidctl secret set|get|delete <NAME> [value]
  fluidctl docs                     the plugin authoring reference
  fluidctl parity                   the surface parity ledger

A .swift path is built first (cached by content); anything else is run as an
already-built helper. FLUID_PACKAGE overrides where FluidKit is found, and
FLUID_HOME where Fluid keeps its data.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let builder = PluginBuilder(fluidPackage: FluidPaths.fluidPackage(), cacheRoot: FluidPaths.buildCache)

func makeServices() -> HostServices {
    HostServices(
        storage: StorageStore(directory: FluidPaths.storageDirectory),
        secrets: FluidPaths.defaultSecrets(),
        platform: .init(
            notify: { plugin, title, body in note("[notify] \(plugin): \(title)" + (body.map { " — \($0)" } ?? "")) },
            open: { url in note("[open] \(url.absoluteString)") },
            copy: { text in note("[copy] \(text.prefix(200))") },
            secretMissing: { _, name in note("[secret] \(name) is not set; run: fluidctl secret set \(name) <value>") }
        )
    )
}

func pngRenderer() -> AuthoringTools.PNGRenderer? {
    #if canImport(FluidUI) && os(macOS)
    return { node, surface in await MainActor.run { Snapshot.png(node, surface: surface) } }
    #else
    return nil
    #endif
}

func helper(for path: String) -> URL {
    let url = URL(fileURLWithPath: path)
    guard url.pathExtension == "swift" else { return url }
    do {
        let output = try builder.build(source: url)
        if !output.cached { note("built \(output.binary.path)") }
        return output.binary
    } catch let failure as PluginBuilder.Failure {
        fail(failure.description)
    } catch {
        fail("build failed: \(error)")
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
    var verbose = false
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
        case "--json": asJSON = true
        case "--png": pngDirectory = value(after: "--png", in: options, at: &index)
        case "--verbose": verbose = true
        default: fail(usage)
        }
        index += 1
    }

    let tools = AuthoringTools(builder: builder, services: makeServices(), png: pngRenderer())
    func run(_ name: String, _ arguments: [String: JSONValue]) async -> MCPToolResult {
        var arguments = arguments
        arguments["path"] = .string(path)
        let result = await tools.call(name, arguments: arguments)
        if result.isError {
            if verbose, case .text(let logs) = await tools.call("fluid_logs", arguments: ["path": .string(path)]).content.first { note(logs) }
            await tools.stopAll()
            fail(result.content.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined(separator: "\n"))
        }
        return result
    }

    _ = await run("fluid_render", ["format": "json"])
    for step in steps {
        if step.kind == "event" {
            _ = await run("fluid_send_event", ["action": .string(step.name), "value": step.value.map(JSONValue.string) ?? .null])
        } else {
            let arguments = step.value.flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) } ?? [:]
            let result = await run("fluid_call_tool", ["name": .string(step.name), "arguments": arguments])
            if case .text(let text) = result.content.first { print("== tool \(step.name) ==\n\(text)") }
        }
    }
    if let pngDirectory {
        let result = await run("fluid_render", ["format": "png", "surface": surfaces.count == 1 ? .string(surfaces[0].rawValue) : .null])
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
        let result = await run("fluid_render", ["format": asJSON ? "json" : "text", "surface": surfaces.count == 1 ? .string(surfaces[0].rawValue) : .null])
        if case .text(let text) = result.content.first { print(text) }
    }
    if verbose, case .text(let logs) = await tools.call("fluid_logs", arguments: ["path": .string(path)]).content.first { note(logs) }
    await tools.stopAll()
}

func flag(_ name: String, in options: [String]) -> String? {
    guard let index = options.firstIndex(of: name), index + 1 < options.count else { return nil }
    return options[index + 1]
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
let rest = Array(arguments.dropFirst())

switch command {
case "docs":
    print(AuthoringGuide.text)
case "parity":
    print(SurfaceParity.ledger())
case "mcp":
    let tools = AuthoringTools(builder: builder, services: makeServices(), png: pngRenderer())
    let server = MCPServer(name: "fluid-authoring", version: FluidVersion.current, instructions: "Tools for writing Fluid plugins: call fluid_docs first, then fluid_new/fluid_build/fluid_render/fluid_send_event.", provider: tools)
    await server.serveStdio()
    await tools.stopAll()
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
case "render":
    guard let path = rest.first else { fail(usage) }
    await render(path, options: Array(rest.dropFirst()))
case "secret":
    guard rest.count >= 2 else { fail(usage) }
    let store = FluidPaths.defaultSecrets()
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
