import Foundation

// Apple Reminders for plugins with the `.reminders` capability. The host
// talks to EventKit; plugins see these plain values. Protocol 15.

/// Whether Stackbar may use the user's reminders.
public enum ReminderAccess: String, Codable, Sendable {
    case granted
    /// The user said no, or a profile restricts it. Only System Settings
    /// can change it now.
    case denied
    /// Not asked yet; the first `reminders` call (or `reminderAccess(ask:
    /// true)`) asks.
    case notDetermined
    /// No Reminders here (Linux, or a build without an Info.plist).
    case unavailable
}

/// A Reminders list. Plugins use lists for categories: EventKit has no
/// public API for sections, tags or flags.
public struct ReminderList: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// `#RRGGBB`.
    public var color: String?
    /// The account it lives in, like "iCloud" or "On My Mac".
    public var account: String?
    /// False for read-only lists, such as some shared ones.
    public var allowsChanges: Bool
    /// The list new reminders go to when none is named.
    public var isDefault: Bool

    public init(id: String, title: String, color: String? = nil, account: String? = nil, allowsChanges: Bool = true, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.color = color
        self.account = account
        self.allowsChanges = allowsChanges
        self.isDefault = isDefault
    }
}

/// How a reminder repeats.
public struct ReminderRecurrence: Codable, Equatable, Sendable {
    public enum Frequency: String, Codable, Sendable { case daily, weekly, monthly, yearly }

    public var frequency: Frequency
    /// Every `interval` days, weeks, months or years.
    public var interval: Int
    /// For weekly repeats: 1 = Sunday … 7 = Saturday. Empty means the due
    /// date's own weekday.
    public var weekdays: [Int]

    public init(_ frequency: Frequency, interval: Int = 1, weekdays: [Int] = []) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
    }

    /// Monday to Friday.
    public static let weekdays = ReminderRecurrence(.weekly, weekdays: [2, 3, 4, 5, 6])
}

/// One reminder.
public struct Reminder: Codable, Equatable, Sendable, Identifiable {
    public enum Priority: String, Codable, Sendable, CaseIterable { case none, low, medium, high }

    /// The fields `saveReminder(_:fields:)` can write one by one.
    public enum Field: String, Codable, Sendable, CaseIterable {
        case list, title, notes, due, priority, completed, recurrence, alarm, url
    }

    /// Empty for a reminder that isn't saved yet. It can change after a
    /// full iCloud resync; `externalID` survives that more often.
    public var id: String
    public var externalID: String?
    /// The `ReminderList` id. Empty on a new reminder means the default list.
    public var list: String
    public var title: String
    /// Cut to 4000 characters.
    public var notes: String?
    public var due: Date?
    /// Whether `due` has a time of day, or is a whole day.
    public var dueHasTime: Bool
    public var priority: Priority
    /// When it was ticked off; nil while open.
    public var completed: Date?
    public var recurrence: ReminderRecurrence?
    /// When Reminders alerts, on every device. Nil for none.
    public var alarm: Date?
    public var url: String?
    /// Set by the host when read.
    public var modified: Date?

    public init(id: String = "", externalID: String? = nil, list: String = "", title: String, notes: String? = nil, due: Date? = nil, dueHasTime: Bool = false, priority: Priority = .none, completed: Date? = nil, recurrence: ReminderRecurrence? = nil, alarm: Date? = nil, url: String? = nil, modified: Date? = nil) {
        self.id = id
        self.externalID = externalID
        self.list = list
        self.title = title
        self.notes = notes
        self.due = due
        self.dueHasTime = dueHasTime
        self.priority = priority
        self.completed = completed
        self.recurrence = recurrence
        self.alarm = alarm
        self.url = url
        self.modified = modified
    }

    /// Copies `fields` from `other` (all of them when nil), keeping the id.
    public func applying(_ other: Reminder, fields: [Field]?) -> Reminder {
        var result = self
        for field in fields ?? Field.allCases {
            switch field {
            case .list: if !other.list.isEmpty { result.list = other.list }
            case .title: result.title = other.title
            case .notes: result.notes = other.notes
            case .due:
                result.due = other.due
                result.dueHasTime = other.dueHasTime
            case .priority: result.priority = other.priority
            case .completed: result.completed = other.completed
            case .recurrence: result.recurrence = other.recurrence
            case .alarm: result.alarm = other.alarm
            case .url: result.url = other.url
            }
        }
        return result
    }
}

/// Which reminders to read.
public struct ReminderQuery: Codable, Equatable, Sendable {
    /// List ids; nil for every list.
    public var lists: [String]?
    /// Also the reminders completed since this date. Nil reads open ones only.
    public var completedSince: Date?

    public init(lists: [String]? = nil, completedSince: Date? = nil) {
        self.lists = lists
        self.completedSince = completedSince
    }

    /// The most a query answers with.
    public static let limit = 2000
}
