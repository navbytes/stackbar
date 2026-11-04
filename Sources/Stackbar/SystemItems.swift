#if os(macOS)
import AppKit
import StackbarHostCore

/// The installed apps and System Settings panes the palette finds by name,
/// as Raycast and Spotlight do. Scanned off the main thread when the
/// palette opens, at most every few minutes.
@MainActor
final class SystemItems {
    static let shared = SystemItems()

    private(set) var entries: [PaletteIndex.Entry] = []
    /// Goes up each time a scan lands, so an open palette redraws.
    private(set) var revision = 0
    private var scannedAt: Date?
    private var scanning = false
    private var icons: [String: NSImage] = [:]

    nonisolated static let appPluginID = "system.apps"
    nonisolated static let settingsPluginID = "system.settings"
    nonisolated private static let settingsApp = "/System/Applications/System Settings.app"

    /// Rescans when the last scan is older than five minutes.
    func refresh(then changed: @escaping @MainActor @Sendable () -> Void) {
        if scanning { return }
        if let scannedAt, Date().timeIntervalSince(scannedAt) < 300 { return }
        scanning = true
        Task.detached(priority: .utility) {
            let found = Self.scanApps() + Self.scanSettingsPanes()
            await MainActor.run {
                self.entries = found
                self.scannedAt = Date()
                self.scanning = false
                self.revision += 1
                changed()
            }
        }
    }

    /// An app's own icon, or System Settings' for a pane; nil for anything
    /// else.
    func icon(for entry: PaletteIndex.Entry) -> NSImage? {
        guard case .open(let url) = entry.kind else { return nil }
        let path: String
        switch entry.pluginID {
        case Self.appPluginID: path = URL(string: url)?.path ?? ""
        case Self.settingsPluginID: path = Self.settingsApp
        default: return nil
        }
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    // MARK: Scanning

    nonisolated private static func scanApps() -> [PaletteIndex.Entry] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", home + "/Applications"]
        var seen = Set<String>()
        var entries: [PaletteIndex.Entry] = []
        func add(_ url: URL) {
            let name = fileManager.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            guard seen.insert(name.lowercased()).inserted else { return }
            let file = url.deletingPathExtension().lastPathComponent
            entries.append(PaletteIndex.Entry(pluginID: appPluginID, pluginName: "Application", title: name, kind: .open(url.absoluteString),
                                              keywords: file == name ? [] : [file]))
        }
        for root in roots {
            let directory = URL(fileURLWithPath: root, isDirectory: true)
            guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    add(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, item.lastPathComponent != "Utilities" {
                    // One level into folders like "Adobe Photoshop 2026/".
                    let inner = (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    inner.filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        return entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The panes System Settings itself lists: the ExtensionKit extensions
    /// on its extension point, opened by `x-apple.systempreferences:<id>`.
    nonisolated private static func scanSettingsPanes() -> [PaletteIndex.Entry] {
        let directory = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var seen = Set<String>()
        return items.compactMap { url -> PaletteIndex.Entry? in
            guard url.pathExtension == "appex", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  let info = bundle.infoDictionary,
                  let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                  (attributes["EXExtensionPointIdentifier"] as? String) == "com.apple.Settings.extension.ui" else { return nil }
            let localized = bundle.localizedInfoDictionary
            let name = (localized?["CFBundleDisplayName"] ?? info["CFBundleDisplayName"] ?? localized?["CFBundleName"] ?? info["CFBundleName"]) as? String
            guard let name, !name.isEmpty, seen.insert(name).inserted else { return nil }
            return PaletteIndex.Entry(pluginID: settingsPluginID, pluginName: "System Settings", title: name, symbol: "gearshape",
                                      kind: .open("x-apple.systempreferences:\(id)"), keywords: ["settings", "preferences"])
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
#endif
