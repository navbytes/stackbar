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

/// A plugin's page in the Store, pushed onto the Store's navigation stack.
struct StorePage: Hashable, Identifiable {
    var pluginID: String
    var indexURL: URL
    var id: String { indexURL.absoluteString + "#" + pluginID }

    init(pluginID: String, indexURL: URL) {
        self.pluginID = pluginID
        self.indexURL = indexURL
    }

    init(_ item: StoreListing.Item) {
        self.init(pluginID: item.entry.id, indexURL: item.catalog.source.url)
    }
}

/// What the Store's sidebar can show.
enum StoreSection: Hashable {
    case discover
    case category(String)
    case installed
    case updates

    var title: String {
        switch self {
        case .discover: return "Discover"
        case .category(let name): return name
        case .installed: return "Installed"
        case .updates: return "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .discover: return "sparkles"
        case .installed: return "square.stack.3d.up.fill"
        case .updates: return "arrow.down.circle.fill"
        case .category(let name): return StoreListing.look(ofCategory: name).symbol
        }
    }

    var color: Color {
        switch self {
        case .discover: return .blue
        case .installed: return .gray
        case .updates: return .teal
        case .category(let name): return PluginIcon.color(StoreListing.look(ofCategory: name).accent)
        }
    }
}

/// The Store window: a sidebar of Discover, categories and your library,
/// and a stack you push plugin pages onto, like the App Store.
struct StoreBrowser: View {
    @Bindable var model: AppModel
    let store: StoreModel
    @State private var section: StoreSection? = .discover
    @State private var path: [StorePage] = []
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                root
                    .navigationDestination(for: StorePage.self) { page in
                        pluginPage(page)
                    }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search plugins")
        .toolbar {
            if !store.updates.isEmpty {
                ToolbarItem {
                    Button(store.updatingAll ? "Updating…" : "Update All") { Task { await store.updateAll() } }
                        .disabled(store.updatingAll)
                }
            }
            ToolbarItem {
                Button {
                    Task { await store.load() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Check the stores again")
                .disabled(store.loading)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                StoreToastView(toast: toast, store: store)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.toast)
        .task {
            await store.load()
            openFocus()
        }
        .onChange(of: model.storeFocus) { openFocus() }
        .onChange(of: section) { path = [] }
        .onChange(of: query) { if !query.isEmpty { path = [] } }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            sidebarLabel(.discover)
            Section("Categories") {
                ForEach(StoreListing.categories(store.catalogs), id: \.self) { name in
                    sidebarLabel(.category(name))
                }
            }
            Section("Library") {
                sidebarLabel(.installed)
                sidebarLabel(.updates, badge: store.updates.count)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sourcesLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button("Sources and Updates…") { AppDelegate.shared?.showSettings(tab: .store) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    /// A sidebar row. The tag must be the row's outermost modifier: a
    /// `.badge` applied after it hides the tag from the list's selection,
    /// and the row stops responding to clicks.
    private func sidebarLabel(_ section: StoreSection, badge: Int = 0) -> some View {
        Label {
            Text(section.title)
        } icon: {
            SettingsIconTile(symbol: section.symbol, color: section.color)
        }
        .badge(badge)
        .tag(section)
    }

    private var sourcesLine: String {
        let names = store.catalogs.map { $0.source.isOfficial ? "\($0.index.name) (signed)" : $0.index.name }
        return names.isEmpty ? "No stores loaded" : "From " + ListFormatter.localizedString(byJoining: names)
    }

    // MARK: - Pages

    @ViewBuilder private var root: some View {
        if store.catalogs.isEmpty {
            if store.loading {
                ProgressView("Loading the Store…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Can't Reach the Store", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(store.problems.isEmpty ? "No plugin sources are set up." : store.problems.joined(separator: "\n"))
                } actions: {
                    Button("Try Again") { Task { await store.load() } }
                }
            }
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            StoreListPage(title: "Results", items: StoreListing.items(store.catalogs, query: query, installed: store.installed), store: store,
                          empty: "No plugins match “\(query)”.") { path.append(StorePage($0)) }
        } else {
            switch section ?? .discover {
            case .discover:
                DiscoverPage(store: store, open: { path.append(StorePage($0)) }, seeAll: { section = $0 })
            case .category(let name):
                StoreListPage(title: name, items: StoreListing.items(store.catalogs, category: name, installed: store.installed), store: store,
                              empty: "Nothing in \(name) yet.") { path.append(StorePage($0)) }
            case .installed:
                StoreListPage(title: "Installed", items: StoreListing.items(store.catalogs, filter: .installed, installed: store.installed), store: store,
                              empty: "Nothing installed from your stores yet.") { path.append(StorePage($0)) }
            case .updates:
                StoreListPage(title: "Updates", items: store.updates, store: store, empty: "Everything is up to date.") { path.append(StorePage($0)) }
            }
        }
    }

    @ViewBuilder private func pluginPage(_ page: StorePage) -> some View {
        if let catalog = store.catalogs.first(where: { $0.source.url == page.indexURL }),
           let entry = catalog.index.search("").first(where: { $0.id == page.pluginID }) {
            StorePluginPage(item: StoreListing.Item(catalog: catalog, entry: entry), store: store)
        } else {
            ContentUnavailableView("No Longer Listed", systemImage: "puzzlepiece.extension", description: Text("This plugin was removed from its store."))
        }
    }

    /// Opens the page a `stackbar://store/<id>` link asked for, once the
    /// stores have loaded.
    private func openFocus() {
        guard let id = model.storeFocus, !store.loading, !store.catalogs.isEmpty else { return }
        model.storeFocus = nil
        query = ""
        if let item = store.find(id) {
            path = [StorePage(item)]
        } else {
            store.toast = StoreToast(entry: nil, text: "None of your stores lists \(id).", isError: true)
        }
    }
}

// MARK: - Discover

struct DiscoverPage: View {
    let store: StoreModel
    let open: (StoreListing.Item) -> Void
    let seeAll: (StoreSection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let featured = StoreListing.featured(store.catalogs, installed: store.installed) {
                    StoreHero(item: featured, store: store) { open(featured) }
                }
                let recent = StoreListing.recent(store.catalogs)
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        StoreSectionHeader(title: "New and Updated")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recent) { item in
                                    StoreShelfCard(item: item) { open(item) }
                                }
                            }
                        }
                    }
                }
                ForEach(StoreListing.categories(store.catalogs), id: \.self) { name in
                    let items = StoreListing.items(store.catalogs, category: name, installed: store.installed)
                    VStack(alignment: .leading, spacing: 4) {
                        StoreSectionHeader(title: name, action: items.count > 6 ? { seeAll(.category(name)) } : nil)
                        StoreRowGrid(items: Array(items.prefix(6)), store: store, open: open)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Discover")
    }
}

/// A heading over a shelf or list, with an optional See All.
struct StoreSectionHeader: View {
    let title: String
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let action {
                Button("See All", action: action).buttonStyle(.link)
            }
        }
    }
}

