import Foundation
import StackbarProtocol

/// The parts of the OS the host reads and changes for plugins: the clipboard,
/// power assertions, battery and running apps, and the calendar.
///
/// The app implements this with AppKit, IOKit and EventKit. `stackbarctl` and the
/// tests use `SimulatedSystem`, so plugins that use these calls build, render
/// and are tested on Linux too. Capabilities are checked in `HostServices`
/// before any of this is reached.
public protocol SystemServices: Sendable {
    /// Cheap; polled twice a second while a plugin has a `.clipboard` trigger.
    func clipboardChangeCount() -> Int
    func readClipboard() -> ClipboardItem?
    func writeClipboard(_ content: ClipboardContent) throws
    /// Writes the content, then pastes it into the app the user was in,
    /// moving the caret and restoring the clipboard as `options` say.
    func paste(_ content: ClipboardContent, options: PasteOptions) async throws
    /// Holds (or with `nil` releases) the plugin's power assertion.
    func keepAwake(_ request: KeepAwakeRequest?, pluginID: String) throws
    func systemStatus() -> SystemStatus
    func calendarEvents(from: Date, to: Date) async throws -> [CalendarEvent]
    /// The frontmost app, its focused window's title and the selected text
    /// (at most `InvocationContext.maxSelectedText`), read now.
    func context() async -> InvocationContext
    /// The paths selected in Finder's frontmost window, read now.
    func finderSelection() async throws -> [String]
    /// An Open panel; nil when the user cancelled.
    func chooseFile(types: [String], for pluginName: String) async throws -> ChosenFile?
    /// A Save panel; the path written, or nil when the user cancelled.
    func saveFile(name: String, data: Data, for pluginName: String) async throws -> String?
    /// An installed app's bundle id, from its name, path or bundle id.
    func resolveApplication(_ nameOrPath: String) async -> String?
    /// The displays and the regular apps' windows, front to back.
    func windows() async throws -> WindowSnapshot
    /// Moves windows to the placements (matched with `WindowMatcher`),
    /// opening apps that aren't running first when `launch` is set.
    func arrangeWindows(_ placements: [WindowPlacement], launch: Bool) async throws -> ArrangeResult
    /// Brings one window to the front, with its app.
    func focusWindow(_ target: WindowTarget) async throws
    /// The menu bar of the app the user was in before Stackbar.
    func menuItems() async throws -> MenuSnapshot
    /// Chooses a menu item of a running app by its path of titles.
    func pressMenuItem(appID: String, path: [String]) async throws
    /// The regular apps that are running, in launch order.
    func runningApps() async throws -> [RunningApp]
    /// Brings a running app to the front; with `launch`, opens it when it
    /// isn't running.
    func activateApp(_ id: String, launch: Bool) async throws
    func hideApp(_ id: String) async throws
    /// Registers (or with `nil` removes) a plugin's key layer.
    func setKeyLayer(_ layer: KeyLayer?, pluginID: String, pluginName: String) throws -> KeyLayerStatus
    func keyLayerStatus(pluginID: String) -> KeyLayerStatus
    /// Registers (or with an empty list removes) a plugin's keywords.
    func setExpansions(_ expansions: [TextExpansion], pluginID: String, pluginName: String) throws -> ExpansionStatus
    func expansionStatus(pluginID: String) -> ExpansionStatus
    /// Whether Stackbar may use Reminders; with `ask`, asks when macOS
    /// hasn't asked yet.
    func reminderAccess(ask: Bool) async -> ReminderAccess
    func reminderLists() async throws -> [ReminderList]
    func createReminderList(title: String, color: String?) async throws -> ReminderList
    func reminders(_ query: ReminderQuery) async throws -> [Reminder]
    /// Creates (empty id) or writes `fields` (nil for all) onto the current
    /// reminder, and answers with what was saved.
    func saveReminder(_ reminder: Reminder, fields: [Reminder.Field]?) async throws -> Reminder
    func deleteReminder(id: String) async throws
    /// The installed apps and System Settings panes, by name.
    func installedApps() async throws -> [InstalledApp]
    /// Files in the user's home whose names hold every word, most recently
    /// used first, without app bundles, their insides, hidden files or
    /// Library internals.
    func findFiles(_ query: FileQuery) async throws -> [FoundFile]
    /// Locks, sleeps, restarts the Mac and the like.
    func perform(_ action: SystemAction) async throws
    /// Adds an event, or changes the one `draft.id` names.
    func saveCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent
    /// The calendars events can be added to.
    func writableCalendars() async throws -> [CalendarInfo]
    /// Opens the user's terminal app running a program and its arguments.
    func openInTerminal(_ command: [String], title: String?) async throws
    /// The text in a kept clipboard image.
    func recognizeText(imageID: String, languages: [String]?) async throws -> RecognizedText
    /// The text in a part of the screen the user drags over; nil on Esc.
    func captureScreenText(languages: [String]?) async throws -> RecognizedText?
    /// Temperatures and fan speeds.
    func sensors() async throws -> [SensorReading]
}

