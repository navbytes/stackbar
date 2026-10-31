import Foundation
import FluidProtocol

/// The parts of the OS the host reads and changes for plugins: the clipboard,
/// power assertions, battery and running apps, and the calendar.
///
/// The app implements this with AppKit, IOKit and EventKit. `fluidctl` and the
/// tests use `SimulatedSystem`, so plugins that use these calls build, render
/// and are tested on Linux too. Capabilities are checked in `HostServices`
/// before any of this is reached.
public protocol SystemServices: Sendable {
    /// Cheap; polled twice a second while a plugin has a `.clipboard` trigger.
    func clipboardChangeCount() -> Int
    func readClipboard() -> ClipboardItem?
    func writeClipboard(_ content: ClipboardContent) throws
    /// Writes the content, then pastes it into the app the user was in.
    func paste(_ content: ClipboardContent) async throws
    /// Holds (or with `nil` releases) the plugin's power assertion.
    func keepAwake(_ request: KeepAwakeRequest?, pluginID: String) throws
    func systemStatus() -> SystemStatus
    func calendarEvents(from: Date, to: Date) async throws -> [CalendarEvent]
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
    public func paste(_ content: ClipboardContent) async throws { throw error }
    public func keepAwake(_ request: KeepAwakeRequest?, pluginID: String) throws { if request != nil { throw error } }
    public func systemStatus() -> SystemStatus { SystemStatus() }
    public func calendarEvents(from: Date, to: Date) async throws -> [CalendarEvent] { throw error }
}

/// An in-memory system for `fluidctl` and tests: a clipboard you copy to with
/// `simulateCopy`, power assertions that are only recorded, a fixed battery,
/// and calendar events you set (or a sample day built around now).
public final class SimulatedSystem: SystemServices, @unchecked Sendable {
    private let lock = NSLock()
    private var changeCount = 0
    private var item: ClipboardItem?
    private var assertions: [String: KeepAwakeRequest] = [:]
    private var status: SystemStatus
    private var events: [CalendarEvent]
    /// Every paste, in order (for tests).
    public private(set) var pasted: [ClipboardContent] = []

    public init(status: SystemStatus = SystemStatus(batteryLevel: 0.8, charging: false, onACPower: false, runningApps: [.init(id: "com.apple.Safari", name: "Safari"), .init(id: "com.apple.dt.Xcode", name: "Xcode")]), events: [CalendarEvent]? = nil) {
        self.status = status
        self.events = events ?? Self.sampleDay()
    }

    /// Reads `FLUID_CALENDAR` (a JSON file of `[CalendarEvent]`) when set.
    public static func fromEnvironment() -> SimulatedSystem {
        var events: [CalendarEvent]?
        if let path = ProcessInfo.processInfo.environment["FLUID_CALENDAR"], let text = try? String(contentsOfFile: path, encoding: .utf8) {
            events = try? SystemCodec.decode([CalendarEvent].self, from: text)
        }
        return SimulatedSystem(events: events)
    }

    /// The user copied something in another app.
    public func simulateCopy(_ text: String, app: SystemStatus.App? = SystemStatus.App(id: "com.apple.Safari", name: "Safari"), concealed: Bool = false) {
        lock.withLock {
            changeCount += 1
            let isURL = text.hasPrefix("https://") || text.hasPrefix("http://")
            item = ClipboardItem(changeCount: changeCount, kind: isURL ? .url : .text, text: concealed ? nil : text, sourceAppID: app?.id, sourceAppName: app?.name, concealed: concealed)
        }
    }

    public func simulate(status: SystemStatus) { lock.withLock { self.status = status } }
    public func simulate(events: [CalendarEvent]) { lock.withLock { self.events = events } }

    /// Plugins holding an assertion, with what they asked for.
    public var keptAwake: [String: KeepAwakeRequest] { lock.withLock { assertions } }