/// The featured plugin, large, on its own colour.
struct StoreHero: View {
    let item: StoreListing.Item
    let store: StoreModel
    let open: () -> Void

    private var entry: PluginIndex.Entry { item.entry }
    private var color: Color { StorePluginIcon.color(entry) }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(["Featured", entry.category].compactMap { $0 }.joined(separator: " · ").uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 12) {
                    StorePluginIcon(entry: entry, size: 48)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    Text(entry.name).font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                }
                if let summary = entry.summary {
                    Text(summary)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    StoreGetButton(item: item, store: store, onColor: true)
                    Button("Learn More", action: open)
                        .buttonStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 380, alignment: .leading)
            Spacer(minLength: 0)
            StoreThumbnail(entry: entry, catalog: item.catalog, height: 200, plain: true)
                .frame(maxWidth: 340)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .onTapGesture(perform: open)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 250)
        .background {
            ZStack {
                LinearGradient(colors: [color, color.mix(with: .black, by: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Lists

/// A page of plugins: a title, then rows in two columns.
struct StoreListPage: View {
    let title: String
    let items: [StoreListing.Item]
    let store: StoreModel
    let empty: String
    let open: (StoreListing.Item) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(empty, systemImage: title == "Updates" ? "checkmark.circle" : "puzzlepiece.extension")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.largeTitle.weight(.bold))
                        StoreRowGrid(items: items, store: store, open: open)
                    }
                    .padding(24)
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(title)
    }
}

struct StoreRowGrid: View {
    let items: [StoreListing.Item]
    let store: StoreModel
    let open: (StoreListing.Item) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 28, alignment: .top)], alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                StoreRow(item: item, store: store) { open(item) }
            }
        }
    }
}

/// One plugin in a list: icon, name and summary open its page; one button
/// does the obvious thing; the rest is in the right-click menu.
struct StoreRow: View {
    let item: StoreListing.Item
    let store: StoreModel
    let open: () -> Void
    @State private var confirmingUninstall = false

    private var entry: PluginIndex.Entry { item.entry }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        StorePluginIcon(entry: entry, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.headline).lineLimit(1)
                            Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show \(entry.name)'s page")
                StoreGetButton(item: item, store: store)
            }
            .padding(.vertical, 12)
        }
        .contextMenu {
            StoreItemMenu(item: item, store: store, open: open) { confirmingUninstall = true }
        }
        .modifier(UninstallDialog(isPresented: $confirmingUninstall, name: entry.name, canTurnOff: store.isOn(entry) == true) { deleteData in
            Task { await store.uninstall(entry, deleteData: deleteData) }
        } turnOff: {
            store.setOn(entry, false)
        })
    }

    private var subtitle: String {
        if case .update = store.state(of: entry), let first = item.catalog.site?.about(entry.id)?.notes(for: entry.version)?.first {
            return "New in \(entry.version): " + first
        }
        return entry.summary ?? entry.category ?? ""
    }
}

