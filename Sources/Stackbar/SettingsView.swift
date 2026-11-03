#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI
import StackbarHostCore
import StackbarProtocol
import StackbarUI

/// Settings: general options, the installed plugins and what they may do,
/// and the plugin store.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            PluginsSettings(model: model).tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }.tag(SettingsTab.plugins)
            CommandsSettings(model: model).tabItem { Label("Commands", systemImage: "command") }.tag(SettingsTab.commands)
            StoreView(model: model).tabItem { Label("Store", systemImage: "bag") }.tag(SettingsTab.store)
        }
        .frame(minWidth: 680, minHeight: 520)
    }
}

enum SettingsTab: Hashable {
    case general, plugins, commands, store
}

struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage(PluginWindows.dockIconKey) private var dockIcon = true

    var body: some View {
        Form {
            Section {
                Toggle("Open Stackbar at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Show in the Dock while a plugin window is open", isOn: $dockIcon)
                    .onChange(of: dockIcon) { AppDelegate.shared?.windows.updatePresence() }
                LabeledContent("Command palette", value: "⌃⌥Space")
            }
            MacOSAlternativesSection()
            Section("Agents") {
                Toggle("Let agents use plugin tools (MCP)", isOn: $model.agentGatewayEnabled)
                if let error = model.agentGatewayError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text("Add Stackbar to Claude Code with:").font(.caption).foregroundStyle(.secondary)
                Text("claude mcp add stackbar -- \(Platform.stackbarctlPath) agent")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Section("Folders") {
                LabeledContent("Plugins") {
                    Button("Show in Finder") { NSWorkspace.shared.open(StackbarPaths.pluginsDirectory) }
                }
                LabeledContent("Bundled plugins") {
                    Button("Install Plugins and Examples") { model.installExamples() }
                }
            }
            Section {
                LabeledContent("Version", value: StackbarVersion.current)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Only an installed Stackbar.app can open at login: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct PluginsSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            List(model.controllers, selection: $model.settingsPlugin) { controller in
                HStack {
                    Circle().fill(color(controller.state)).frame(width: 8, height: 8)
                    Text(controller.name).foregroundStyle(controller.isEnabled ? .primary : .secondary)
                    if !controller.isEnabled { OffBadge() }
                    if controller.isWaitingForApproval { Image(systemName: "lock.shield").foregroundStyle(.orange) }
                }
            }
            .frame(minWidth: 180, maxWidth: 220)
            if let controller = model.controllers.first(where: { $0.id == model.settingsPlugin }) {
                PluginPage(controller: controller, model: model).id(controller.id)
            } else {
                Text(model.controllers.isEmpty ? "No plugins yet." : "Select a plugin").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func color(_ state: PluginSupervisor.State) -> Color {
        switch state {
        case .running: return .green
        case .starting, .restarting: return .orange
        case .failed: return .red
        case .stopped: return .gray
        }
    }
}

/// A plugin's page: its own settings (the `settings` surface) and what
/// Stackbar knows about it.
struct PluginPage: View {
    let controller: PluginController
    let model: AppModel
    @State private var showingAbout = false

    private var hasSettings: Bool { controller.manifest?.surfaces.contains(.settings) == true }

    var body: some View {
        VStack(spacing: 0) {
            if hasSettings {
                Picker("", selection: $showingAbout) {
                    Text("Settings").tag(false)
                    Text("About").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.vertical, 10)
            }
            if hasSettings && !showingAbout {
                ScrollView {
                    Group {
                        if let node = controller.settings {
                            NodeView(node: node, send: controller.send)
                                .environment(\.stackbarRemoteImage, controller.remoteImages)
                        } else if controller.state == .running {
                            Text("\(controller.name) has no settings yet.").foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(20)
                }
            } else {
                PluginDetail(controller: controller, model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PluginDetail: View {
    let controller: PluginController
    let model: AppModel

    @State private var confirmingUninstall = false

    var body: some View {
        Form {
            Section(controller.name) {
                if let manifest = controller.manifest {
                    LabeledContent("Id", value: manifest.id)
                    LabeledContent("Version", value: manifest.version)
                    if let summary = manifest.summary { Text(summary) }
                }
                LabeledContent("File", value: controller.source.path).textSelection(.enabled)
                Toggle("Turned on", isOn: Binding(get: { controller.isEnabled }, set: { controller.isEnabled = $0 }))
                if !controller.isEnabled {
                    Text("\(controller.name) doesn't run, and isn't in the menu bar, the palette or widgets, until you turn it on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if controller.isEnabled, let manifest = controller.manifest, !manifest.surfaces.contains(.menuBar) {
                    // Without this, a palette-only plugin looks like it didn't install.
                    Text("\(controller.name) has no menu bar item. Press ⌃⌥Space and type its name" + (manifest.hotkey.map { ", or press \($0)" } ?? "") + ".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if controller.isEnabled, controller.manifest?.surfaces.contains(.menuBar) == true {
                    Toggle("Show in menu bar", isOn: Binding(get: { !controller.hiddenFromMenuBar }, set: { controller.hiddenFromMenuBar = !$0 }))
                    if controller.hiddenFromMenuBar {
                        Text("Open its panel from the command palette" + (controller.manifest?.hotkey.map { " or with \($0)" } ?? "") + ".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Allowed") {
                let granted = controller.manifest.map { model.ledger.review($0).granted } ?? []
                if granted.isEmpty { Text("Nothing beyond the basics.").foregroundStyle(.secondary) }
                ForEach(Array(granted.enumerated()), id: \.offset) { _, capability in Text(capability.summary) }
                if controller.isWaitingForApproval {
                    ForEach(Array(controller.pendingApproval.enumerated()), id: \.offset) { _, capability in
                        Text("Asks for: " + capability.summary).foregroundStyle(.orange)
                    }
                    Button("Allow") { controller.approve() }
                }
            }
            if let names = controller.manifest?.secretNames, !names.isEmpty {
                Section {
                    ForEach(names, id: \.self) { name in
                        SecretRow(controller: controller, name: name, sharedWith: model.controllers
                            .filter { $0 !== controller && $0.manifest?.secretNames.contains(name) == true }
                            .map(\.name))
                    }
                } header: {
                    Text("Secrets")
                } footer: {
                    Text("Kept in your Keychain. Secrets are shared by name, so changing or clearing one does it for every plugin that uses it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Network") {
                ForEach(controller.networkReport(), id: \.self) { Text($0).font(.caption) }
            }
            if controller.manifest?.runCommands.isEmpty == false {
                Section("Commands run") {
                    let runs = model.services.runs.recentRuns(pluginID: controller.pluginID).prefix(10)
                    if runs.isEmpty { Text("Nothing yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                        Text(Self.describe(run)).font(.caption).textSelection(.enabled)
                    }
                }
            }
            if !controller.commands.isEmpty {
                Section("Commands") {
                    ForEach(controller.commands, id: \.id) { command in
                        LabeledContent(command.title, value: command.kind == .view ? "View" : "Run")
                    }
                    Button("Aliases and Hotkeys…") { AppDelegate.shared?.showCommandSettings() }
                }
            }
            if !controller.tools.isEmpty {
                Section("Agent tools") {
                    ForEach(controller.tools, id: \.name) { tool in LabeledContent(tool.name, value: tool.description) }
                }
            }
            Section {
                HStack {
                    Button("Rebuild") { controller.reload() }
                    Button("Edit with Claude…") { Platform.editWithClaude(controller.source) }
                    Spacer()
                    Button("Move to Trash…", role: .destructive) { confirmingUninstall = true }
                }
            }
        }
        .formStyle(.grouped)
        .modifier(UninstallDialog(isPresented: $confirmingUninstall, name: controller.name, canTurnOff: controller.isEnabled) { deleteData in
            Task { await model.uninstall(controller, deleteData: deleteData) }
        } turnOff: {
            controller.isEnabled = false
        })
    }

    /// "12:04 /opt/homebrew/bin/brew · exit 0 · 1.2s · 14 KB"
    static func describe(_ run: CommandRunGate.Record) -> String {
        let how = run.timedOut ? "timed out" : (run.cancelled ? "stopped" : "exit \(run.status)")
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(run.stdoutBytes + run.stderrBytes), countStyle: .file)
        return [run.at.formatted(date: .omitted, time: .shortened) + " " + run.path, how, String(format: "%.1fs", run.duration), bytes].joined(separator: " · ")
    }
}

/// One declared secret on a plugin's page: whether it is saved, and Change
/// or Clear. The value itself is never shown.
struct SecretRow: View {
    let controller: PluginController
    let name: String
    let sharedWith: [String]

    @State private var isSaved = false
    @State private var editing = false
    @State private var value = ""
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.monospaced())
                    Text(isSaved ? "Saved" : "Not set").font(.caption).foregroundStyle(isSaved ? Color.secondary : Color.orange)
                    if !sharedWith.isEmpty {
                        Text("Also used by " + ListFormatter.localizedString(byJoining: sharedWith)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !editing {
                    Button(isSaved ? "Change…" : "Set…") { editing = true }
                    if isSaved {
                        Button("Clear…", role: .destructive) { confirmingClear = true }
                    }
                }
            }
            if editing {
                HStack {
                    SecureField(isSaved ? "New value" : "Value", text: $value)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Cancel") { value = ""; editing = false }
                    Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { isSaved = controller.hasSecret(name) }
        .confirmationDialog("Clear \(name)?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) {
                controller.clearSecret(name)
                isSaved = controller.hasSecret(name)
            }
        } message: {
            Text(sharedWith.isEmpty
                ? "\(controller.name) will ask for it again the next time it needs it."
                : "\(controller.name) and the other plugins that use it will ask for it again the next time they need it.")
        }
    }

    private func save() {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        controller.saveSecret(name, value: value)
        value = ""
        editing = false
        isSaved = controller.hasSecret(name)
    }
}

/// Marks a plugin that is turned off.
struct OffBadge: View {
    var body: some View {
        Text("Off")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

/// Asks before uninstalling: keep the plugin's data, delete it too, or just
/// turn the plugin off.
struct UninstallDialog: ViewModifier {
    @Binding var isPresented: Bool
    let name: String
    let canTurnOff: Bool
    let uninstall: (_ deleteData: Bool) -> Void
    let turnOff: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Uninstall \(name)?", isPresented: $isPresented, titleVisibility: .visible) {
            if canTurnOff { Button("Turn Off Instead") { turnOff() } }
            Button("Move to Trash", role: .destructive) { uninstall(false) }
            Button("Move to Trash and Delete Its Data", role: .destructive) { uninstall(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its file goes to the Trash. Its saved data stays unless you delete it, so installing it again picks up where it left off. Secrets you entered are shared by name with other plugins, so they stay either way.")
        }
    }
}
#endif