extension SystemServices {
    public func context() async -> InvocationContext { InvocationContext() }
    public func finderSelection() async throws -> [String] { throw SystemServiceError("Finder is not available on this platform") }
    public func chooseFile(types: [String], for pluginName: String) async throws -> ChosenFile? { throw SystemServiceError("choosing files is not available on this platform") }
    public func saveFile(name: String, data: Data, for pluginName: String) async throws -> String? { throw SystemServiceError("saving files is not available on this platform") }
    public func resolveApplication(_ nameOrPath: String) async -> String? { nil }
    public func windows() async throws -> WindowSnapshot { throw SystemServiceError("windows are not available on this platform") }
    public func arrangeWindows(_ placements: [WindowPlacement], launch: Bool) async throws -> ArrangeResult { throw SystemServiceError("windows are not available on this platform") }
    public func focusWindow(_ target: WindowTarget) async throws { throw SystemServiceError("windows are not available on this platform") }
    public func menuItems() async throws -> MenuSnapshot { throw SystemServiceError("menus are not available on this platform") }
    public func pressMenuItem(appID: String, path: [String]) async throws { throw SystemServiceError("menus are not available on this platform") }
    public func runningApps() async throws -> [RunningApp] { throw SystemServiceError("apps are not available on this platform") }
    public func activateApp(_ id: String, launch: Bool) async throws { throw SystemServiceError("apps are not available on this platform") }
    public func hideApp(_ id: String) async throws { throw SystemServiceError("apps are not available on this platform") }
    public func setKeyLayer(_ layer: KeyLayer?, pluginID: String, pluginName: String) throws -> KeyLayerStatus {
        if layer == nil { return .off }
        throw SystemServiceError("key layers are not available on this platform")
    }
    public func keyLayerStatus(pluginID: String) -> KeyLayerStatus { .off }
    public func setExpansions(_ expansions: [TextExpansion], pluginID: String, pluginName: String) throws -> ExpansionStatus {
        if expansions.isEmpty { return .off }
        throw SystemServiceError("text expansion is not available on this platform")
    }
    public func expansionStatus(pluginID: String) -> ExpansionStatus { .off }
    public func installedApps() async throws -> [InstalledApp] { throw SystemServiceError("apps are not available on this platform") }
    public func findFiles(_ query: FileQuery) async throws -> [FoundFile] { throw SystemServiceError("finding files is not available on this platform") }
    public func perform(_ action: SystemAction) async throws { throw SystemServiceError("system actions are not available on this platform") }
    public func saveCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent { throw SystemServiceError("adding calendar events is not available on this platform") }
    public func writableCalendars() async throws -> [CalendarInfo] { throw SystemServiceError("calendars are not available on this platform") }
    public func openInTerminal(_ command: [String], title: String?) async throws { throw SystemServiceError("opening a terminal is not available on this platform") }
    public func recognizeText(imageID: String, languages: [String]?) async throws -> RecognizedText { throw SystemServiceError("reading text in images is not available on this platform") }
    public func captureScreenText(languages: [String]?) async throws -> RecognizedText? { throw SystemServiceError("reading text on screen is not available on this platform") }
    public func sensors() async throws -> [SensorReading] { throw SystemServiceError("sensors are not available on this platform") }
    public func reminderAccess(ask: Bool) async -> ReminderAccess { .unavailable }
    public func reminderLists() async throws -> [ReminderList] { throw SystemServiceError("Reminders is not available on this platform") }
    public func createReminderList(title: String, color: String?) async throws -> ReminderList { throw SystemServiceError("Reminders is not available on this platform") }
    public func reminders(_ query: ReminderQuery) async throws -> [Reminder] { throw SystemServiceError("Reminders is not available on this platform") }
    public func saveReminder(_ reminder: Reminder, fields: [Reminder.Field]?) async throws -> Reminder { throw SystemServiceError("Reminders is not available on this platform") }
    public func deleteReminder(id: String) async throws { throw SystemServiceError("Reminders is not available on this platform") }
}

public struct SystemServiceError: Error, CustomStringConvertible, Sendable {
    public var description: String
    public init(_ description: String) { self.description = description }
}

/// A system with no clipboard, power or calendar, for hosts that have none.
public struct UnsupportedSystem: SystemServices {
    public init() {}
    private var error: SystemServiceError { SystemServiceError("not available on this platform") }
    public func clipboardChangeCount() -> Int { 0 }
    public func readClipboard() -> ClipboardItem? { nil }
    public func writeClipboard(_ content: ClipboardContent) throws { throw error }
    public func paste(_ content: ClipboardContent, options: PasteOptions) async throws { throw error }
    public func keepAwake(_ request: KeepAwakeRequest?, pluginID: String) throws { if request != nil { throw error } }
    public func systemStatus() -> SystemStatus { SystemStatus() }
    public func calendarEvents(from: Date, to: Date) async throws -> [CalendarEvent] { throw error }
}

/// An in-memory system for `stackbarctl` and tests: a clipboard you copy to with
/// `simulateCopy`, power assertions that are only recorded, a fixed battery,
/// and calendar events you set (or a sample day built around now).
public final class SimulatedSystem: SystemServices, @unchecked Sendable {
    private let lock = NSLock()
    private var changeCount = 0
    private var item: ClipboardItem?
    private var assertions: [String: KeepAwakeRequest] = [:]
    private var status: SystemStatus
    private var events: [CalendarEvent]
    /// Plain text of simulated formatted copies, by content id.
    private var stored: [String: String] = [:]
    private var simulatedContext = InvocationContext(frontmostApp: .init(bundleID: "com.apple.Safari", name: "Safari"), windowTitle: "Stackbar")
    /// Every paste, in order (for tests).
    public var pasted: [ClipboardContent] { lock.withLock { pastes.map(\.content) } }
    /// Every paste with its options, in order (for tests).
    public private(set) var pastes: [(content: ClipboardContent, options: PasteOptions)] = []
    /// How long after a paste the clipboard is put back (0.5 s on the Mac).
    public var restoreDelay: Duration = .milliseconds(500)
    private var performedActions: [SystemAction] = []
    /// Every system action asked for, in order (for tests and `render`).
    public var performed: [SystemAction] { lock.withLock { performedActions } }

    public func perform(_ action: SystemAction) async throws {
        lock.withLock { performedActions.append(action) }
    }

