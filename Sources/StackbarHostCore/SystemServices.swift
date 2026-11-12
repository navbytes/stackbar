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
    /// An Open panel for one folder, starting at `startingAt` when given;
    /// the folder's path, or nil when the user cancelled.
    func chooseFolder(prompt: String?, startingAt: String?, for pluginName: String) async throws -> String?
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
    /// Shows the screen magnifier; nil when the user presses Escape.
    func pickColor() async throws -> PickedColor?
    /// The Mac's Dictionary definition of a word, or nil.
    func define(_ word: String) async -> Definition?
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
    public func chooseFolder(prompt: String?, startingAt: String?, for pluginName: String) async throws -> String? { throw SystemServiceError("choosing folders is not available on this platform") }
    public func resolveApplication(_ nameOrPath: String) async -> String? { nil }
    public func windows() async throws -> WindowSnapshot { throw SystemServiceError("windows are not available on this platform") }
    public func arrangeWindows(_ placements: [WindowPlacement], launch: Bool) async throws -> ArrangeResult { throw SystemServiceError("windows are not available on this platform") }
    public func focusWindow(_ target: WindowTarget) async throws { throw SystemServiceError("windows are not available on this platform") }
    public func menuItems() async throws -> MenuSnapshot { throw SystemServiceError("menus are not available on this platform") }
    public func pressMenuItem(appID: String, path: [String]) async throws { throw SystemServiceError("menus are not available on this platform") }
    public func pickColor() async throws -> PickedColor? { throw SystemServiceError("picking colors is not available on this platform") }
    public func define(_ word: String) async -> Definition? { nil }
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

/// A `CalendarEvent.id` on a Mac: the EventKit identifier, then `@` and the
/// occurrence's start in whole seconds since 1970, so a repeating event
/// changes on that day only. EventKit identifiers can hold `@` themselves,
/// so the start is the part after the last one.
public enum CalendarEventID {
    public static func make(identifier: String, start: Date) -> String {
        identifier + "@" + String(Int(start.timeIntervalSince1970))
    }

    /// The identifier and the start; the start is nil when the id has none
    /// (then the whole id is the identifier).
    public static func split(_ id: String) -> (identifier: String, start: Double?) {
        guard let at = id.lastIndex(of: "@"), let seconds = Double(id[id.index(after: at)...]) else { return (id, nil) }
        return (String(id[..<at]), seconds)
    }
}
