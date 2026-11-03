#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarProtocol

/// A plugin's page in Settings → Store: what the website's plugin page shows,
/// natively. The renders and README come from the store's `site.json`; a
/// store without one still gets the header, permissions and details.
struct StorePluginPage: View {
    let entry: PluginIndex.Entry
    let catalog: PluginStore.Catalog
    let state: StoreAvailability
    let isOn: Bool?
    let install: () -> Void
    let uninstall: (_ deleteData: Bool) -> Void
    let setOn: (Bool) -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var about: StoreSite.About? { catalog.site?.about(entry.id) }
    /// README facts the page shows elsewhere (Needs under permissions,
    /// Surfaces and Requires under details), as the website does.
    private static let shownElsewhere: Set<String> = ["Needs", "Surfaces", "Requires"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    whatsNew
                    gallery
                    if let about, !about.paragraphs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(about.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(Self.markdown(paragraph)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    permissions
                    features
                    details
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer.padding(12)
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 520, idealHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            StorePluginIcon(entry: entry, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).font(.title.weight(.semibold))
                if let summary = entry.summary { Text(summary).font(.title3).foregroundStyle(.secondary) }
                Text(["by \(entry.publisher)", entry.version, entry.category].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StoreActions(entry: entry, state: state, isOn: isOn, notes: about?.notes(for: entry.version), install: install, uninstall: uninstall, setOn: setOn)
        }
    }

    /// The README's notes for this version. An update shows them first, so
    /// the user sees what they're getting before choosing Update.
    @ViewBuilder private var whatsNew: some View {
        if let notes = about?.notes(for: entry.version) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What's new in \(entry.version)").font(.headline)
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(Self.markdown(note)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(StorePluginIcon.color(entry.accent).opacity(0.1)))
        }
    }

    @ViewBuilder private var gallery: some View {
        let renders = catalog.site?.renders(entry.id, version: entry.version) ?? []
        if !renders.isEmpty {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(renders, id: \.surface) { item in
                        if let path = item.render.path(dark: colorScheme == .dark), let url = URL(string: path, relativeTo: catalog.source.url) {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: url.absoluteURL) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)).frame(width: 220)
                                }
                                .frame(maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
                                Text(Self.surfaceNames[item.surface] ?? item.surface).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What it asks for").font(.headline)
            if entry.capabilities.isEmpty {
                Label("Nothing. No network, files or secrets.", systemImage: "checkmark.shield")
            } else {
                ForEach(entry.capabilities, id: \.self) { Label($0, systemImage: "lock") }
                if let needs = about?.facts.first(where: { $0.label == "Needs" })?.text {
                    Text(Self.markdown(needs)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Stackbar asks before the plugin can use any of it.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder private var features: some View {
        let facts = (about?.facts ?? []).filter { !Self.shownElsewhere.contains($0.label) }
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("What it does").font(.headline)
                ForEach(facts, id: \.label) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label).font(.subheadline.weight(.semibold))
                        Text(Self.markdown(fact.text)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var details: some View {
        let rows: [(String, String)] = [
            ("Version", entry.version),
            ("Updated", entry.updated ?? "—"),
            ("Category", entry.category ?? "Other"),
            ("Shows in", (entry.surfaces ?? []).filter { $0 != "settings" }.map { Self.surfaceNames[$0] ?? $0 }.joined(separator: ", ")),
            ("Requires", "Stackbar \(entry.minimumStackbar ?? "any version")" + (entry.minimumStackbar == nil ? "" : " or later")),
            ("Publisher", entry.publisher + (catalog.source.publicKey != nil ? " (signed)" : "")),
        ]
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(rows.filter { !$0.1.isEmpty }, id: \.0) { row in
                GridRow {
                    Text(row.0).foregroundStyle(.secondary)
                    Text(row.1).textSelection(.enabled)
                }
            }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            if let page = catalog.webPage(for: entry) {
                Link("Open Web Page", destination: page)
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(page.absoluteString, forType: .string)
                }
                .help("Copies \(page.absoluteString)")
            }
            if let homepage = entry.homepage, let url = URL(string: homepage) {
                Link(catalog.source.isOfficial ? "View Source" : "Homepage", destination: url)
            }
            Spacer()
            Button("Done", action: close).keyboardShortcut(.defaultAction)
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
        PluginIcon(symbol: entry.symbol, accent: entry.accent.flatMap(Accent.init(rawValue:)), size: size)
    }

    /// The tile colour for an index's accent name. An app that predates a
    /// new hue (the index keeps it as a string) shows grey.
    static func color(_ accent: String?) -> Color {
        PluginIcon.color(accent.flatMap(Accent.init(rawValue:)))
    }
}

/// Install, Update, Turn On/Off and Uninstall for one store entry, shared by
/// the list row and the plugin page.
struct StoreActions: View {
    let entry: PluginIndex.Entry
    let state: StoreAvailability
    let isOn: Bool?
    /// This version's release notes, shown on the Update button.
    var notes: [String]?
    let install: () -> Void
    let uninstall: (_ deleteData: Bool) -> Void
    let setOn: (Bool) -> Void
    @State private var confirmingUninstall = false

    var body: some View {
        Group {
            switch state {
            case .available: Button("Install", action: install)
            case .installed:
                VStack(alignment: .trailing) {
                    if isOn == false { OffBadge() }
                    HStack {
                        onOffButton
                        Button("Uninstall…", role: .destructive) { confirmingUninstall = true }
                    }
                }
            case .update(let from):
                VStack(alignment: .trailing) {
                    if isOn == false { OffBadge() }
                    Button("Update to \(entry.version)", action: install)
                        .help(updateHelp(from: from))
                    HStack {
                        onOffButton.buttonStyle(.link)
                        Button("Uninstall…", role: .destructive) { confirmingUninstall = true }.buttonStyle(.link)
                    }
                }
            case .needsStackbar(let version): Text("Needs Stackbar \(version)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .modifier(UninstallDialog(isPresented: $confirmingUninstall, name: entry.name, canTurnOff: isOn == true, uninstall: uninstall) {
            setOn(false)
        })
    }

    private func updateHelp(from installed: String) -> String {
        var lines = ["Installed: \(installed)"]
        if let notes {
            lines.append("")
            lines.append("What's new:")
            lines.append(contentsOf: notes.map { "• " + $0 })
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder private var onOffButton: some View {
        if let isOn {
            Button(isOn ? "Turn Off" : "Turn On") { setOn(!isOn) }
                .help(isOn ? "Stops it and takes it out of the menu bar, the palette and widgets. Its settings and data stay." : "Runs it again")
        }
    }
}
#endif
