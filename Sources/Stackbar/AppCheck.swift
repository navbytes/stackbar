#if os(macOS)
import AppKit
import StackbarHostCore

/// `STACKBAR_APPCHECK=<folder>`: Stackbar walks through a new user's first
/// minute on its own, writes `results.json` and light and dark screenshots
/// into the folder, and quits. The App check job in CI runs it on a clean
/// macOS runner, so the flows a switcher judges first are checked on every
/// change instead of waiting for a hand check on a Mac.
///
/// With `STACKBAR_APPCHECK_MODE=upgrade` it checks a home that an older
/// release left behind instead: the plugins are still there and still
/// answer, and nothing waits for an approval it already had.
@MainActor
enum AppCheck {
    static var folder: URL? {
        ProcessInfo.processInfo.environment["STACKBAR_APPCHECK"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static var isUpgrade: Bool { ProcessInfo.processInfo.environment["STACKBAR_APPCHECK_MODE"] == "upgrade" }

    /// What the golden path may cost on a CI runner, which is a slow VM. A
    /// real Mac is several times faster; these catch regressions, not noise.
    enum Budget {
        static let paletteOpenMedianMs = 100.0
        static let paletteOpenMaxMs = 500.0
        static let searchMs = 1_500.0
    }

    /// One query a new user types, and what must come first.
    struct Golden {
        var query: String
        var top: String
    }

    static let golden: [Golden] = [
        // Two letters and Return opens Safari: the 0.30 bug where Safari
        // was missing from the index.
        Golden(query: "saf", top: "Safari"),
        Golden(query: "calendar", top: "Calendar"),
        Golden(query: "terminal", top: "Terminal"),
        Golden(query: "12*12", top: "144"),
    ]

    private struct Check: Encodable {
        var name: String
        var passed: Bool
        var detail: String
        var ms: Double?
    }

    private static var checks: [Check] = []
    private static var shots: [String] = []

    private static func record(_ name: String, _ passed: Bool, _ detail: String, ms: Double? = nil) {
        checks.append(Check(name: name, passed: passed, detail: detail, ms: ms))
    }

    static func run(app: AppDelegate) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task { @MainActor in
            if isUpgrade {
                await checkUpgradedHome(app)
            } else {
                await checkWelcome(app, folder: folder)
            }
            let ready = await checkPlugins(app)
            if ready {
                await checkPaletteOpen(app, folder: folder)
                await checkSearches(app, folder: folder)
                await checkReturn(app)
                await checkActions(app, folder: folder)
            }
            if !isUpgrade {
                await checkSettings(app, folder: folder)
                await checkStore(app, folder: folder)
            }
            write(to: folder)
            NSApp.terminate(nil)
        }
    }

    // MARK: - The first minute

    /// A fresh Mac gets the welcome window at a usable size (0.27.0 showed a
    /// clipped strip), and the default starter set installs.
    private static func checkWelcome(_ app: AppDelegate, folder: URL) async {
        app.welcomeIfNeeded()
        let shown = await waitUntil(seconds: 5) { app.welcomeWindow?.isVisible == true }
        let height = app.welcomeWindow?.contentView?.frame.height ?? 0
        record("Welcome shows on a fresh Mac", shown && height >= 300, "visible \(shown), content height \(Int(height)) pt")
        if let window = app.welcomeWindow { await shoot(window, "welcome", folder: folder) }
        app.welcomeWindow?.close()
        let seen = UserDefaults.standard.bool(forKey: WelcomeView.seenKey)
        record("Closing Welcome counts as seen", seen, "welcomeSeen \(seen)")

        guard let starter = BundledStore.starterSets.first else {
            record("Starter set installs", false, "no starter sets")
            return
        }
        let before = Set(app.model.controllers.map(\.pluginID))
        app.model.installStarters(starter.pluginIDs)
        let added = Set(app.model.controllers.map(\.pluginID)).subtracting(before)
        let available = Set(app.model.bundledStore.starters().map(\.id)).union(BundledStore.corePluginIDs)
        let missing = starter.pluginIDs.intersection(available).subtracting(added).subtracting(before)
        record("Starter set \"\(starter.name)\" installs", missing.isEmpty, missing.isEmpty ? "added \(added.sorted().joined(separator: ", "))" : "missing \(missing.sorted().joined(separator: ", "))")
    }

    /// An older release's home: the plugins it ran are all still here.
    private static func checkUpgradedHome(_ app: AppDelegate) async {
        let expected = ProcessInfo.processInfo.environment["STACKBAR_APPCHECK_PLUGINS"]?
            .split(separator: ",").map(String.init) ?? []
        let have = Set(app.model.controllers.map(\.pluginID))
        let lost = expected.filter { !have.contains($0) }
        record("Plugins survive the update", !expected.isEmpty && lost.isEmpty, lost.isEmpty ? "\(expected.count) plugins kept" : "lost \(lost.joined(separator: ", "))")
        let welcome = app.welcomeWindow?.isVisible == true
        record("No Welcome after an update", !welcome, "welcome visible \(welcome)")
    }

    /// Every plugin starts, and the core ones (apps, sums, files) never wait
    /// for an approval: they answer on the first search.
    private static func checkPlugins(_ app: AppDelegate) async -> Bool {
        let start = Date()
        let settled = await waitUntil(seconds: 240) {
            !app.model.controllers.isEmpty && app.model.controllers.allSatisfy { $0.isSettled || $0.isWaitingForApproval }
        }
        let failed = app.model.controllers.filter(\.hasFailed).map(\.name)
        record("Plugins start", settled && failed.isEmpty, settled ? (failed.isEmpty ? "\(app.model.controllers.count) running" : "failed: \(failed.joined(separator: ", "))") : "still starting: \(app.model.controllers.filter { !$0.isSettled }.map(\.name).joined(separator: ", "))", ms: ms(since: start))

        let core = app.model.controllers.filter { BundledStore.corePluginIDs.contains($0.pluginID) }
        let waiting = core.filter(\.isWaitingForApproval).map(\.name)
        record("Core plugins need no approval", core.count == BundledStore.corePluginIDs.count && waiting.isEmpty, waiting.isEmpty ? "\(core.map(\.name).sorted().joined(separator: ", "))" : "waiting: \(waiting.joined(separator: ", "))")

        // The starters ask once, as they would a user; approve them so the
        // rest of the check can search them.
        for controller in app.model.controllers where controller.isWaitingForApproval {
            _ = controller.approve()
        }
        let ready = await waitUntil(seconds: 120) {
            app.model.controllers.allSatisfy { !$0.isWaitingForApproval && $0.isSettled }
        }
        try? await Task.sleep(for: .seconds(2))
        return ready
    }

    private static func checkPaletteOpen(_ app: AppDelegate, folder: URL) async {
        var opens: [Double] = []
        for _ in 0..<10 {
            let start = Date()
            app.palette.toggle()
            _ = await waitUntil(seconds: 5) { app.palette.isVisible }
            await nextFrame()
            opens.append(ms(since: start))
            app.palette.hide()
            try? await Task.sleep(for: .milliseconds(200))
        }
        let sorted = opens.sorted()
        let median = sorted[sorted.count / 2], max = sorted.last ?? 0
        record("Palette opens fast", median <= Budget.paletteOpenMedianMs && max <= Budget.paletteOpenMaxMs,
               "median \(median) ms (budget \(Budget.paletteOpenMedianMs)), max \(max) ms (budget \(Budget.paletteOpenMaxMs))", ms: median)
        app.palette.toggle()
        _ = await waitUntil(seconds: 5) { app.palette.isVisible }
        if let window = app.palette.window { await shoot(window, "palette-empty", folder: folder) }
        app.palette.hide()
    }

    /// Each golden query puts the right row first, within the budget.
    private static func checkSearches(_ app: AppDelegate, folder: URL) async {
        for item in golden {
            app.palette.toggle()
            _ = await waitUntil(seconds: 5) { app.palette.isVisible }
            let start = Date()
            app.palette.session.query = item.query
            let found = await waitUntil(seconds: Budget.searchMs / 1_000 * 3) { matches(app.palette.session.selectedEntry, item.top) }
            let took = ms(since: start)
            let top = app.palette.session.results.prefix(3).map { $0.title }.joined(separator: " | ")
            record("\"\(item.query)\" puts \(item.top) first", found && took <= Budget.searchMs,
                   found ? "\(took) ms (budget \(Budget.searchMs))" : "top rows: \(top)", ms: found ? took : nil)
            if item.query == "saf", let window = app.palette.window { await shoot(window, "palette-results", folder: folder) }
            app.palette.hide()
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Return on the first row does what it says: a sum is copied. (The
    /// 0.25 bug: Return on the first result did nothing.)
    private static func checkReturn(_ app: AppDelegate) async {
        NSPasteboard.general.clearContents()
        app.palette.toggle()
        _ = await waitUntil(seconds: 5) { app.palette.isVisible }
        app.palette.session.query = "12*12"
        _ = await waitUntil(seconds: 5) { matches(app.palette.session.selectedEntry, "144") }
        app.palette.session.submit()
        let copied = await waitUntil(seconds: 5) { NSPasteboard.general.string(forType: .string)?.contains("144") == true }
        let closed = await waitUntil(seconds: 2) { !app.palette.isVisible }
        record("Return on a sum copies it and closes", copied && closed,
               "clipboard \(NSPasteboard.general.string(forType: .string) ?? "empty"), palette closed \(closed)")
        app.palette.hide()
    }

    /// ⌘K lists actions for the selected row, and ⎋ closes it again.
    private static func checkActions(_ app: AppDelegate, folder: URL) async {
        app.palette.toggle()
        _ = await waitUntil(seconds: 5) { app.palette.isVisible }
        app.palette.session.query = "calendar"
        _ = await waitUntil(seconds: 5) { matches(app.palette.session.selectedEntry, "Calendar") }
        app.palette.session.toggleActions()
        let shown = app.palette.session.showingActions && !app.palette.session.actions.isEmpty
        let titles = app.palette.session.actions.prefix(4).map(\.title).joined(separator: ", ")
        if let window = app.palette.window { await shoot(window, "palette-actions", folder: folder) }
        let backed = app.palette.session.back()
        let closedActions = backed && !app.palette.session.showingActions
        record("⌘K shows actions, ⎋ closes them", shown && closedActions, "actions: \(titles); ⎋ closed them \(closedActions)")
        app.palette.hide()
        record("⎋ hides the palette", !app.palette.isVisible, "visible \(app.palette.isVisible)")
    }

    private static func checkSettings(_ app: AppDelegate, folder: URL) async {
        var pages: [(String, SettingsTab)] = SettingsTab.sections.map { ("settings-\(name($0.title))", $0) }
        if let core = app.model.controllers.first(where: { $0.pluginID == "io.navbytes.stackbar.plugins.calculator" }) {
            pages.append(("settings-plugin-calculator", .plugin(core.id)))
        }
        var shown = 0
        for (file, tab) in pages {
            app.showSettings(tab: tab)
            try? await Task.sleep(for: .milliseconds(400))
            guard let window = NSApp.windows.first(where: { $0.title == "Stackbar Settings" && $0.isVisible }) else { continue }
            shown += 1
            await shoot(window, file, folder: folder)
        }
        record("Settings opens on every page", shown == pages.count, "\(shown) of \(pages.count) pages shown")
        NSApp.windows.first { $0.title == "Stackbar Settings" }?.close()
    }

    private static func checkStore(_ app: AppDelegate, folder: URL) async {
        app.showStore()
        let shown = await waitUntil(seconds: 5) { NSApp.windows.contains { $0.title == "Plugin Store" && $0.isVisible } }
        // Let the index load and the cards draw.
        try? await Task.sleep(for: .seconds(4))
        if let window = NSApp.windows.first(where: { $0.title == "Plugin Store" }) { await shoot(window, "store", folder: folder) }
        let listed = app.model.store.catalogs.reduce(0) { $0 + $1.index.plugins.count }
        record("Store opens and lists plugins", shown && listed > 0, "visible \(shown), \(listed) listings")
        NSApp.windows.first { $0.title == "Plugin Store" }?.close()
    }

    // MARK: - Output

    private static func write(to folder: URL) {
        let failed = checks.filter { !$0.passed }
        let report: [String: Any] = [
            "version": StackbarVersion.current,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "mode": isUpgrade ? "upgrade" : "fresh",
            "passed": failed.isEmpty,
            "screenshots": shots,
            "checks": checks.map { check -> [String: Any] in
                var row: [String: Any] = ["name": check.name, "passed": check.passed, "detail": check.detail]
                if let ms = check.ms { row["ms"] = ms }
                return row
            },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent(isUpgrade ? "upgrade.json" : "results.json"), options: .atomic)
        }
    }

    /// The window in light and in dark, drawn by the app itself, so it needs
    /// no Screen Recording permission.
    private static func shoot(_ window: NSWindow, _ name: String, folder: URL) async {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            try? await Task.sleep(for: .milliseconds(400))
            await nextFrame()
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let file = "\(name)-\(suffix).png"
            if (try? png.write(to: folder.appendingPathComponent(file))) != nil { shots.append(file) }
        }
        NSApp.appearance = nil
    }

    // MARK: - Helpers

    private static func matches(_ entry: PaletteIndex.Entry?, _ text: String) -> Bool {
        guard let entry else { return false }
        return entry.title == text || (text.allSatisfy(\.isNumber) && entry.title.contains(text))
    }

    private static func name(_ title: String) -> String {
        title.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
    }

    private static func ms(since start: Date) -> Double { (Date().timeIntervalSince(start) * 10_000).rounded() / 10 }

    private static func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private static func nextFrame() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
#endif
