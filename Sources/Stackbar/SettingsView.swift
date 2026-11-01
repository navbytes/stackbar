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
            StoreView(model: model).tabItem { Label("Store", systemImage: "bag") }.tag(SettingsTab.store)
        }
        .frame(minWidth: 680, minHeight: 520)
    }
}

enum SettingsTab: Hashable {
    case general, plugins, store
}

struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var showInDock = DockPresence.enabled

    var body: some View {
        Form {
            Section {
                Toggle("Open Stackbar at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                LabeledContent("Command palette", value: "⌃⌥Space")
                Toggle("Show in the Dock while a window is open", isOn: $showInDock)
                    .onChange(of: showInDock) { _, on in DockPresence.enabled = on }
                Text("Plugin windows and Settings then appear in ⌘Tab and the Dock, so they're easy to find behind other windows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                    Text(controller.name)
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

    var body: some View {
        Form {
            Section(controller.name) {
                if let manifest = controller.manifest {
                    LabeledContent("Id", value: manifest.id)
                    LabeledContent("Version", value: manifest.version)
                    if let summary = manifest.summary { Text(summary) }
                }
                LabeledContent("File", value: controller.source.path).textSelection(.enabled)
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
            Section("Network") {
                ForEach(controller.networkReport(), id: \.self) { Text($0).font(.caption) }
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
                    Button("Move to Trash", role: .destructive) { Task { await model.uninstall(controller) } }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The plugin store: browse the configured indexes and install signed bundles.
struct StoreView: View {
    @Bindable var model: AppModel
    @State private var newIndex = ""
    @State private var catalogs: [(url: URL, index: PluginIndex)] = []
    @State private var query = ""
    @State private var status: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Index URL (https://…/index.json)", text: $newIndex).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newIndex.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !model.indexURLs.contains(trimmed) else { return }
                    model.indexURLs.append(trimmed)
                    newIndex = ""
                    Task { await load() }
                }
            }
            TextField("Search", text: $query).textFieldStyle(.roundedBorder)
            if loading { ProgressView().controlSize(.small) }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            List {
                ForEach(catalogs, id: \.url) { catalog in
                    Section(catalog.index.name) {
                        ForEach(catalog.index.search(query)) { entry in
                            StoreRow(entry: entry, installed: model.controller(for: entry.id) != nil) {
                                Task { await install(entry, from: catalog.url) }
                            }
                        }
                    }
                }
            }
            if model.indexURLs.isEmpty {
                Text("Add an index to browse plugins. Anyone can publish one with `stackbarctl index build`.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var loaded: [(URL, PluginIndex)] = []
        var problems: [String] = []
        for string in model.indexURLs {
            guard let url = URL(string: string) else { continue }
            do {
                loaded.append((url, try await PluginIndex.fetch(url)))
            } catch {
                problems.append("\(string): \(error)")
            }
        }
        catalogs = loaded.map { (url: $0.0, index: $0.1) }
        status = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    private func install(_ entry: PluginIndex.Entry, from indexURL: URL) async {
        do {
            let bundle = try await PluginIndex.bundle(for: entry, indexURL: indexURL)
            let file = try model.installer.install(bundle)
            model.add(file)
            status = "Installed \(entry.name). Open it from the menu bar to allow what it asks for."
        } catch {
            status = "Could not install \(entry.name): \(error)"
        }
    }
}

struct StoreRow: View {
    let entry: PluginIndex.Entry
    let installed: Bool
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.name) \(entry.version)").font(.headline)
                if let summary = entry.summary { Text(summary).font(.callout) }
                Text("by \(entry.publisher)").font(.caption).foregroundStyle(.secondary)
                ForEach(entry.capabilities, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button(installed ? "Installed" : "Install", action: install).disabled(installed)
        }
        .padding(.vertical, 4)
    }
}
#endif
