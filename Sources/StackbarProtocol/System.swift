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
    /// For text copied with formatting (rich text, HTML, an app's own
    /// types): an id the host keeps the complete original under, to put it
    /// back exactly with `ClipboardContent.stored(id:)`. `nil` for plain text.
    public var contentID: String?
    /// The app that was frontmost when the copy happened.
    public var sourceAppID: String?
    public var sourceAppName: String?
    /// The copying app marked it as a password or as transient
    /// (nspasteboard.org's ConcealedType and TransientType). The host never
    /// hands out the content of such an item; clipboard managers skip it.
    public var concealed: Bool
    public var copiedAt: Date

    public init(changeCount: Int, kind: Kind, text: String? = nil, files: [String] = [], imageID: String? = nil, imageSize: [Int]? = nil, contentID: String? = nil, sourceAppID: String? = nil, sourceAppName: String? = nil, concealed: Bool = false, copiedAt: Date = Date()) {
        self.changeCount = changeCount
        self.kind = kind
        self.text = text
        self.files = files
        self.imageID = imageID
        self.imageSize = imageSize
        self.contentID = contentID
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
    /// Everything that was copied, formatting included, as the host kept it
    /// under `ClipboardItem.contentID`.
    case stored(id: String)
}

/// How the host pastes.
public struct PasteOptions: Codable, Equatable, Sendable {
    /// Put back what was on the clipboard about half a second after pasting,
    /// unless the user copied something in the meantime. The pasted text is
    /// marked transient, so clipboard managers skip it.
    public var restoreClipboard: Bool
    /// Characters (grapheme clusters) to move the caret left after pasting,
    /// one ← press each, for a `{cursor}` placeholder.
    public var cursorFromEnd: Int

    public init(restoreClipboard: Bool = false, cursorFromEnd: Int = 0) {
        self.restoreClipboard = restoreClipboard
        self.cursorFromEnd = min(max(0, cursorFromEnd), Self.maxCursorFromEnd)
    }

    /// A plugin's JSON never skips the clamp: a negative or huge count from the
    /// wire lands inside `0...maxCursorFromEnd`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            restoreClipboard: try container.decode(Bool.self, forKey: .restoreClipboard),
            cursorFromEnd: try container.decode(Int.self, forKey: .cursorFromEnd)
        )
    }

    /// At most this many ← presses.
    public static let maxCursorFromEnd = 10_000
}

/// A file the user picked in an Open panel.
public struct ChosenFile: Codable, Equatable, Sendable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    public static let maxBytes = 5 * 1024 * 1024
}

/// Asks the host to keep the Mac awake for this plugin.
public struct KeepAwakeRequest: Codable, Equatable, Sendable {
    /// Keep the display on too, not just the system.
    public var display: Bool
    /// Shown by `pmset -g assertions` and Activity Monitor.
    public var reason: String

    public init(display: Bool = true, reason: String = "Stackbar plugin") {
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
    /// Displays other than the built-in one that are connected now.
    /// Optional so a plugin built against an older host still decodes.
    public var externalDisplays: Int?
    /// Bytes received on the network interfaces, a counter: sample it twice
    /// for a download rate. It can wrap (the per-interface counters are 32
    /// bits), so treat a sample lower than the last as a fresh start.
    public var networkBytesReceived: UInt64?
    /// A VPN tunnel (utun, ipsec or ppp with an IPv4 address) is up.
    public var vpnActive: Bool?

    public init(batteryLevel: Double? = nil, charging: Bool = false, onACPower: Bool = true, lowPowerMode: Bool = false, runningApps: [App] = [], keptAwakeBy: [String] = [], externalDisplays: Int? = nil, networkBytesReceived: UInt64? = nil, vpnActive: Bool? = nil) {
        self.batteryLevel = batteryLevel
        self.charging = charging
        self.onACPower = onACPower
        self.lowPowerMode = lowPowerMode
        self.runningApps = runningApps
        self.keptAwakeBy = keptAwakeBy
        self.externalDisplays = externalDisplays
        self.networkBytesReceived = networkBytesReceived
        self.vpnActive = vpnActive
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

/// An event to add to a calendar, or the changes to one (`id` set).
/// Protocol 21.
public struct CalendarEventDraft: Codable, Equatable, Sendable {
    /// Empty adds an event; an id from `saveCalendarEvent` changes it.
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var url: String?
    /// A calendar's id from `writableCalendars()`; nil is the default one.
    public var calendarID: String?
    /// Minutes before the start for an alert; nil adds none.
    public var alertMinutes: Int?

    public init(id: String = "", title: String, start: Date, end: Date, isAllDay: Bool = false, location: String? = nil, notes: String? = nil, url: String? = nil, calendarID: String? = nil, alertMinutes: Int? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.url = url
        self.calendarID = calendarID
        self.alertMinutes = alertMinutes
    }

    /// What the host refuses before touching the calendar.
    public var problem: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "an event needs a title" }
        if title.count > 500 { return "an event's title is at most 500 characters" }
        if end < start { return "an event can't end before it starts" }
        if end.timeIntervalSince(start) > 31 * 86400 { return "an event lasts at most 31 days" }
        if (notes?.count ?? 0) > 10_000 { return "an event's notes are at most 10,000 characters" }
        if let alertMinutes, !(0...40_320).contains(alertMinutes) { return "an alert is 0 to 40,320 minutes before" }
        return nil
    }
}

/// A calendar events can be added to. Protocol 21.
public struct CalendarInfo: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// `#RRGGBB`.
    public var color: String?
    /// iCloud, Google, On My Mac…
    public var account: String?
    public var isDefault: Bool

    public init(id: String, title: String, color: String? = nil, account: String? = nil, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.color = color
        self.account = account
        self.isDefault = isDefault
    }
}

/// Text read from an image or the screen. Protocol 21.
public struct RecognizedText: Codable, Equatable, Sendable {
    /// Every line, top to bottom, joined with newlines.
    public var text: String
    /// Each line on its own, with how sure Vision was (0 to 1).
    public var lines: [Line]

    public struct Line: Codable, Equatable, Sendable {
        public var text: String
        public var confidence: Double

        public init(text: String, confidence: Double) {
            self.text = text
            self.confidence = confidence
        }
    }

    public init(lines: [Line]) {
        self.lines = lines
        self.text = lines.map(\.text).joined(separator: "\n")
    }
}

/// One temperature or fan reading. Protocol 21.
public struct SensorReading: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Degrees Celsius.
        case temperature
        /// Revolutions a minute.
        case fan
    }

    /// Stable across readings: `cpu`, `gpu`, `battery`, `fan-0`.
    public var id: String
    /// What the user sees: "CPU", "GPU", "Battery", "Fan 1".
    public var name: String
    public var kind: Kind
    public var value: Double
    /// A fan's top speed, when the Mac reports it.
    public var maximum: Double?

    public init(id: String, name: String, kind: Kind, value: Double, maximum: Double? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.value = value
        self.maximum = maximum
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
