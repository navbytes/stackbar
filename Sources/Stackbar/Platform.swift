#if os(macOS)
import AppKit
import UserNotifications
import StackbarHostCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The app's side effects on the system.
@MainActor
enum Platform {
    /// A user notification. Uses UserNotifications in a real app bundle; an
    /// unbundled development build (`swift run Stackbar`) has no bundle id, where
    /// that framework crashes, so it falls back to AppleScript.
    static func notify(_ note: HostNotification) {
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" {
            NotificationRouter.shared.post(note)
        } else {
            let script = "display notification \(appleScriptString(note.body ?? "")) with title \(appleScriptString(note.title)) subtitle \(appleScriptString(note.pluginName))"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
    }

    /// Opens a new GitHub issue with the version, macOS and
    /// `stackbarctl doctor` filled in; the user reads it before sending.
    static func reportProblem() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        Task {
            let doctor = await doctorOutput()
            NSWorkspace.shared.open(ProblemReport.issueURL(version: StackbarVersion.current, macOS: macOS, doctor: doctor))
        }
    }

    /// The embedded stackbarctl's `doctor`, or a note when it can't run.
    private static func doctorOutput() async -> String {
        guard let tool = Bundle.main.url(forAuxiliaryExecutable: "stackbarctl") else { return "(stackbarctl is not in this build)" }
        return await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = tool
            process.arguments = ["doctor"]
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { return "(could not run stackbarctl doctor: \(error.localizedDescription))" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Opens a URL or file with the app that has this bundle id.
    static func open(_ url: URL, with bundleID: String) async throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw SystemServiceError("no app with the bundle id \(bundleID) is installed")
        }
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Opens the coding agent picked in Settings › Agents on the plugin, in
    /// the terminal picked in Settings › General, after refreshing the
    /// plugins folder's `AGENTS.md`.
    static func editPlugin(_ file: URL, with editor: PluginEditor, customCommand: String) {
        AgentNotes.write(in: file.deletingLastPathComponent(), stackbarctl: stackbarctlPath)
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("stackbar-edit-\(UUID().uuidString.prefix(8)).command")
        do {
            try editor.script(for: file, stackbarctl: stackbarctlPath, customCommand: customCommand).write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            Task { _ = await MacSystem.open(script: script) }
        } catch {
            NSWorkspace.shared.open(file)
        }
    }

    /// Copies the prompt "Edit with …" starts an agent with, for an agent
    /// started by hand or one that isn't a terminal app.
    static func copyAgentPrompt(_ file: URL) {
        AgentNotes.write(in: file.deletingLastPathComponent(), stackbarctl: stackbarctlPath)
        copy(PluginEditor.prompt(for: file))
    }

    /// `stackbarctl` next to the app's executable in a bundle, or in the same
    /// build folder during development.
    static var stackbarctlPath: String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return executable.deletingLastPathComponent().appendingPathComponent("stackbarctl").path
    }

    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
#endif
