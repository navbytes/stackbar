#if os(macOS)
import AppKit
import Observation
import StackbarHostCore
import StackbarProtocol

/// The app's state: the plugins, the services they share, and the things
/// that span plugins (palette, agent gateway, widgets, store).
@MainActor
@Observable
final class AppModel {
    private(set) var controllers: [PluginController] = []
    private(set) var palette = PaletteIndex(includesAppEntries: true)
    private(set) var agentGatewayError: String?
    /// Which Settings page is showing: an app section or a plugin's page.
    var settingsTab = SettingsTab.general
    /// The command Settings → Commands shows.
    var settingsCommand: CommandKey?
    /// The plugin a `stackbar://store/<id>` link asked the Store window to show.
    var storeFocus: String?
    var indexURLs: [String] {
        didSet { UserDefaults.standard.set(indexURLs, forKey: "indexURLs") }
    }
    /// Install newer versions of store plugins without asking. New
    /// capabilities in an update still wait for approval.
    var autoUpdatePlugins: Bool {
        didSet { UserDefaults.standard.set(autoUpdatePlugins, forKey: "autoUpdatePlugins") }
    }
    /// Updates the last store check found and didn't install.
    private(set) var pendingUpdates: [PluginStore.Update] = []
    var agentGatewayEnabled: Bool {
        didSet {
            UserDefaults.standard.set(agentGatewayEnabled, forKey: "agentGateway")
            updateAgentGateway()
        }
    }

    @ObservationIgnored let services: HostServices
    /// Stackbar's own updates (Sparkle, in the release build).
    @ObservationIgnored let updater = Updater()
    /// Commands: the registry, preferences, hotkeys and the runner.
    @ObservationIgnored private(set) var commands: CommandCenter!
    /// The Store's indexes, installs and toasts, shared by the Store window
    /// and Settings.
    @ObservationIgnored private(set) var store: StoreModel!
    @ObservationIgnored let ledger: CapabilityLedger
    /// Which plugins are turned off, by id.
    @ObservationIgnored let switches = PluginSwitches()
    /// Plugins taken over by one that `replaces` them.
    @ObservationIgnored let handover = PluginHandover(file: StackbarPaths.dataDirectory.appendingPathComponent("handovers.json"))
    @ObservationIgnored let installer = PluginInstaller(pluginsDirectory: StackbarPaths.pluginsDirectory, publishers: PublisherStore(file: StackbarPaths.publishersFile), recordFile: StackbarPaths.dataDirectory.appendingPathComponent("installed.json"))
    @ObservationIgnored let builder = PluginBuilder(stackbarPackage: StackbarPaths.stackbarPackage(), cacheRoot: StackbarPaths.buildCache)
    /// Installing, updating and removing plugins, the same way from the
    /// Store, Settings and the update check.
    @ObservationIgnored private(set) var installation: PluginInstallation!
    @ObservationIgnored let widgets = WidgetSnapshotStore.shared()
    /// Presses on widget buttons, left by the widget extension.
    @ObservationIgnored private let widgetActions = WidgetActionInbox.shared()
    /// Which plugin tools agents may use (Settings → Agents).
    @ObservationIgnored let agentConsent = AgentConsent(file: StackbarPaths.dataDirectory.appendingPathComponent("agent-tools.json"))
    /// Plugins run in the App Sandbox unless `STACKBAR_SANDBOX=0` (for
    /// debugging a plugin that needs more than its manifest declares).
    @ObservationIgnored let sandbox = ProcessInfo.processInfo.environment["STACKBAR_SANDBOX"] != "0"
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var agentServer: UnixSocketServer?
    @ObservationIgnored var onPluginsChanged: (() -> Void)?
    @ObservationIgnored private var storeTimer: Timer?

    /// Clipboard images and formatted copies the host keeps for plugins.
    nonisolated static let clipboardImages = ClipboardImageStore(directory: StackbarPaths.dataDirectory.appendingPathComponent("ClipboardImages", isDirectory: true))

    /// Loads kept clipboard images for a plugin's row previews; only for
    /// plugins allowed to read the clipboard.
    static func previewImages(for controller: PluginController) -> (@Sendable (String) -> Data?)? {
        guard controller.manifest?.capabilities.contains(.clipboard) == true else { return nil }
        let store = clipboardImages
        return { id in store.data(for: id) }
    }

