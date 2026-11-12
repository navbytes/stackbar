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
    @State private var toolInstalled = AppHousekeeping.commandLineToolInstalled
    @State private var toolError: String?
    @State private var installingTool = false
    @State private var confirmingClearHistory = false

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
                SettingsRow(title: "Tab with text", caption: "Hands what you typed to this command, as Raycast's Tab does for AI.") {
                    PaletteTabPicker(model: model)
                }
                Toggle("Compact: show only the search field until you type", isOn: $paletteCompact)
                    .toggleStyle(TrailingSwitchStyle())
                SettingsRow(title: "Search history", caption: "The palette learns what you pick for what you type, and ranks it first next time.") {
                    Button("Clear…") { confirmingClearHistory = true }
                }
            }
            .confirmationDialog("Clear the palette's search history?", isPresented: $confirmingClearHistory) {
                Button("Clear", role: .destructive) {
                    model.commands.memory.clear()
                }
            } message: {
                Text("Results go back to their default order. Recent and frecency start over; favorites and aliases stay.")
            }
            HyperKeySettings()
            SpotlightReplacementsSection(model: model)
            MainSearchSection(model: model)
            // What only plugin authors and terminal users change, below
            // everything a new user looks for.
            SettingsGroup("For Plugin Authors") {
                SettingsRow(title: "Plugins folder", caption: "Drop a .swift plugin here and Stackbar builds and runs it.") {
                    Button("Show in Finder") { NSWorkspace.shared.open(StackbarPaths.pluginsDirectory) }
                }
                SettingsRow(title: "Bundled plugins and examples", caption: "Copies the examples that ship with Stackbar into the plugins folder.") {
                    Button("Install") { model.installExamples() }
                }
                SettingsRow(title: "Command-line tool", caption: toolError ?? (toolInstalled ? "stackbarctl is in /usr/local/bin, so Terminal and agents can run it." : "Puts stackbarctl in /usr/local/bin so you can run it in Terminal. Asks for your password.")) {
                    Button(toolInstalled ? "Installed" : "Install") {
                        installingTool = true
                        Task {
                            toolError = await AppHousekeeping.installCommandLineTool()
                            toolInstalled = AppHousekeeping.commandLineToolInstalled
                            installingTool = false
                        }
                    }
                    .disabled(toolInstalled || installingTool)
                }
                SettingsRow(title: "Open commands in", caption: "Where a plugin's Open in Terminal runs, such as Docker's shell or a script command.") {
                    TerminalPicker()
                }
                SettingsRow(title: "More folders for commands", caption: "Plugins and scripts also find programs here, after Homebrew and the system folders. Separate folders with colons, like ~/.cargo/bin:~/.local/bin.") {
                    CommandFoldersField()
                }
            }
            SettingsTransferGroup(model: model)
            SettingsGroup("Reset") {
                SettingsRow(title: "Remove all data", caption: "Moves plugins, saved data, caches and logs to the Trash, deletes Stackbar's secrets and settings, and quits.") {
                    Button("Remove…", role: .destructive) { AppHousekeeping.removeAllData(model: model) }
                }
            }
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
            SettingsGroup("Connect Claude Code", footer: "Run this once in Terminal. Claude Code then starts Stackbar's gateway when it needs a tool. Other MCP clients add the same command, \(Platform.stackbarctlPath) agent, as a stdio server.") {
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
            PluginEditorGroup(model: model)
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
/// Which coding agent "Edit with …" opens on a plugin.
struct PluginEditorGroup: View {
    @Bindable var model: AppModel

    private var footer: String {
        switch model.pluginEditor {
        case .claudeCode, .codex:
            return "Opens in the terminal chosen in General, in the plugin's folder, with Stackbar's authoring tools added to the agent. The folder's AGENTS.md tells any agent how to build and check a plugin."
        case .opencode, .cursor, .pi:
            return "Opens in the terminal chosen in General, in the plugin's folder. The agent reads the folder's AGENTS.md, which shows it how to build and check a plugin with stackbarctl."
        case .custom:
            return "Runs in the plugin's folder, in the terminal chosen in General. {file}, {dir}, {prompt} and {stackbarctl} are replaced, already quoted. The folder's AGENTS.md tells the agent how to build and check a plugin."
        }
    }

    var body: some View {
        SettingsGroup("Edit Plugins With", footer: footer) {
            SettingsRow(title: "Coding agent", caption: "Used by Edit with \(model.pluginEditor.name) on a plugin. Copy Agent Prompt, in a plugin's ⋯ menu, works with any other.") {
                Picker("Coding agent", selection: $model.pluginEditor) {
                    ForEach(PluginEditor.allCases, id: \.self) { editor in
                        Text(editor.title).tag(editor)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if model.pluginEditor == .custom {
                TextField("Command", text: $model.pluginEditorCommand, prompt: Text(PluginEditor.customExample))
                    .font(.system(.callout, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
        }
    }
}

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

/// Everything about one plugin on one page, ordered by the questions a user
/// comes with: is it working (the activity line), what does it need from me
/// (approval, a secret it asked for, a build problem), its own settings,
/// then the rest: secrets it may use, folders, shortcuts and, folded away,
/// permissions and the details for debugging.
struct PluginPage: View {
    let controller: PluginController
    let model: AppModel

    @State private var confirmingUninstall = false
    @State private var showingDiagnostics = false
    @State private var showingPermissions = false
    /// Narrows a long settings surface to the sections that mention it.
    @State private var filter = ""
    /// Titles of the plugin's sections the user folded, remembered per plugin.
    @State private var collapsed: Set<String> = []
    /// The folders the user chose for the plugin, read when the page shows.
    @State private var folders: [String] = []

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
            if let replacement = model.replacement(for: controller) {
                SettingsGroup {
                    SettingsRow(symbol: "arrow.triangle.merge", color: .blue, title: "\(replacement) replaces \(controller.name)",
                                caption: "Everything \(controller.name) did is in \(replacement) now, and its shortcuts and aliases moved there. You can uninstall it.") {
                        Button("Uninstall…") { confirmingUninstall = true }
                    }
                }
            } else if !controller.isEnabled {
                SettingsGroup {
                    SettingsRow(symbol: "power", color: .gray, title: "\(controller.name) is turned off", caption: "It doesn't run, and isn't in the menu bar, the palette or widgets, until you turn it on.")
                }
            }
            activityLine
            if controller.isWaitingForApproval { approval }
            if let problem = controller.problem {
                SettingsGroup {
                    SettingsRow(symbol: "exclamationmark.triangle.fill", color: .red, title: "\(controller.name) didn't build or start", caption: problem) {
                        Button("Rebuild") { controller.reload() }
                    }
                }
            }
            neededSecrets
            pluginSettings
            otherSecrets
            chosenFolders
            shortcuts
            permissions
            diagnostics
            actions
        }
        .onAppear {
            folders = AppModel.folderGrants.folders(for: controller.pluginID)
            collapsed = PluginSettingsFolds.load(controller.pluginID)
        }
        .onChange(of: controller.pluginID) { _, id in
            folders = AppModel.folderGrants.folders(for: id)
            collapsed = PluginSettingsFolds.load(id)
            filter = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: AppModel.folderGrantsChanged)) { _ in
            folders = AppModel.folderGrants.folders(for: controller.pluginID)
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

    /// Under the header: what the plugin is doing now. "Applying your
    /// change…" while a control on this page is being handled, the latest
    /// error with Try Again, or when it last showed something new.
    @ViewBuilder private var activityLine: some View {
        if controller.isEnabled, controller.problem == nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let line = controller.activity.line(now: context.date, isRunning: controller.state == .running) {
                    SettingsGroup {
                        SettingsRow(symbol: Self.symbol(line.kind), color: Self.color(line.kind), title: line.text, caption: line.detail) {
                            switch line.kind {
                            case .applying, .slow:
                                ProgressView().controlSize(.small)
                            case .problem where controller.activity.problem != nil:
                                Button("Try Again") {
                                    controller.dismissProblem()
                                    controller.refresh()
                                }
                                Button("Dismiss") { controller.dismissProblem() }
                            case .problem:
                                Button("Restart") { controller.restart() }
                            case .updated, .waiting:
                                Button("Refresh Now") { controller.refresh() }
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private static func symbol(_ kind: PluginActivity.Line.Kind) -> String {
        switch kind {
        case .applying, .slow: return "arrow.triangle.2.circlepath"
        case .problem: return "exclamationmark.triangle.fill"
        case .updated: return "checkmark.circle.fill"
        case .waiting: return "hourglass"
        }
    }

    private static func color(_ kind: PluginActivity.Line.Kind) -> Color {
        switch kind {
        case .applying, .slow: return .blue
        case .problem: return .orange
        case .updated: return .green
        case .waiting: return .gray
        }
    }

    /// The plugin's own `settings` surface, drawn as grouped sections so it
    /// reads as part of the page. A long one (five or more sections) gets
    /// links to each section, a filter and sections that fold.
    @ViewBuilder private var pluginSettings: some View {
        if controller.isEnabled, manifest?.surfaces.contains(.settings) == true {
            if let node = controller.settings {
                let outline = PluginSettingsOutline(node)
                Group {
                    if outline.isLong {
                        longSettings(outline)
                    } else {
                        NodeView(node: node, send: controller.send)
                    }
                }
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

    @ViewBuilder private func longSettings(_ outline: PluginSettingsOutline) -> some View {
        let parts = outline.filtered(filter)
        SettingsOutlineBar(outline: outline, filter: $filter, allCollapsed: outline.titled.allSatisfy { collapsed.contains($0.title ?? "") }) { part in
            setFolded(part.title, false)
        } toggleAll: { fold in
            collapsed = fold ? Set(outline.titled.compactMap(\.title)) : []
            PluginSettingsFolds.save(collapsed, for: controller.pluginID)
        }
        if parts.isEmpty {
            Text("No settings mention “\(filter)”.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        ForEach(parts, id: \.index) { part in
            if let title = part.title, case .section(_, let children) = part.node {
                let folded = filter.isEmpty && collapsed.contains(title)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { setFolded(title, !folded) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .rotationEffect(.degrees(folded ? 0 : 90))
                            Text(title).font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(folded ? "Show \(title)" : "Fold \(title) away")
                    if !folded {
                        NodeView(node: .section(title: nil, children: children), send: controller.send)
                    }
                }
                .padding(.bottom, folded ? 6 : 0)
                .id(PluginSettingsOutline.anchor(part.index))
            } else {
                NodeView(node: part.node, send: controller.send)
                    .id(PluginSettingsOutline.anchor(part.index))
            }
        }
    }

    private func setFolded(_ title: String?, _ fold: Bool) {
        guard let title else { return }
        if fold { collapsed.insert(title) } else { collapsed.remove(title) }
        PluginSettingsFolds.save(collapsed, for: controller.pluginID)
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
                    let command = manifest?.hotkeyCommand.flatMap { id in entries.first { $0.spec.id == id } }
                    SettingsRow(title: command.map { "Open \($0.spec.title)" } ?? "Open its panel", caption: "Set by the plugin") {
                        KeyCaps(text: KeyCombo.glyphs(hotkey))
                    }
                }
                SettingsRow(title: "Find it in the palette", caption: "Press \(KeyCombo.glyphs(PaletteController.chosenHotKey)) and type \(controller.name).")
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
            SettingsGroup(footer: showingPermissions ? "\(controller.name) runs in its own sandbox and can use only what is listed here." : nil) {
                DisclosureGroup(isExpanded: $showingPermissions) {
                    VStack(alignment: .leading, spacing: 10) {
                        permissionRows(rows)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Permissions")
                    Text(rows.isEmpty ? "Nothing beyond the basics" : "\(rows.count) allowed or asked for in its sandbox").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func permissionRows(_ rows: [SettingsPresentation.PermissionRow]) -> some View {
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

    /// Folders picked with `Stackbar.chooseFolder`: the plugin's commands
    /// may run in them until removed here.
    @ViewBuilder private var chosenFolders: some View {
        let pluginID = controller.pluginID
        if !folders.isEmpty {
            SettingsGroup("Folders you chose", footer: "\(controller.name) can run its commands in these folders. Removing one stops that at once.") {
                ForEach(folders, id: \.self) { folder in
                    SettingsRow(symbol: "folder.fill", color: SettingsPresentation.Access.files.color,
                                title: (folder as NSString).lastPathComponent,
                                caption: (folder as NSString).abbreviatingWithTildeInPath) {
                        Button("Remove") {
                            try? AppModel.folderGrants.remove(folder, for: pluginID)
                            folders = AppModel.folderGrants.folders(for: pluginID)
                        }
                    }
                }
            }
        }
    }

    private var secretGroups: (needed: [String], other: [String]) {
        SettingsPresentation.secretGroups(declared: manifest?.secretNames ?? [], missing: controller.missingSecrets)
    }

    private func secretRow(_ name: String, isNeeded: Bool) -> some View {
        SecretRow(controller: controller, name: name, sharedWith: model.controllers
            .filter { $0 !== controller && $0.manifest?.secretNames.contains(name) == true }
            .map(\.name), isNeeded: isNeeded)
    }

    /// Secrets the plugin asked for and found empty: near the top, because
    /// it can't do its job until they are set.
    @ViewBuilder private var neededSecrets: some View {
        let needed = secretGroups.needed
        if controller.isEnabled, !needed.isEmpty {
            SettingsGroup("Needs you", footer: "\(controller.name) asked for \(needed.count == 1 ? "this" : "these") and couldn't find \(needed.count == 1 ? "it" : "them"). Kept in your Keychain.") {
                ForEach(needed, id: \.self) { secretRow($0, isNeeded: true) }
            }
        }
    }

    /// The other declared secrets. A manifest names every secret the plugin
    /// could use, so an empty one here is not a problem.
    @ViewBuilder private var otherSecrets: some View {
        let other = secretGroups.other
        if !other.isEmpty {
            SettingsGroup(secretGroups.needed.isEmpty ? "Secrets" : "Other secrets", footer: "Kept in your Keychain and shared by name, so changing or clearing one does it for every plugin that uses it. Set only the ones your setup uses.") {
                ForEach(other, id: \.self) { secretRow($0, isNeeded: false) }
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
                    HStack {
                        Text("Log").font(.subheadline.weight(.semibold))
                        Spacer()
                        if !controller.logs.isEmpty {
                            Button("Copy Log") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(controller.logs.joined(separator: "\n"), forType: .string)
                            }
                            .controlSize(.small)
                        }
                    }
                    if controller.logs.isEmpty {
                        Text("Nothing logged since it started.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(controller.logs.suffix(50).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced()).foregroundStyle(line.hasPrefix("[error]") ? Color.orange : Color.primary)
                            .textSelection(.enabled)
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
            Button("Edit with \(model.pluginEditor.name)…") { model.editPlugin(controller.source) }
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
    /// The plugin asked for it and it isn't set.
    var isNeeded = false

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
                    let state = SettingsPresentation.secretState(isSaved: isSaved, isNeeded: isNeeded)
                    Text(state.text).font(.caption).foregroundStyle(state.isWarning ? Color.orange : Color.secondary)
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
        .task { isSaved = await controller.hasSecretOffMain(name) }
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

/// Settings › Terminal › More folders for commands.
struct CommandFoldersField: View {
    @AppStorage(CommandResolver.extraFoldersKey) private var folders = ""

    var body: some View {
        TextField("~/.cargo/bin", text: $folders)
            .frame(width: 220)
    }
}

/// Settings › Command Palette › Tab with text: any fallback command, the
/// default (Ask AI when installed) or nothing.
struct PaletteTabPicker: View {
    let model: AppModel
    @AppStorage(PaletteTabTarget.defaultsKey) private var chosen = ""

    var body: some View {
        let fallbacks = model.commands.registry.entries.filter(\.spec.fallback)
        let preferred = fallbacks.first { $0.key == PaletteTabTarget.preferred }
        Picker("Tab with text", selection: $chosen) {
            Text(preferred.map { "Default (\($0.spec.title))" } ?? "Default (Ask AI, when installed)").tag("")
            ForEach(fallbacks, id: \.key) { entry in
                Text("\(entry.spec.title) — \(entry.pluginName)").tag(entry.key.description)
            }
            Text("Nothing: move focus").tag(PaletteTabTarget.off)
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// The terminals Stackbar can start that are installed, plus the default:
/// whatever opens `.command` files.
struct TerminalPicker: View {
    @AppStorage(TerminalChoice.defaultsKey) private var chosen = ""

    private var installed: [TerminalChoice] {
        TerminalChoice.known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    var body: some View {
        Picker("Open commands in", selection: $chosen) {
            Text("Default (opens .command files)").tag("")
            ForEach(installed) { terminal in
                Text(terminal.name).tag(terminal.bundleID)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}
#endif
