import Foundation

/// The type a host call answers with, inside `HostResult.value`. Each one is
/// declared once, in `HostReplies`, and both sides use it: the host encodes
/// its answer with `result`, the plugin library reads it with `decode`. So a
/// call's answer can't be written as one type and read as another.
public struct HostReply<Value: Codable & Sendable>: Sendable {
    public init() {}

    /// The host's answer.
    public func result(_ value: Value) -> HostResult {
        .value(SystemCodec.encode(value))
    }

    /// The host's answer when there may be nothing (the user pressed Esc,
    /// the clipboard is empty): `.value(nil)`.
    public func result(ifAny value: Value?) -> HostResult {
        .value(value.map(SystemCodec.encode))
    }

    /// The plugin's reading of the host's answer; nil when it was empty.
    public func decode(_ json: String?) throws -> Value? {
        try json.map { try SystemCodec.decode(Value.self, from: $0) }
    }

    /// A whole result read back: its value, nil for `.value(nil)`, or the
    /// host's refusal thrown.
    public func decode(_ result: HostResult) throws -> Value? {
        switch result {
        case .value(let json): return try decode(json)
        case .failure(let message): throw HostReplyError(message: message)
        default: throw HostReplyError(message: "expected a value, got \(result)")
        }
    }
}

/// The host refused a call whose value was read with `HostReply.decode`.
public struct HostReplyError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public var description: String { message }
}

/// Every host call that answers with a value, and the type of that value.
/// Calls that answer `.ok`, or a plain string (`saveFile`,
/// `resolveApplication`, `secret`), aren't listed.
public enum HostReplies {
    public static let clipboardRead = HostReply<ClipboardItem>()
    public static let systemStatus = HostReply<SystemStatus>()
    public static let calendarEvents = HostReply<[CalendarEvent]>()
    public static let saveCalendarEvent = HostReply<CalendarEvent>()
    public static let writableCalendars = HostReply<[CalendarInfo]>()
    public static let reminderAccess = HostReply<ReminderAccess>()
    public static let reminderLists = HostReply<[ReminderList]>()
    public static let createReminderList = HostReply<ReminderList>()
    public static let reminders = HostReply<[Reminder]>()
    public static let saveReminder = HostReply<Reminder>()
    public static let run = HostReply<RunResult>()
    public static let context = HostReply<InvocationContext>()
    public static let finderSelection = HostReply<[String]>()
    public static let chooseFile = HostReply<ChosenFile>()
    public static let chooseFolder = HostReply<ChosenFolder>()
    public static let grantedFolders = HostReply<[String]>()
    public static let windows = HostReply<WindowSnapshot>()
    public static let arrangeWindows = HostReply<ArrangeResult>()
    public static let installedApps = HostReply<[InstalledApp]>()
    public static let runningApps = HostReply<[RunningApp]>()
    public static let findFiles = HostReply<[FoundFile]>()
    /// `setKeyLayer` and `keyLayerStatus`.
    public static let keyLayer = HostReply<KeyLayerStatus>()
    /// `setExpansions` and `expansionStatus`.
    public static let expansions = HostReply<ExpansionStatus>()
    /// `recognizeText` and `captureScreenText`.
    public static let recognizedText = HostReply<RecognizedText>()
    public static let sensors = HostReply<[SensorReading]>()
    public static let menuItems = HostReply<MenuSnapshot>()
    public static let pickColor = HostReply<PickedColor>()
    public static let define = HostReply<Definition>()
}