    public func clipboardChangeCount() -> Int { lock.withLock { changeCount } }
    public func readClipboard() -> ClipboardItem? { lock.withLock { item } }

    public func writeClipboard(_ content: ClipboardContent) throws {
        lock.withLock {
            changeCount += 1
            switch content {
            case .text(let text): item = ClipboardItem(changeCount: changeCount, kind: .text, text: text, sourceAppID: "dev.fluid.app", sourceAppName: "Fluid")
            case .files(let files): item = ClipboardItem(changeCount: changeCount, kind: .files, text: files.joined(separator: "\n"), files: files, sourceAppID: "dev.fluid.app", sourceAppName: "Fluid")
            case .image(let id): item = ClipboardItem(changeCount: changeCount, kind: .image, imageID: id, sourceAppID: "dev.fluid.app", sourceAppName: "Fluid")
            }
        }
    }

    public func paste(_ content: ClipboardContent) async throws {
        try writeClipboard(content)
        lock.withLock { pasted.append(content) }
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

    /// A believable day: a stand-up that started, a call with a Meet link
    /// soon, an all-day event, a declined one and a Zoom call this afternoon.
    public static func sampleDay(now: Date = Date()) -> [CalendarEvent] {
        let minute = 60.0
        let start = Calendar.current.startOfDay(for: now)
        return [
            CalendarEvent(id: "sample-allday", title: "Release week", start: start, end: start.addingTimeInterval(86400), isAllDay: true, calendar: "Team", calendarColor: "#8E8E93"),
            CalendarEvent(id: "sample-standup", title: "Stand-up", start: now.addingTimeInterval(-10 * minute), end: now.addingTimeInterval(5 * minute), location: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc", calendar: "Work", calendarColor: "#0A84FF", participation: .accepted, attendees: 6, organizer: "Ana"),
            CalendarEvent(id: "sample-design", title: "Design review: onboarding", start: now.addingTimeInterval(25 * minute), end: now.addingTimeInterval(55 * minute), notes: "Join with Google Meet: https://meet.google.com/abc-defg-hij", calendar: "Work", calendarColor: "#0A84FF", participation: .accepted, attendees: 4, organizer: "Sam"),
            CalendarEvent(id: "sample-declined", title: "Budget sync", start: now.addingTimeInterval(90 * minute), end: now.addingTimeInterval(120 * minute), location: "Room 4", calendar: "Work", participation: .declined, attendees: 9),
            CalendarEvent(id: "sample-zoom", title: "1:1 with Lee", start: now.addingTimeInterval(180 * minute), end: now.addingTimeInterval(210 * minute), location: "https://us02web.zoom.us/j/1234567890?pwd=abc", calendar: "Work", calendarColor: "#0A84FF", participation: .tentative, attendees: 2, organizer: "Lee"),
        ]
    }
}

/// Clipboard images the host hands to plugins by id: PNG files named by
/// their hash, newest kept, oldest pruned. Lives in the host so a plugin's
/// 1 MB of storage only needs the ids.
public final class ClipboardImageStore: @unchecked Sendable {
    public let directory: URL
    public let limit: Int
    private let lock = NSLock()

    public init(directory: URL, limit: Int = 200) {
        self.directory = directory
        self.limit = limit
    }

    /// Saves the image and returns its id. The same bytes get the same id.
    @discardableResult
    public func save(_ png: Data) throws -> String {
        try lock.withLock {
            let id = SHA256.hex(png).prefix(32)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(id).png")
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            } else {
                try png.write(to: file, options: .atomic)
            }
            prune()
            return String(id)
        }
    }

    public func data(for id: String) -> Data? {
        guard id.allSatisfy({ $0.isHexDigit }), !id.isEmpty else { return nil }
        return lock.withLock { try? Data(contentsOf: directory.appendingPathComponent("\(id).png")) }
    }

    private func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys), files.count > limit else { return }
        let dated = files.map { file in (file, (try? file.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
