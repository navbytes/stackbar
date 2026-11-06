#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarProtocol

/// A plugin's page in the Store, pushed like an App Store page: what the
/// website's plugin page shows, natively. The renders and README come from
/// the store's `site.json`; a store without one still gets the header, the
/// info strip, privacy and details.
struct StorePluginPage: View {
    let item: StoreListing.Item
    let store: StoreModel
    @State private var confirmingUninstall = false
    @Environment(\.colorScheme) private var colorScheme

    private var entry: PluginIndex.Entry { item.entry }
    private var catalog: PluginStore.Catalog { item.catalog }
    private var about: StoreSite.About? { catalog.site?.about(entry.id) }
    /// README facts the page shows elsewhere (Needs under privacy, Surfaces
    /// and Requires in the strip), as the website does.
    private static let shownElsewhere: Set<String> = ["Needs", "Surfaces", "Requires"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                infoStrip
                gallery
                notesAndAbout
                privacy
                features
                details
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(entry.name)
        .toolbar {
            ToolbarItem {
                Menu {
                    StoreItemMenu(item: item, store: store, open: nil, uninstall: { confirmingUninstall = true })
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Turn off, uninstall, share")
            }
        }
        .modifier(UninstallDialog(isPresented: $confirmingUninstall, name: entry.name, canTurnOff: store.isOn(entry) == true) { deleteData in
            Task { await store.uninstall(entry, deleteData: deleteData) }
        } turnOff: {
            store.setOn(entry, false)
        })
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            StorePluginIcon(entry: entry, size: 104)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name).font(.largeTitle.weight(.bold))
                if let author = entry.communityAuthor, let profile = URL(string: "https://github.com/\(author)") {
                    Link("by @\(author)", destination: profile).font(.headline)
                }
                if let summary = entry.summary {
                    Text(summary).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    StoreGetButton(item: item, store: store)
                    if store.isOn(entry) == false { StatusTag(text: "Turned off") }
                    Text(catalog.source.publicKey != nil ? "Signed by \(entry.publisher)" : "From \(catalog.index.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    /// The facts people check before installing, in one row.
    private var infoStrip: some View {
        let kinds = SettingsPresentation.storePermissions(entry).compactMap(\.access)
        let surfaces = (entry.surfaces ?? []).filter { $0 != "settings" }
        let cells: [(String, String, String)] = [
            ("Version", entry.version, entry.updated ?? " "),
            ("Category", entry.category ?? "Other", " "),
            ("Asks For", entry.capabilities.isEmpty ? "Nothing" : "\(entry.capabilities.count)",
             entry.capabilities.isEmpty ? "Fully sandboxed" : ListFormatter.localizedString(byJoining: Array(Set(kinds.map(\.title))).sorted())),
            ("Shows In", surfaces.isEmpty ? "—" : "\(surfaces.count)", surfaces.map { Self.surfaceNames[$0] ?? $0 }.joined(separator: ", ")),
            ("Requires", entry.minimumStackbar.map { "\($0)+" } ?? "Any", "Stackbar"),
        ]
        return VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    if index > 0 { Divider().frame(height: 46) }
                    VStack(spacing: 3) {
                        Text(cell.0.uppercased()).font(.caption2.weight(.semibold)).tracking(0.4).foregroundStyle(.secondary)
                        Text(cell.1).font(.title3.weight(.bold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        Text(cell.2).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                }
            }
            .padding(.vertical, 10)
            Divider()
        }
    }

    @ViewBuilder private var gallery: some View {
        let renders = catalog.site?.renders(entry.id, version: entry.version) ?? []
        if !renders.isEmpty {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(renders, id: \.surface) { render in
                        if let path = render.render.path(dark: colorScheme == .dark), let url = URL(string: path, relativeTo: catalog.source.url) {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: url.absoluteURL) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)).frame(width: 260)
                                }
                                .frame(maxHeight: 340)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                                Text(Self.surfaceNames[render.surface] ?? render.surface).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    /// What's new beside the description, the way the App Store pairs them.
    @ViewBuilder private var notesAndAbout: some View {
        let notes = about?.notes(for: entry.version)
        let paragraphs = about?.paragraphs ?? []
        if notes != nil || !paragraphs.isEmpty {
            HStack(alignment: .top, spacing: 32) {
                if let notes {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("What's New").font(.title3.weight(.bold))
                            Spacer()
                            Text(["Version \(entry.version)", entry.updated].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(Self.markdown(note)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !paragraphs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About").font(.title3.weight(.bold))
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(Self.markdown(paragraph)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// What the plugin may use, as cards, like the App Store's privacy labels.
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy").font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                if entry.capabilities.isEmpty {
                    privacyCard(symbol: "checkmark.shield.fill", color: .green, title: "Asks for nothing", text: "No network, files, commands, secrets or clipboard.")
                }
                ForEach(Array(SettingsPresentation.storePermissions(entry).enumerated()), id: \.offset) { _, permission in
                    let access = permission.access
                    privacyCard(symbol: access?.symbol ?? "lock.fill", color: access?.color ?? .gray, title: access?.title ?? "Access", text: permission.summary)
                }
                privacyCard(symbol: "lock.shield.fill", color: .blue, title: "Sandboxed", text: "Stackbar asks before the plugin can use any of this, and blocks everything else.")
            }
            if let needs = about?.facts.first(where: { $0.label == "Needs" })?.text {
                Text(Self.markdown(needs)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func privacyCard(symbol: String, color: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsIconTile(symbol: symbol, color: color, size: 26)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    @ViewBuilder private var features: some View {
        let facts = (about?.facts ?? []).filter { !Self.shownElsewhere.contains($0.label) }
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What It Does").font(.title3.weight(.bold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.label).font(.subheadline.weight(.semibold))
                            Text(Self.markdown(fact.text)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var details: some View {
        let rows: [(String, String)] = [
            ("Publisher", entry.publisher + (catalog.source.publicKey != nil ? " (signed)" : "")),
            ("Store", catalog.index.name),
            ("Version", entry.version),
            ("Updated", entry.updated ?? "—"),
            ("Category", entry.category ?? "Other"),
            ("Shows in", (entry.surfaces ?? []).filter { $0 != "settings" }.map { Self.surfaceNames[$0] ?? $0 }.joined(separator: ", ")),
            ("Requires", "Stackbar \(entry.minimumStackbar ?? "any version")" + (entry.minimumStackbar == nil ? "" : " or later")),
            ("Id", entry.id),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Information").font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 24, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(rows.filter { !$0.1.isEmpty }, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).font(.caption).foregroundStyle(.secondary)
                        Text(row.1).font(.callout).textSelection(.enabled)
                    }
                }
            }
            HStack(spacing: 16) {
                if let page = catalog.webPage(for: entry) {
                    Link("Web Page", destination: page)
                }
                if let homepage = entry.homepage, let url = URL(string: homepage) {
                    Link(catalog.source.isOfficial ? "Source Code" : "Homepage", destination: url)
                }
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }

    static let surfaceNames = [
        "menuBar": "Menu bar", "panel": "Panel", "window": "Window", "widget": "Desktop widget",
        "settings": "Settings page", "palette": "Command palette",
    ]

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// A store entry's icon: the same tile as an installed plugin's, from the
/// accent and symbol the index carries.
struct StorePluginIcon: View {
    let entry: PluginIndex.Entry
    var size: CGFloat = 40

    var body: some View {
        let category = StoreListing.look(ofCategory: entry.category)
        PluginIcon(symbol: entry.symbol ?? category.symbol, accent: entry.accent.flatMap(Accent.init(rawValue:)) ?? category.accent, size: size)
    }

    /// The tile colour for an entry: its accent, else its category's. An
    /// app that predates a new hue (the index keeps it as a string) uses the
    /// category's too.
    static func color(_ entry: PluginIndex.Entry) -> Color {
        PluginIcon.color(entry.accent.flatMap(Accent.init(rawValue:)) ?? StoreListing.look(ofCategory: entry.category).accent)
    }
}

#endif
