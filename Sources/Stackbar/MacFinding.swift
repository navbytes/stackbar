#if os(macOS)
import AppKit
import CoreServices
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
        // Safari and a few other Apple apps live in the App Cryptex since
        // macOS 13: /Applications/Safari.app is only a symlink into it.
        // CoreServices/Applications holds Screen Sharing, Ticket Viewer and
        // Directory Utility.
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     "/System/Cryptexes/App/System/Applications", "/System/Library/CoreServices/Applications", home + "/Applications"]
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        func add(_ url: URL) {
            // A symlinked bundle is read where it really is, but listed under
            // the path the user knows.
            let bundle = Bundle(url: url) ?? Bundle(url: url.resolvingSymlinksInPath())
            guard let id = bundle?.bundleIdentifier, seen.insert(id).inserted else { return }
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
        // Finder lives with the system's agents, which the list leaves out.
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        // Whatever the scan missed that Launch Services knows opens links,
        // so no browser is ever left out.
        if let link = URL(string: "https://example.com") {
            NSWorkspace.shared.urlsForApplications(toOpen: link).forEach(add)
        }
        // Then every other app Spotlight knows: deeper folders, other drives,
        // Xcode's Simulator. With indexing off this finds nothing and the
        // scan above stands.
        for path in spotlightApps() where AppListFilter.keeps(path) {
            let url = URL(fileURLWithPath: path)
            guard let info = Bundle(url: url)?.infoDictionary, (info["LSBackgroundOnly"] as? Bool) != true else { continue }
            add(url)
        }
        return apps
    }

    /// The paths of every application bundle in Spotlight's index, on every
    /// indexed drive. Spotlight's C API, run synchronously off the main
    /// thread (see `SpotlightFiles` for why not `NSMetadataQuery`).
    private static func spotlightApps() -> [String] {
        let text = "kMDItemContentTypeTree == \"com.apple.application-bundle\""
        guard let search = MDQueryCreate(kCFAllocatorDefault, text as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(search, [kMDQueryScopeComputerIndexed] as CFArray, 0)
        MDQuerySetMaxCount(search, 5000)
        guard MDQueryExecute(search, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        defer { MDQueryStop(search) }
        var paths: [String] = []
        for index in 0..<MDQueryGetResultCount(search) {
            guard let raw = MDQueryGetResultAtIndex(search, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { paths.append(path) }
        }
        return paths
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
///
/// This uses Spotlight's C API (`MDQuery`) run synchronously on a background
/// queue, not `NSMetadataQuery`: that one must be set up on the main thread
/// with a run loop, and when it is not it raises an Objective-C exception,
/// which unwinds through Swift's concurrency runtime and leaves the app to
/// crash a few seconds later (0.20.0 did this).
enum SpotlightFiles {
    /// How many hits Spotlight hands back at most: some are left out
    /// (bundles, Library, hidden files), so a little past the limit.
    static let gathered = 80

    static func find(_ query: FileQuery) async throws -> [FoundFile] {
        let words = query.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let text = FileSearchFilter.spotlightQuery(words)
        let limit = query.limit
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try search(text, limit: limit) })
            }
        }
    }

    private static func search(_ text: String, limit: Int) throws -> [FoundFile] {
        let sorting = [kMDItemLastUsedDate] as CFArray
        guard let search = MDQueryCreate(kCFAllocatorDefault, text as CFString, nil, sorting) else {
            throw SystemServiceError("Spotlight couldn't read that search")
        }
        MDQuerySetSearchScope(search, [kMDQueryScopeHome] as CFArray, 0)
        // Newest first (kMDQueryReverseSortOrderFlag), then the first few.
        MDQuerySetSortOptionFlagsForAttribute(search, kMDItemLastUsedDate, 1)
        MDQuerySetMaxCount(search, gathered)
        guard MDQueryExecute(search, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw SystemServiceError("Spotlight couldn't search")
        }
        defer { MDQueryStop(search) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [FoundFile] = []
        let count = MDQueryGetResultCount(search)
        var index = 0
        while index < count, found.count < limit {
            defer { index += 1 }
            guard let raw = MDQueryGetResultAtIndex(search, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            let type = MDItemCopyAttribute(item, kMDItemContentType) as? String
            let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            if let file = FileSearchFilter.found(path: path, home: home, isFolder: type == "public.folder", lastUsed: used) {
                found.append(file)
            }
        }
        return found
    }
}
#endif
