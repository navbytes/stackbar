import Foundation
import StackbarHostCore
import StackbarProtocol
#if canImport(StackbarUI) && os(macOS)
import StackbarUI
#endif

// What the commands share: failing with a message, reading flags, and the
// loader, services and simulated system every plugin runs against here.

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
/// Plugins' saved values go to a scratch folder unless `--real-storage`
/// (or `STACKBAR_HOME`), so trying a plugin can't overwrite the app's data.
let realStorage = CommandLine.arguments.contains("--real-storage")
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
        storage: StorageStore(directory: StackbarPaths.toolStorageDirectory(realStorage: realStorage)),
        secrets: StackbarPaths.defaultSecrets(),
        platform: .init(
            notify: { posted in
                let buttons = posted.actions.isEmpty ? "" : " [" + posted.actions.map { "\($0.title) → \($0.url)" }.joined(separator: ", ") + "]"
                note("[notify] \(posted.pluginName): \(posted.title)" + (posted.body.map { " — \($0)" } ?? "") + buttons)
            },
            alert: { posted in note("[alert] \(posted.pluginName): \(posted.title)" + (posted.body.map { " — \($0)" } ?? "") + " [" + posted.actions.map(\.title).joined(separator: ", ") + "]") },
            playSound: { sound in note("[sound] \(sound.rawValue)") },
            hud: { message, isError in note("[hud\(isError ? " error" : "")] \(message)") },
            open: { url in note("[open] \(url.absoluteString)") },
            copy: { text in note("[copy] \(text.prefix(200))") },
            secretMissing: { _, name in note("[secret] \(name) is not set; run: stackbarctl secret set \(name) <value>") },
            system: simulatedSystem,
            window: { _, request in note("[window] \(request.action.rawValue)" + (request.keepOnTop == true ? " (keep on top)" : "")) }
        )
    )
}

func pngRenderer(dark: Bool = false) -> AuthoringTools.PNGRenderer? {
    #if canImport(StackbarUI) && os(macOS)
    return { node, surface, images in await MainActor.run { Snapshot.png(node, surface: surface, dark: dark, images: images) } }
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

/// Puts the plugin's next launch in preview mode. The plugin inherits
/// stackbarctl's environment, so setting it here reaches the helper.
func usePreview(_ name: String, of path: String) {
    let known = previews(of: path)
    guard known.contains(where: { $0.name == name }) else {
        fail(known.isEmpty
            ? "\(path) has no previews; add `static let previews` (see stackbarctl docs)"
            : "\(path) has no preview named \(name); it has \(known.map(\.name).joined(separator: ", "))")
    }
    setenv(stackbarPreviewEnvironmentKey, name, 1)
}

func previews(of path: String) -> [PreviewSpec] {
    do {
        return try PluginProcess.readPreviews(executable: helper(for: path))
    } catch {
        fail("\(error)")
    }
}

func flag(_ name: String, in options: [String]) -> String? {
    guard let index = options.firstIndex(of: name), index + 1 < options.count else { return nil }
    return options[index + 1]
}
