#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI
import StackbarHostCore
import StackbarProtocol

/// Settings → Commands: every plugin's commands, with the alias, hotkey,
/// on/off switch and link permission the user gives each one.
struct CommandsSettings: View {
    @Bindable var model: AppModel
    @State private var query = ""

    private var center: CommandCenter { model.commands }

    var body: some View {
        // Read so edits elsewhere (the palette's Disable) redraw this.
        let _ = center.revision
        let entries = center.registry.entries.filter(matches)
        let plugins = Dictionary(grouping: entries, by: \.pluginID)
        let order = entries.map(\.pluginID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search commands", text: $query).textFieldStyle(.roundedBorder)
            if entries.isEmpty {
                Text(center.registry.entries.isEmpty ? "No plugin has commands yet. Plugins add them with `var commands`." : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(order, id: \.self) { pluginID in
                            Section(plugins[pluginID]?.first?.pluginName ?? pluginID) {
                                ForEach(plugins[pluginID] ?? [], id: \.key) { entry in
                                    CommandSettingsRow(center: center, entry: entry, highlighted: entry.key == model.settingsCommand)
                                        .id(entry.key.description)
                                }
                                ForEach(center.problems[pluginID] ?? [], id: \.self) { problem in
                                    Text(problem).font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .onAppear {
                        if let key = model.settingsCommand { proxy.scrollTo(key.description, anchor: .center) }
                    }
                }
            }
            Text("An alias jumps to a command when you type it in the palette (⌃⌥Space). A hotkey runs it from anywhere. Links look like stackbar://commands/<plugin>/<command>?argument=value.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func matches(_ entry: CommandRegistry.Entry) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [entry.spec.title, entry.spec.subtitle ?? "", entry.pluginName, entry.spec.keywords.joined(separator: " "), center.preferences[entry.key].alias ?? ""]
            .contains { TextMatch.score(query, in: $0) != nil }
    }
}

struct CommandSettingsRow: View {
    let center: CommandCenter
    let entry: CommandRegistry.Entry
    let highlighted: Bool
    @State private var alias = ""
    @State private var problem: String?

    private var preference: CommandPreference { center.preferences[entry.key] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: entry.spec.symbol ?? (entry.spec.kind == .view ? "list.bullet.rectangle" : "command"))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.spec.title)
                    Text(entry.spec.kind == .view ? "Opens a view" : (entry.spec.arguments.isEmpty ? "Runs" : "Runs with " + entry.spec.arguments.map(\.placeholder).joined(separator: ", ")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Alias", text: $alias)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit { save { $0.alias = alias } }
                HotKeyRecorder(spec: preference.hotkey) { spec in save { $0.hotkey = spec } }
                Toggle("", isOn: Binding(get: { preference.enabled }, set: { enabled in save { $0.enabled = enabled } }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Show in the palette")
                Menu {
                    if entry.spec.exposure == .everywhere {
                        Button("Copy Link") { Platform.copy(CommandLink(key: entry.key).url) }
                        Toggle("Links May Run It Without Asking", isOn: Binding(get: { preference.linksAllowed }, set: { allowed in save { $0.linksAllowed = allowed } }))
                    } else {
                        Text("Only from inside Stackbar")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if let problem = problem ?? center.hotKeyProblems[entry.key] {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .background(highlighted ? Color.accentColor.opacity(0.08) : .clear)
        .onAppear { alias = preference.alias ?? "" }
    }

    private func save(_ change: (inout CommandPreference) -> Void) {
        var next = preference
        change(&next)
        do {
            try center.set(next, for: entry.key)
            problem = nil
            alias = center.preferences[entry.key].alias ?? ""
        } catch {
            problem = "\(error)"
            alias = preference.alias ?? ""
        }
    }
}

/// Records a shortcut: click, press the keys. Esc cancels and ⌫ clears.
/// It listens only to keys pressed in this window while recording.
struct HotKeyRecorder: View {
    let spec: String?
    let onChange: (String?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : (spec.map(ActionsPanel.glyphs) ?? "Record Hotkey"))
                .frame(minWidth: 96)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            stop()
        case kVK_Delete, kVK_ForwardDelete:
            onChange(nil)
            stop()
        default:
            guard let recorded = Self.spec(for: event) else {
                NSSound.beep()
                return
            }
            onChange(recorded)
            stop()
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// `cmd+shift+p` from a key press; nil without ⌘, ⌃ or ⌥ or for a key a
    /// hotkey can't use.
    static func spec(for event: NSEvent) -> String? {
        var parts: [String] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        let key: String?
        if event.keyCode == UInt16(kVK_Space) {
            key = "space"
        } else if let index = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12].firstIndex(of: Int(event.keyCode)) {
            key = "f\(index + 1)"
        } else {
            key = event.characters(byApplyingModifiers: [])?.lowercased()
        }
        guard let key else { return nil }
        let spec = (parts + [key]).joined(separator: "+")
        return HotKeySpec(spec) == nil ? nil : spec
    }
}
#endif
