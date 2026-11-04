#if os(macOS)
import AppKit
import StackbarHostCore
import StackbarProtocol

/// The finding calls on a Mac: the installed apps and System Settings panes
/// (`Stackbar.installedApps()`), and files by name from Spotlight's index
/// (`Stackbar.findFiles`). Plugins such as Applications and File Search
/// build the palette's results from them.
extension MacSystem {
    func installedApps() async throws -> [InstalledApp] {
        await InstalledApps.shared.list()
    }

    func findFiles(_ query: FileQuery) async throws -> [FoundFile] {
        try await SpotlightFiles.find(query)
    }
}

/// The apps and Settings panes, scanned off the main thread and kept for a
/// few minutes: a launcher asks on every keystroke.
actor InstalledApps {
    static let shared = InstalledApps()

    private var cached: [InstalledApp] = []
    private var scannedAt: Date?

    func list() -> [InstalledApp] {
        if let scannedAt, Date().timeIntervalSince(scannedAt) < 300 { return cached }
        cached = (Self.scanApps() + Self.scanSettingsPanes())
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        scannedAt = Date()
        return cached
    }

    private static let settingsApp = "/System/Applications/System Settings.app"

    private static func scanApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", home + "/Applications"]
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        func add(_ url: URL) {
            guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { return }
            let name = fileManager.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let file = url.deletingPathExtension().lastPathComponent
            apps.append(InstalledApp(id: id, name: name, path: url.path, keywords: file == name ? [] : [file]))
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
        return apps
    }

    /// The panes System Settings itself lists: the ExtensionKit extensions
    /// on its extension point, opened by `x-apple.systempreferences:<id>`.
    private static func scanSettingsPanes() -> [InstalledApp] {
        let directory = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var seen = Set<String>()
        return items.compactMap { url -> InstalledApp? in
            guard url.pathExtension == "appex", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  let info = bundle.infoDictionary,
                  let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                  (attributes["EXExtensionPointIdentifier"] as? String) == "com.apple.Settings.extension.ui" else { return nil }
            let localized = bundle.localizedInfoDictionary
            let name = (localized?["CFBundleDisplayName"] ?? info["CFBundleDisplayName"] ?? localized?["CFBundleName"] ?? info["CFBundleName"]) as? String
            guard let name, !name.isEmpty, seen.insert(name).inserted else { return nil }
            return InstalledApp(id: id, name: name, path: settingsApp, kind: .settingsPane, keywords: ["settings", "preferences"],
                                url: "x-apple.systempreferences:\(id)")
        }
    }
}

/// One Spotlight search: every word somewhere in the name, case and accents
/// ignored, in the user's home, most recently used first.
@MainActor
enum SpotlightFiles {
    /// Gives up after this long, with what it has.
    static let timeout: Duration = .seconds(3)

    static func find(_ query: FileQuery) async throws -> [FoundFile] {
        let words = query.text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let search = NSMetadataQuery()
        search.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: words.map {
            NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\($0)*")
        })
        search.searchScopes = [NSMetadataQueryUserHomeScope]
        search.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        let gathered = Gathered()
        let observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: search, queue: .main) { _ in
            MainActor.assumeIsolated { gathered.finish() }
        }
        defer {
            search.stop()
            NotificationCenter.default.removeObserver(observer)
        }
        guard search.start() else { throw SystemServiceError("Spotlight couldn't search") }
        await gathered.wait(timeout: timeout)
        search.disableUpdates()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [FoundFile] = []
        // Look a little past the limit: some hits are left out (bundles,
        // Library, hidden files).
        for index in 0..<min(search.resultCount, 80) where found.count < query.limit {
            guard let item = search.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let type = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
            let used = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
            if let file = FileSearchFilter.found(path: path, home: home, isFolder: type == "public.folder", lastUsed: used) {
                found.append(file)
            }
        }
        return found
    }

    /// Resumes once Spotlight has gathered, or at the timeout.
    @MainActor
    private final class Gathered {
        private var done = false
        private var waiter: CheckedContinuation<Void, Never>?

        func finish() {
            done = true
            waiter?.resume()
            waiter = nil
        }

        func wait(timeout: Duration) async {
            if done { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish()
            }
            await withCheckedContinuation { continuation in
                if done { continuation.resume() } else { waiter = continuation }
            }
        }
    }
}
#endif
