import Foundation
import StackbarHostCore
import StackbarProtocol
#if canImport(StackbarUI) && os(macOS)
import StackbarUI
#endif

// `stackbarctl render`: a plugin's surfaces as text, JSON, PNG or frames, after
// the events, tools and copies the options ask for.

func render(_ path: String, options: [String]) async {
    var surfaces: [Surface] = [.menuBar, .panel]
    var steps: [(kind: String, name: String, value: String?)] = []
    var asJSON = false
    var pngDirectory: String?
    var framesPath: String?
    var dark = false
    var verbose = false
    var confirmEvents = false
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
        case "--frames": framesPath = value(after: "--frames", in: options, at: &index)
        case "--hold", "--wait":
            let name = options[index]
            let text = value(after: name, in: options, at: &index)
            guard let seconds = Double(text), seconds >= 0, seconds <= 30 else { fail("\(name) takes seconds (0 to 30), not \(text)") }
            steps.append((String(name.dropFirst(2)), text, nil))
        case "--dark": dark = true
        case "--verbose": verbose = true
        case "--confirm": confirmEvents = true
        case "--command": command = value(after: "--command", in: options, at: &index)
        case "--preview": usePreview(value(after: "--preview", in: options, at: &index), of: path)
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

    if framesPath != nil {
        if command != nil { fail("--frames records the plugin's own surfaces, not a --command view") }
        if surfaces.count != 1 { surfaces = [.panel] }
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

    // --frames: what the surface looks like after the first render and
    // after each step, as PNG on macOS and as text elsewhere.
    let framesAsPNG = pngRenderer(dark: dark) != nil
    var frames: [(data: Data, seconds: Double)] = []
    func captureFrame() async {
        guard framesPath != nil else { return }
        let result = await run("stackbar_render", ["format": .string(framesAsPNG ? "png" : "text"), "surface": .string(surfaces[0].rawValue)])
        for item in result.content {
            if case .image(let data, _) = item { frames.append((data, 1)) }
            if !framesAsPNG, case .text(let text) = item { frames.append((Data(text.utf8), 1)) }
        }
    }
    await captureFrame()
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
        if step.kind == "hold" {
            if !frames.isEmpty { frames[frames.count - 1].seconds = Double(step.name) ?? 1 }
            continue
        }
        if step.kind == "wait" {
            try? await Task.sleep(for: .seconds(Double(step.name) ?? 1))
            await captureFrame()
            continue
        }
        if step.kind == "event", step.name.hasPrefix("view/") { await openView() }
        if step.kind == "event" {
            let value: JSONValue = step.value.map { text in
                text.hasPrefix("{") ? (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .string(text) : .string(text)
            } ?? .null
            let result = await run("stackbar_send_event", ["action": .string(step.name), "value": value, "confirm": .bool(confirmEvents)])
            if case .text(let text) = result.content.first, text.hasPrefix("Held:") { print("== \(step.name) ==\n\(text)") }
            if command != nil, step.name.hasPrefix("view/"), case .text(let text) = result.content.first { viewText = text }
        } else if step.kind == "copy" {
            _ = await run("stackbar_simulate_copy", ["text": .string(step.name)])
        } else {
            let arguments = step.value.flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) } ?? [:]
            let result = await run("stackbar_call_tool", ["name": .string(step.name), "arguments": arguments])
            if case .text(let text) = result.content.first { print("== tool \(step.name) ==\n\(text)") }
        }
        await captureFrame()
    }
    await openView()
    if let framesPath {
        writeFrames(frames, to: framesPath, asPNG: framesAsPNG)
    } else if let viewText {
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

func writeFrames(_ frames: [(data: Data, seconds: Double)], to path: String, asPNG: Bool) {
    guard asPNG else {
        for (index, frame) in frames.enumerated() {
            print("== frame \(index + 1) (\(frame.seconds) s) ==\n\(String(decoding: frame.data, as: UTF8.self))")
        }
        return
    }
    #if canImport(StackbarUI) && os(macOS)
    guard let data = AnimatedPNG.make(frames.map { ($0.data, $0.seconds) }) else { fail("couldn't join \(frames.count) frames into \(path)") }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    do { try data.write(to: url) } catch { fail("couldn't write \(path): \(error)") }
    print("\(path) (\(frames.count) frames)")
    #endif
}