    init() {
        indexURLs = UserDefaults.standard.stringArray(forKey: "indexURLs") ?? []
        autoUpdatePlugins = UserDefaults.standard.object(forKey: "autoUpdatePlugins") as? Bool ?? true
        agentGatewayEnabled = UserDefaults.standard.object(forKey: "agentGateway") as? Bool ?? true
        let secretRouter = SecretRouter()
        let ledger = CapabilityLedger(file: StackbarPaths.ledgerFile)
        self.ledger = ledger
        services = HostServices(
            storage: StorageStore(directory: StackbarPaths.storageDirectory),
            secrets: StackbarPaths.defaultSecrets(includeEnvironment: false),
            platform: HostServices.Platform(
                notify: { note in Task { @MainActor in Platform.notify(note) } },
                alert: { note in Task { @MainActor in AlertPresenter.shared.show(note) } },
                playSound: { sound in Task { @MainActor in NSSound(named: NSSound.Name(sound.rawValue))?.play() } },
                hud: { message, isError in Task { @MainActor in HUD.shared.show(message, isError: isError) } },
                open: { url in
                    Task { @MainActor in
                        if let app = AppDelegate.shared { app.route(url) } else { NSWorkspace.shared.open(url) }
                    }
                },
                openWith: { url, bundleID in try await Platform.open(url, with: bundleID) },
                copy: { text in Task { @MainActor in Platform.copy(text) } },
                secretMissing: { pluginID, name in secretRouter.route(pluginID, name) },
                system: MacSystem(images: Self.clipboardImages),
                approvalNeeded: { pluginID in secretRouter.reviewAgain(pluginID) }
            ),
            runs: CommandRunGate(root: StackbarPaths.runDirectory) { pluginID, line in HostLog.shared.write(.info, line, plugin: pluginID) },
            approvedCommands: { ledger.approvedCommandPaths(for: $0) }
        )
        secretRouter.model = self
        installation = PluginInstallation(installer: installer, ledger: ledger, switches: switches, storage: services.storage, secrets: services.secrets,
                                          helpers: .init(directory: builder.downloadedHelpers, stackbarKit: builder.stackbarKit),
                                          trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
        commands = CommandCenter(model: self, services: services)
        // A key layer's assign chord (Right ⌘ ⌥ + a letter) runs the
        // plugin's assign command, as a hotkey would.
        MacKeyLayer.shared.onAssign = { [weak self] key, arguments in
            Task { @MainActor in await self?.commands.run(key, arguments: arguments, source: .hotkey) }
        }
        // A typed keyword runs its plugin's command, which pastes.
        MacTextExpansion.shared.onExpand = { [weak self] key in
            Task { @MainActor in self?.commands.runFromExpansion(key) }
        }
        store = StoreModel(model: self)
    }

    // MARK: - Plugins

    func start() {
        try? FileManager.default.createDirectory(at: StackbarPaths.pluginsDirectory, withIntermediateDirectories: true)
        // Refresh the examples already installed; installing new ones stays
        // the user's choice (the welcome prompt or the menu item).
        refreshInstalled()
        bundledStore.syncExamples()
        // Apps, sums and files in the palette come from plugins.
        if !bundledStore.installCore(offered: StackbarPaths.dataDirectory.appendingPathComponent("core-plugins.json")).isEmpty {
            refreshInstalled()
        }
        commands.start()
        for source in Self.discover() { add(source) }
        let watcher = DirectoryWatcher(directory: StackbarPaths.pluginsDirectory)
        watcher.start { [weak self] change in
            Task { @MainActor in self?.apply(change) }
        }
        self.watcher = watcher
        updateAgentGateway()
        listenForWidgetActions()
        Task { await checkStore() }
        storeTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkStore() }
        }
    }

    // MARK: - Store

    /// The indexes the store reads: the official one first.
    var storeSources: [PluginStore.Source] { PluginStore.sources(userURLs: indexURLs) }

    /// Compares plugins installed from a store with the indexes: installs
    /// updates (or lists them when automatic updates are off) and moves
    /// withdrawn plugins to the Trash.
    func checkStore() async {
        refreshInstalled()
        let installed = installer.installed
        guard !installed.isEmpty else { return }
        let (catalogs, _) = await PluginStore.load(storeSources)
        await refreshHelpers(installed: installed, catalogs: catalogs)
        let review = PluginStore.review(catalogs, installed: installed)
        for withdrawn in review.withdrawn {
            let running = controllers.filter { $0.pluginID == withdrawn.installed.id }
            for controller in running { await remove(controller) }
            let stuck = await installation.withdraw(withdrawn.installed, loaded: running.map(\.source))
            let outcome = stuck.isEmpty ? "is in the Trash" : "could not be moved to the Trash and is still in the plugins folder"
            Platform.notify(HostNotification(pluginID: withdrawn.installed.id, pluginName: "Stackbar", title: "Removed a withdrawn plugin", body: "\(withdrawn.installed.id) \(withdrawn.installed.version) was withdrawn by its publisher and \(outcome): \(withdrawn.reason)"))
        }
        guard autoUpdatePlugins else {
            pendingUpdates = review.updates
            return
        }
        var remaining: [PluginStore.Update] = []
        for update in review.updates {
            if (try? await installUpdate(update)) == nil { remaining.append(update) }
        }
        pendingUpdates = remaining
    }

    /// Downloads, verifies and writes a newer version; the folder watcher
    /// then reloads the plugin.
    func installUpdate(_ update: PluginStore.Update) async throws {
        let bundle = try await PluginIndex.bundle(for: update.entry, indexURL: update.indexURL)
        guard bundle.manifest.id == update.entry.id else { throw PluginBundle.BundleError.manifestMismatch }
        // Verified before the helper, which can be up to 64 MB, is fetched.
        try bundle.verify()
        let helper = try await prebuiltHelper(for: bundle, indexURL: update.indexURL)
        let file = try installation.install(bundle, helper: helper)
        if let controller = controller(for: update.entry.id) { controller.reload() } else { add(file) }
        pendingUpdates.removeAll { $0.entry.id == update.entry.id }
        refreshInstalled()
    }

    // MARK: - Prebuilt helpers

    /// The prebuilt helper to install with a store bundle. Throws when this
    /// Mac can't build the plugin and the store has no helper for it yet, so
    /// an update waits rather than breaking a plugin that runs.
    func prebuiltHelper(for bundle: PluginBundle, indexURL: URL) async throws -> PrebuiltHelpers.Download? {
        let builder = builder
        let toolchain = await Task.detached { PluginBuilder.hasToolchain }.value
        return try await PrebuiltHelpers.prepare(bundle, indexURL: indexURL, builder: builder, toolchain: toolchain)
    }

    /// Fetches helpers that installed store plugins are missing (after a
    /// Stackbar update, or one installed before helpers existed) and restarts
    /// a plugin that failed for want of one.
    private func refreshHelpers(installed: [PluginInstaller.Installed], catalogs: [PluginStore.Catalog]) async {
        let builder = builder
        let publishers = installer.publishers
        let toolchain = await Task.detached { PluginBuilder.hasToolchain }.value
        let refreshed = await PrebuiltHelpers.refresh(installed: installed, catalogs: catalogs, publishers: publishers, builder: builder, toolchain: toolchain)
        for id in refreshed {
            if let controller = controller(for: id), case .failed = controller.state { controller.reload() }
        }
    }

    func stop() async {
        prepareForTermination()
        for controller in controllers { await controller.stop() }
    }

    /// The synchronous part of shutting down: stop watching and serving.
    func prepareForTermination() {
        storeTimer?.invalidate()
        storeTimer = nil
        watcher?.stop()
        agentServer?.stop()
        agentServer = nil
    }

    func add(_ source: URL) {
        let resolved = source.resolvingSymlinksInPath().standardizedFileURL
        guard !controllers.contains(where: { $0.source.resolvingSymlinksInPath().standardizedFileURL == resolved }) else { return }
        let controller = PluginController(source: source, model: self)
        controllers.append(controller)
        onPluginsChanged?()
        Task { await controller.load() }
    }

    func remove(_ controller: PluginController) async {
        await controller.stop()
        controllers.removeAll { $0 === controller }
        palette.remove(pluginID: controller.pluginID)
        commands.forget(pluginID: controller.pluginID)
        widgets.remove(controller.pluginID)
        onPluginsChanged?()
    }

    /// Removes a plugin (see `PluginInstallation.uninstall`): every copy
    /// loaded under the same id stops first, so nothing of it is left
    /// running. Its saved data stays unless `deleteData`, so installing it
    /// again picks up where it left off.
    /// Returns the files that could not be moved to the Trash.
    @discardableResult
    func uninstall(_ controller: PluginController, deleteData: Bool = false) async -> [URL] {
        let id = controller.pluginID
        let providers = controller.manifest?.capabilities.compactMap { capability -> OAuthProvider? in
            if case .oauth(let provider) = capability { return provider }
            return nil
        } ?? []
        let files = installation.files(of: id, loaded: [controller.source])
        let doomed = controllers.filter { $0 === controller || $0.pluginID == id || files.contains($0.source.standardizedFileURL) }
        for other in doomed { await remove(other) }
        let stuck = await installation.uninstall(id, loaded: doomed.map(\.source), deleteData: deleteData, providers: providers)
        refreshInstalled()
        return stuck
    }

    /// Removes an installed plugin by id, whether or not it is loaded.
    @discardableResult
    func uninstall(pluginID: String, deleteData: Bool = false) async -> [URL] {
        if let controller = controller(for: pluginID) {
            return await uninstall(controller, deleteData: deleteData)
        } else {
            let stuck = await installation.uninstall(pluginID, deleteData: deleteData)
            refreshInstalled()
            return stuck
        }
    }

    /// Plugins installed from a store or a bundle, for the store pane.
    private(set) var installedPlugins: [PluginInstaller.Installed] = []

    func refreshInstalled() {
        installedPlugins = installer.installed
    }

    /// A plugin was turned off: take it out of the palette, commands,
    /// widgets and the menu bar until it is turned on again.
    func pluginTurnedOff(_ controller: PluginController) {
        palette.remove(pluginID: controller.pluginID)
        commands.forget(pluginID: controller.pluginID)
        widgets.remove(controller.pluginID)
        onPluginsChanged?()
    }

    /// `manifest`'s plugin is running and reported `commands`: hand over each
    /// plugin it `replaces` that hasn't been yet. Aliases, hotkeys, usage and
    /// favourites move to its commands with the same ids, and the old plugin
    /// is turned off (its page in Settings then offers to uninstall it).
    func handOver(to manifest: Manifest, commands specs: [CommandSpec]) {
        for oldID in handover.pending(for: manifest) {
            let old = controllers.first { $0.pluginID == oldID }
            let wasInstalled = old != nil || installer.installed.contains { $0.id == oldID }
            let oldTitles = Dictionary(commands.registry.commands(for: oldID).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            let moved = handover.hand(from: oldID, to: manifest.id, commands: Dictionary(specs.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }),
                                      oldTitles: oldTitles, preferences: commands.preferences, memory: commands.memory)
            guard wasInstalled else { continue }
            if let old, old.isEnabled {
                old.isEnabled = false
            } else {
                switches.set(oldID, on: false)
            }
            let oldName = old?.name ?? oldID
            let carried = moved.isEmpty ? "" : " Your shortcuts and aliases moved over."
            HostLog.shared.write(.info, "\(manifest.name) replaces \(oldName): turned it off, moved \(moved.count) command preferences", plugin: manifest.id)
            Platform.notify(HostNotification(pluginID: manifest.id, pluginName: "Stackbar", title: "\(manifest.name) replaces \(oldName)",
                                             body: "\(oldName) is turned off and can be uninstalled from Settings.\(carried)"))
        }
    }

    /// The name of the plugin that took `controller`'s plugin over, if one did.
    func replacement(for controller: PluginController) -> String? {
        guard let id = handover.replacement(of: controller.pluginID) else { return nil }
        return controllers.first { $0.pluginID == id }?.name
    }

    func controller(for pluginID: String) -> PluginController? {
        controllers.first { $0.pluginID == pluginID }
    }

    private func apply(_ change: DirectoryWatcher.Change) {
        for file in change.added { add(file) }
        for file in change.removed {
            if let controller = controllers.first(where: { $0.source.standardizedFileURL == file.standardizedFileURL }) {
                Task { await remove(controller) }
            }
        }
        for file in change.modified {
            controllers.first { $0.source.standardizedFileURL == file.standardizedFileURL }?.reload()
        }
    }

    /// `--plugin <path>` arguments, then every `.swift` file in the plugins folder.
    static func discover() -> [URL] {
        var sources: [URL] = []
        let arguments = CommandLine.arguments
        for (index, argument) in arguments.enumerated() where argument == "--plugin" && index + 1 < arguments.count {
            sources.append(URL(fileURLWithPath: arguments[index + 1]))
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: StackbarPaths.pluginsDirectory, includingPropertiesForKeys: nil)) ?? []
        sources += files.filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return sources
    }

    /// Installs the first-party plugins from the signed bundles the app
    /// carries and copies the examples into the plugins folder (see
    /// `BundledStore`). Returns how many files were added.
    @discardableResult
    func installExamples() -> Int {
        let added = bundledStore.installMissing()
        for file in added { add(file) }
        refreshInstalled()
        return added.count
    }

    /// The carried plugins the welcome window's user picked.
    func installStarters(_ ids: Set<String>) {
        for file in bundledStore.install(ids: ids) { add(file) }
        refreshInstalled()
    }

    /// The plugins that ship with the app.
    var bundledStore: BundledStore {
        BundledStore(bundlesDirectory: builder.stackbarPackage.appendingPathComponent("Bundles", isDirectory: true),
                     examplesDirectory: builder.stackbarPackage.appendingPathComponent("Examples", isDirectory: true),
                     pluginsDirectory: StackbarPaths.pluginsDirectory,
                     record: StackbarPaths.dataDirectory.appendingPathComponent("bundled.json"),
                     installer: installer)
    }

    // MARK: - Cross-plugin features

    func panelChanged(_ controller: PluginController) {
        // On a copy: mutating `palette` in place tells an open palette it
        // changed even when this render offered the same things.
        var next = palette
        if next.update(pluginID: controller.pluginID, pluginName: controller.name, panel: controller.panel) { palette = next }
    }

    /// The registry or preferences changed: rebuild the palette's commands.
    func commandsChanged() {
        palette.setCommands(commands.registry.entries, preferences: commands.preferences.all)
    }

    func headlessPanelsChanged(_ controllers: [PluginController]) {
        palette.setHeadlessPanels(controllers.map { (pluginID: $0.pluginID, name: $0.name) })
    }

    /// Opens a command of a plugin in the palette (a row's navigate action,
    /// a link, a hotkey).
    func openCommand(pluginID: String, target: CommandTarget, source: InvocationSource) {
        guard let entry = commands.registry.entry(CommandKey(pluginID: pluginID, commandID: target.command)) else {
            HUD.shared.show("\(target.command) is not a command of this plugin", isError: true)
            return
        }
        commands.start(entry, arguments: target.arguments, source: source)
    }

    /// The widget extension posts a Darwin notification after leaving a
    /// press; presses left while Stackbar was starting are read at once.
    private func listenForWidgetActions() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let model = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in model.drainWidgetActions() }
        }, WidgetActionInbox.notification as CFString, nil, .deliverImmediately)
        drainWidgetActions()
    }

    /// Sends each waiting widget press to its plugin, as a panel click would.
    func drainWidgetActions() {
        for press in widgetActions.drain() {
            controller(for: press.pluginID)?.send(press.action, press.value)
        }
    }

    func widgetChanged(_ controller: PluginController) {
        guard let node = controller.widget else { return }
        try? widgets.write(WidgetSnapshot(pluginID: controller.pluginID, name: controller.name, node: node))
        Platform.reloadWidgets()
    }

    func secretMissing(pluginID: String, name: String) {
        controller(for: pluginID)?.secretMissing(name)
    }

    func runningSupervisors() -> [PluginSupervisor] {
        controllers.compactMap(\.supervisor)
    }

    private func updateAgentGateway() {
        agentServer?.stop()
        agentServer = nil
        agentGatewayError = nil
        guard agentGatewayEnabled else { return }
        let directory = AgentDirectory(model: self)
        let server = MCPServer(name: "stackbar", version: StackbarVersion.current, instructions: "Tools from the plugins running in Stackbar. Call stackbar_plugins to see them.", provider: RuntimeTools(consent: agentConsent) { await directory.supervisors() })
        do {
            try FileManager.default.createDirectory(at: StackbarPaths.dataDirectory, withIntermediateDirectories: true)
            agentServer = try UnixSocketServer(path: StackbarPaths.agentSocket.path) { line in await server.handle(line: line) }
        } catch {
            agentGatewayError = "\(error)"
        }
    }
}

/// Lets the services (which are Sendable and built before the model) reach
/// the model when a plugin asks for a secret the user hasn't entered.
final class SecretRouter: @unchecked Sendable {
    @MainActor weak var model: AppModel?

    func route(_ pluginID: String, _ name: String) {
        Task { @MainActor in self.model?.secretMissing(pluginID: pluginID, name: name) }
    }

    /// A plugin's declared command moved: its approval shows again.
    func reviewAgain(_ pluginID: String) {
        Task { @MainActor in self.model?.controller(for: pluginID)?.reviewAgain() }
    }
}

/// The running plugins, read on the main actor for the agent gateway.
final class AgentDirectory: @unchecked Sendable {
    @MainActor private weak var model: AppModel?

    @MainActor init(model: AppModel) { self.model = model }

    func supervisors() async -> [PluginSupervisor] {
        await MainActor.run { model?.runningSupervisors() ?? [] }
    }
}
#endif
