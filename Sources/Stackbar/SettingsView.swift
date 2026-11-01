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
                if controller.manifest?.surfaces.contains(.menuBar) == true {
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
            Section("Network") {
                ForEach(controller.networkReport(), id: \.self) { Text($0).font(.caption) }
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
                    Button("Move to Trash", role: .destructive) { Task { await model.uninstall(controller) } }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The plugin store: browse the official index and any added ones, install
/// signed bundles, and update them.
struct StoreView: View {
    @Bindable var model: AppModel
    @State private var newIndex = ""
    @State private var catalogs: [PluginStore.Catalog] = []
    @State private var query = ""
    @State private var status: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Add an index URL (https://…/index.json)", text: $newIndex).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newIndex.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !model.indexURLs.contains(trimmed), trimmed != OfficialIndex.url.absoluteString else { return }
                    model.indexURLs.append(trimmed)
                    newIndex = ""
                    Task { await load() }
                }
            }
            HStack {
                TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                Toggle("Update automatically", isOn: $model.autoUpdatePlugins).toggleStyle(.checkbox)
            }
            if loading { ProgressView().controlSize(.small) }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            List {
                ForEach(catalogs, id: \.source.url) { catalog in
                    Section {
                        ForEach(catalog.index.byCategory(catalog.index.search(query)), id: \.category) { group in
                            Text(group.category).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(group.entries) { entry in
                                StoreRow(entry: entry, indexURL: catalog.source.url, state: state(of: entry)) {
                                    Task { await install(entry, from: catalog) }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(catalog.index.name)
                            if catalog.source.isOfficial {
                                Text("Signed by navbytes").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Spacer()
                                Button("Remove") {
                                    model.indexURLs.removeAll { $0 == catalog.source.url.absoluteString }
                                    Task { await load() }
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                }
            }
            if model.storeSources.isEmpty {
                Text("Add an index to browse plugins. Anyone can publish one with `stackbarctl index build`.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .task { await load() }
    }

    private func state(of entry: PluginIndex.Entry) -> StoreRow.Availability {
        if let needed = entry.requiredStackbar() { return .needsStackbar(needed) }
        if let record = model.installer.installed.first(where: { $0.id == entry.id }) {
            return entry.isNewer(than: record.version) ? .update(from: record.version) : .installed
        }
        return model.controller(for: entry.id) != nil ? .installed : .available
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let result = await PluginStore.load(model.storeSources)
        catalogs = result.catalogs
        status = result.problems.isEmpty ? nil : result.problems.joined(separator: "\n")
    }

    private func install(_ entry: PluginIndex.Entry, from catalog: PluginStore.Catalog) async {
        do {
            try catalog.index.checkInstallable(entry)
            let bundle = try await PluginIndex.bundle(for: entry, indexURL: catalog.source.url)
            let file = try model.installer.install(bundle)
            if let controller = model.controller(for: entry.id) { controller.reload() } else { model.add(file) }
            status = "Installed \(entry.name) \(entry.version). Open it from the menu bar to allow what it asks for."
        } catch {
            status = "Could not install \(entry.name): \(error)"
        }
    }
}

struct StoreRow: View {
    enum Availability: Equatable {
        case available
        case installed
        case update(from: String)
        case needsStackbar(String)
    }

    let entry: PluginIndex.Entry
    let indexURL: URL
    let state: Availability
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let screenshot = entry.screenshot, let url = URL(string: screenshot, relativeTo: indexURL) {
                AsyncImage(url: url.absoluteURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.secondary.opacity(0.1)
                }
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.name) \(entry.version)").font(.headline)
                if let summary = entry.summary { Text(summary).font(.callout) }
                HStack(spacing: 6) {
                    Text("by \(entry.publisher)")
                    if let homepage = entry.homepage, let url = URL(string: homepage) { Link("Read more", destination: url) }
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(entry.capabilities, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            switch state {
            case .available: Button("Install", action: install)
            case .installed: Button("Installed", action: {}).disabled(true)
            case .update(let from): Button("Update", action: install).help("Installed: \(from)")
            case .needsStackbar(let version): Text("Needs Stackbar \(version)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
