#if os(macOS)
import AppKit
import StackbarHostCore
import StackbarUI
import SwiftUI
import UniformTypeIdentifiers

/// Settings › General: export the whole setup to one file, or bring one in.
struct SettingsTransferGroup: View {
    @State private var problem: String?

    var body: some View {
        SettingsGroup("Move to Another Mac", footer: "The file has your plugins, what they saved, aliases, hotkeys and favourites. It never has secrets or the permissions you gave plugins: they ask again after an import.") {
            SettingsRow(title: "Settings file", caption: "Export on this Mac, then import on the other.") {
                HStack {
                    Button("Import…") { importSettings() }
                    Button("Export…") { exportSettings() }
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }

    private static var type: UTType {
        UTType(filenameExtension: SettingsArchive.fileExtension, conformingTo: .json) ?? .json
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.type]
        panel.nameFieldStringValue = "Stackbar \(Date().formatted(.iso8601.year().month().day())).\(SettingsArchive.fileExtension)"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try SettingsArchive.export(dataDirectory: StackbarPaths.dataDirectory).encoded()
            try data.write(to: url, options: .atomic)
            problem = nil
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            problem = "Couldn't export: \(error.localizedDescription)"
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.type, .json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let archive: SettingsArchive
        do {
            archive = try SettingsArchive.decode(Data(contentsOf: url))
        } catch {
            problem = "Couldn't import \(url.lastPathComponent): \(error)"
            return
        }
        let summary = archive.summary
        let alert = NSAlert()
        alert.messageText = "Import \(url.lastPathComponent)?"
        var lines = ["\(summary.pluginFiles.count) plugins, \(summary.savedValues) saved values and \(summary.preferences) preferences, from Stackbar \(archive.stackbarVersion)."]
        if !summary.pluginFiles.isEmpty {
            lines.append("Plugins: " + summary.pluginFiles.map { ($0 as NSString).deletingPathExtension }.joined(separator: ", ") + ".")
        }
        lines.append("Plugins with the same name are replaced. Each plugin asks for its permissions again. Stackbar restarts to load them.")
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: "Import and Restart")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try archive.apply(to: StackbarPaths.dataDirectory)
            UserDefaults.standard.set(true, forKey: WelcomeView.seenKey)
            Self.relaunch()
        } catch {
            problem = "Couldn't import: \(error.localizedDescription)"
        }
    }

    /// Opens a fresh copy once this one has quit (only one Stackbar runs).
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
#endif
