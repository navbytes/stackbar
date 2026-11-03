#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarProtocol

/// Where a store entry stands against what is installed.
enum StoreAvailability: Equatable {
    case available
    case installed
    case update(from: String)
    case needsStackbar(String)
}

/// Which plugin's page is open in the store.
struct StorePage: Identifiable, Equatable {
    var pluginID: String
    var indexURL: URL
    var id: String { indexURL.absoluteString + "#" + pluginID }
}

/// The plugin store: a grid of cards from the official index and any added
/// ones, filtered by category and by installed or updatable, with a shelf of
/// what's new. A card opens the plugin's page; installing and updating verify
/// the signed bundle.
struct StoreView: View {
    @Bindable var model: AppModel
    @State private var newIndex = ""
    @State private var catalogs: [PluginStore.Catalog] = []
    @State private var query = ""
    @State private var filter = StoreListing.Filter.all
    @State private var category: String?
    @State private var status: String?
    @State private var loading = false
    @State private var updatingAll = false
    @State private var showingSources = false
    /// The plugin whose page is open.
    @State private var page: StorePage?

    private var installed: StoreListing.Installed {
        StoreListing.Installed(
            versions: Dictionary(model.installedPlugins.map { ($0.id, $0.version) }, uniquingKeysWith: { first, _ in first }),
            loaded: Set(model.controllers.map(\.pluginID)))
    }

    private var items: [StoreListing.Item] {
        StoreListing.items(catalogs, query: query, category: category, filter: filter, installed: installed)
    }

