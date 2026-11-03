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

/// The plugin store: browse the official index and any added ones, install
/// signed bundles, and update them.
struct StoreView: View {
    @Bindable var model: AppModel
    @State private var newIndex = ""
    @State private var catalogs: [PluginStore.Catalog] = []
    @State private var query = ""
    @State private var status: String?
    @State private var loading = false
    /// The plugin whose page is open.
    @State private var page: StorePage?

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
                                let controller = model.controller(for: entry.id)
                                StoreRow(entry: entry, catalog: catalog, state: state(of: entry), isOn: controller?.isEnabled) {
                                    Task { await install(entry, from: catalog) }
                                } uninstall: { deleteData in
                                    Task { await uninstall(entry, deleteData: deleteData) }
                                } setOn: { on in
                                    controller?.isEnabled = on
                                } open: {
                                    page = StorePage(pluginID: entry.id, indexURL: catalog.source.url)
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
        .onChange(of: model.storeFocus) { openFocus() }
        .sheet(item: $page) { page in
            if let catalog = catalogs.first(where: { $0.source.url == page.indexURL }),
               let entry = catalog.index.search("").first(where: { $0.id == page.pluginID }) {
                let controller = model.controller(for: entry.id)
                StorePluginPage(entry: entry, catalog: catalog, state: state(of: entry), isOn: controller?.isEnabled) {
                    Task { await install(entry, from: catalog) }
                } uninstall: { deleteData in
                    Task { await uninstall(entry, deleteData: deleteData) }
                } setOn: { on in
                    controller?.isEnabled = on
                } close: {
                    self.page = nil
                }
            } else {
                VStack(spacing: 12) {
                    Text("This plugin is no longer listed.")
                    Button("Done") { self.page = nil }.keyboardShortcut(.defaultAction)
                }
                .padding(40)
            }
        }
    }

    /// Opens the page a `stackbar://store/<id>` link asked for, once the
    /// stores have loaded.
    private func openFocus() {
        guard let id = model.storeFocus, !loading, !catalogs.isEmpty else { return }
        model.storeFocus = nil
        if let found = PluginStore.find(id, in: catalogs) {
            page = StorePage(pluginID: found.entry.id, indexURL: found.catalog.source.url)
        } else {
            status = "None of your stores lists \(id)."
        }
    }

    private func state(of entry: PluginIndex.Entry) -> StoreRow.Availability {
        if let needed = entry.requiredStackbar() { return .needsStackbar(needed) }
        if let record = model.installedPlugins.first(where: { $0.id == entry.id }) {
            return entry.isNewer(than: record.version) ? .update(from: record.version) : .installed
        }
        return model.controller(for: entry.id) != nil ? .installed : .available
    }

    private func load() async {
        loading = true
        defer { loading = false }
        model.refreshInstalled()
        let result = await PluginStore.load(model.storeSources, site: true)
        catalogs = result.catalogs
        status = result.problems.isEmpty ? nil : result.problems.joined(separator: "\n")
        loading = false
        openFocus()
    }

    private func install(_ entry: PluginIndex.Entry, from catalog: PluginStore.Catalog) async {
        do {
            try catalog.index.checkInstallable(entry)
            let bundle = try await PluginIndex.bundle(for: entry, indexURL: catalog.source.url)
            let file = try model.installer.install(bundle)
            if let controller = model.controller(for: entry.id) { controller.reload() } else { model.add(file) }
            model.refreshInstalled()
            status = "Installed \(entry.name) \(entry.version). Open it from the menu bar to allow what it asks for."
        } catch {
            status = "Could not install \(entry.name): \(error)"
        }
    }
}

extension StoreView {
    private func uninstall(_ entry: PluginIndex.Entry, deleteData: Bool) async {
        if let controller = model.controller(for: entry.id) {
            await model.uninstall(controller, deleteData: deleteData)
        } else if let record = model.installedPlugins.first(where: { $0.id == entry.id }) {
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: record.file), resultingItemURL: nil)
            try? model.installer.forget(entry.id)
            model.switches.set(entry.id, on: true)
            if deleteData { await model.services.storage.erase(entry.id) }
            model.refreshInstalled()
        }
        status = "Moved \(entry.name) to the Trash" + (deleteData ? " and deleted its data." : ".")
    }
}

/// Which plugin's page is open in the store.
struct StorePage: Identifiable, Equatable {
    var pluginID: String
    var indexURL: URL
    var id: String { indexURL.absoluteString + "#" + pluginID }
}

struct StoreRow: View {
    enum Availability: Equatable {
        case available
        case installed
        case update(from: String)
        case needsStackbar(String)
    }

    let entry: PluginIndex.Entry
    let catalog: PluginStore.Catalog
    let state: Availability
    /// Whether the installed plugin is on; nil when it isn't loaded.
    let isOn: Bool?
    let install: () -> Void
    let uninstall: (_ deleteData: Bool) -> Void
    let setOn: (Bool) -> Void
    /// Opens the plugin's page.
    let open: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// This version's most telling render from the store's site.json, then
    /// the index's single screenshot.
    private var thumbnail: URL? {
        let path = catalog.site?.thumbnail(entry.id, version: entry.version)?.path(dark: colorScheme == .dark) ?? entry.screenshot
        return path.flatMap { URL(string: $0, relativeTo: catalog.source.url)?.absoluteURL }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    if let thumbnail {
                        AsyncImage(url: thumbnail) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            StorePluginIcon(entry: entry, size: 40)
                        }
                        .frame(width: 96, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        StorePluginIcon(entry: entry, size: 40).frame(width: 96, height: 64)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            StorePluginIcon(entry: entry, size: 16)
                            Text("\(entry.name) \(entry.version)").font(.headline)
                        }
                        if let summary = entry.summary { Text(summary).font(.callout).multilineTextAlignment(.leading) }
                        Text("by \(entry.publisher)").font(.caption).foregroundStyle(.secondary)
                        ForEach(entry.capabilities, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(entry.name)'s page")
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                StoreActions(entry: entry, state: state, isOn: isOn, install: install, uninstall: uninstall, setOn: setOn)
                HStack(spacing: 8) {
                    Button("Details", action: open)
                    if let page = catalog.webPage(for: entry) {
                        Link("Web Page", destination: page)
                    } else if let homepage = entry.homepage, let url = URL(string: homepage) {
                        Link("Homepage", destination: url)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
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
