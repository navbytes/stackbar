#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarProtocol
import StackbarUI

/// The popover a plugin's panel tree is drawn in, with the host's banners
/// (approval, missing secrets, problems) above it and the plugin's controls
/// in a footer.
struct PanelView: View {
    let controller: PluginController
    let model: AppModel
    let windows: PluginWindows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if controller.isWaitingForApproval {
                            ApprovalBanner(controller: controller)
                        }
                        ForEach(controller.missingSecrets, id: \.self) { secret in
                            SecretPrompt(controller: controller, secret: secret)
                        }
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(maxHeight: 560)
                .environment(\.stackbarScrollTo, { key in proxy.scrollTo(key) })
                .environment(\.stackbarShownCount, controller.panelShownCount)
                .environment(\.stackbarImageData, AppModel.previewImages(for: controller))
            }
            Divider()
            PanelFooter(controller: controller, model: model, windows: windows)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 380)
    }

    @ViewBuilder private var content: some View {
        if let problem = controller.problem {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(controller.name) could not start", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.red)
                Text(problem)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button("Try Again") { controller.reload() }
                    Button("Edit with Claude") { Platform.editWithClaude(controller.source) }
                }
            }
        } else if let panel = controller.panel {
            NodeView(node: panel, send: controller.send)
        } else if controller.building || controller.state == .starting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(controller.building ? "Building \(controller.name)… the first build takes a few seconds." : "Starting \(controller.name)…").foregroundStyle(.secondary)
            }
        } else {
            Text("\(controller.name) has no panel.").foregroundStyle(.secondary)
        }
    }
}

struct ApprovalBanner: View {
    let controller: PluginController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(controller.isNewInstall ? "\(controller.name) asks to:" : "This update of \(controller.name) also asks to:", systemImage: "lock.shield")
                .font(.headline)
            ForEach(Array(controller.pendingApproval.enumerated()), id: \.offset) { _, capability in
                Text("• " + capability.summary).font(.callout)
            }
            Text(controller.isNewInstall ? "It runs without these until you allow them." : "It keeps running with what you allowed before.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Allow") { controller.approve() }.keyboardShortcut(.defaultAction)
                Button("Review Source") { NSWorkspace.shared.open(controller.source) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

struct SecretPrompt: View {
    let controller: PluginController
    let secret: String
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(controller.name) needs \(secret)", systemImage: "key").font(.headline)
            Text("Stackbar keeps it in your Keychain and gives it only to plugins that declare it.").font(.caption).foregroundStyle(.secondary)
            HStack {
                SecureField(secret, text: $value).textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save).disabled(value.isEmpty)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
    }

    private func save() {
        guard !value.isEmpty else { return }
        controller.saveSecret(secret, value: value)
        value = ""
    }
}

struct PanelFooter: View {
    let controller: PluginController
    let model: AppModel
    let windows: PluginWindows

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(stateColor).frame(width: 8, height: 8).help(stateText)
            Text(controller.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if controller.manifest?.surfaces.contains(.window) == true {
                Button {
                    windows.open(controller)
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.borderless)
                .help("Open in a Window")
            }
            Button {
                controller.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            if controller.manifest?.surfaces.contains(.settings) == true {
                Button {
                    AppDelegate.shared?.showSettings(plugin: controller)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                .help("\(controller.name) Settings (⌘,)")
            }
            Menu {
                Button("Restart Plugin") { controller.restart() }
                Button("Rebuild") { controller.reload() }
                Divider()
                Button("Edit with Claude…") { Platform.editWithClaude(controller.source) }
                Button("Fork…") { fork() }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([controller.source]) }
                Divider()
                Menu("Network Activity") {
                    ForEach(controller.networkReport(), id: \.self) { Text($0) }
                }
                Button("Copy Recent Log") { Platform.copy(controller.logs.joined(separator: "\n")) }
                Divider()
                Button("Command Palette") { AppDelegate.shared?.palette.toggle() }
                Button("Stackbar Settings…") { AppDelegate.shared?.showSettings() }
                Button("Quit Stackbar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func fork() {
        guard let copy = try? PluginFork.forkFile(controller.source, in: StackbarPaths.pluginsDirectory, name: controller.name + " Copy") else { return }
        model.add(copy)
        Platform.editWithClaude(copy)
    }

    private var stateText: String {
        switch controller.state {
        case .running: return "Running"
        case .starting: return "Starting"
        case .restarting(let attempt, let seconds): return "Restarting (attempt \(attempt), in \(Int(seconds))s)"
        case .failed(let reason): return "Stopped: \(reason)"
        case .stopped: return "Stopped"
        }
    }

    private var stateColor: Color {
        switch controller.state {
        case .running: return controller.isWaitingForApproval ? .orange : .green
        case .starting, .restarting: return .orange
        case .failed: return .red
        case .stopped: return .gray
        }
    }
}
#endif
