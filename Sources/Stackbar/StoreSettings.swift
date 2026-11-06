#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarUI

/// Settings → Store & Updates: how plugins update, what is waiting, and the
/// stores the Store window reads. Browsing happens in the Store window.
struct StoreSettings: View {
    @Bindable var model: AppModel
    @State private var newIndex = ""

    private var store: StoreModel { model.store }

    var body: some View {
        SettingsPage {
            SettingsPageHeader(title: "Store & Updates", subtitle: "Find plugins in the Store. Updates are checked once a day.") {
                SettingsIconTile(symbol: SettingsTab.store.symbol, color: SettingsTab.store.color, size: 52)
            } trailing: {
                Button("Open Store") { AppDelegate.shared?.showStore() }
                    .buttonStyle(.borderedProminent)
            }
            AppUpdatesGroup(updater: model.updater)
            SettingsGroup("Plugin Updates", footer: "Updates that ask for something new still wait for you to allow it.") {
                Toggle("Update plugins automatically", isOn: $model.autoUpdatePlugins)
                    .toggleStyle(TrailingSwitchStyle())
                let updates = store.updates
                if updates.isEmpty {
                    SettingsRow(symbol: "checkmark.circle.fill", color: .green, title: "Everything is up to date")
                } else {
                    ForEach(updates) { item in
                        HStack(spacing: 10) {
                            StorePluginIcon(entry: item.entry, size: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.entry.name)
                                Text(versionLine(item)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StoreGetButton(item: item, store: store).controlSize(.small)
                        }
                    }
                    HStack {
                        Spacer()
                        Button(store.updatingAll ? "Updating…" : "Update All") { Task { await store.updateAll() } }
                            .disabled(store.updatingAll)
                    }
                }
            }
            SettingsGroup("Plugin Sources", footer: "Anyone can publish an index with `stackbarctl index build`. Plugins from it run in the same sandbox and ask for the same permissions.") {
                ForEach(model.storeSources, id: \.url) { source in
                    let name = store.catalogs.first { $0.source.url == source.url }?.index.name
                    SettingsRow(symbol: source.isOfficial ? "checkmark.seal.fill" : "shippingbox.fill", color: source.isOfficial ? .blue : .gray,
                                title: name ?? source.url.host() ?? source.url.absoluteString,
                                caption: source.isOfficial ? "Signed by navbytes" : source.url.absoluteString) {
                        if !source.isOfficial {
                            Button("Remove", role: .destructive) {
                                model.indexURLs.removeAll { $0 == source.url.absoluteString }
                                Task { await store.load() }
                            }
                        }
                    }
                }
                HStack {
                    TextField("Add an index URL (https://…/index.json)", text: $newIndex)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addIndex)
                    Button("Add", action: addIndex)
                        .disabled(newIndex.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if !store.problems.isEmpty {
                SettingsGroup("Problems") {
                    ForEach(store.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }
            }
        }
        .task { if store.catalogs.isEmpty { await store.load() } }
    }

    private func versionLine(_ item: StoreListing.Item) -> String {
        let installed = store.installed.versions[item.entry.id].map { "\($0) → " } ?? ""
        return installed + item.entry.version
    }

    private func addIndex() {
        let trimmed = newIndex.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !model.indexURLs.contains(trimmed), trimmed != OfficialIndex.url.absoluteString else { return }
        model.indexURLs.append(trimmed)
        newIndex = ""
        Task { await store.load() }
    }
}
/// Stackbar's own version and Sparkle's settings.
struct AppUpdatesGroup: View {
    @Bindable var updater: Updater

    var body: some View {
        SettingsGroup("Stackbar", footer: updater.isAvailable ? "Stackbar checks for a new version once a day and asks before it installs one." : Updater.unavailableNote) {
            SettingsRow(title: "Version \(StackbarVersion.current)", caption: "What changed in each release is in the release notes.") {
                HStack {
                    Button("Release Notes") { NSWorkspace.shared.open(ProblemReport.releasesURL) }
                    Button("Check for Updates…") { updater.checkForUpdates(nil) }
                        .disabled(updater.isAvailable && !updater.canCheck)
                }
            }
            if updater.isAvailable {
                Toggle("Check for Stackbar updates automatically", isOn: $updater.checksAutomatically)
                    .toggleStyle(TrailingSwitchStyle())
                SettingsRow(title: "Get beta versions", caption: "Try new versions before everyone else. Betas can have rough edges; turn this off to go back to the next regular release.") {
                    Toggle("Get beta versions", isOn: $updater.getsBetas)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }
}
#endif
