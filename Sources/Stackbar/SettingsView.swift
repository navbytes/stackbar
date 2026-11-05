#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI
import StackbarHostCore
import StackbarProtocol
import StackbarUI
import UniformTypeIdentifiers

/// Settings, laid out like System Settings: app sections at the top of a
/// sidebar, then every plugin with its icon and status. Each item opens one
/// page.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var query = ""

    private var selection: Binding<SettingsTab?> {
        Binding(get: { model.settingsTab }, set: { if let tab = $0 { model.settingsTab = tab } })
    }

    private var plugins: [PluginController] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.controllers }
        return model.controllers.filter { TextMatch.score(query, in: $0.name) != nil }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    ForEach(SettingsTab.sections.filter(matches), id: \.self) { tab in
                        SettingsSidebarLabel(tab: tab, updates: model.pendingUpdates.count).tag(tab)
                    }
                }
                Section("Plugins") {
                    ForEach(plugins) { controller in
                        PluginSidebarLabel(controller: controller).tag(SettingsTab.plugin(controller.id))
                    }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .navigationTitle(title)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private func matches(_ tab: SettingsTab) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || TextMatch.score(query, in: tab.title) != nil
    }

    private var title: String {
        if case .plugin(let id) = model.settingsTab {
            return model.controllers.first { $0.id == id }?.name ?? "Plugin"
        }
        return model.settingsTab.title
    }

    @ViewBuilder private var detail: some View {
        switch model.settingsTab {
        case .general: GeneralSettings(model: model)
        case .commands: CommandsSettings(model: model)
        case .agents: AgentsSettings(model: model)
        case .privacy: PrivacySettings(model: model)
        case .store: StoreSettings(model: model)
        case .plugin(let id):
            if let controller = model.controllers.first(where: { $0.id == id }) {
                PluginPage(controller: controller, model: model).id(controller.id)
            } else {
                ContentUnavailableView("No Plugin", systemImage: "puzzlepiece.extension", description: Text("It was removed. Pick another plugin in the sidebar."))
            }
        }
    }
}

/// What the Settings window shows: an app section or one plugin's page.
enum SettingsTab: Hashable {
    case general, commands, agents, privacy, store
    case plugin(PluginController.ID)

    /// The app sections, in sidebar order.
    static let sections: [SettingsTab] = [.general, .commands, .agents, .privacy, .store]

    /// An app section by its `stackbar://settings/<page>` name.
    init?(page: String) {
        switch page {
        case "general": self = .general
        case "commands": self = .commands
        case "agents": self = .agents
        case "privacy": self = .privacy
        case "store": self = .store
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .commands: return "Commands & Hotkeys"
        case .agents: return "Agents"
        case .privacy: return "Privacy & Secrets"
        case .store: return "Store & Updates"
        case .plugin: return "Plugin"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .commands: return "command"
        case .agents: return "sparkles"
        case .privacy: return "hand.raised.fill"
        case .store: return "bag.fill"
        case .plugin: return "puzzlepiece.extension.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .commands: return .indigo
        case .agents: return .pink
        case .privacy: return .blue
        case .store: return .teal
        case .plugin: return .gray
        }
    }
}

struct SettingsSidebarLabel: View {
    let tab: SettingsTab
    let updates: Int

    var body: some View {
        Label {
            Text(tab.title)
        } icon: {
            SettingsIconTile(symbol: tab.symbol, color: tab.color)
        }
        .badge(tab == .store && updates > 0 ? updates : 0)
    }
}

struct PluginSidebarLabel: View {
    let controller: PluginController

