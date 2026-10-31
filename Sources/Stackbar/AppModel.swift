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
    var indexURLs: [String] {
        didSet { UserDefaults.standard.set(indexURLs, forKey: "indexURLs") }
    }
    var agentGatewayEnabled: Bool {
        didSet {
            UserDefaults.standard.set(agentGatewayEnabled, forKey: "agentGateway")
            updateAgentGateway()
        }
    }

    @ObservationIgnored let services: HostServices
    @ObservationIgnored let ledger = CapabilityLedger(file: StackbarPaths.ledgerFile)
    @ObservationIgnored let installer = PluginInstaller(pluginsDirectory: StackbarPaths.pluginsDirectory, publishers: PublisherStore(file: StackbarPaths.publishersFile), recordFile: StackbarPaths.dataDirectory.appendingPathComponent("installed.json"))
    @ObservationIgnored let builder = PluginBuilder(stackbarPackage: StackbarPaths.stackbarPackage(), cacheRoot: StackbarPaths.buildCache)
    @ObservationIgnored let widgets = WidgetSnapshotStore.shared()
    /// Plugins run in the App Sandbox unless `STACKBAR_SANDBOX=0` (for
    /// debugging a plugin that needs more than its manifest declares).
    @ObservationIgnored let sandbox = ProcessInfo.processInfo.environment["STACKBAR_SANDBOX"] != "0"
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var agentServer: UnixSocketServer?
    @ObservationIgnored var onPluginsChanged: (() -> Void)?

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
        agentGatewayEnabled = UserDefaults.standard.object(forKey: "agentGateway") as? Bool ?? true
        let secretRouter = SecretRouter()
        services = HostServices(
            storage: StorageStore(directory: StackbarPaths.storageDirectory),
            secrets: StackbarPaths.defaultSecrets(includeEnvironment: false),
            platform: HostServices.Platform(
                notify: { note in Task { @MainActor in Platform.notify(note) } },
                alert: { note in Task { @MainActor in AlertPresenter.shared.show(note) } },
                open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } },
                copy: { text in Task { @MainActor in Platform.copy(text) } },
                secretMissing: { pluginID, name in secretRouter.route(pluginID, name) },
                system: MacSystem(images: Self.clipboardImages)
            )
        )
        secretRouter.model = self
    }

    // MARK: - Plugins

    func start() {
        try? FileManager.default.createDirectory(at: StackbarPaths.pluginsDirectory, withIntermediateDirectories: true)
        for source in Self.discover() { add(source) }
        let watcher = DirectoryWatcher(directory: StackbarPaths.pluginsDirectory)
        watcher.start { [weak self] change in
            Task { @MainActor in self?.apply(change) }
        }
        self.watcher = watcher
        updateAgentGateway()
    }

    func stop() async {
        prepareForTermination()
        for controller in controllers { await controller.stop() }
    }

    /// The synchronous part of shutting down: stop watching and serving.
    func prepareForTermination() {
        watcher?.stop()
        agentServer?.stop()
        agentServer = nil
    }

    func add(_ source: URL) {
        guard !controllers.contains(where: { $0.source.standardizedFileURL == source.standardizedFileURL }) else { return }
        let controller = PluginController(source: source, model: self)
        controllers.append(controller)
        onPluginsChanged?()
        Task { await controller.load() }
    }

    func remove(_ controller: PluginController) async {
        await controller.stop()
        controllers.removeAll { $0 === controller }
        palette.remove(pluginID: controller.pluginID)
        widgets.remove(controller.pluginID)
        onPluginsChanged?()
    }

    /// Deletes a plugin's file (to the Trash) and forgets its approvals.
    func uninstall(_ controller: PluginController) async {
        await remove(controller)
        try? FileManager.default.trashItem(at: controller.source, resultingItemURL: nil)
        try? ledger.revoke(controller.pluginID)
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

    /// Copies the bundled plugins (Plugins/) and examples (Examples/) into the
    /// plugins folder, skipping any already there.
    @discardableResult
    func installExamples() -> Int {
        let folders = ["Plugins", "Examples"].map { builder.stackbarPackage.appendingPathComponent($0, isDirectory: true) }
        let files = folders.flatMap { folder in
            FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        }
        var count = 0
        for file in files {
            let destination = StackbarPaths.pluginsDirectory.appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            if (try? FileManager.default.copyItem(at: file, to: destination)) != nil {
                add(destination)
                count += 1
            }
        }
        return count
    }

    // MARK: - Cross-plugin features

    func panelChanged(_ controller: PluginController) {
        palette.update(pluginID: controller.pluginID, pluginName: controller.name, panel: controller.panel)
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
