#if os(macOS)
import AppKit
import Observation
import StackbarHostCore
import StackbarProtocol

/// The Store's state, shared by the Store window and Settings → Store &
/// Updates: the loaded indexes, what is installing, and the last result to
/// show as a toast.
@MainActor
@Observable
final class StoreModel {
    private(set) var catalogs: [PluginStore.Catalog] = []
    private(set) var loading = false
    /// Problems loading an index, in words.
    private(set) var problems: [String] = []
    /// Plugin ids being installed or updated.
    private(set) var installing: Set<String> = []
    private(set) var updatingAll = false
    /// The last thing that happened, for the toast.
    var toast: StoreToast?

    @ObservationIgnored private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var installed: StoreListing.Installed {
        StoreListing.Installed(
            versions: Dictionary(model.installedPlugins.map { ($0.id, $0.version) }, uniquingKeysWith: { first, _ in first }),
            loaded: Set(model.controllers.map(\.pluginID)))
    }

    var updates: [StoreListing.Item] {
        StoreListing.items(catalogs, filter: .updates, installed: installed)
    }

    func state(of entry: PluginIndex.Entry) -> StoreAvailability {
        if let needed = entry.requiredStackbar() { return .needsStackbar(needed) }
        if let record = model.installedPlugins.first(where: { $0.id == entry.id }) {
            return entry.isNewer(than: record.version) ? .update(from: record.version) : .installed
        }
        return model.controller(for: entry.id) != nil ? .installed : .available
    }

    /// Whether the installed plugin is on; nil when it isn't loaded.
    func isOn(_ entry: PluginIndex.Entry) -> Bool? {
        model.controller(for: entry.id)?.isEnabled
    }

    func setOn(_ entry: PluginIndex.Entry, _ on: Bool) {
        model.controller(for: entry.id)?.isEnabled = on
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        model.refreshInstalled()
        let result = await PluginStore.load(model.storeSources, site: true)
        catalogs = result.catalogs
        problems = result.problems
    }

    func find(_ pluginID: String) -> StoreListing.Item? {
        PluginStore.find(pluginID, in: catalogs).map { StoreListing.Item(catalog: $0.catalog, entry: $0.entry) }
    }

    @discardableResult
    func install(_ item: StoreListing.Item, quietly: Bool = false) async -> Bool {
        let entry = item.entry
        installing.insert(entry.id)
        defer { installing.remove(entry.id) }
        let wasInstalled = state(of: entry) != .available
        do {
            try item.catalog.index.checkInstallable(entry)
            let bundle = try await PluginIndex.bundle(for: entry, indexURL: item.catalog.source.url)
            // Verified before the helper, which can be up to 64 MB, is fetched.
            try bundle.verify()
            // Fetched first: on a Mac that can't build plugins, a plugin with
            // no prebuilt helper yet is not installed (or updated) at all.
            let helper = try await model.prebuiltHelper(for: bundle, indexURL: item.catalog.source.url)
            let file = try model.installation.install(bundle, helper: helper)
            if let controller = model.controller(for: entry.id) { controller.reload() } else { model.add(file) }
            model.refreshInstalled()
            if !quietly {
                toast = StoreToast(entry: entry, text: wasInstalled ? "Updated to \(entry.version)" : "Installed. Open it to allow what it asks for.", isError: false)
            }
            return true
        } catch {
            toast = StoreToast(entry: entry, text: "Couldn't install: \(error)", isError: true)
            return false
        }
    }

    /// Installs every update, one at a time. New permissions in an update
    /// still wait for the user's approval when the plugin next asks.
    func updateAll() async {
        updatingAll = true
        defer { updatingAll = false }
        var updated: [String] = []
        var failed: [String] = []
        for item in updates {
            if await install(item, quietly: true) { updated.append(item.entry.name) } else { failed.append(item.entry.name) }
        }
        let text = (updated.isEmpty ? "" : "Updated \(ListFormatter.localizedString(byJoining: updated)).")
            + (failed.isEmpty ? "" : " Couldn't update \(ListFormatter.localizedString(byJoining: failed)).")
        toast = StoreToast(entry: nil, text: text.trimmingCharacters(in: .whitespaces), isError: !failed.isEmpty)
    }

    func uninstall(_ entry: PluginIndex.Entry, deleteData: Bool) async {
        let stuck = await model.uninstall(pluginID: entry.id, deleteData: deleteData)
        if stuck.isEmpty {
            toast = StoreToast(entry: entry, text: "Moved to the Trash" + (deleteData ? " with its data" : ""), isError: false)
        } else {
            toast = StoreToast(entry: entry, text: "Couldn't move \(entry.name) to the Trash; it is still in the plugins folder", isError: true)
        }
    }

    /// Opens an installed plugin: its panel when it has one, otherwise its
    /// Settings page.
    func open(_ entry: PluginIndex.Entry) {
        guard let controller = model.controller(for: entry.id) else { return }
        if controller.isEnabled, controller.manifest?.surfaces.contains(.panel) == true {
            AppDelegate.shared?.showPanel(pluginID: controller.pluginID)
        } else {
            AppDelegate.shared?.showSettings(plugin: controller)
        }
    }
}

/// A result to show briefly at the bottom of the Store.
struct StoreToast: Identifiable, Equatable {
    let id = UUID()
    /// The plugin it is about, for its icon and an Open button.
    var entry: PluginIndex.Entry?
    var text: String
    var isError: Bool
}
#endif