    public init(status: SystemStatus = SystemStatus(batteryLevel: 0.8, charging: false, onACPower: false, runningApps: [.init(id: "com.apple.Safari", name: "Safari"), .init(id: "com.apple.dt.Xcode", name: "Xcode")]), events: [CalendarEvent]? = nil) {
        self.status = status
        self.events = events ?? Self.sampleDay()
    }

    /// Reads `STACKBAR_CALENDAR` (a JSON file of `[CalendarEvent]`) and
    /// `STACKBAR_CONTEXT` (`InvocationContext` as JSON, inline or a file) and
    /// `STACKBAR_WINDOWS` (`WindowSnapshot` as JSON, inline or a file) and
    /// `STACKBAR_APPS` (`[RunningApp]` as JSON, inline or a file) and
    /// `STACKBAR_REMINDERS` (`SimulatedReminders` as JSON, inline or a file)
    /// and `STACKBAR_MENUS` (`MenuSnapshot` as JSON, inline or a file) when
    /// set.
    public static func fromEnvironment() -> SimulatedSystem {
        let environment = ProcessInfo.processInfo.environment
        var events: [CalendarEvent]?
        if let path = environment["STACKBAR_CALENDAR"], let text = try? String(contentsOfFile: path, encoding: .utf8) {
            events = try? SystemCodec.decode([CalendarEvent].self, from: text)
        }
        let system = SimulatedSystem(events: events)
        if let value = environment["STACKBAR_WINDOWS"] {
            let text = value.hasPrefix("{") ? value : ((try? String(contentsOfFile: value, encoding: .utf8)) ?? "")
            if let windows = try? SystemCodec.decode(WindowSnapshot.self, from: text) { system.simulate(windows: windows) }
        }
        if let value = environment["STACKBAR_APPS"] {
            let text = value.hasPrefix("[") ? value : ((try? String(contentsOfFile: value, encoding: .utf8)) ?? "")
            if let apps = try? SystemCodec.decode([RunningApp].self, from: text) { system.simulate(apps: apps) }
        }
        if let value = environment["STACKBAR_MENUS"] {
            let text = value.hasPrefix("{") ? value : ((try? String(contentsOfFile: value, encoding: .utf8)) ?? "")
            if let menus = try? SystemCodec.decode(MenuSnapshot.self, from: text) { system.simulate(menus: menus) }
        }
        if let value = environment["STACKBAR_REMINDERS"] {
            let text = value.hasPrefix("{") ? value : ((try? String(contentsOfFile: value, encoding: .utf8)) ?? "")
            if let state = try? SystemCodec.decode(SimulatedReminders.self, from: text) { system.simulate(reminders: state) }
        }
        if let value = environment["STACKBAR_CONTEXT"] {
            let text = value.hasPrefix("{") ? value : ((try? String(contentsOfFile: value, encoding: .utf8)) ?? "")
            if let context = try? SystemCodec.decode(InvocationContext.self, from: text) { system.simulate(context: context) }
        }
        return system
    }

    private var chosen: [ChosenFile?] = []
    /// Every Save panel answered, in order (for tests).
    public private(set) var saved: [(name: String, data: Data)] = []
    /// Installed apps by name, for `resolveApplication`.
    public var applications: [String: String] = ["Safari": "com.apple.Safari", "Google Chrome": "com.google.Chrome", "Xcode": "com.apple.dt.Xcode", "Finder": "com.apple.finder"]

    /// The next Open panel picks this file (`nil`: the user cancels).
    public func simulate(chosenFile: ChosenFile?) { lock.withLock { chosen.append(chosenFile) } }

    public func chooseFile(types: [String], for pluginName: String) async throws -> ChosenFile? {
        lock.withLock { chosen.isEmpty ? nil : chosen.removeFirst() }
    }

    public func saveFile(name: String, data: Data, for pluginName: String) async throws -> String? {
        lock.withLock {
            saved.append((name, data))
            return "/Users/you/Downloads/" + name
        }
    }

