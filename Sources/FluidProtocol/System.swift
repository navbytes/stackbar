import Foundation

// Values for the system host calls: the clipboard, keeping the Mac awake,
// power and running apps, and the calendar. The host reads the OS (AppKit,
// IOKit, EventKit) so plugins stay portable, sandboxed and testable on Linux;
// these types are what crosses the wire, JSON-encoded inside `HostResult.value`.

/// What is on the clipboard right now, as the host read it.
public struct ClipboardItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text, url, files, image
    }

    /// Increases with every change to the clipboard, by anyone. Compare it
    /// with the last one you saw to tell a new copy from a repeat read.
    public var changeCount: Int
    public var kind: Kind
    /// The text, the URL, or (for `.files`) the paths, one per line. `nil`
    /// for an image or a concealed item.
    public var text: String?
    /// File paths, for `.files`.
    public var files: [String]
    /// For `.image`: an id the host keeps the image under, to put it back on
    /// the clipboard with `ClipboardContent.image(id:)`. The host keeps the
    /// most recent images only; an old id can stop working.
    public var imageID: String?
    /// Width and height in pixels, for `.image`.
    public var imageSize: [Int]?
    /// The app that was frontmost when the copy happened.
    public var sourceAppID: String?
    public var sourceAppName: String?
    /// The copying app marked it as a password or as transient
    /// (nspasteboard.org's ConcealedType and TransientType). The host never
    /// hands out the content of such an item; clipboard managers skip it.
    public var concealed: Bool
    public var copiedAt: Date

    public init(changeCount: Int, kind: Kind, text: String? = nil, files: [String] = [], imageID: String? = nil, imageSize: [Int]? = nil, sourceAppID: String? = nil, sourceAppName: String? = nil, concealed: Bool = false, copiedAt: Date = Date()) {
        self.changeCount = changeCount
        self.kind = kind
        self.text = text
        self.files = files
        self.imageID = imageID
        self.imageSize = imageSize
        self.sourceAppID = sourceAppID
        self.sourceAppName = sourceAppName
        self.concealed = concealed
        self.copiedAt = copiedAt
    }
}

/// What a plugin puts back on the clipboard.
public enum ClipboardContent: Codable, Equatable, Sendable {
    case text(String)
    case files([String])
    /// An image the host handed out as `ClipboardItem.imageID`.
    case image(id: String)
}

/// Asks the host to keep the Mac awake for this plugin.
public struct KeepAwakeRequest: Codable, Equatable, Sendable {
    /// Keep the display on too, not just the system.
    public var display: Bool
    /// Shown by `pmset -g assertions` and Activity Monitor.
    public var reason: String

    public init(display: Bool = true, reason: String = "Fluid plugin") {
        self.display = display
        self.reason = reason
    }
}

/// Power and running apps, as the host sees them now.
public struct SystemStatus: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// 0...1, or `nil` on a Mac without a battery.
    public var batteryLevel: Double?
    public var charging: Bool
    public var onACPower: Bool
    public var lowPowerMode: Bool
    /// Regular (Dock) apps that are running, by bundle id.
    public var runningApps: [App]
    /// Plugins currently keeping the Mac awake through the host, by id.
    public var keptAwakeBy: [String]

    public init(batteryLevel: Double? = nil, charging: Bool = false, onACPower: Bool = true, lowPowerMode: Bool = false, runningApps: [App] = [], keptAwakeBy: [String] = []) {
        self.batteryLevel = batteryLevel
        self.charging = charging
        self.onACPower = onACPower
        self.lowPowerMode = lowPowerMode
        self.runningApps = runningApps
        self.keptAwakeBy = keptAwakeBy
    }
}

/// One event from the user's calendars (EventKit on the Mac).
public struct CalendarEvent: Codable, Equatable, Sendable {
    public enum Participation: String, Codable, Sendable {
        /// Not an invitation, or the calendar doesn't say.
        case none
        case pending, accepted, tentative, declined
    }

    /// Stable for one occurrence of an event (recurring events repeat it with
    /// a different start).
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    /// The description, cut to 4000 characters.
    public var notes: String?
    public var url: String?
    public var calendar: String
    /// `#RRGGBB`, the calendar's color.
    public var calendarColor: String?
    public var participation: Participation
    public var attendees: Int
    public var organizer: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, location: String? = nil, notes: String? = nil, url: String? = nil, calendar: String = "Calendar", calendarColor: String? = nil, participation: Participation = .none, attendees: Int = 0, organizer: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.url = url
        self.calendar = calendar
        self.calendarColor = calendarColor
        self.participation = participation
        self.attendees = attendees
        self.organizer = organizer
    }
}

/// How system values are encoded inside `HostResult.value`: JSON with ISO
/// 8601 dates, the same on both sides.
public enum SystemCodec {
    public static func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    public static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(string.utf8))
    }
}