    private var updates: [StoreListing.Item] {
        StoreListing.items(catalogs, filter: .updates, installed: installed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            if loading { ProgressView().controlSize(.small) }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    shelf
                    grid
                    sources
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .task { await load() }
        .onChange(of: model.storeFocus) { openFocus() }
        .sheet(item: $page) { page in
            pageSheet(page)
        }
    }

    // MARK: - Parts

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search plugins", text: $query).textFieldStyle(.roundedBorder)
                Picker("Show", selection: $filter) {
                    Text("All").tag(StoreListing.Filter.all)
                    Text("Installed").tag(StoreListing.Filter.installed)
                    Text(updates.isEmpty ? "Updates" : "Updates (\(updates.count))").tag(StoreListing.Filter.updates)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        StoreChip(title: "All", isSelected: category == nil) { category = nil }
                        ForEach(StoreListing.categories(catalogs), id: \.self) { name in
                            StoreChip(title: name, isSelected: category == name) { category = category == name ? nil : name }
                        }
                    }
                }
                if !updates.isEmpty {
                    Button(updatingAll ? "Updating…" : "Update All") { Task { await updateAll() } }
                        .disabled(updatingAll)
                }
                Toggle("Update automatically", isOn: $model.autoUpdatePlugins).toggleStyle(.checkbox)
            }
        }
    }

    /// "New and updated": shown on the unfiltered store only.
    @ViewBuilder private var shelf: some View {
        let recent = StoreListing.recent(catalogs)
        if filter == .all, category == nil, query.isEmpty, !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("New and updated").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recent) { item in
                            StoreShelfCard(item: item) { open(item) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var grid: some View {
        let listed = items
        if listed.isEmpty, !loading {
            VStack(spacing: 6) {
                Text(emptyTitle).font(.headline)
                if filter != .all || category != nil || !query.isEmpty {
                    Button("Show All Plugins") {
                        filter = .all
                        category = nil
                        query = ""
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(listed) { item in
                    let entry = item.entry
                    let controller = model.controller(for: entry.id)
                    StoreCard(item: item, state: state(of: entry), isOn: controller?.isEnabled) {
                        Task { await install(entry, from: item.catalog) }
                    } uninstall: { deleteData in
                        Task { await uninstall(entry, deleteData: deleteData) }
                    } setOn: { on in
                        controller?.isEnabled = on
                    } open: {
                        open(item)
                    }
                }
            }
        }
    }

    private var emptyTitle: String {
        if model.storeSources.isEmpty { return "Add a plugin source below to browse plugins." }
        switch filter {
        case .updates: return "Everything is up to date."
        case .installed: return "Nothing installed from your stores yet."
        case .all: return query.isEmpty ? "No plugins here yet." : "No plugins match “\(query)”."
        }
    }

    /// The stores the list comes from: the signed official index and any the
    /// user added. Anyone can publish one with `stackbarctl index build`.
    private var sources: some View {
        DisclosureGroup("Plugin sources", isExpanded: $showingSources) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.storeSources, id: \.url) { source in
                    HStack {
                        let name = catalogs.first { $0.source.url == source.url }?.index.name
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name ?? source.url.absoluteString)
                            Text(source.isOfficial ? "Signed by navbytes" : source.url.absoluteString)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !source.isOfficial {
                            Button("Remove") {
                                model.indexURLs.removeAll { $0 == source.url.absoluteString }
                                Task { await load() }
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
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
                Text("Anyone can publish an index with `stackbarctl index build`. Plugins from it run in the same sandbox and ask for the same permissions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder private func pageSheet(_ page: StorePage) -> some View {
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

    // MARK: - Actions

    private func open(_ item: StoreListing.Item) {
        page = StorePage(pluginID: item.entry.id, indexURL: item.catalog.source.url)
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

    private func state(of entry: PluginIndex.Entry) -> StoreAvailability {
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

    @discardableResult
    private func install(_ entry: PluginIndex.Entry, from catalog: PluginStore.Catalog) async -> Bool {
        do {
            try catalog.index.checkInstallable(entry)
            let bundle = try await PluginIndex.bundle(for: entry, indexURL: catalog.source.url)
            let file = try model.installer.install(bundle)
            if let controller = model.controller(for: entry.id) { controller.reload() } else { model.add(file) }
            model.refreshInstalled()
            status = "Installed \(entry.name) \(entry.version). Open it from the menu bar to allow what it asks for."
            return true
        } catch {
            status = "Could not install \(entry.name): \(error)"
            return false
        }
    }

    /// Installs every update, one at a time. New permissions in an update
    /// still wait for the user's approval when the plugin next asks.
    private func updateAll() async {
        updatingAll = true
        defer { updatingAll = false }
        var updated: [String] = []
        var failed: [String] = []
        for item in updates {
            if await install(item.entry, from: item.catalog) { updated.append(item.entry.name) } else { failed.append(item.entry.name) }
        }
        status = (updated.isEmpty ? "" : "Updated \(ListFormatter.localizedString(byJoining: updated)).")
            + (failed.isEmpty ? "" : " Could not update \(ListFormatter.localizedString(byJoining: failed)).")
    }

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

/// A category filter.
struct StoreChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The picture a card shows: this version's most telling render from the
/// store's site.json, then the index's screenshot, then the plugin's icon.
struct StoreThumbnail: View {
    let entry: PluginIndex.Entry
    let catalog: PluginStore.Catalog
    var height: CGFloat = 150
    @Environment(\.colorScheme) private var colorScheme

    private var url: URL? {
        let path = catalog.site?.thumbnail(entry.id, version: entry.version)?.path(dark: colorScheme == .dark) ?? entry.screenshot
        return path.flatMap { URL(string: $0, relativeTo: catalog.source.url)?.absoluteURL }
    }

    var body: some View {
        ZStack {
            Rectangle().fill(StorePluginIcon.color(entry.accent).opacity(0.1))
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit().padding(8)
                } placeholder: {
                    StorePluginIcon(entry: entry, size: 44)
                }
            } else {
                StorePluginIcon(entry: entry, size: 44)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

/// One plugin in the grid.
struct StoreCard: View {
    let item: StoreListing.Item
    let state: StoreAvailability
    /// Whether the installed plugin is on; nil when it isn't loaded.
    let isOn: Bool?
    let install: () -> Void
    let uninstall: (_ deleteData: Bool) -> Void
    let setOn: (Bool) -> Void
    /// Opens the plugin's page.
    let open: () -> Void

    private var entry: PluginIndex.Entry { item.entry }
    private var notes: [String]? { item.catalog.site?.about(entry.id)?.notes(for: entry.version) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 8) {
                    StoreThumbnail(entry: entry, catalog: item.catalog)
                    HStack(spacing: 8) {
                        StorePluginIcon(entry: entry, size: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.name).font(.headline).lineLimit(1)
                            Text([entry.version, entry.category].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    if let summary = entry.summary {
                        Text(summary).font(.callout).lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                    }
                    if case .update = state, let first = notes?.first {
                        Text("New: " + first).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            .padding(.horizontal, 12)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(entry.name)'s page")
            Spacer(minLength: 8)
            HStack(alignment: .bottom) {
                Text(item.catalog.source.isOfficial ? "by \(entry.publisher)" : "from \(item.catalog.index.name)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                StoreActions(entry: entry, state: state, isOn: isOn, notes: notes, install: install, uninstall: uninstall, setOn: setOn)
                    .controlSize(.small)
            }
            .padding([.horizontal, .bottom], 12)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A plugin on the "New and updated" shelf.
struct StoreShelfCard: View {
    let item: StoreListing.Item
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                StoreThumbnail(entry: item.entry, catalog: item.catalog, height: 96)
                HStack(spacing: 6) {
                    StorePluginIcon(entry: item.entry, size: 18)
                    Text(item.entry.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                .padding(.horizontal, 8)
                Text(item.entry.updated.map { "\(item.entry.version) · \($0)" } ?? item.entry.version)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], 8)
            }
            .frame(width: 200)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(item.entry.name)'s page")
    }
}
#endif
