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
    private(set) var palette = PaletteIndex()
    private(set) var agentGatewayError: String?
    /// Which Settings tab is showing, and which plugin's page.
    var settingsTab = SettingsTab.general
    var settingsPlugin: PluginController.ID?
    /// The command Settings → Commands shows.
    var settingsCommand: CommandKey?
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
    /// Commands: the registry, preferences, hotkeys and the runner.
    @ObservationIgnored private(set) var commands: CommandCenter!
    @ObservationIgnored let ledger: CapabilityLedger
    @ObservationIgnored let installer = PluginInstaller(pluginsDirectory: StackbarPaths.pluginsDirectory, publishers: PublisherStore(file: StackbarPaths.publishersFile), recordFile: StackbarPaths.dataDirectory.appendingPathComponent("installed.json"))
    @ObservationIgnored let builder = PluginBuilder(stackbarPackage: StackbarPaths.stackbarPackage(), cacheRoot: StackbarPaths.buildCache)
    @ObservationIgnored let widgets = WidgetSnapshotStore.shared()
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
                open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } },
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
        commands = CommandCenter(model: self, services: services)
    }

    // MARK: - Plugins

    func start() {
        try? FileManager.default.createDirectory(at: StackbarPaths.pluginsDirectory, withIntermediateDirectories: true)
        // First-party plugins now come from the store: turn untouched copies
        // from before into store installs of the same id. Then refresh the
        // examples already installed; installing new ones stays the user's
        // choice (the welcome prompt or the menu item).
        for migration in bundledStore.migrate() { Self.moveDefaults(from: migration.old, to: migration.new) }
        refreshInstalled()
        syncBundled(installMissing: false)
        commands.start()
        for source in Self.discover() { add(source) }
        let watcher = DirectoryWatcher(directory: StackbarPaths.pluginsDirectory)
        watcher.start { [weak self] change in
            Task { @MainActor in self?.apply(change) }
        }
        self.watcher = watcher
        updateAgentGateway()
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
        let review = PluginStore.review(catalogs, installed: installed)
        for withdrawn in review.withdrawn {
            if let controller = controller(for: withdrawn.installed.id) { await remove(controller) }
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: withdrawn.installed.file), resultingItemURL: nil)
            try? installer.forget(withdrawn.installed.id)
            Platform.notify(HostNotification(pluginID: withdrawn.installed.id, pluginName: "Stackbar", title: "Removed a withdrawn plugin", body: "\(withdrawn.installed.id) \(withdrawn.installed.version) was withdrawn by its publisher and is in the Trash: \(withdrawn.reason)"))
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
        let file = try installer.install(bundle)
        if let controller = controller(for: update.entry.id) { controller.reload() } else { add(file) }
        pendingUpdates.removeAll { $0.entry.id == update.entry.id }
        refreshInstalled()
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

    /// Moves a plugin's file to the Trash and forgets it: its approvals, and
    /// the store's record of installing it (so the store offers it again and
    /// the update check doesn't bring it back). Every copy loaded under the
    /// same id goes, so nothing of it is left running.
    func uninstall(_ controller: PluginController) async {
        let id = controller.pluginID
        var files = [controller.source.standardizedFileURL]
        files += installer.installed.filter { $0.id == id }.map { URL(fileURLWithPath: $0.file).standardizedFileURL }
        let doomed = controllers.filter { $0 === controller || $0.pluginID == id || files.contains($0.source.standardizedFileURL) }
        for other in doomed { await remove(other) }
        for file in Set(files) where FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
        }
        try? installer.forget(id)
        try? ledger.revoke(id)
        refreshInstalled()
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
    /// carries (see `BundledStore`), copies the examples (Examples/) into the
    /// plugins folder and updates copies the user hasn't edited (see
    /// `BundledPlugins`). Returns how many were installed or updated.
    @discardableResult
    func installExamples() -> Int {
        let result = syncBundled(installMissing: true)
        for file in result.installed { add(file) }
        let fromStore = bundledStore.installMissing()
        for file in fromStore { add(file) }
        refreshInstalled()
        return result.installed.count + result.updated.count + fromStore.count
    }

    /// The first-party plugins' signed bundles carried in the app.
    var bundledStore: BundledStore {
        BundledStore(bundlesDirectory: builder.stackbarPackage.appendingPathComponent("Bundles", isDirectory: true),
                     pluginsDirectory: StackbarPaths.pluginsDirectory,
                     bundledRecord: StackbarPaths.dataDirectory.appendingPathComponent("bundled.json"),
                     installer: installer)
    }

    /// Per-file preferences follow a plugin whose file was replaced.
    static func moveDefaults(from old: URL, to new: URL) {
        let defaults = UserDefaults.standard
        for prefix in ["hiddenFromMenuBar.", "declaresMenuBar.", "disabled."] {
            if let value = defaults.object(forKey: prefix + old.path) {
                defaults.set(value, forKey: prefix + new.path)
                defaults.removeObject(forKey: prefix + old.path)
            }
        }
    }

    /// Run at launch before discovery, so new versions of the bundled
    /// plugins arrive with a new app.
    @discardableResult
    func syncBundled(installMissing: Bool) -> BundledPlugins.Result {
        let folders = ["Examples"].map { builder.stackbarPackage.appendingPathComponent($0, isDirectory: true) }
        let files = folders.flatMap { folder in
            FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        }
        let bundled = BundledPlugins(directory: StackbarPaths.pluginsDirectory, recordFile: StackbarPaths.dataDirectory.appendingPathComponent("bundled.json"))
        return bundled.sync(files, installMissing: installMissing)
    }

    // MARK: - Cross-plugin features

    func panelChanged(_ controller: PluginController) {
        palette.update(pluginID: controller.pluginID, pluginName: controller.name, panel: controller.panel)
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
        AppDelegate.shared?.palette.open(entry, arguments: target.arguments, source: source)
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
        let server = MCPServer(name: "stackbar", version: StackbarVersion.current, instructions: "Tools from the plugins running in Stackbar. Call stackbar_plugins to see them.", provider: RuntimeTools { await directory.supervisors() })
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
