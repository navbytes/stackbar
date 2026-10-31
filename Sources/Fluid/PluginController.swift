#if os(macOS)
import Foundation
import Observation
import FluidHostCore
import FluidProtocol

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
    private(set) var tools: [ToolSpec] = []
    private(set) var problem: String?
    private(set) var building = false
    private(set) var logs: [String] = []
    /// Capabilities the plugin asks for that the user hasn't approved.
    private(set) var pendingApproval: [Capability] = []
    private(set) var isNewInstall = false
    /// Declared secrets the plugin asked for that aren't set.
    private(set) var missingSecrets: [String] = []

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
    }

    var isWaitingForApproval: Bool { !pendingApproval.isEmpty }

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
                let binary = source.pathExtension == "swift" ? try builder.build(source: source).binary : source
                let manifest = try PluginProcess.readManifest(executable: binary)
                if sandbox { try builder.sign(binary: binary, manifest: manifest) }
                return (binary, manifest)
            }.value
            guard generation == loadGeneration else { return }
            let problems = manifest.problems
            if !problems.isEmpty { throw PluginSession.SessionError.badManifest(problems) }
            if let clash = model.controllers.first(where: { $0 !== self && $0.pluginID == manifest.id }) {
                throw LoadError.duplicateID(manifest.id, clash.source.lastPathComponent)
            }
            self.manifest = manifest
            pluginID = manifest.id
            name = manifest.name

            let review = model.ledger.review(manifest)
            switch review {
            case .approved:
                pendingApproval = []
            case .needsApproval(let added, _, _, let isNew):
                pendingApproval = added
                isNewInstall = isNew
            }

            await supervisor?.stop()
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
        Task { await supervisor?.event(action, value: value) }
    }

    func setVisible(_ surface: Surface, _ visible: Bool) {
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
            await supervisor?.stop()
            await supervisor?.start()
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
        case .tools(let specs):
            tools = specs
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