/// Get, Update or Open, as a capsule; a spinner while it installs.
struct StoreGetButton: View {
    let item: StoreListing.Item
    let store: StoreModel
    /// Drawn on the hero's colour rather than the window background.
    var onColor = false

    private var entry: PluginIndex.Entry { item.entry }

    var body: some View {
        Group {
            if store.installing.contains(entry.id) {
                ProgressView().controlSize(.small).frame(width: 72)
            } else {
                switch store.state(of: entry) {
                case .available:
                    capsule("Get", prominent: true) { Task { await store.install(item) } }
                        .help("Install \(entry.name) \(entry.version)")
                case .update(let from):
                    capsule("Update", prominent: true) { Task { await store.install(item) } }
                        .help("Update from \(from) to \(entry.version)")
                case .installed:
                    capsule("Open", prominent: false) { store.open(entry) }
                        .help(store.isOn(entry) == false ? "\(entry.name) is turned off: opens its Settings page" : "Open \(entry.name)")
                case .needsStackbar(let version):
                    Text("Needs Stackbar \(version)").font(.caption).foregroundStyle(onColor ? .white.opacity(0.8) : .secondary)
                }
            }
        }
        .animation(.snappy, value: store.installing.contains(entry.id))
    }

    @ViewBuilder private func capsule(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let label = Text(title).font(.callout.weight(.bold)).frame(minWidth: 52)
        if onColor {
            Button(action: action) { label.foregroundStyle(.black.opacity(0.85)) }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.white)
        } else if prominent {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}

/// The items of a plugin's "…" and right-click menus.
struct StoreItemMenu: View {
    let item: StoreListing.Item
    let store: StoreModel
    var open: (() -> Void)?
    let uninstall: () -> Void

    private var entry: PluginIndex.Entry { item.entry }

    private var isInstalled: Bool {
        switch store.state(of: entry) {
        case .installed, .update: return true
        case .available, .needsStackbar: return false
        }
    }

    var body: some View {
        if let open { Button("Show Page", action: open) }
        if let isOn = store.isOn(entry) {
            Button(isOn ? "Turn Off" : "Turn On") { store.setOn(entry, !isOn) }
        }
        if isInstalled {
            Button("Uninstall…", role: .destructive, action: uninstall)
        }
        Divider()
        if let page = item.catalog.webPage(for: entry) {
            Button("Copy Link") { Platform.copy(page.absoluteString) }
            Button("Open Web Page") { NSWorkspace.shared.open(page) }
        }
        if let homepage = entry.homepage, let url = URL(string: homepage) {
            Button(item.catalog.source.isOfficial ? "View Source" : "Open Homepage") { NSWorkspace.shared.open(url) }
        }
    }
}

// MARK: - Pictures and cards

/// The picture a card shows: this version's most telling render from the
/// store's site.json, then the index's screenshot, then the plugin's icon.
struct StoreThumbnail: View {
    let entry: PluginIndex.Entry
    let catalog: PluginStore.Catalog
    var height: CGFloat = 150
    /// No tinted backdrop: the hero draws its own.
    var plain = false
    @Environment(\.colorScheme) private var colorScheme

    private var url: URL? {
        let path = catalog.site?.thumbnail(entry.id, version: entry.version)?.path(dark: colorScheme == .dark) ?? entry.screenshot
        return path.flatMap { URL(string: $0, relativeTo: catalog.source.url)?.absoluteURL }
    }

    var body: some View {
        ZStack {
            if !plain {
                Rectangle().fill(StorePluginIcon.color(entry).opacity(0.12))
            }
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
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

/// A plugin on the "New and Updated" shelf.
struct StoreShelfCard: View {
    let item: StoreListing.Item
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                StoreThumbnail(entry: item.entry, catalog: item.catalog, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                HStack(spacing: 8) {
                    StorePluginIcon(entry: item.entry, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.entry.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(item.entry.updated.map { "\(item.entry.version) · \($0)" } ?? item.entry.version)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 230)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(item.entry.name)'s page")
    }
}

/// The result of an install, update or uninstall, briefly, at the bottom.
struct StoreToastView: View {
    let toast: StoreToast
    let store: StoreModel

    var body: some View {
        HStack(spacing: 10) {
            if let entry = toast.entry {
                StorePluginIcon(entry: entry, size: 24)
            } else {
                Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toast.isError ? .orange : .green)
            }
            Group {
                if let entry = toast.entry {
                    Text("\(Text(entry.name).fontWeight(.semibold)) \(toast.text)")
                } else {
                    Text(toast.text)
                }
            }
            .lineLimit(2)
            .textSelection(.enabled)
            if let entry = toast.entry, !toast.isError, store.state(of: entry) == .installed {
                Button("Open") { store.open(entry) }.buttonStyle(.link)
            }
            Button {
                store.toast = nil
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(toast.isError ? 8 : 4))
            if store.toast?.id == toast.id { store.toast = nil }
        }
    }
}
#endif