    var body: some View {
        let status = SettingsPresentation.status(controller.state, isEnabled: controller.isEnabled, waitingForApproval: controller.isWaitingForApproval, missingSecrets: controller.missingSecrets)
        Label {
            HStack(spacing: 6) {
                Text(controller.name)
                    .lineLimit(1)
                    .foregroundStyle(controller.isEnabled ? .primary : .secondary)
                Spacer(minLength: 4)
                StatusDot(tone: status.tone)
            }
        } icon: {
            PluginIcon(manifest: controller.manifest, size: 20)
                .saturation(controller.isEnabled ? 1 : 0)
        }
        .help(status.text)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage(PluginWindows.dockIconKey) private var dockIcon = true
    @AppStorage(PaletteSession.compactKey) private var paletteCompact = false

    var body: some View {
        SettingsPage {
            SettingsPageHeader(title: "Stackbar", subtitle: "A launcher, menu bar and widgets you extend in one Swift file.", detail: "Version \(StackbarVersion.current)") {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
            } trailing: {
                EmptyView()
            }
            SettingsGroup("Startup and Dock") {
                Toggle("Open Stackbar at login", isOn: $launchAtLogin)
                    .toggleStyle(TrailingSwitchStyle())
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show in the Dock while a plugin window is open", isOn: $dockIcon)
                    .toggleStyle(TrailingSwitchStyle())
                    .onChange(of: dockIcon) { AppDelegate.shared?.windows.updatePresence() }
            }
            SettingsGroup("Command Palette") {
                SettingsRow(title: "Open the palette", caption: "Apps, files, sums and every plugin's commands. Click to record another hotkey.") {
                    PaletteHotKeyPicker()
                }
                SettingsRow(title: "Aliases and hotkeys", caption: "Give any command a short alias or its own shortcut.") {
                    Button("Edit…") { model.settingsTab = .commands }
                }
                Toggle("Compact: show only the search field until you type", isOn: $paletteCompact)
                    .toggleStyle(TrailingSwitchStyle())
            }
            SettingsGroup("Plugins") {
                SettingsRow(title: "Plugins folder", caption: "Drop a .swift plugin here and Stackbar builds and runs it.") {
                    Button("Show in Finder") { NSWorkspace.shared.open(StackbarPaths.pluginsDirectory) }
                }
                SettingsRow(title: "Bundled plugins and examples", caption: "Copies the examples that ship with Stackbar into the plugins folder.") {
                    Button("Install") { model.installExamples() }
                }
            }
            SpotlightReplacementsSection(model: model)
            SettingsTransferGroup(model: model)
        }
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

/// A shortcut drawn as a key cap.
struct KeyCaps: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

// MARK: - Agents

struct AgentsSettings: View {
    @Bindable var model: AppModel
    @State private var copied = false

    private var command: String { "claude mcp add stackbar -- \(Platform.stackbarctlPath) agent" }

    private var status: SettingsPresentation.Status {
        guard model.agentGatewayEnabled else { return .init(text: "Off", tone: .off) }
        return model.agentGatewayError == nil ? .init(text: "Ready for agents", tone: .good) : .init(text: "Not running", tone: .failed)
    }

    var body: some View {
        SettingsPage {
            SettingsPageHeader(title: "Agents", subtitle: "Let Claude Code and other MCP clients use the tools your plugins offer.", status: status) {
                SettingsIconTile(symbol: SettingsTab.agents.symbol, color: SettingsTab.agents.color, size: 52)
            } trailing: {
                Toggle("Let agents use plugin tools", isOn: $model.agentGatewayEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if let error = model.agentGatewayError {
                SettingsGroup {
                    SettingsRow(symbol: "exclamationmark.triangle.fill", color: .red, title: "The agent gateway didn't start", caption: error)
                }
            }
            SettingsGroup("Connect Claude Code", footer: "Run this once in Terminal. Claude Code then starts Stackbar's gateway when it needs a tool.") {
                HStack(alignment: .center, spacing: 10) {
                    Text(command)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(copied ? "Copied" : "Copy") {
                        Platform.copy(command)
                        copied = true
                    }
                }
            }
            let offering = model.controllers.filter { !$0.tools.isEmpty }
            SettingsGroup("Tools Your Plugins Offer", footer: "Turn off any tool you don't want agents to call. Tools that return private data, like your clipboard, stay off until you turn them on.") {
                if offering.isEmpty {
                    Text("None of your plugins offers tools yet.").foregroundStyle(.secondary)
                }
                ForEach(offering) { controller in
                    AgentToolsRow(model: model, controller: controller)
                }
            }
        }
    }
}

/// One plugin's tools in Settings → Agents, each with its own switch, plus
/// the switch for agents reading its panel.
struct AgentToolsRow: View {
    let model: AppModel
    let controller: PluginController
    /// The consent store isn't observable; bumped after each change.
    @State private var revision = 0

    var body: some View {
        let _ = revision
        let specs = controller.tools
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PluginIcon(manifest: controller.manifest, size: 20)
                Text(controller.name)
                Spacer()
                Button("Plugin Settings") { model.settingsTab = .plugin(controller.id) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            ForEach(specs.map(\.name) + [AgentConsent.panel], id: \.self) { tool in
                Toggle(isOn: Binding(get: { model.agentConsent.allows(pluginID: controller.pluginID, tool: tool, specs: specs) },
                                     set: { allowed in
                                         model.agentConsent.set(allowed, pluginID: controller.pluginID, tool: tool, specs: specs)
                                         revision += 1
                                     })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool == AgentConsent.panel ? "Read its panel" : tool)
                        Text(caption(tool, specs)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.leading, 30)
            }
        }
    }

    private func caption(_ tool: String, _ specs: [ToolSpec]) -> String {
        let optIn = AgentConsent.isOptIn(tool, specs: specs) ? " Off until you turn it on." : ""
        if tool == AgentConsent.panel { return "stackbar_read: what its panel shows, as text." + optIn }
        return (specs.first { $0.name == tool }?.description ?? "") + optIn
    }
}

// MARK: - Privacy & Secrets

struct PrivacySettings: View {
    let model: AppModel

    var body: some View {
        let plugins = model.controllers.compactMap { controller -> SettingsPresentation.PluginAccess? in
            guard let manifest = controller.manifest else { return nil }
            return .init(id: controller.id, name: controller.name, granted: model.ledger.review(manifest).granted, pending: controller.pendingApproval)
        }
        let groups = SettingsPresentation.overview(plugins).filter { $0.access != .secret }
        let secrets = SettingsPresentation.secrets(model.controllers.map { (name: $0.name, secrets: $0.manifest?.secretNames ?? []) })
        SettingsPage {
            SettingsPageHeader(title: "Privacy & Secrets", subtitle: "Every plugin runs in its own sandbox and can reach only what you allowed. Here is what each one can reach.") {
                SettingsIconTile(symbol: SettingsTab.privacy.symbol, color: SettingsTab.privacy.color, size: 52)
            } trailing: {
                EmptyView()
            }
            if CrashReports.isAvailable {
                CrashReportsGroup()
            }
            if model.controllers.contains(where: { $0.manifest?.capabilities.contains(.textExpansion) == true }) {
                TextExpansionGroup()
            }
            if groups.isEmpty {
                SettingsGroup {
                    SettingsRow(symbol: "checkmark.shield.fill", color: .green, title: "No plugin reaches beyond the basics", caption: "No network, files, commands, clipboard or calendar.")
                }
            }
            ForEach(groups, id: \.access) { group in
                SettingsGroup(group.access.title) {
                    ForEach(Array(group.holders.enumerated()), id: \.offset) { _, holder in
                        holderRow(holder, access: group.access)
                    }
                }
            }
            if !secrets.isEmpty {
                SettingsGroup("Secrets", footer: "Kept in your Keychain and shared by name, so changing or clearing one does it for every plugin that uses it.") {
                    ForEach(secrets, id: \.secret) { item in
                        let users = model.controllers.filter { $0.manifest?.secretNames.contains(item.secret) == true }
                        if let first = users.first {
                            SecretRow(controller: first, name: item.secret, sharedWith: users.dropFirst().map(\.name), usedBy: item.plugins)
                        }
                    }
                }
            }
        }
    }

    private func holderRow(_ holder: SettingsPresentation.AccessGroup.Holder, access: SettingsPresentation.Access) -> some View {
        let manifest = model.controllers.first { $0.id == holder.pluginID }?.manifest
        return Button {
            model.settingsTab = .plugin(holder.pluginID)
        } label: {
            HStack(spacing: 10) {
                PluginIcon(manifest: manifest, size: 20)
                Text(holder.pluginName)
                Text(holder.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if holder.isPending { StatusTag(text: "Asks", color: .orange) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(holder.pluginName)'s page")
    }
}

// MARK: - A plugin's page

/// Everything about one plugin on one page: its own settings first, then
/// how to reach it, what it may use, its secrets and, folded away, the
/// details for debugging.
struct PluginPage: View {
    let controller: PluginController
    let model: AppModel

    @State private var confirmingUninstall = false
    @State private var showingDiagnostics = false

    private var manifest: Manifest? { controller.manifest }

    private var status: SettingsPresentation.Status {
        SettingsPresentation.status(controller.state, isEnabled: controller.isEnabled, waitingForApproval: controller.isWaitingForApproval, missingSecrets: controller.missingSecrets)
    }

    var body: some View {
        SettingsPage {
            SettingsPageHeader(title: controller.name, subtitle: manifest?.summary, status: status, detail: manifest.map { "Version \($0.version)" }) {
                PluginIcon(manifest: manifest, size: 56)
            } trailing: {
                Toggle("Turned on", isOn: Binding(get: { controller.isEnabled }, set: { controller.isEnabled = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(controller.isEnabled ? "Turn \(controller.name) off. Its settings and data stay." : "Turn \(controller.name) on")
            }
            if !controller.isEnabled {
                SettingsGroup {
                    SettingsRow(symbol: "power", color: .gray, title: "\(controller.name) is turned off", caption: "It doesn't run, and isn't in the menu bar, the palette or widgets, until you turn it on.")
                }
            }
            if controller.isWaitingForApproval { approval }
            if let problem = controller.problem {
                SettingsGroup {
                    SettingsRow(symbol: "exclamationmark.triangle.fill", color: .red, title: "\(controller.name) didn't build or start", caption: problem) {
                        Button("Rebuild") { controller.reload() }
                    }
                }
            }
            pluginSettings
            shortcuts
            permissions
            secrets
            diagnostics
            actions
        }
        .modifier(UninstallDialog(isPresented: $confirmingUninstall, name: controller.name, canTurnOff: controller.isEnabled) { deleteData in
            Task { await model.uninstall(controller, deleteData: deleteData) }
        } turnOff: {
            controller.isEnabled = false
        })
    }

    private var approval: some View {
        SettingsGroup {
            SettingsRow(symbol: "hand.raised.fill", color: .orange, title: "\(controller.name) is waiting for your approval",
                        caption: "It asks for " + ListFormatter.localizedString(byJoining: controller.pendingApproval.map(\.summary)) + ".") {
                Button("Allow") { controller.approve() }.buttonStyle(.borderedProminent)
            }
        }
    }

    /// The plugin's own `settings` surface, drawn as grouped sections so it
    /// reads as part of the page.
    @ViewBuilder private var pluginSettings: some View {
        if controller.isEnabled, manifest?.surfaces.contains(.settings) == true {
            if let node = controller.settings {
                NodeView(node: node, send: controller.send)
                    .environment(\.stackbarRemoteImage, controller.remoteImages)
                    .environment(\.stackbarGroupedSections, true)
            } else if controller.state == .running {
                SettingsGroup("Settings") {
                    Text("\(controller.name) has no settings yet.").foregroundStyle(.secondary)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var shortcuts: some View {
        let _ = model.commands.revision
        let entries = model.commands.registry.entries.filter { $0.pluginID == controller.pluginID }
        let hasMenuBar = manifest?.surfaces.contains(.menuBar) == true
        if controller.isEnabled, manifest != nil {
            SettingsGroup("Menu Bar and Shortcuts", footer: shortcutsFooter(hasMenuBar: hasMenuBar, hasCommands: !entries.isEmpty)) {
                if hasMenuBar {
                    Toggle("Show in menu bar", isOn: Binding(get: { !controller.hiddenFromMenuBar }, set: { controller.hiddenFromMenuBar = !$0 }))
                        .toggleStyle(TrailingSwitchStyle())
                }
                if let hotkey = manifest?.hotkey {
                    SettingsRow(title: "Open its panel", caption: "Set by the plugin") {
                        KeyCaps(text: ActionsPanel.glyphs(hotkey))
                    }
                }
                SettingsRow(title: "Find it in the palette", caption: "Press \(ActionsPanel.glyphs(PaletteController.chosenHotKey)) and type \(controller.name).")
                ForEach(entries, id: \.key) { entry in
                    CommandSettingsRow(center: model.commands, entry: entry, highlighted: entry.key == model.settingsCommand)
                }
                ForEach(model.commands.problems[controller.pluginID] ?? [], id: \.self) { problem in
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func shortcutsFooter(hasMenuBar: Bool, hasCommands: Bool) -> String? {
        var parts: [String] = []
        if !hasMenuBar { parts.append("\(controller.name) has no menu bar item.") }
        if hasMenuBar && controller.hiddenFromMenuBar { parts.append("Hidden from the menu bar: open its panel from the palette.") }
        if hasMenuBar && !controller.hiddenFromMenuBar && controller.menuBarIdle {
            parts.append("Out of the menu bar until it has something to show: open its panel from the palette.")
        }
        if hasCommands { parts.append("An alias jumps to a command when you type it in the palette. A hotkey runs it from anywhere.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    @ViewBuilder private var permissions: some View {
        let granted = manifest.map { model.ledger.review($0).granted } ?? []
        let rows = SettingsPresentation.permissions(granted: granted, pending: controller.pendingApproval)
        let hasSecrets = !(manifest?.secretNames.isEmpty ?? true)
        if !rows.isEmpty || !hasSecrets {
            SettingsGroup("Permissions", footer: "\(controller.name) runs in its own sandbox and can use only what is listed here.") {
                if rows.isEmpty {
                    SettingsRow(symbol: "checkmark.shield.fill", color: .green, title: "Nothing beyond the basics", caption: "No network, files, commands, clipboard or calendar.")
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    SettingsRow(symbol: row.access.symbol, color: row.access.color, title: row.title, caption: row.detail) {
                        if row.isPending {
                            StatusTag(text: "Asks", color: .orange)
                        } else {
                            StatusTag(text: "Allowed", color: .green)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var secrets: some View {
        if let names = manifest?.secretNames, !names.isEmpty {
            SettingsGroup("Secrets", footer: "Kept in your Keychain. Secrets are shared by name, so changing or clearing one does it for every plugin that uses it.") {
                ForEach(names, id: \.self) { name in
                    SecretRow(controller: controller, name: name, sharedWith: model.controllers
                        .filter { $0 !== controller && $0.manifest?.secretNames.contains(name) == true }
                        .map(\.name))
                }
            }
        }
    }

    private var diagnostics: some View {
        SettingsGroup {
            DisclosureGroup("Diagnostics", isExpanded: $showingDiagnostics) {
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        if let manifest {
                            GridRow { Text("Id").foregroundStyle(.secondary); Text(manifest.id) }
                            GridRow { Text("Version").foregroundStyle(.secondary); Text(manifest.version) }
                        }
                        GridRow { Text("File").foregroundStyle(.secondary); Text(controller.source.path).truncationMode(.middle) }
                    }
                    .font(.callout)
                    .textSelection(.enabled)
                    let network = controller.networkReport()
                    if !network.isEmpty {
                        Text("Network").font(.subheadline.weight(.semibold))
                        ForEach(network, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    }
                    if manifest?.runCommands.isEmpty == false {
                        let runs = model.services.runs.recentRuns(pluginID: controller.pluginID).prefix(10)
                        Text("Commands run").font(.subheadline.weight(.semibold))
                        if runs.isEmpty { Text("Nothing yet.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                            Text(Self.describe(run)).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                    if !controller.tools.isEmpty {
                        Text("Agent tools").font(.subheadline.weight(.semibold))
                        ForEach(controller.tools, id: \.name) { tool in
                            Text("\(tool.name): \(tool.description)").font(.caption).textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Rebuild") { controller.reload() }
            Button("Edit with Claude…") { Platform.editWithClaude(controller.source) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([controller.source]) }
            Spacer()
            Button("Uninstall…", role: .destructive) { confirmingUninstall = true }
        }
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
    /// Every plugin that uses it, on the Privacy & Secrets page.
    var usedBy: [String]?

    @State private var isSaved = false
    @State private var editing = false
    @State private var value = ""
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SettingsIconTile(symbol: SettingsPresentation.Access.secret.symbol, color: SettingsPresentation.Access.secret.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.monospaced())
                    Text(isSaved ? "Saved" : "Not set").font(.caption).foregroundStyle(isSaved ? Color.secondary : Color.orange)
                    if let usedBy {
                        Text("Used by " + ListFormatter.localizedString(byJoining: usedBy)).font(.caption).foregroundStyle(.secondary)
                    } else if !sharedWith.isEmpty {
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
/// Settings › Privacy: the crash-report switch.
/// The switch for text expansion and the apps it skips. Plugins register
/// keywords; this is where the user can stop all of it at once.
struct TextExpansionGroup: View {
    @State private var enabled = MacTextExpansion.isEnabled
    @State private var excluded = MacTextExpansion.excludedApps
    @State private var tick = 0

    var body: some View {
        let summary = MacTextExpansion.shared.summary
        SettingsGroup("Text Expansion", footer: "Stackbar watches what you type only for the keywords plugins set up, keeps the last few characters in memory and nothing else, and never in password fields. Plugins never see your typing.") {
            Toggle("Expand keywords as you type", isOn: $enabled)
                .toggleStyle(TrailingSwitchStyle())
                .onChange(of: enabled) { _, on in MacTextExpansion.isEnabled = on; tick += 1 }
            if enabled {
                SettingsRow(symbol: Self.symbol(summary), color: Self.color(summary), title: Self.title(summary), caption: Self.caption(summary)) {
                    if summary.needsAccessibility {
                        Button("Open Accessibility…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
                .id(tick)
                ForEach(excluded, id: \.self) { id in
                    SettingsRow(title: Self.appName(id), caption: "Never expands here") {
                        Button("Remove") { set(excluded.filter { $0 != id }) }
                    }
                }
                SettingsRow(title: "Skip another app", caption: "Keywords won't expand while it is in front.") {
                    Button("Choose App…") { chooseApp() }
                }
            }
        }
    }

    private func set(_ apps: [String]) {
        excluded = apps
        MacTextExpansion.excludedApps = apps
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Skip"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, !excluded.contains(id) else { return }
        set(excluded + [id])
    }

    private static func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private typealias Summary = (keywords: Int, plugins: [String], listening: Bool, needsAccessibility: Bool)
    private static func symbol(_ s: Summary) -> String { s.needsAccessibility ? "exclamationmark.triangle.fill" : "keyboard" }
    private static func color(_ s: Summary) -> Color { s.needsAccessibility ? .orange : (s.listening ? .green : .gray) }
    private static func title(_ s: Summary) -> String {
        if s.needsAccessibility { return "Needs Accessibility access" }
        if s.keywords == 0 { return "No keywords yet" }
        return "\(s.keywords) keyword\(s.keywords == 1 ? "" : "s") from \(s.plugins.joined(separator: ", "))"
    }
    private static func caption(_ s: Summary) -> String? {
        if s.needsAccessibility { return "Stackbar uses it to see keywords as you type them and to paste." }
        if let app = MacKeyLayer.secureInputHolder() { return "Paused while \(app) has Secure Input on." }
        return s.keywords == 0 ? "Give a snippet a keyword in Snippets." : nil
    }
}

struct CrashReportsGroup: View {
    @State private var allowed = CrashReports.isAllowed

    var body: some View {
        SettingsGroup("Crash Reports", footer: "A report has where Stackbar crashed, its version, the macOS version and the Mac model. Never plugin names, logs, files or your computer's name.") {
            Toggle("Send a report when Stackbar crashes", isOn: $allowed)
                .toggleStyle(TrailingSwitchStyle())
                .onChange(of: allowed) { _, on in CrashReports.isAllowed = on }
        }
    }
}
#endif
