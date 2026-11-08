#if os(macOS)
import Foundation
import Observation
import StackbarHostCore
import StackbarProtocol

/// One plugin as the UI sees it: its build, its approvals, its supervisor,
/// and the latest trees for each surface, observable by SwiftUI and AppKit.
@MainActor
@Observable
final class PluginController: Identifiable {
    let id: String
    let source: URL
    private(set) var name: String
    private(set) var pluginID: String
    private(set) var manifest: Manifest?
    private(set) var state: PluginSupervisor.State = .stopped
    private(set) var menuBar: ViewNode?
    /// The trees as the plugin sent them. Surfaces draw `panel`, `window`
    /// and `settings`, which show an armed confirmation (`confirmer`).
    private var panelTree: ViewNode?
    private var windowTree: ViewNode?
    private(set) var widget: ViewNode?
    private var settingsTree: ViewNode?
    /// The host's "press again" for this plugin's actions that carry
    /// `confirm` (protocol 25): one arm across its panel, window, settings
    /// and the palette's rows from its panel.
    private(set) var confirmer = ActionConfirmer()
    var panel: ViewNode? { panelTree.map { confirmer.decorate($0, surface: .panel) } }
    var window: ViewNode? { windowTree.map { confirmer.decorate($0, surface: .window) } }
    /// The plugin's page in Settings, when its manifest lists `.settings`.
    var settings: ViewNode? { settingsTree.map { confirmer.decorate($0, surface: .settings) } }
    /// What a left click on the status item does, when not the panel.
    private(set) var menuBarClick: MenuBarClick?
    private(set) var tools: [ToolSpec] = []
    private(set) var commands: [CommandSpec] = []
    /// The user took the plugin's item out of the menu bar (Settings).
    var hiddenFromMenuBar: Bool {
        didSet {
            guard hiddenFromMenuBar != oldValue else { return }
            UserDefaults.standard.set(hiddenFromMenuBar, forKey: "hiddenFromMenuBar." + source.path)
            model?.onPluginsChanged?()
        }
    }
    /// The plugin's menu bar drew nothing at all last time (protocol 17), so
    /// its item is out of the bar until it draws something; its panel opens
    /// from the palette meanwhile. Remembered across launches so the item
    /// doesn't flash in while the plugin starts.
    private(set) var menuBarIdle: Bool {
        didSet {
            guard menuBarIdle != oldValue else { return }
            UserDefaults.standard.set(menuBarIdle, forKey: "menuBarIdle." + source.path)
            model?.onPluginsChanged?()
        }
    }
    /// The user turned the plugin off (Settings or the store): it is listed
    /// but not built or run, and it shows nowhere else. Kept by plugin id
    /// (`PluginSwitches`), so it survives the file moving.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if let id = manifest?.id ?? model?.switches.knownID(for: source) {
                model?.switches.set(id, on: isEnabled)
            } else {
                UserDefaults.standard.set(!isEnabled, forKey: "disabled." + source.path)
            }
            if isEnabled {
                reload()
            } else {
                Task { await turnOff() }
            }
        }
    }
    private(set) var problem: String?
    private(set) var building = false
    private(set) var logs: [String] = []
    /// Capabilities the plugin asks for that the user hasn't approved.
    private(set) var pendingApproval: [Capability] = []
    private(set) var isNewInstall = false
    /// Declared secrets the plugin asked for that aren't set.
    private(set) var missingSecrets: [String] = []
    /// Counts popover openings, so searchable lists reset and take focus.
    private(set) var panelShownCount = 0
    /// Goes up each time remote images the trees name finish loading, so
    /// the surfaces that show them draw again.
    private(set) var imageGeneration = 0

    @ObservationIgnored private(set) var supervisor: PluginSupervisor?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    /// The newest load's build, cancelled when a newer load or a stop comes.
    @ObservationIgnored private var buildTicket: BuildTicket?
    /// Drops the arm when its window passes, so the control can't keep
    /// saying "Press again" after a press would arm it anew.
    @ObservationIgnored private var confirmExpiry: Task<Void, Never>?

    init(source: URL, model: AppModel) {
        self.id = source.path
        self.source = source
        self.model = model
        self.name = UserDefaults.standard.string(forKey: "pluginName." + source.path) ?? source.deletingPathExtension().lastPathComponent
        self.pluginID = model.switches.knownID(for: source) ?? source.path
        hiddenFromMenuBar = UserDefaults.standard.bool(forKey: "hiddenFromMenuBar." + source.path)
        menuBarIdle = UserDefaults.standard.bool(forKey: "menuBarIdle." + source.path)
        isEnabled = model.switches.isOn(file: source)
    }

    /// Whether the plugin draws in the menu bar: it lists `.menuBar` (or did
    /// last time, while it builds), the user hasn't hidden it, and its menu
    /// bar isn't empty right now.
    var showsInMenuBar: Bool {
        declaresMenuBar && !hiddenFromMenuBar && !menuBarIdle && isEnabled
    }

    var declaresMenuBar: Bool {
        manifest.map { $0.surfaces.contains(.menuBar) }
            ?? (UserDefaults.standard.object(forKey: "declaresMenuBar." + source.path) as? Bool ?? true)
    }

    /// A plugin with a panel and no menu-bar item opens it centered instead.
    var hasHeadlessPanel: Bool {
        isEnabled && !showsInMenuBar && manifest?.surfaces.contains(.panel) == true
    }

    var isWaitingForApproval: Bool { !pendingApproval.isEmpty }
    /// Granted `.context`: commands get what the user was in.
    var readsContext: Bool { manifest?.capabilities.contains(.context) == true && !pendingApproval.contains(.context) }

    /// A declared command now resolves to another program: show the
    /// approval again, and stop granting that command until the user agrees.
    func reviewAgain() {
        guard let manifest, let model else { return }
        let review = model.ledger.review(manifest)
        guard case .needsApproval(let added, _, let granted, let isNew) = review else { return }
        pendingApproval = added
        isNewInstall = isNew
        Task { await supervisor?.grant(granted) }
    }

    /// Builds the plugin if it is a `.swift` file, checks its capabilities
    /// against what was approved, then starts its helper.
    func load() async {
        guard let model else { return }
        // A plugin that is off isn't built at all: it costs nothing and
        // asks for nothing until it is turned on.
        guard isEnabled else {
            await turnOff()
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        // A build of an older version still waiting its turn is skipped.
        buildTicket?.cancel()
        let ticket = BuildTicket()
        buildTicket = ticket
        building = true
        problem = nil
        state = .starting
        defer { if generation == loadGeneration { building = false } }
        let source = source
        let loader = PluginLoader(builder: model.builder, sandbox: model.sandbox)
        do {
            let loaded = try await loader.loadInBackground(source, ticket: ticket)
            guard generation == loadGeneration else { return }
            let manifest = loaded.manifest
            // Just installed from the Store: what was built must be what
            // was signed, or the install is undone.
            try model.installation.confirm(manifest, file: source)
            if let clash = model.controllers.first(where: { $0 !== self && $0.pluginID == manifest.id }) {
                throw LoadError.duplicateID(manifest.id, clash.source.lastPathComponent)
            }
            let showedInMenuBar = showsInMenuBar
            self.manifest = manifest
            pluginID = manifest.id
            name = manifest.name
            UserDefaults.standard.set(manifest.surfaces.contains(.menuBar), forKey: "declaresMenuBar." + source.path)
            UserDefaults.standard.set(manifest.name, forKey: "pluginName." + source.path)
            if !model.switches.adopt(manifest.id, for: source) { isEnabled = false }
            if showsInMenuBar != showedInMenuBar || manifest.surfaces.contains(.panel) { model.onPluginsChanged?() }

            let review = model.ledger.review(manifest)
            switch review {
            case .approved:
                pendingApproval = []
            case .needsApproval(let added, _, _, let isNew):
                pendingApproval = added
                isNewInstall = isNew
            }

            guard isEnabled else {
                await turnOff()
                return
            }

            await supervisor?.stop()
            // A newer load (the file changed again) or a stop ran while the
            // old helper was stopping; starting this one too would leave a
            // helper running that nothing refers to.
            guard generation == loadGeneration else { return }
            updatesTask?.cancel()
            let (updates, continuation) = AsyncStream.makeStream(of: PluginSupervisor.Update.self)
            let next = PluginSupervisor(executable: loaded.binary, manifest: manifest, grantedCapabilities: review.granted, services: model.services) { continuation.yield($0) }
            supervisor = next
            // One consumer, so updates are applied in the order they happened.
            updatesTask = Task { [weak self] in
                for await update in updates { self?.apply(update) }
            }
            await next.start()
        } catch {
            guard generation == loadGeneration else { return }
            // The helper from the last good build is still running: stop it,
            // or its updates would flip the state back from failed.
            updatesTask?.cancel()
            updatesTask = nil
            let previous = supervisor
            supervisor = nil
            state = .failed("could not start")
            problem = "\(error)"
            await previous?.stop()
        }
    }

    /// The source changed on disk: rebuild and restart, keeping the last
    /// trees on screen meanwhile.
    func reload() {
        Task { await load() }
    }

    /// Stops the helper and clears what the plugin showed, keeping its
    /// manifest so Settings can still name it.
    private func turnOff() async {
        await stop()
        menuBar = nil
        panelTree = nil
        windowTree = nil
        widget = nil
        settingsTree = nil
        cancelConfirmation()
        menuBarClick = nil
        tools = []
        commands = []
        problem = nil
        model?.pluginTurnedOff(self)
    }

    func stop() async {
        // A build still running for this plugin must not start it afterwards.
        loadGeneration += 1
        buildTicket?.cancel()
        buildTicket = nil
        building = false
        updatesTask?.cancel()
        await supervisor?.stop()
        supervisor = nil
        state = .stopped
        cancelConfirmation()
    }

    /// Saves the approval and grants it to the running helper. The task
    /// ends once the helper has it, so a command started after it is
    /// allowed what it asks for; nil when the approval couldn't be saved.
    @discardableResult
    func approve() -> Task<Void, Never>? {
        guard let manifest, let model else { return nil }
        do {
            try model.ledger.approve(manifest)
            pendingApproval = []
            isNewInstall = false
            let supervisor = supervisor
            return Task {
                await supervisor?.grant(manifest.capabilities)
                await supervisor?.refresh()
            }
        } catch {
            problem = "could not save the approval: \(error)"
            return nil
        }
    }

    /// A click, toggle or field from a surface (`SendAction`).
    func send(_ action: ActionID, _ value: EventValue?) {
        press(action, value)
    }

    /// Sends a press to the plugin; false when it was held for a second
    /// press instead (the palette stays open for it).
    @discardableResult
    func press(_ action: ActionID, _ value: EventValue?) -> Bool {
        // A row action that opens one of the plugin's commands is the host's
        // to perform; the plugin never hears about it.
        for root in [panelTree, windowTree, settingsTree].compactMap({ $0 }) {
            if let target = root.rows.flatMap(\.actions).first(where: { $0.id == action })?.navigate {
                model?.openCommand(pluginID: pluginID, target: target, source: .panel)
                return true
            }
        }
        // An action that carries `confirm` is held on its first press: the
        // host says so and redraws, and only a second press reaches the
        // plugin.
        let trees: [(Surface, ViewNode?)] = [(.panel, panelTree), (.window, windowTree), (.settings, settingsTree)]
        let found = trees.first { $0.1?.actions.contains(action) == true }
        let wasArmed = confirmer.arm != nil
        if case .armed(let arm) = confirmer.press(action, surface: found?.0, in: found?.1) {
            HUD.shared.show(arm.prompt)
            VoiceOver.announce(arm.prompt)
            scheduleExpiry(arm.deadline)
            armChanged()
            return false
        }
        if wasArmed { armChanged() }
        Task { await supervisor?.event(action, value: value) }
        return true
    }

    /// The palette lists the panel's rows, so it hears when one arms or
    /// stops being armed.
    private func armChanged() {
        model?.panelChanged(self)
    }

    /// Whether a press of `action` would be held for confirmation: the
    /// widget opens the panel for these instead of arming, since it can't
    /// redraw in time.
    func asksToConfirm(_ action: ActionID) -> Bool {
        [panelTree, windowTree, settingsTree, widget].contains { $0?.confirmations[action] != nil }
    }

    /// Esc, or the surface closing: forget an arm.
    func cancelConfirmation(_ surface: Surface? = nil) {
        guard confirmer.cancel(surface: surface) else { return }
        confirmExpiry?.cancel()
        confirmExpiry = nil
        armChanged()
    }

    private func scheduleExpiry(_ deadline: Date) {
        confirmExpiry?.cancel()
        confirmExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow) + 0.05))
            guard !Task.isCancelled, let self, self.confirmer.expire() else { return }
            VoiceOver.announce("Cancelled")
            self.armChanged()
        }
    }

    func setVisible(_ surface: Surface, _ visible: Bool) {
        if surface == .panel && visible { panelShownCount += 1 }
        if !visible { cancelConfirmation(surface) }
        Task { await supervisor?.setVisible(surface, visible) }
    }

    func refresh() {
        Task { await supervisor?.refresh() }
    }

    func wake() {
        Task { await supervisor?.wake() }
    }

    func displaysChanged() {
        Task { await supervisor?.displaysChanged() }
    }

    func appsChanged() {
        Task { await supervisor?.appsChanged() }
    }

    func remindersChanged() {
        Task { await supervisor?.remindersChanged() }
    }

    func restart() {
        Task {
            guard let current = supervisor else { return }
            await current.stop()
            // Restart only the helper that was stopped, not a newer one.
            guard current === supervisor else { return }
            await current.start()
        }
    }

    func secretMissing(_ secret: String) {
        if !missingSecrets.contains(secret) { missingSecrets.append(secret) }
    }

    func saveSecret(_ secret: String, value: String) {
        guard let model else { return }
        do {
            try model.services.secrets.setSecret(value.trimmingCharacters(in: .whitespacesAndNewlines), for: secret)
            missingSecrets.removeAll { $0 == secret }
            refresh()
        } catch {
            problem = "could not save \(secret): \(error)"
        }
    }

    /// `hasSecret` read off the main thread: a Keychain read can block (or
    /// prompt), which would freeze a page that is only opening.
    func hasSecretOffMain(_ secret: String) async -> Bool {
        guard let secrets = model?.services.secrets else { return false }
        return await Task.detached { ((try? secrets.secret(secret)) ?? nil)?.isEmpty == false }.value
    }

    /// Whether a value is saved for `secret`. The Keychain is the only store
    /// the app reads (environment variables are for the CLI), so this is what
    /// plugins get.
    func hasSecret(_ secret: String) -> Bool {
        guard let model else { return false }
        return ((try? model.services.secrets.secret(secret)) ?? nil)?.isEmpty == false
    }

    /// Forgets a saved secret. Secrets are shared by name, so every plugin that
    /// declares it loses it; the next time one asks, its panel prompts again.
    func clearSecret(_ secret: String) {
        guard let model else { return }
        do {
            try model.services.secrets.setSecret(nil, for: secret)
            refresh()
        } catch {
            problem = "could not clear \(secret): \(error)"
        }
    }

    func networkReport() -> [String] {
        guard let manifest, let model else { return [] }
        return model.services.audit.report(for: manifest).lines
    }

    /// Loads a tree's remote images for the panel, window and settings
    /// surfaces, from the domains the user approved the plugin to reach.
    var remoteImages: (@Sendable (String) -> Data?)? {
        _ = imageGeneration
        guard let images = model?.services.images else { return nil }
        return { images.data(for: $0) }
    }

    private func loadImages(_ root: ViewNode) {
        guard let manifest, let images = model?.services.images, !root.imageURLs.isEmpty else { return }
        let pending = Set(pendingApproval.flatMap { capability -> [String] in
            if case .network(let hosts) = capability { return hosts }
            return []
        })
        let hosts = manifest.networkHosts.filter { !pending.contains($0) }
        let pluginID = manifest.id
        Task { [weak self] in
            let loaded = await images.load(root, pluginID: pluginID, allowedHosts: hosts)
            if !loaded.isEmpty { self?.imageGeneration += 1 }
        }
    }

    private func apply(_ update: PluginSupervisor.Update) {
        switch update {
        case .state(let newState):
            if newState != state { model?.commands.pluginStateChanged(pluginID, newState) }
            state = newState
        case .render(.menuBar, let root):
            menuBar = root
            menuBarIdle = root.isNothing
        case .render(.panel, let root):
            panelTree = root
            confirmer.rendered(root, surface: .panel)
            model?.panelChanged(self)
            loadImages(root)
        case .render(.window, let root):
            windowTree = root
            confirmer.rendered(root, surface: .window)
            loadImages(root)
        case .render(.widget, let root):
            widget = root
            model?.widgetChanged(self)
        case .render(.settings, let root):
            settingsTree = root
            confirmer.rendered(root, surface: .settings)
            loadImages(root)
        case .menuBarClick(let click):
            menuBarClick = click
        case .tools(let specs):
            tools = specs
        case .commands(let specs):
            commands = specs
            model?.commands.commandsChanged(self, specs)
        case .view(let session, let seq, let root):
            model?.commands.received(session: session, seq: seq, root: root)
        case .log(let level, let message):
            logs.append("[\(level.rawValue)] \(message)")
            if logs.count > 300 { logs.removeFirst(logs.count - 300) }
        }
    }

    enum LoadError: Error, CustomStringConvertible {
        case duplicateID(String, String)

        var description: String {
            switch self {
            case .duplicateID(let id, let other): return "\(other) already uses the id \(id). Give this plugin its own id in its manifest."
            }
        }
    }
}
#endif
