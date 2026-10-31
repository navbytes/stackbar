#if os(macOS)
import AppKit
import UserNotifications
import FluidHostCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The app's side effects on the system.
@MainActor
enum Platform {
    /// A user notification. Uses UserNotifications in a real app bundle; an
    /// unbundled development build (`swift run Fluid`) has no bundle id, where
    /// that framework crashes, so it falls back to AppleScript.
    static func notify(plugin: String, title: String, body: String?) {
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" {
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = plugin
            if let body { content.body = body }
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        } else {
            let script = "display notification \(appleScriptString(body ?? "")) with title \(appleScriptString(title)) subtitle \(appleScriptString(plugin))"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Opens Terminal with Claude Code on the plugin and Fluid's authoring
    /// tools attached.
    static func editWithClaude(_ file: URL) {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("fluid-claude-\(UUID().uuidString.prefix(8)).command")
        do {
            try PluginFork.claudeScript(for: file, fluidctl: fluidctlPath).write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            NSWorkspace.shared.open(file)
        }
    }

    /// `fluidctl` next to the app's executable in a bundle, or in the same
    /// build folder during development.
    static var fluidctlPath: String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return executable.deletingLastPathComponent().appendingPathComponent("fluidctl").path
    }

    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
#endif
