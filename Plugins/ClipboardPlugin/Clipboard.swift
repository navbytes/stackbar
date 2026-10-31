import FluidKit
import Foundation

/// Clipboard history: everything you copy, searchable, pinnable and one
/// keystroke from being pasted back.
///
/// ⌘⇧V opens it from anywhere. Type to filter, click (or ⌘1...⌘9) to paste
/// into the app you were in. Pinned items stay at the top and are never
/// trimmed. Passwords are skipped: the host never hands out items an app
/// marks as concealed or transient, and items from password managers (or any
/// app you add) are ignored. Images are kept by the host and pasted back.
@main
final class Clipboard: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.fluid.clipboard",
        name: "Clipboard History",
        version: "1.0.0",
        summary: "Everything you copy, searchable and one keystroke from pasting back.",
        surfaces: [.menuBar, .panel, .window],
        triggers: [.launch, .clipboard],
        capabilities: [.clipboard],
        hotkey: "cmd+shift+v"
    )

    struct Entry: Codable, Equatable {
        var id: String
        var kind: ClipboardItem.Kind
        var text: String?
        var files: [String] = []
        var imageID: String?
        var imageSize: [Int]?
        var appID: String?
        var appName: String?
        var firstCopied: Date
        var lastCopied: Date
        var count: Int = 1
        var pinned = false

        /// What makes two copies the same item.
        var fingerprint: String {
            switch kind {
            case .image: return "image:" + (imageID ?? id)
            case .files: return "files:" + files.joined(separator: "\n")
            case .text, .url: return "text:" + (text ?? "")
            }
        }

        var content: ClipboardContent {
            switch kind {
            case .image: return .image(id: imageID ?? "")
            case .files: return .files(files)
            case .text, .url: return .text(text ?? "")
            }
        }

        var title: String {
            switch kind {
            case .image:
                let size = imageSize.map { "\($0.first ?? 0)×\($0.last ?? 0)" } ?? ""
                return "Image \(size)".trimmingCharacters(in: .whitespaces)
            case .files:
                let names = files.map { ($0 as NSString).lastPathComponent }
                return names.count == 1 ? names[0] : "\(names.count) files: " + names.prefix(3).joined(separator: ", ")
            case .text, .url:
                let line = (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let shown = trimmed.isEmpty ? "(whitespace)" : trimmed
                return shown.count > 90 ? String(shown.prefix(89)) + "…" : shown
            }
        }

        var symbol: String {
            switch kind {
            case .text: return "doc.plaintext"
            case .url: return "link"
            case .files: return "doc.on.doc"
            case .image: return "photo"
            }
        }

        var bytes: Int { (text?.utf8.count ?? 0) + files.reduce(0) { $0 + $1.utf8.count } + 200 }
    }

    enum Order: String, CaseIterable, Codable {
        case recent = "Last copied"
        case first = "First copied"
        case frequent = "Most used"
    }

    /// Password managers whose copies are never recorded, on top of the
    /// concealed-type marker most of them already set.
    static let defaultIgnored = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.dashlane.dashlanephonefinal", "org.keepassxc.keepassxc",
    ]

    /// The plugin's 1 MB of storage, less room for settings.
    static let storageBudget = 850_000
    static let maxEntryCharacters = 100_000

    @Stored("limit") var limit = 200.0
    @Stored("order") var order = Order.recent
    @Stored("pasteDirectly") var pasteDirectly = true
    @Stored("keepImages") var keepImages = true
    @Stored("ignoredApps") var ignoredApps = Clipboard.defaultIgnored
    @Stored("paused") var paused = false

    /// The history, read from storage once and written back when it changes
    /// (a `@Stored` array would be decoded on every render).
    private var cached: [Entry]?
    private var lastChange: Int?
    private var ignoreNext = false
    var lastError: String?

    var entries: [Entry] {
        get {
            if let cached { return cached }
            let loaded = Fluid.storage.value("history", as: [Entry].self) ?? []
            cached = loaded
            return loaded
        }
        set {
            cached = newValue
            Fluid.storage.set("history", newValue)
        }
    }

    // MARK: Recording

    func refresh() async throws {
        guard let item = try await Fluid.clipboard() else { return }
        // The first read after a launch records what is on the clipboard
        // now; if it is already in the history it just moves to the top.
        defer { lastChange = item.changeCount }
        guard item.changeCount != lastChange else { return }
        if ignoreNext {
            ignoreNext = false
            return
        }
        guard !paused, !item.concealed else { return }
        if let app = item.sourceAppID, isIgnored(app: app, name: item.sourceAppName) { return }
        if item.kind == .image && !keepImages { return }
        record(item)
    }

    func record(_ item: ClipboardItem) {
        var entry = Entry(
            id: UUID().uuidString, kind: item.kind, text: item.text.map { String($0.prefix(Self.maxEntryCharacters)) }, files: item.files,
            imageID: item.imageID, imageSize: item.imageSize, appID: item.sourceAppID, appName: item.sourceAppName,
            firstCopied: item.copiedAt, lastCopied: item.copiedAt
        )
        if entry.kind != .image && entry.kind != .files && (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        var history = entries
        if let index = history.firstIndex(where: { $0.fingerprint == entry.fingerprint }) {
            var existing = history.remove(at: index)
            existing.lastCopied = item.copiedAt
            existing.count += 1
            // Keep the original source; a re-copy from Fluid itself says nothing new.
            if item.sourceAppID != "dev.fluid.app" {
                existing.appID = item.sourceAppID ?? existing.appID
                existing.appName = item.sourceAppName ?? existing.appName
            }
            entry = existing
        }
        history.insert(entry, at: 0)
        entries = trimmed(history)
    }

    /// Drops the oldest unpinned items past the limit or the storage budget.
    func trimmed(_ history: [Entry]) -> [Entry] {
        var kept: [Entry] = []
        var unpinned = 0
        var bytes = 0
        for entry in history {
            bytes += entry.bytes
            if entry.pinned {
                kept.append(entry)
                continue
            }
            guard unpinned < Int(limit), bytes <= Self.storageBudget else { continue }
            unpinned += 1
            kept.append(entry)
        }
        return kept
    }

    func isIgnored(app id: String, name: String?) -> Bool {
        ignoredApps.contains { ignored in
            ignored.caseInsensitiveCompare(id) == .orderedSame || (name.map { ignored.caseInsensitiveCompare($0) == .orderedSame } ?? false)
        }
    }

    // MARK: Acting on an entry

    func use(_ entry: Entry, paste: Bool) async {
        do {
            if paste {
                try await Fluid.paste(entry.content)
            } else if case .text(let text) = entry.content {
                Fluid.copy(text)
            } else {
                try await Fluid.setClipboard(entry.content)
            }
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    func update(_ id: String, _ change: (inout Entry) -> Void) {
        var history = entries
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        change(&history[index])
        entries = history
    }

    func delete(_ id: String) {
        entries = entries.filter { $0.id != id }
    }

    func clear(keepPinned: Bool = true) {
        entries = keepPinned ? entries.filter(\.pinned) : []
    }

    var sorted: [Entry] {
        let history = entries
        switch order {
        case .recent: return history.sorted { $0.lastCopied > $1.lastCopied }
        case .first: return history.sorted { $0.firstCopied > $1.firstCopied }
        case .frequent: return history.sorted { ($0.count, $0.lastCopied) > ($1.count, $1.lastCopied) }
        }
    }

    // MARK: Surfaces

    var menuBar: ViewContent {
        Label("", symbol: paused ? "pause.circle" : "list.clipboard").role(paused ? .warning : .primary)
    }

    var panel: ViewContent { content(full: false) }

    /// The window adds managing the ignored apps.
    var window: ViewContent { content(full: true) }

    @ViewBuilder func content(full: Bool) -> ViewContent {
        let all = sorted
        let pinned = all.filter(\.pinned)
        let history = all.filter { !$0.pinned }
        HStack {
            Text("Clipboard").style(.headline)
            Badge("\(all.count)")
            if paused { Badge("Paused", role: .warning) }
        }
        if let lastError {
            Text(lastError).style(.caption).role(.warning)
        }
        if all.isEmpty {
            ContentUnavailableView("Nothing copied yet", symbol: "list.clipboard", message: paused ? "Recording is paused." : "Copy something in any app and it shows up here.")
        } else {
            List(searchable: true) {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(Array(pinned.enumerated())) { index, entry in
                            row(entry, shortcut: index < 9 ? "cmd+\(index + 1)" : nil)
                        }
                    }
                }
                if pinned.isEmpty {
                    ForEach(Array(history.enumerated())) { index, entry in
                        row(entry, shortcut: index < 9 ? "cmd+\(index + 1)" : nil)
                    }
                } else {
                    Section("History") {
                        ForEach(Array(history.enumerated())) { index, entry in
                            let position = pinned.count + index
                            row(entry, shortcut: position < 9 ? "cmd+\(position + 1)" : nil)
                        }
                    }
                }
            }
        }
        HStack {
            Button(paused ? "Resume" : "Pause", symbol: paused ? "play.fill" : "pause.fill") { self.paused.toggle() }
            Button("Ignore next copy", symbol: "eye.slash") { self.ignoreNext = true }
            Button("Clear history", symbol: "trash", role: .critical) { self.clear() }
        }
        settings(full: full)
    }

    @ViewBuilder func settings(full: Bool) -> ViewContent {
        Section("Settings") {
            Toggle("Paste into the app on click", isOn: pasteDirectly) { self.pasteDirectly = $0 }
            Picker("Order", options: Order.allCases.map(\.rawValue), selection: order.rawValue) { self.order = Order(rawValue: $0) ?? .recent }
            Slider("Keep \(Int(limit)) items", value: limit, in: 25...1000, step: 25) { value in
                self.limit = value
                self.entries = self.trimmed(self.entries)
            }
            Toggle("Keep images", isOn: keepImages) { self.keepImages = $0 }
            if full {
                ignoredAppSettings
            } else {
                LabeledContent("Ignored apps", value: "\(ignoredApps.count); manage them in the window").role(.secondary)
            }
        }
    }

    @ViewBuilder var ignoredAppSettings: ViewContent {
        TextField("Ignore an app (bundle id or name)") { app in
            let app = app.trimmingCharacters(in: .whitespaces)
            guard !app.isEmpty, !self.ignoredApps.contains(app) else { return }
            self.ignoredApps.append(app)
        }
        if let recent = entries.first(where: { $0.appID != nil && $0.appID != "dev.fluid.app" }), let app = recent.appID, !isIgnored(app: app, name: recent.appName) {
            Button("Ignore \(recent.appName ?? app)", symbol: "hand.raised", key: "ignore-recent") { self.ignoredApps.append(app) }
        }
        ForEach(ignoredApps) { app in
            Row(app, subtitle: "Ignored", symbol: "hand.raised", key: "ignored-\(app)")
                .action("Stop ignoring") { self.ignoredApps.removeAll { $0 == app } }
        }
    }

    func row(_ entry: Entry, shortcut: String?) -> Row {
        let source = [entry.appName, Self.relative(entry.lastCopied), entry.count > 1 ? "×\(entry.count)" : nil, entry.kind == .text ? "\(entry.text?.count ?? 0) chars" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        var row = Row(entry.title, subtitle: source, symbol: entry.pinned ? "pin.fill" : entry.symbol, key: entry.id)
            .action(pasteDirectly ? "Paste" : "Copy", shortcut: shortcut) { await self.use(entry, paste: self.pasteDirectly) }
            .action(pasteDirectly ? "Copy" : "Paste") { await self.use(entry, paste: !self.pasteDirectly) }
            .action(entry.pinned ? "Unpin" : "Pin", shortcut: "cmd+p") { self.update(entry.id) { $0.pinned.toggle() } }
        if entry.kind == .url, let url = entry.text {
            row = row.action("Open link") { Fluid.open(url.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return row.action("Delete", shortcut: "cmd+delete", role: .critical) { self.delete(entry.id) }
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Agents

    var tools: [AgentTool] {
        AgentTool("recent_clips", description: "The most recent clipboard items, newest first", parameters: [ToolParameter("count", .number, description: "How many (default 10)", required: false)]) { arguments in
            let count = Int(arguments.number("count") ?? 10)
            return self.sorted.prefix(max(1, min(count, 50))).enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
        }
        AgentTool("search_clips", description: "Clipboard items containing the text, newest first, in full", parameters: [ToolParameter("query", description: "Text to look for")]) { arguments in
            let query = arguments.string("query") ?? ""
            let found = self.sorted.filter { ($0.text ?? "").localizedCaseInsensitiveContains(query) }.prefix(10)
            return found.isEmpty ? "Nothing in the history contains \"\(query)\"." : found.map { $0.text ?? $0.title }.joined(separator: "\n---\n")
        }
        AgentTool("copy_clip", description: "Put a history item back on the clipboard, by its position in recent_clips", parameters: [ToolParameter("position", .number, description: "1 is the newest")]) { arguments in
            let position = Int(arguments.number("position") ?? 0)
            let items = self.sorted
            guard position >= 1, position <= items.count else { return "There is no item \(position)." }
            await self.use(items[position - 1], paste: false)
            return "Copied \(items[position - 1].title)"
        }
    }
}
