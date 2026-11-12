import Foundation
import StackbarHostCore
import StackbarProtocol

// The commands that take a plugin and say something about it.

/// `new`: a starter plugin file.
@MainActor
func newPlugin(_ rest: [String]) {
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
}

/// `build`: the helper's path, built if it wasn't.
@MainActor
func build(_ rest: [String]) {
    guard let path = rest.first else { fail(usage) }
    print(helper(for: path).path)
}

/// `manifest`: what the plugin declares, and what is wrong with it.
@MainActor
func manifest(_ rest: [String]) {
    guard let path = rest.first else { fail(usage) }
    do {
        let manifest = try PluginProcess.readManifest(executable: helper(for: path))
        if rest.contains("--json") {
            print(String(decoding: try ManifestReport(manifest).encoded(), as: UTF8.self))
        } else {
            print("\(manifest.name) \(manifest.version) (\(manifest.id))")
            if let summary = manifest.summary { print(summary) }
            print("surfaces: " + manifest.surfaces.map(\.rawValue).joined(separator: ", "))
            for line in SandboxEntitlements.summary(for: manifest) { print("- \(line)") }
            for problem in manifest.problems { print("! \(problem)") }
        }
    } catch {
        fail("\(error)")
    }
}

/// `previews`: the plugin's named previews.
@MainActor
func listPreviews(_ rest: [String]) {
    guard let path = rest.first else { fail(usage) }
    let list = previews(of: path)
    if rest.contains("--json") {
        print(String(decoding: (try? LineCodec.encode(list)) ?? Data("[]".utf8), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    } else if list.isEmpty {
        print("no previews")
    } else {
        for preview in list { print("\(preview.name)\t\(preview.surface.rawValue)\t\(preview.title)") }
    }
}

/// `commands` lists the plugin's commands; `run` runs one and prints its result.
@MainActor
func commands(_ rest: [String], run: Bool) async {
    guard let path = rest.first else { fail(usage) }
    let tools = AuthoringTools(loader: loader, services: makeServices(), png: nil)
    var callArguments: [String: JSONValue] = ["path": .string(path)]
    var toolName = "stackbar_list_commands"
    if run {
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
}

/// `soak`: the plugin under load, failing when its memory grows.
@MainActor
func soak(_ rest: [String]) async -> Never {
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
}
