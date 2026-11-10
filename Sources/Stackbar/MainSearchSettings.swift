#if os(macOS)
import AppKit
import SwiftUI
import StackbarHostCore
import StackbarProtocol
import StackbarUI

/// Settings › General: which plugins answer in the palette's main search,
/// the alias that searches only one of them, and the fallbacks offered when
/// little matches (palette-root-commands). A plugin asks for the main search
/// with `.rootSearch()`; the user decides here.
struct MainSearchSection: View {
    @Bindable var model: AppModel

    private var center: CommandCenter { model.commands }

    var body: some View {
        // Read so a change from Settings → Commands or the palette redraws this.
        let _ = center.revision
        let searchers = center.registry.entries.filter { $0.spec.rootSearch && $0.spec.kind == .view && center.preferences[$0.key].enabled }
        if !searchers.isEmpty {
            SettingsGroup("Main Search", footer: "Plugins that answer what you type in the palette. Off, a plugin still answers after its alias and a space.") {
                ForEach(searchers, id: \.key) { entry in
                    SettingsRow(symbol: entry.spec.symbol ?? "magnifyingglass", color: .indigo,
                                title: entry.spec.rootSection.map { "\(entry.pluginName) · \($0)" } ?? entry.pluginName,
                                caption: Self.caption(entry)) {
                        MainSearchAliasField(center: center, entry: entry)
                        Toggle("", isOn: Binding(get: { RootSearchGate.isOn(entry, preference: center.preferences[entry.key]) },
                                                 set: { on in update(entry.key) { $0.inRootSearch = on } }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help("Show results in the main search")
                    }
                }
            }
        }
        let available = center.registry.entries.filter { RootSearchGate.offersFallback($0.spec, preference: center.preferences[$0.key]) }
        if !available.isEmpty {
            let chosen = center.fallbacks
            let byKey = Dictionary(available.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            // The offered ones in their order, then the rest.
            let ordered = chosen.compactMap { byKey[$0] } + available.filter { !chosen.contains($0.key) }
            SettingsGroup("Fallbacks", footer: "Offered for what you typed when fewer than \(PaletteFallbacks.threshold) results match, in this order. Tab hands the text to Ask AI either way.") {
                ForEach(ordered, id: \.key) { entry in
                    let position = chosen.firstIndex(of: entry.key)
                    SettingsRow(symbol: entry.spec.symbol ?? "arrow.turn.down.right", color: .teal, title: entry.spec.title, caption: entry.pluginName) {
                        if let position {
                            Button { move(entry.key, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless)
                                .disabled(position == 0)
                                .accessibilityLabel("Move Up")
                            Button { move(entry.key, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless)
                                .disabled(position == chosen.count - 1)
                                .accessibilityLabel("Move Down")
                        }
                        Toggle("", isOn: Binding(get: { position != nil }, set: { center.setFallback(entry.key, offered: $0) }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help("Offer as a fallback")
                    }
                }
            }
        }
    }

    /// When the command answers: any text, or only text of its shape.
    static func caption(_ entry: CommandRegistry.Entry) -> String {
        let when = entry.spec.rootPattern == nil ? "Answers any text" : "Answers only text of its own shape"
        return RootSearchGate.defaultOn(entry) ? when : when + " · off unless you turn it on"
    }

    private func update(_ key: CommandKey, _ change: (inout CommandPreference) -> Void) {
        var next = center.preferences[key]
        change(&next)
        try? center.set(next, for: key)
    }

    private func move(_ key: CommandKey, by offset: Int) {
        var list = center.fallbacks
        guard let from = list.firstIndex(of: key) else { return }
        let to = from + offset
        guard list.indices.contains(to) else { return }
        list.swapAt(from, to)
        center.setFallbacks(list)
    }
}

/// A command's alias, as in Settings → Commands: the default shows until
/// the user types another, and emptying the field drops it.
private struct MainSearchAliasField: View {
    let center: CommandCenter
    let entry: CommandRegistry.Entry
    @State private var alias = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(entry.spec.defaultAlias ?? "Alias", text: $alias)
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
            .onDisappear(perform: save)
            .onAppear { alias = center.alias(of: entry.key) ?? "" }
            .help(problem ?? "Type this and a space in the palette to search only \(entry.pluginName)")
    }

    private func save() {
        let typed = alias.trimmingCharacters(in: .whitespaces).lowercased()
        guard typed != (center.alias(of: entry.key) ?? "") else { return }
        let suggested = entry.spec.defaultAlias
        var next = center.preferences[entry.key]
        next.alias = typed == suggested ? nil : (typed.isEmpty && suggested == nil ? nil : typed)
        do {
            try center.set(next, for: entry.key)
            problem = nil
        } catch {
            problem = "\(error)"
            alias = center.alias(of: entry.key) ?? ""
            NSSound.beep()
        }
    }
}
#endif
