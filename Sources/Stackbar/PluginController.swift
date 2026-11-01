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
    private(set) var panel: ViewNode?
    private(set) var window: ViewNode?
    private(set) var widget: ViewNode?
    /// The plugin's page in Settings, when its manifest lists `.settings`.
    private(set) var settings: ViewNode?
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

    @ObservationIgnored private(set) var supervisor: PluginSupervisor?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0

    init(source: URL, model: AppModel) {
        self.id = source.path
        self.source = source
        self.model = model
        self.name = source.deletingPathExtension().lastPathComponent
        self.pluginID = source.path
        hiddenFromMenuBar = UserDefaults.standard.bool(forKey: "hiddenFromMenuBar." + source.path)
    }

    /// Whether the plugin draws in the menu bar: it lists `.menuBar` (or did
    /// last time, while it builds) and the user hasn't hidden it.
    var showsInMenuBar: Bool {
        let declares = manifest.map { $0.surfaces.contains(.menuBar) }
            ?? (UserDefaults.standard.object(forKey: "declaresMenuBar." + source.path) as? Bool ?? true)
        return declares && !hiddenFromMenuBar
    }

    /// A plugin with a panel and no menu-bar item opens it centered instead.
    var hasHeadlessPanel: Bool {
        !showsInMenuBar && manifest?.surfaces.contains(.panel) == true
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
        loadGeneration += 1
        let generation = loadGeneration
        building = true
        problem = nil
        state = .starting
        defer { if generation == loadGeneration { building = false } }
        let source = source
        let builder = model.builder
        let sandbox = model.sandbox
        do {
            let (binary, manifest) = try await Task.detached {
                let built = source.pathExtension == "swift" ? try builder.build(source: source).binary : source
                let manifest = try PluginProcess.readManifest(executable: built)
                // The sandboxed copy is what runs; the manifest was read from
                // the unsigned build, which has the same code.
                let binary = sandbox ? try builder.sign(binary: built, manifest: manifest) : built
                return (binary, manifest)
            }.value
            guard generation == loadGeneration else { return }
            let problems = manifest.problems
            if !problems.isEmpty { throw PluginSession.SessionError.badManifest(problems) }
            if let clash = model.controllers.first(where: { $0 !== self && $0.pluginID == manifest.id }) {
                throw LoadError.duplicateID(manifest.id, clash.source.lastPathComponent)
            }
            let showedInMenuBar = showsInMenuBar
            self.manifest = manifest
            pluginID = manifest.id
            name = manifest.name
            UserDefaults.standard.set(manifest.surfaces.contains(.menuBar), forKey: "declaresMenuBar." + source.path)
            if showsInMenuBar != showedInMenuBar || manifest.surfaces.contains(.panel) { model.onPluginsChanged?() }

            let review = model.ledger.review(manifest)
            switch review {
            case .approved:
                pendingApproval = []
            case .needsApproval(let added, _, _, let isNew):
                pendingApproval = added
                isNewInstall = isNew
            }

            await supervisor?.stop()
            // A newer load (the file changed again) or a stop ran while the
            // old helper was stopping; starting this one too would leave a
            // helper running that nothing refers to.
            guard generation == loadGeneration else { return }
            updatesTask?.cancel()
            let (updates, continuation) = AsyncStream.makeStream(of: PluginSupervisor.Update.self)
            let next = PluginSupervisor(executable: binary, manifest: manifest, grantedCapabilities: review.granted, services: model.services) { continuation.yield($0) }
            supervisor = next
            // One consumer, so updates are applied in the order they happened.
            updatesTask = Task { [weak self] in
                for await update in updates { self?.apply(update) }
            }
            await next.start()
        } catch {
            guard generation == loadGeneration else { return }
            state = .failed("could not start")
            problem = "\(error)"
        }
    }

    /// The source changed on disk: rebuild and restart, keeping the last
    /// trees on screen meanwhile.
    func reload() {
        Task { await load() }
    }

    func stop() async {
        // A build still running for this plugin must not start it afterwards.
        loadGeneration += 1
        building = false
        updatesTask?.cancel()
        await supervisor?.stop()
        supervisor = nil
        state = .stopped
    }

    func approve() {
        guard let manifest, let model else { return }
        do {
            try model.ledger.approve(manifest)
            pendingApproval = []
            isNewInstall = false
            Task {
                await supervisor?.grant(manifest.capabilities)
                await supervisor?.refresh()
            }
        } catch {
            problem = "could not save the approval: \(error)"
        }
    }

    func send(_ action: ActionID, _ value: EventValue?) {
        // A row action that opens one of the plugin's commands is the host's
        // to perform; the plugin never hears about it.
        for root in [panel, window, settings].compactMap({ $0 }) {
            if let target = root.rows.flatMap(\.actions).first(where: { $0.id == action })?.navigate {
                model?.openCommand(pluginID: pluginID, target: target, source: .panel)
                return
            }
        }
        Task { await supervisor?.event(action, value: value) }
    }

    func setVisible(_ surface: Surface, _ visible: Bool) {
        if surface == .panel && visible { panelShownCount += 1 }
        Task { await supervisor?.setVisible(surface, visible) }
    }

    func refresh() {
        Task { await supervisor?.refresh() }
    }

    func wake() {
        Task { await supervisor?.wake() }
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

    func networkReport() -> [String] {
        guard let manifest, let model else { return [] }
        return model.services.audit.report(for: manifest).lines
    }

    private func apply(_ update: PluginSupervisor.Update) {
        switch update {
        case .state(let newState):
            if case .restarting = newState { model?.commands.pluginRestarted(pluginID) }
            state = newState
        case .render(.menuBar, let root):
            menuBar = root
        case .render(.panel, let root):
            panel = root
            model?.panelChanged(self)
        case .render(.window, let root):
            window = root
        case .render(.widget, let root):
            widget = root
            model?.widgetChanged(self)
        case .render(.settings, let root):
            settings = root
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
