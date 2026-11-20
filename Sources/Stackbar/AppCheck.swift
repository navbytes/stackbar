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
        /// The first open builds the panel and its views.
        static let paletteFirstOpenMs = 1_000.0
        static let paletteOpenMedianMs = 100.0
        static let paletteOpenMaxMs = 250.0
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
                await checkBack(app)
                await checkArrowsInViews(app)
                await checkStrayKeys(app)
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
        let shown = await AppDriver.waitUntil(seconds: 5) { app.welcomeWindow?.isVisible == true }
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
        let available = Set(app.model.bundledStore.starters().map(\.id)).union(BundledStore.corePluginIDs)
        let wanted = starter.pluginIDs.intersection(available)
        // Installed plugins join as the folder watcher sees them.
        _ = await AppDriver.waitUntil(seconds: 20) { wanted.isSubset(of: Set(app.model.controllers.map(\.pluginID))) }
        let added = Set(app.model.controllers.map(\.pluginID)).subtracting(before)
        let missing = wanted.subtracting(added).subtracting(before)
        record("Starter set \"\(starter.name)\" installs", missing.isEmpty, missing.isEmpty ? "added \(added.sorted().joined(separator: ", "))" : "missing \(missing.sorted().joined(separator: ", "))")
    }

    /// An older release's home: the plugins it ran are all still here.
    private static func checkUpgradedHome(_ app: AppDelegate) async {
        // By name, as the old release's benchmark lists them.
        let expected = ProcessInfo.processInfo.environment["STACKBAR_APPCHECK_PLUGINS"]?
            .split(separator: ",").map(String.init) ?? []
        // A plugin whose helper is rebuilt for the new version joins once
        // it is ready (#183), so give them the time an update takes.
        _ = await AppDriver.waitUntil(seconds: 180) { Set(expected).isSubset(of: Set(app.model.controllers.map(\.name))) }
        let have = Set(app.model.controllers.map(\.name))
        let lost = expected.filter { !have.contains($0) }
        record("Plugins survive the update", !expected.isEmpty && lost.isEmpty, lost.isEmpty ? "\(expected.count) plugins kept" : "lost \(lost.joined(separator: ", "))")
        let welcome = app.welcomeWindow?.isVisible == true
        record("No Welcome after an update", !welcome, "welcome visible \(welcome)")
    }

    /// Every plugin starts, and the core ones (apps, sums, files) never wait
    /// for an approval: they answer on the first search.
    private static func checkPlugins(_ app: AppDelegate) async -> Bool {
        let start = Date()
        let settled = await AppDriver.waitUntil(seconds: 240) {
            !app.model.controllers.isEmpty && app.model.controllers.allSatisfy { $0.isSettled || $0.isWaitingForApproval }
        }
        let failed = app.model.controllers.filter(\.hasFailed).map(\.name)
        record("Plugins start", settled && failed.isEmpty, settled ? (failed.isEmpty ? "\(app.model.controllers.count) running" : "failed: \(failed.joined(separator: ", "))") : "still starting: \(app.model.controllers.filter { !$0.isSettled }.map(\.name).joined(separator: ", "))", ms: AppDriver.ms(since: start))

        let core = app.model.controllers.filter { BundledStore.corePluginIDs.contains($0.pluginID) }
        let waiting = core.filter(\.isWaitingForApproval).map(\.name)
        record("Core plugins need no approval", core.count == BundledStore.corePluginIDs.count && waiting.isEmpty, waiting.isEmpty ? "\(core.map(\.name).sorted().joined(separator: ", "))" : "waiting: \(waiting.joined(separator: ", "))")

        // The starters ask once, as they would a user; approve them so the
        // rest of the check can search them.
        for controller in app.model.controllers where controller.isWaitingForApproval {
            _ = controller.approve()
        }
        let ready = await AppDriver.waitUntil(seconds: 120) {
            app.model.controllers.allSatisfy { !$0.isWaitingForApproval && $0.isSettled }
        }
        try? await Task.sleep(for: .seconds(2))
        return ready
    }

    private static func checkPaletteOpen(_ app: AppDelegate, folder: URL) async {
        var opens = await AppDriver.paletteOpens(app, pause: .milliseconds(200))
        let first = opens.removeFirst()
        record("Palette opens the first time", first <= Budget.paletteFirstOpenMs, "\(first) ms (budget \(Budget.paletteFirstOpenMs))", ms: first)
        let sorted = opens.sorted()
        let median = sorted[sorted.count / 2], max = sorted.last ?? 0
        record("Palette opens fast after that", median <= Budget.paletteOpenMedianMs && max <= Budget.paletteOpenMaxMs,
               "median \(median) ms (budget \(Budget.paletteOpenMedianMs)), max \(max) ms (budget \(Budget.paletteOpenMaxMs))", ms: median)
        app.palette.toggle()
        _ = await AppDriver.waitUntil(seconds: 5) { app.palette.isVisible }
        if let window = app.palette.window { await shoot(window, "palette-empty", folder: folder) }
        app.palette.hide()
    }

    /// Each golden query puts the right row first, within the budget.
    private static func checkSearches(_ app: AppDelegate, folder: URL) async {
        for item in golden {
            app.palette.toggle()
            _ = await AppDriver.waitUntil(seconds: 5) { app.palette.isVisible }
            let start = Date()
            app.palette.session.query = item.query
            let found = await AppDriver.waitUntil(seconds: Budget.searchMs / 1_000 * 3) { matches(app.palette.session.selectedEntry, item.top) }
            let took = AppDriver.ms(since: start)
            let top = app.palette.session.results.prefix(3).map { $0.title }.joined(separator: " | ")
            record("\"\(item.query)\" puts \(item.top) first", found && took <= Budget.searchMs,
                   found ? "\(took) ms (budget \(Budget.searchMs))" : "top rows: \(top)", ms: found ? took : nil)
            if item.query == "saf" {
                // Files answer the same first search, with no approval
                // (first-minute 4.2: apps, sums and files on a new account).
                // A found file, not the Search Files command itself.
                func found() -> [PaletteIndex.Entry] {
                    app.palette.session.results.filter { entry in
                        guard entry.pluginName == "File Search" else { return false }
                        if case .command = entry.kind { return false }
                        return true
                    }
                }
                let files = await AppDriver.waitUntil(seconds: 8) { !found().isEmpty }
                let names = found().prefix(2).map(\.title)
                record("Files show on the first search", files, files ? names.joined(separator: ", ") : "no File Search rows for \"saf\"")
                if let window = app.palette.window { await shoot(window, "palette-results", folder: folder) }
            }
            app.palette.hide()
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Return on the first row does what it says: a sum is copied. (The
    /// 0.25 bug: Return on the first result did nothing.)
    private static func checkReturn(_ app: AppDelegate) async {
        NSPasteboard.general.clearContents()
        app.palette.toggle()
        _ = await AppDriver.waitUntil(seconds: 5) { app.palette.isVisible }
        app.palette.session.query = "12*12"
        _ = await AppDriver.waitUntil(seconds: 5) { matches(app.palette.session.selectedEntry, "144") }
        app.palette.session.submit()
        let copied = await AppDriver.waitUntil(seconds: 5) { NSPasteboard.general.string(forType: .string)?.contains("144") == true }
        let closed = await AppDriver.waitUntil(seconds: 2) { !app.palette.isVisible }
        record("Return on a sum copies it and closes", copied && closed,
               "clipboard \(NSPasteboard.general.string(forType: .string) ?? "empty"), palette closed \(closed)")
        app.palette.hide()
    }

    /// ⌘K lists actions for the selected row, and ⎋ closes it again.
    private static func checkActions(_ app: AppDelegate, folder: URL) async {
        app.palette.toggle()
        _ = await AppDriver.waitUntil(seconds: 5) { app.palette.isVisible }
        app.palette.session.query = "calendar"
        _ = await AppDriver.waitUntil(seconds: 5) { matches(app.palette.session.selectedEntry, "Calendar") }
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

    /// ⎋ out of a command puts the root back on the row that opened it,
    /// not on its first line (a palette-review leftover).
    private static func checkBack(_ app: AppDelegate) async {
        app.palette.toggle()
        _ = await AppDriver.waitUntil(seconds: 5) { app.palette.isVisible }
        let session = app.palette.session
        session.query = "search"
        // A view command below the first row, so going back has a line to keep.
        func viewCommand() -> Int? {
            session.results.indices.dropFirst().first { index in
                if case .command(let spec) = session.results[index].kind { return spec.kind == .view && spec.arguments.isEmpty }
                return false
            }
        }
        _ = await AppDriver.waitUntil(seconds: 5) { viewCommand() != nil }
        guard let index = viewCommand() else {
            record("⎋ from a command keeps the row it opened", false, "no view command below the first row for \"search\": \(session.results.prefix(5).map(\.title))")
            app.palette.hide()
            return
        }
        session.move(index)
        let chosen = session.selectedEntry
        session.submit()
        let opened = await AppDriver.waitUntil(seconds: 10) {
            if case .view = session.top { return true }
            return false
        }
        let backed = session.back()
        let kept = session.selectedEntry?.id == chosen?.id
        record("⎋ from a command keeps the row it opened", opened && backed && kept,
               "opened \(chosen?.title ?? "nothing") \(opened), back on \(session.selectedEntry?.title ?? "nothing")")
        app.palette.hide()
    }

    /// Down moves the highlight in a plugin's list right after the list
    /// opens, without Tab first. The key goes in as AppKit delivers a real
    /// one, through the panel's first responder, so it fails the way a
    /// person sees it fail when no field holds the keyboard. Each view
    /// command is tried at several delays and along three paths: opened
    /// from the root, the palette hidden and shown again on it, and Esc
    /// back to the root then opened again. The detail names what held the
    /// keyboard each time it failed.
    private static func checkArrowsInViews(_ app: AppDelegate) async {
        let session = app.palette.session
        let commands = app.model.commands.registry.entries
            .filter { $0.spec.kind == .view && $0.spec.arguments.isEmpty }
            .prefix(10)
        var tries = 0
        var failures: [String] = []
        var skipped: [String] = []

        func open(_ command: CommandRegistry.Entry) async -> CommandViewModel? {
            // As a person does it: the name typed in the root's field, then Return.
            session.query = command.spec.title
            try? await Task.sleep(for: .milliseconds(120))
            session.enter(command, source: .palette)
            _ = await AppDriver.waitUntil(seconds: 10) {
                if case .view = session.top { return true }
                return false
            }
            if case .view(let view) = session.top { return view }
            return nil
        }

        /// Waits `delay`, then presses Down; false when the highlight stayed.
        func pressAndCheck(_ view: CommandViewModel, delay: Int, label: String) async -> Bool? {
            try? await Task.sleep(for: .milliseconds(delay))
            let early = keyHolder(app.palette.window)
            guard await AppDriver.waitUntil(seconds: 5, { session.rows(of: view).count >= 2 && !view.isShowingPlaceholder }) else { return nil }
            let before = session.selectedRow(of: view)?.key
            let holder = keyHolder(app.palette.window)
            // On the last row already (a two-row list opened again), Up is
            // the arrow that can move.
            pressArrow(up: before == session.rows(of: view).last?.key, in: app.palette.window)
            await AppDriver.nextFrame()
            try? await Task.sleep(for: .milliseconds(50))
            tries += 1
            let moved = session.selectedRow(of: view)?.key != before
            if !moved { failures.append("\(label) +\(delay)ms: keyboard with \(early), then \(holder)") }
            return moved
        }

        for command in commands {
            let title = command.spec.title
            commandLoop: for round in 0..<3 {
                for delay in [0, 40, 120, 400] {
                    app.palette.toggle()
                    _ = await AppDriver.waitUntil(seconds: 5) { app.palette.isVisible }
                    await AppDriver.nextFrame()
                    guard let view = await open(command) else {
                        skipped.append("\(title) didn't open")
                        app.palette.hide()
                        break commandLoop
                    }
                    guard await pressAndCheck(view, delay: delay, label: "\(title) opened") != nil else {
                        skipped.append("\(title) has under 2 rows")
                        app.palette.hide()
                        break commandLoop
                    }
                    if round == 0 {
                        // Hidden and shown again within the resume window: back on the view.
                        app.palette.toggle()
                        try? await Task.sleep(for: .milliseconds(150))
                        app.palette.toggle()
                        _ = await AppDriver.waitUntil(seconds: 5) { app.palette.isVisible }
                        if case .view(let resumed) = session.top {
                            _ = await pressAndCheck(resumed, delay: delay, label: "\(title) resumed")
                        }
                    } else if round == 1 {
                        // Esc to the root, then the same command again.
                        _ = session.back()
                        await AppDriver.nextFrame()
                        session.enter(command, source: .palette)
                        _ = await AppDriver.waitUntil(seconds: 10) {
                            if case .view(let again) = session.top { return again !== view }
                            return false
                        }
                        if case .view(let again) = session.top {
                            _ = await pressAndCheck(again, delay: delay, label: "\(title) after Esc")
                        }
                    }
                    app.palette.hide()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        record("Down moves in a plugin's list right after it opens", tries > 0 && failures.isEmpty,
               "\(tries - failures.count)/\(tries) moved. Failed: \(failures.joined(separator: "; ")). Skipped: \(skipped.joined(separator: "; "))")
    }

    /// With the keyboard taken from every field on purpose, Down still
    /// moves the highlight and the view's field takes the keyboard back,
    /// so a focus lost some other way never leaves the arrows dead.
    private static func checkStrayKeys(_ app: AppDelegate) async {
        let session = app.palette.session
        let commands = app.model.commands.registry.entries.filter { $0.spec.kind == .view && $0.spec.arguments.isEmpty }
        for command in commands {
            app.palette.toggle()
            _ = await AppDriver.waitUntil(seconds: 5) { app.palette.isVisible }
            session.enter(command, source: .palette)
            let ready = await AppDriver.waitUntil(seconds: 10) {
                guard case .view(let view) = session.top else { return false }
                return session.rows(of: view).count >= 2 && !view.isShowingPlaceholder
            }
            guard ready, case .view(let view) = session.top, let window = app.palette.window else {
                app.palette.hide()
                continue
            }
            try? await Task.sleep(for: .milliseconds(300))
            window.makeFirstResponder(nil)
            let taken = keyHolder(window)
            let before = session.selectedRow(of: view)?.key
            pressArrow(up: before == session.rows(of: view).last?.key, in: window)
            await AppDriver.nextFrame()
            try? await Task.sleep(for: .milliseconds(300))
            let moved = session.selectedRow(of: view)?.key != before
            let holder = keyHolder(window)
            let back = holder.hasPrefix("field")
            record("Down works with no field holding the keyboard", moved && back,
                   "\(command.spec.title): keyboard with \(taken); Down moved \(moved); then keyboard with \(holder)")
            app.palette.hide()
            return
        }
        record("Down works with no field holding the keyboard", false, "no view command with 2 rows to try")
    }

    /// A plain Down (or Up) arrow, delivered as AppKit delivers a real key press.
    private static func pressArrow(up: Bool = false, in window: NSWindow?) {
        let character = up ? "\u{F700}" : "\u{F701}"
        guard let window, let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: up ? 126 : 125
        ) else { return }
        NSApp.sendEvent(event)
    }

    /// What holds the keyboard in the window: a text field (by its
    /// placeholder), or the class of whatever else is first responder.
    private static func keyHolder(_ window: NSWindow?) -> String {
        guard let window else { return "no window" }
        let key = window.isKeyWindow ? "" : " (window not key)"
        guard let responder = window.firstResponder else { return "nothing" + key }
        if let editor = responder as? NSTextView, let field = editor.delegate as? NSTextField {
            return "field \"\(field.placeholderString ?? "")\"" + key
        }
        if responder === window { return "the window itself" + key }
        return String(describing: type(of: responder)) + key
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
            guard let window = app.settingsWindow, window.isVisible else { continue }
            shown += 1
            await shoot(window, file, folder: folder)
        }
        record("Settings opens on every page", shown == pages.count, "\(shown) of \(pages.count) pages shown")
        app.settingsWindow?.close()
    }

    private static func checkStore(_ app: AppDelegate, folder: URL) async {
        app.showStore()
        let shown = await AppDriver.waitUntil(seconds: 5) { app.storeWindow?.isVisible == true }
        // Let the index load and the cards draw.
        try? await Task.sleep(for: .seconds(4))
        if let window = app.storeWindow { await shoot(window, "store", folder: folder) }
        let listed = app.model.store.catalogs.reduce(0) { $0 + $1.index.plugins.count }
        record("Store opens and lists plugins", shown && listed > 0, "visible \(shown), \(listed) listings")
        app.storeWindow?.close()
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
    /// no Screen Recording permission. Glass the window server composites
    /// (a sidebar, the palette's backdrop) comes out blank; the content is
    /// what these are for.
    private static func shoot(_ window: NSWindow, _ name: String, folder: URL) async {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            try? await Task.sleep(for: .milliseconds(400))
            await AppDriver.nextFrame()
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
}
#endif