    public func resolveApplication(_ nameOrPath: String) async -> String? {
        let apps = lock.withLock { applications }
        if apps.values.contains(nameOrPath) { return nameOrPath }
        let name = nameOrPath.hasSuffix(".app") ? ((nameOrPath as NSString).lastPathComponent as NSString).deletingPathExtension : nameOrPath
        return apps.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private var simulatedWindows = SimulatedSystem.sampleWindows()
    /// Apps `arrangeWindows(launch: true)` can open, with the windows they
    /// come up with (by default: one window at the main display's top-left).
    public var launchable: [String: [WindowInfo]] = [:]

    /// The displays and windows `windows()` reports and `arrangeWindows` moves.
    public func simulate(windows: WindowSnapshot) { lock.withLock { simulatedWindows = windows } }
    public var currentWindows: WindowSnapshot { lock.withLock { simulatedWindows } }

    public func windows() async throws -> WindowSnapshot { lock.withLock { simulatedWindows } }

    public func arrangeWindows(_ placements: [WindowPlacement], launch: Bool) async throws -> ArrangeResult {
        lock.withLock {
            var snapshot = simulatedWindows
            var result = ArrangeResult()
            if launch {
                let running = Set(snapshot.windows.map(\.appID))
                var openedIDs: [String] = []
                for placement in placements where !running.contains(placement.appID) && !openedIDs.contains(placement.appID) {
                    guard let windows = launchable[placement.appID] ?? (applications.values.contains(placement.appID) ? [WindowInfo(appID: placement.appID, appName: placement.appName, frame: WindowRect(x: 0, y: 25, width: 800, height: 600))] : nil) else { continue }
                    openedIDs.append(placement.appID)
                    result.opened.append(placement.appName)
                    snapshot.windows += windows
                }
            }
            let match = WindowMatcher.match(placements, to: snapshot.windows)
            for assignment in match.assignments.reversed() {
                let placement = placements[assignment.placement]
                var window = snapshot.windows[assignment.window]
                if window.frame != placement.frame || window.isMinimized != placement.isMinimized { result.moved += 1 }
                window.frame = placement.frame
                window.isMinimized = placement.isMinimized
                window.displayID = snapshot.display(for: placement.frame)?.id
                snapshot.windows[assignment.window] = window
            }
            result.missing = match.missing.map { placements[$0].appName }
            // Restored windows come to the front in the saved order; the
            // rest keep theirs behind them.
            let front = match.assignments.sorted { $0.placement < $1.placement }.map(\.window)
            let rest = snapshot.windows.indices.filter { !front.contains($0) }.sorted { snapshot.windows[$0].order < snapshot.windows[$1].order }
            var ordered = (front + rest).map { snapshot.windows[$0] }
            for index in ordered.indices { ordered[index].order = index }
            simulatedWindows = WindowSnapshot(displays: snapshot.displays, windows: ordered)
            return result
        }
    }

    public func focusWindow(_ target: WindowTarget) async throws {
        try lock.withLock {
            var windows = simulatedWindows.windows
            guard let index = target.index(in: windows) else { throw SystemServiceError("\(target.appID) has no such window") }
            var window = windows.remove(at: index)
            window.isMinimized = false
            windows.insert(window, at: 0)
            for position in windows.indices { windows[position].order = position }
            simulatedWindows = WindowSnapshot(displays: simulatedWindows.displays, windows: windows)
            appActions.append("focus \(target.appID) \(window.title)")
        }
    }

    // MARK: Menus

    private var simulatedMenus = SimulatedSystem.sampleMenus()
    /// The menu bar `menuItems()` reports and `pressMenuItem` chooses from.
    public func simulate(menus: MenuSnapshot) { lock.withLock { simulatedMenus = menus } }

    public func menuItems() async throws -> MenuSnapshot { lock.withLock { simulatedMenus } }

    public func pressMenuItem(appID: String, path: [String]) async throws {
        try lock.withLock {
            guard simulatedMenus.appID == appID else { throw SystemServiceError("\(appID) isn't the app whose menus were read") }
            guard let item = simulatedMenus.items.first(where: { $0.path == path }) else { throw SystemServiceError("no menu item \(path.joined(separator: " > "))") }
            guard item.isEnabled else { throw SystemServiceError("\(item.title) is dimmed right now") }
            appActions.append("press \(appID) \(path.joined(separator: " > "))")
        }
    }

    static func sampleMenus() -> MenuSnapshot {
        MenuSnapshot(appID: "com.apple.Safari", appName: "Safari", items: [
            MenuItemInfo(path: ["Safari", "Settings…"], shortcut: "⌘,"),
            MenuItemInfo(path: ["File", "New Window"], shortcut: "⌘N"),
            MenuItemInfo(path: ["File", "New Private Window"], shortcut: "⇧⌘N"),
            MenuItemInfo(path: ["File", "Export as PDF…"]),
            MenuItemInfo(path: ["Edit", "Undo"], shortcut: "⌘Z", isEnabled: false),
            MenuItemInfo(path: ["View", "Show Tab Bar"], shortcut: "⇧⌘T", isChecked: true),
            MenuItemInfo(path: ["View", "Zoom In"], shortcut: "⌘+"),
            MenuItemInfo(path: ["History", "Show All History"], shortcut: "⌘Y"),
            MenuItemInfo(path: ["Bookmarks", "Add Bookmark…"], shortcut: "⌘D"),
            MenuItemInfo(path: ["Window", "Merge All Windows"]),
        ])
    }

    // MARK: Apps and key layers

    private var simulatedApps = SimulatedSystem.sampleApps()
    /// Every key layer registered, and what presses do with them.
    public let keyLayers = KeyLayerRegistry()
    public let expansions = TextExpansionRegistry()
    /// Every app the simulated windows cycled, hid or opened, in order (for
    /// tests): `"cycleWindows com.apple.Safari"` and so on.
    public private(set) var appActions: [String] = []

    /// The apps `runningApps()` reports; one `isActive` is the frontmost.
    public func simulate(apps: [RunningApp]) { lock.withLock { simulatedApps = apps } }
    public var currentApps: [RunningApp] { lock.withLock { simulatedApps } }

    public func runningApps() async throws -> [RunningApp] { lock.withLock { simulatedApps } }

    public func activateApp(_ id: String, launch: Bool) async throws {
        try lock.withLock {
            if simulatedApps.contains(where: { $0.id == id }) {
                frontLocked(id)
            } else if launch, let name = applications.first(where: { $0.value == id })?.key {
                simulatedApps.append(RunningApp(id: id, name: name, path: "/Applications/\(name).app"))
                appActions.append("launch \(id)")
                frontLocked(id)
            } else {
                throw SystemServiceError(launch ? "no app \(id) is installed" : "\(id) isn't running")
            }
        }
    }

    public func hideApp(_ id: String) async throws {
        try lock.withLock {
            guard let index = simulatedApps.firstIndex(where: { $0.id == id }) else { throw SystemServiceError("\(id) isn't running") }
            simulatedApps[index].isHidden = true
            if simulatedApps[index].isActive {
                simulatedApps[index].isActive = false
                // The next visible app comes forward, as on the Mac.
                if let next = simulatedApps.firstIndex(where: { !$0.isHidden }) { simulatedApps[next].isActive = true }
            }
            appActions.append("hide \(id)")
        }
    }

    private func frontLocked(_ id: String) {
        for index in simulatedApps.indices {
            simulatedApps[index].isActive = simulatedApps[index].id == id
            if simulatedApps[index].id == id { simulatedApps[index].isHidden = false }
        }
    }

    public func setKeyLayer(_ layer: KeyLayer?, pluginID: String, pluginName: String) throws -> KeyLayerStatus {
        try keyLayers.set(layer, pluginID: pluginID, pluginName: pluginName)
        return keyLayerStatus(pluginID: pluginID)
    }

    public func keyLayerStatus(pluginID: String) -> KeyLayerStatus {
        guard keyLayers.registration(for: pluginID) != nil else { return .off }
        let conflict = keyLayers.conflict(for: pluginID)
        return KeyLayerStatus(listening: conflict == nil, conflict: conflict)
    }

    public func setExpansions(_ expansions: [TextExpansion], pluginID: String, pluginName: String) throws -> ExpansionStatus {
        try self.expansions.set(expansions, pluginID: pluginID, pluginName: pluginName)
        return expansionStatus(pluginID: pluginID)
    }

    public func expansionStatus(pluginID: String) -> ExpansionStatus {
        let count = expansions.count(for: pluginID)
        guard count > 0 else { return .off }
        return ExpansionStatus(listening: true, keywords: count, taken: expansions.taken(for: pluginID))
    }

    /// Presses `key` with `held` down, as the Mac tap would, and applies what
    /// the router decides. Returns the decision; an assignment is returned
    /// for the caller to run as a command.
    @discardableResult
    public func pressKeyLayer(_ key: String, held: Set<KeyLayerTrigger> = [.rightCommand]) async -> KeyLayerRouter.Decision {
        let decision = KeyLayerRouter.route(key: key, held: held, layers: keyLayers.listening, running: currentApps)
        switch decision {
        case .activate(let id): try? await activateApp(id, launch: false)
        case .launch(let id): try? await activateApp(id, launch: true)
        case .hide(let id): try? await hideApp(id)
        case .cycleWindows(let id): lock.withLock { appActions.append("cycleWindows \(id)") }
        case .passThrough, .swallow, .assign: break
        }
        return decision
    }

    // MARK: Installed apps and files

    /// `applications` as installed apps, with two Settings panes.
    public func installedApps() async throws -> [InstalledApp] {
        let apps = lock.withLock { applications }
        let installed = apps.map { InstalledApp(id: $0.value, name: $0.key, path: "/Applications/\($0.key).app") }
        let panes = [
            InstalledApp(id: "com.apple.Wi-Fi-Settings.extension", name: "Wi-Fi", path: "/System/Applications/System Settings.app", kind: .settingsPane,
                         url: "x-apple.systempreferences:com.apple.Wi-Fi-Settings.extension"),
            InstalledApp(id: "com.apple.Displays-Settings.extension", name: "Displays", path: "/System/Applications/System Settings.app", kind: .settingsPane,
                         url: "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
        ]
        return (installed + panes).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The files `findFiles` searches.
    public var simulatedFiles: [FoundFile] = SimulatedSystem.sampleFiles()

    public func findFiles(_ query: FileQuery) async throws -> [FoundFile] {
        let words = query.text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let files = lock.withLock { simulatedFiles }
        return Array(files.filter { file in words.allSatisfy { file.name.lowercased().contains($0) } }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
            .prefix(query.limit))
    }

    public static func sampleFiles() -> [FoundFile] {
        let now = Date()
        return [
            FoundFile(path: "/Users/you/Documents/Q3 plan.pdf", name: "Q3 plan.pdf", folder: "~/Documents", lastUsed: now.addingTimeInterval(-3600)),
            FoundFile(path: "/Users/you/Documents/Plans", name: "Plans", folder: "~/Documents", isFolder: true, lastUsed: now.addingTimeInterval(-7200)),
            FoundFile(path: "/Users/you/Desktop/plan sketch.png", name: "plan sketch.png", folder: "~/Desktop", lastUsed: now.addingTimeInterval(-86400)),
            FoundFile(path: "/Users/you/Downloads/invoice-2026-10.pdf", name: "invoice-2026-10.pdf", folder: "~/Downloads", lastUsed: now.addingTimeInterval(-172_800)),
            FoundFile(path: "/Users/you/code/stackbar/README.md", name: "README.md", folder: "~/code/stackbar", lastUsed: now.addingTimeInterval(-600)),
        ]
    }

    /// Safari in front, with Xcode, Slack and Spotify behind it.
    public static func sampleApps() -> [RunningApp] {
        [
            RunningApp(id: "com.apple.finder", name: "Finder", path: "/System/Library/CoreServices/Finder.app"),
            RunningApp(id: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app", isActive: true),
            RunningApp(id: "com.apple.dt.Xcode", name: "Xcode", path: "/Applications/Xcode.app"),
            RunningApp(id: "com.tinyspeck.slackmacgap", name: "Slack", path: "/Applications/Slack.app"),
            RunningApp(id: "com.spotify.client", name: "Spotify", path: "/Applications/Spotify.app"),
        ]
    }

    /// A laptop on a desk display: Xcode and Safari on the big screen,
    /// Slack on the laptop.
    public static func sampleWindows() -> WindowSnapshot {
        let desk = DisplayInfo(id: "9C1E4F2B-7A1D-4E59-8C3A-5B2F6D0E1A44", name: "Studio Display", frame: WindowRect(x: 0, y: 0, width: 2560, height: 1440), visibleFrame: WindowRect(x: 0, y: 33, width: 2560, height: 1407), isMain: true)
        let laptop = DisplayInfo(id: "37D8832A-2D66-02CA-B9F7-8F30A301B230", name: "Built-in Retina Display", frame: WindowRect(x: 2560, y: 458, width: 1512, height: 982), isBuiltIn: true)
        return WindowSnapshot(displays: [desk, laptop], windows: [
            WindowInfo(appID: "com.apple.dt.Xcode", appName: "Xcode", title: "Stackbar — Windows.swift", frame: WindowRect(x: 0, y: 33, width: 1700, height: 1407), displayID: desk.id, order: 0),
            WindowInfo(appID: "com.apple.Safari", appName: "Safari", title: "Stackbar docs", frame: WindowRect(x: 1700, y: 33, width: 860, height: 1407), displayID: desk.id, order: 1),
            WindowInfo(appID: "com.tinyspeck.slackmacgap", appName: "Slack", title: "Slack — navbytes", frame: WindowRect(x: 2560, y: 458, width: 1512, height: 982), displayID: laptop.id, order: 2),
            WindowInfo(appID: "com.apple.Safari", appName: "Safari", title: "Pull requests", frame: WindowRect(x: 400, y: 200, width: 1200, height: 900), displayID: desk.id, order: 3, isMinimized: true),
        ])
    }

    /// What the user is in: `context()` and `finderSelection()` return it.
    public func simulate(context: InvocationContext) { lock.withLock { simulatedContext = context } }
    public var currentContext: InvocationContext { lock.withLock { simulatedContext } }

    public func context() async -> InvocationContext {
        lock.withLock {
            var context = simulatedContext
            context.finderSelection = nil
            context.selectedText = context.selectedText.map(InvocationContext.capped)
            return context
        }
    }

    public func finderSelection() async throws -> [String] {
        lock.withLock { simulatedContext.finderSelection ?? [] }
    }

    /// The user copied something in another app.
    /// The user copied something in another app. `formatted` makes it
    /// rich text the host keeps a content id for.
    public func simulateCopy(_ text: String, app: SystemStatus.App? = SystemStatus.App(id: "com.apple.Safari", name: "Safari"), concealed: Bool = false, formatted: Bool = false) {
        lock.withLock {
            changeCount += 1
            let isURL = text.hasPrefix("https://") || text.hasPrefix("http://")
            let contentID = formatted && !concealed ? "rich\(changeCount)" : nil
            if let contentID { stored[contentID] = text }
            item = ClipboardItem(changeCount: changeCount, kind: isURL ? .url : .text, text: concealed ? nil : text, contentID: contentID, sourceAppID: app?.id, sourceAppName: app?.name, concealed: concealed)
        }
    }

    public func simulate(status: SystemStatus) { lock.withLock { self.status = status } }
    public func simulate(events: [CalendarEvent]) { lock.withLock { self.events = events } }

    // MARK: Reminders

    private var reminderState = SimulatedReminders.sample()
    private var nextReminderID = 1

    /// Replaces the simulated lists, reminders and access.
    public func simulate(reminders state: SimulatedReminders) { lock.withLock { reminderState = state } }
    /// The simulated lists, reminders and access, as they are now.
    public var simulatedReminders: SimulatedReminders { lock.withLock { reminderState } }

    public func reminderAccess(ask: Bool) async -> ReminderAccess {
        lock.withLock {
            if ask, reminderState.access == .notDetermined { reminderState.access = reminderState.grantWhenAsked ? .granted : .denied }
            return reminderState.access
        }
    }

    private func requireReminders() throws {
        switch lock.withLock({ reminderState.access }) {
        case .granted: return
        case .notDetermined:
            let granted = lock.withLock {
                reminderState.access = reminderState.grantWhenAsked ? .granted : .denied
                return reminderState.access == .granted
            }
            if !granted { throw SystemServiceError("Reminders access was declined; allow Stackbar in System Settings > Privacy & Security > Reminders") }
        case .denied: throw SystemServiceError("Stackbar has no access to your reminders; allow it in System Settings > Privacy & Security > Reminders")
        case .unavailable: throw SystemServiceError("Reminders is not available on this platform")
        }
    }

    public func reminderLists() async throws -> [ReminderList] {
        try requireReminders()
        return lock.withLock { reminderState.lists }
    }

    public func createReminderList(title: String, color: String?) async throws -> ReminderList {
        try requireReminders()
        return lock.withLock {
            let list = ReminderList(id: "list-\(reminderState.lists.count + 1)", title: title, color: color, account: "iCloud")
            reminderState.lists.append(list)
            return list
        }
    }

    public func reminders(_ query: ReminderQuery) async throws -> [Reminder] {
        try requireReminders()
        return lock.withLock {
            reminderState.reminders.filter { reminder in
                guard query.lists?.contains(reminder.list) ?? true else { return false }
                guard let completed = reminder.completed else { return true }
                return query.completedSince.map { completed >= $0 } ?? false
            }
        }
    }

    public func saveReminder(_ reminder: Reminder, fields: [Reminder.Field]?) async throws -> Reminder {
        try requireReminders()
        return try lock.withLock {
            if reminder.id.isEmpty {
                var saved = reminder
                saved.id = "reminder-\(nextReminderID)"
                saved.externalID = saved.id
                nextReminderID += 1
                if saved.list.isEmpty { saved.list = reminderState.lists.first(where: \.isDefault)?.id ?? reminderState.lists.first?.id ?? "" }
                guard reminderState.lists.contains(where: { $0.id == saved.list }) else { throw SystemServiceError("no Reminders list \(saved.list)") }
                saved.modified = Date()
                reminderState.reminders.append(saved)
                return saved
            }
            guard let index = reminderState.reminders.firstIndex(where: { $0.id == reminder.id }) else {
                throw SystemServiceError("no reminder \(reminder.id); it may have been deleted")
            }
            var saved = reminderState.reminders[index].applying(reminder, fields: fields)
            guard reminderState.lists.contains(where: { $0.id == saved.list }) else { throw SystemServiceError("no Reminders list \(saved.list)") }
            saved.modified = Date()
            reminderState.reminders[index] = saved
            return saved
        }
    }

    public func deleteReminder(id: String) async throws {
        try requireReminders()
        lock.withLock { reminderState.reminders.removeAll { $0.id == id } }
    }

    /// Plugins holding an assertion, with what they asked for.
    public var keptAwake: [String: KeepAwakeRequest] { lock.withLock { assertions } }

    public func clipboardChangeCount() -> Int { lock.withLock { changeCount } }
    public func readClipboard() -> ClipboardItem? { lock.withLock { item } }

    public func writeClipboard(_ content: ClipboardContent) throws {
        lock.withLock {
            changeCount += 1
            switch content {
            case .text(let text): item = ClipboardItem(changeCount: changeCount, kind: .text, text: text, sourceAppID: "io.navbytes.stackbar", sourceAppName: "Stackbar")
            case .files(let files): item = ClipboardItem(changeCount: changeCount, kind: .files, text: files.joined(separator: "\n"), files: files, sourceAppID: "io.navbytes.stackbar", sourceAppName: "Stackbar")
            case .image(let id): item = ClipboardItem(changeCount: changeCount, kind: .image, imageID: id, sourceAppID: "io.navbytes.stackbar", sourceAppName: "Stackbar")
            case .stored(let id): item = ClipboardItem(changeCount: changeCount, kind: .text, text: stored[id], contentID: id, sourceAppID: "io.navbytes.stackbar", sourceAppName: "Stackbar")
            }
        }
    }

    public func paste(_ content: ClipboardContent, options: PasteOptions) async throws {
        let before = lock.withLock { item }
        try writeClipboard(content)
        let written = lock.withLock {
            pastes.append((content, options))
            // Marked transient, as on the Mac: clipboard managers skip it.
            if options.restoreClipboard { item?.concealed = true }
            return changeCount
        }
        guard options.restoreClipboard else { return }
        let delay = restoreDelay
        Task {
            try? await Task.sleep(for: delay)
            self.lock.withLock {
                // The user copied something since: leave their copy alone.
                guard self.changeCount == written else { return }
                self.changeCount += 1
                self.item = before.map { var item = $0; item.changeCount = self.changeCount; return item }
            }
        }
    }

    public func keepAwake(_ request: KeepAwakeRequest?, pluginID: String) throws {
        lock.withLock { assertions[pluginID] = request }
    }

    public func systemStatus() -> SystemStatus {
        lock.withLock {
            var status = status
            status.keptAwakeBy = assertions.keys.sorted()
            return status
        }
    }

    public func calendarEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        lock.withLock { events.filter { $0.end > from && $0.start < to }.sorted { $0.start < $1.start } }
    }

    // MARK: Calendar writes, terminal, text and sensors (protocol 21)

    /// The calendars `writableCalendars()` lists; the first is the default.
    public var simulatedCalendars = [CalendarInfo(id: "work", title: "Work", color: "#1BADF8", account: "iCloud", isDefault: true), CalendarInfo(id: "home", title: "Home", color: "#63DA38", account: "iCloud")]
    /// Every command opened in the terminal, in order (for tests).
    public private(set) var terminalCommands: [[String]] = []
    private var recognized: [String: RecognizedText] = [:]
    private var screenText: RecognizedText? = RecognizedText(lines: [.init(text: "Bonjour tout le monde", confidence: 0.98)])
    private var simulatedSensors: [SensorReading] = [
        SensorReading(id: "cpu", name: "CPU", kind: .temperature, value: 52.5),
        SensorReading(id: "gpu", name: "GPU", kind: .temperature, value: 44),
        SensorReading(id: "battery", name: "Battery", kind: .temperature, value: 31),
        SensorReading(id: "fan-0", name: "Fan", kind: .fan, value: 1850, maximum: 4900),
    ]

    /// What `recognizeText` reads in a kept image.
    public func simulate(text: RecognizedText, inImage id: String) { lock.withLock { recognized[id] = text } }
    /// What `captureScreenText` answers; nil is the user pressing Esc.
    public func simulate(screenText: RecognizedText?) { lock.withLock { self.screenText = screenText } }
    public func simulate(sensors: [SensorReading]) { lock.withLock { simulatedSensors = sensors } }

    public func saveCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent {
        try lock.withLock {
            let calendar = draft.calendarID.flatMap { id in simulatedCalendars.first { $0.id == id } } ?? simulatedCalendars.first { $0.isDefault } ?? simulatedCalendars[0]
            if draft.calendarID != nil, !simulatedCalendars.contains(where: { $0.id == draft.calendarID }) { throw SystemServiceError("no calendar \(draft.calendarID ?? "")") }
            var event = CalendarEvent(id: draft.id.isEmpty ? "event-\(UUID().uuidString.prefix(8))" : draft.id, title: draft.title, start: draft.start, end: draft.end,
                                      isAllDay: draft.isAllDay, location: draft.location, notes: draft.notes, url: draft.url, calendar: calendar.title, calendarColor: calendar.color)
            if let index = events.firstIndex(where: { $0.id == draft.id }), !draft.id.isEmpty {
                event.participation = events[index].participation
                event.attendees = events[index].attendees
                events[index] = event
            } else {
                guard draft.id.isEmpty else { throw SystemServiceError("no event \(draft.id)") }
                events.append(event)
            }
            return event
        }
    }

    public func writableCalendars() async throws -> [CalendarInfo] { lock.withLock { simulatedCalendars } }

    public func openInTerminal(_ command: [String], title: String?) async throws {
        lock.withLock { terminalCommands.append(command) }
    }

    public func recognizeText(imageID: String, languages: [String]?) async throws -> RecognizedText {
        try lock.withLock {
            guard let text = recognized[imageID] else { throw SystemServiceError("no kept image \(imageID)") }
            return text
        }
    }

    public func captureScreenText(languages: [String]?) async throws -> RecognizedText? { lock.withLock { screenText } }

    public func sensors() async throws -> [SensorReading] { lock.withLock { simulatedSensors } }

    /// A believable day: a stand-up that started, a call with a Meet link
    /// soon, an all-day event, a declined one and a Zoom call this afternoon.
    /// Late in the evening the later meetings would run past midnight, so
    /// those move to tomorrow morning instead (09:30, 11:00, 14:00, keeping
    /// their order), and no meeting ever spans two days.
    public static func sampleDay(now: Date = Date()) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let slots = [9.5, 11, 14].map { tomorrow.addingTimeInterval($0 * 3600) }
        var moved = 0
        return sampleEvents(now: now, start: start, tomorrow: tomorrow).map { event in
            guard !event.isAllDay, event.start >= now, event.end > tomorrow, moved < slots.count else { return event }
            var event = event
            let length = event.end.timeIntervalSince(event.start)
            event.start = slots[moved]
            event.end = slots[moved].addingTimeInterval(length)
            moved += 1
            return event
        }
    }

    private static func sampleEvents(now: Date, start: Date, tomorrow: Date) -> [CalendarEvent] {
        let minute = 60.0
        return [
            CalendarEvent(id: "sample-allday", title: "Release week", start: start, end: tomorrow, isAllDay: true, calendar: "Team", calendarColor: "#8E8E93"),
            CalendarEvent(id: "sample-standup", title: "Stand-up", start: now.addingTimeInterval(-10 * minute), end: now.addingTimeInterval(5 * minute), location: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc", calendar: "Work", calendarColor: "#0A84FF", participation: .accepted, attendees: 6, organizer: "Ana"),
            CalendarEvent(id: "sample-design", title: "Design review: onboarding", start: now.addingTimeInterval(25 * minute), end: now.addingTimeInterval(55 * minute), notes: "Join with Google Meet: https://meet.google.com/abc-defg-hij", calendar: "Work", calendarColor: "#0A84FF", participation: .accepted, attendees: 4, organizer: "Sam"),
            CalendarEvent(id: "sample-declined", title: "Budget sync", start: now.addingTimeInterval(90 * minute), end: now.addingTimeInterval(120 * minute), location: "Room 4", calendar: "Work", participation: .declined, attendees: 9),
            CalendarEvent(id: "sample-zoom", title: "1:1 with Lee", start: now.addingTimeInterval(180 * minute), end: now.addingTimeInterval(210 * minute), location: "https://us02web.zoom.us/j/1234567890?pwd=abc", calendar: "Work", calendarColor: "#0A84FF", participation: .tentative, attendees: 2, organizer: "Lee"),
        ]
    }
}

/// Clipboard content the host hands to plugins by id: images as PNG, and
/// formatted copies as a snapshot of every pasteboard type. Files are named
/// by their hash; the newest are kept and the oldest pruned past `limit`
/// files or `maxBytes` in all. Lives in the host so a plugin's 1 MB of
/// storage only needs the ids.
public final class ClipboardImageStore: @unchecked Sendable {
    public let directory: URL
    public let limit: Int
    public let maxBytes: Int
    private let lock = NSLock()

    public init(directory: URL, limit: Int = 1000, maxBytes: Int = 512 * 1024 * 1024) {
        self.directory = directory
        self.limit = limit
        self.maxBytes = maxBytes
    }

    /// Saves the data and returns its id. The same bytes get the same id.
    @discardableResult
    public func save(_ data: Data) throws -> String {
        try lock.withLock {
            let id = SHA256.hex(data).prefix(32)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(id).bin")
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            } else {
                try data.write(to: file, options: .atomic)
            }
            prune()
            return String(id)
        }
    }

    public func data(for id: String) -> Data? {
        guard id.allSatisfy({ $0.isHexDigit }), !id.isEmpty else { return nil }
        return lock.withLock {
            (try? Data(contentsOf: directory.appendingPathComponent("\(id).bin")))
                ?? (try? Data(contentsOf: directory.appendingPathComponent("\(id).png")))
        }
    }

    private func prune() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let described = files.map { file -> (URL, Date, Int) in
            let values = try? file.resourceValues(forKeys: keys)
            return (file, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var bytes = 0
        for (index, entry) in described.enumerated() {
            bytes += entry.2
            if index >= limit || bytes > maxBytes { try? FileManager.default.removeItem(at: entry.0) }
        }
    }
}

/// What `SimulatedSystem` keeps for Reminders: lists, reminders and the
/// access the user gave (or gives when asked).
public struct SimulatedReminders: Codable, Equatable, Sendable {
    public var access: ReminderAccess
    /// What the simulated prompt answers when access is `notDetermined`.
    public var grantWhenAsked: Bool
    public var lists: [ReminderList]
    public var reminders: [Reminder]

    public init(access: ReminderAccess = .granted, grantWhenAsked: Bool = true, lists: [ReminderList] = [], reminders: [Reminder] = []) {
        self.access = access
        self.grantWhenAsked = grantWhenAsked
        self.lists = lists
        self.reminders = reminders
    }

    /// Two lists, Reminders (the default) and Groceries, with nothing in them.
    public static func sample() -> SimulatedReminders {
        SimulatedReminders(lists: [
            ReminderList(id: "list-1", title: "Reminders", color: "#FF9500", account: "iCloud", isDefault: true),
            ReminderList(id: "list-2", title: "Groceries", color: "#34C759", account: "iCloud"),
        ])
    }
}
