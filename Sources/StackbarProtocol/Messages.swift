import Foundation

/// The protocol version a host and plugin agree on in `hello`/`ready`.
public enum StackbarProtocolVersion {
    /// 2 added host calls, tools, topics and the stored-values snapshot.
    /// 3 added the clipboard, keep-awake, system status and calendar calls.
    /// 4 added the settings surface.
    /// 5 added the menu-bar click action, notification buttons and row previews.
    /// 6 added full-screen alerts.
    /// 7 added commands, command views, forms and row navigation.
    /// 8 added running declared commands and reading the user's context.
    /// 9 added file panels, finding apps and rows with an app's icon.
    /// 10 added paste options (restoring the clipboard, the cursor) and storage grants.
    /// 11 added styling, shapes, images, timers, tappable content, layered
    /// stacks, segmented pickers, ring and timed progress, and system sounds.
    /// 12 added radial, angular and glass paints, remote images, blur, symbol
    /// effects, numeric transitions, hover and grids.
    /// 13 added listing and arranging windows, and the displays trigger.
    /// 14 added the app calls, the key layer and the apps trigger.
    /// 15 added Reminders: the reminder calls and the reminders trigger.
    /// 16 added root-search and fallback commands, installed apps, finding
    /// files and file icons on rows.
    /// 17 added root patterns on root-search commands, opt-in agent tools,
    /// widget buttons that act, and menu-bar items that hide while empty.
    /// 18 added the HUD call and system actions.
    /// 19 added text expansion: keywords the host expands as you type.
    /// 20 added focusing a window and the front app's menu items.
    /// 21 added picking a color from the screen, dictionary definitions,
    /// notification buttons that run the plugin's own commands, adding
    /// calendar events, opening a command in a terminal, reading text in
    /// images and on screen, and temperature and fan sensors.
    /// 22 added rows kept out of the palette's results.
    /// 23 added the clock node the host keeps current, and live sliders that
    /// send values while dragged.
    /// 24 added folders the user chooses for a plugin's commands, and the SSH
    /// agent capability.
    /// 25 added `confirm` on row actions, buttons and tappables: the host
    /// asks for a second press before it sends the action.
    /// 26 added the lock, sleep, frontApp, power, audio, network and volumes
    /// triggers.
    /// 27 added a command's default alias; panel affordances left the
    /// palette's main search.
    public static let current = 27
}

/// Host → plugin.
public enum HostMessage: Codable, Equatable, Sendable {
    /// The first message. The plugin answers with `ready`, then renders.
    /// `storage` is the plugin's saved values (JSON strings by key), so
    /// `@Stored` reads never wait on the host.
    case hello(protocolVersion: Int, surfaces: [Surface], storage: [String: String] = [:])
    /// Run `refresh()`, then re-render.
    case trigger(reason: TriggerReason)
    /// The user acted on something the plugin rendered.
    case event(action: ActionID, value: EventValue?)
    /// A surface opened or closed (the panel, mostly).
    case visibility(surface: Surface, visible: Bool)
    /// Exit cleanly; the host kills the process if it doesn't.
    case shutdown
    /// The answer to a plugin's `request` with the same id.
    case response(id: Int, result: HostResult)
    /// Another plugin published to a topic this one listens to.
    case topic(name: String, payload: String, from: String)
    /// An agent called one of the plugin's tools.
    case callTool(id: Int, name: String, arguments: [String: EventValue])
    /// Run one of the plugin's run commands; answered with `commandResult`.
    /// `context` is set only for plugins granted `.context`.
    case runCommand(id: Int, command: String, arguments: [String: String], source: InvocationSource, context: InvocationContext?)
    /// A view command opened in the palette. The plugin answers with `view`
    /// carrying the same `seq`.
    case openView(session: Int, command: String, query: CommandQuery, seq: Int, context: InvocationContext?)
    /// The user typed or changed an argument in an open view.
    case updateView(session: Int, query: CommandQuery, seq: Int)
    /// The view was closed or popped; its handlers can go.
    case closeView(session: Int)
    /// Output of a streamed `run`, whose request had this id.
    case runOutput(id: Int, channel: RunChannel, data: Data)
    /// A streamed `run` ended; nothing more comes for this id.
    case runExit(id: Int, exit: RunExit)
}

public enum TriggerReason: String, Codable, Sendable {
    case launch, interval, wake, manual, file, topic, clipboard, displays, apps, reminders
    /// Protocol 26: the system triggers.
    case locked, unlocked, sleep, frontApp, power, audio, network, volumes
}

/// The value that came with an event: a toggle's new state, a slider's number.
public indirect enum EventValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case text(String)
    /// A submitted form: each field's value by its name.
    case fields([String: EventValue])
}

/// Plugin → host.
public enum PluginMessage: Codable, Equatable, Sendable {
    case ready(protocolVersion: Int)
    /// The whole tree for one surface. Sent only when it changed.
    case render(surface: Surface, root: ViewNode)
    case log(level: LogLevel, message: String)
    /// Sent after every host message has been fully handled (refresh or action
    /// done, renders sent). Lets a host or a test know the plugin is quiet.
    case settled
    /// A call into the host. The host answers with `response(id:)`; ids are
    /// chosen by the plugin and only need to be unique among open requests.
    case request(id: Int, call: HostCall)
    /// The tools the plugin offers agents. Sent after `ready` and whenever
    /// the list changes.
    case tools([ToolSpec])
    /// The result of a `callTool`.
    case toolResult(id: Int, text: String, isError: Bool)
    /// What a left click on the status item does: run the plugin's click
    /// action (`MenuBarClick.action` names it), or open the panel when `nil`.
    /// A right click always opens the panel. Sent when it changes.
    case menuBarClick(MenuBarClick?)
    /// The commands the plugin offers. Sent after `ready` and whenever the
    /// list changes.
    case commands([CommandSpec])
    /// The answer to `runCommand`.
    case commandResult(id: Int, result: CommandResult)
    /// An open view's tree, for the query with `seq`. Also sent unasked after
    /// an action or refresh changed what an open view shows.
    case view(session: Int, seq: Int, root: ViewNode)
}

/// A plugin's left-click action on its status item, like starting or
/// stopping a keep-awake session.
public struct MenuBarClick: Codable, Equatable, Sendable {
    /// What the click does, as the status item's tooltip says it.
    public var title: String
    /// Sent back in an `event` when the user clicks.
    public var action: ActionID

    public init(title: String, action: ActionID) {
        self.title = title
        self.action = action
    }
}

/// A button on a notification. The host opens `url` when it is clicked
/// (the same URLs `openURL` allows), so it works after the plugin moved on.
/// With `command` set instead (protocol 21), the click runs that command of
/// the plugin that posted it, with `arguments`, as if picked in the palette:
/// Snooze, +5 min, Start Break.
public struct NotificationAction: Codable, Equatable, Sendable {
    public var title: String
    public var url: String
    /// One of the posting plugin's own command ids. Protocol 21.
    public var command: String?
    public var arguments: [String: String]?

    public init(_ title: String, url: String) {
        self.title = title
        self.url = url
    }

    /// A button that runs one of the plugin's own commands. Protocol 21.
    public init(_ title: String, command: String, arguments: [String: String] = [:]) {
        self.title = title
        self.url = ""
        self.command = command
        self.arguments = arguments.isEmpty ? nil : arguments
    }
}

/// What a plugin can ask the host to do. Every call is checked against the
/// capabilities the user approved; a call outside them fails with a message
/// that says which capability is missing.
public enum HostCall: Codable, Equatable, Sendable {
    /// Saves a value under `key` (a JSON string), or removes it with `nil`.
    case storageSet(key: String, value: String?)
    /// Reads a secret the manifest declares. Answers `.value(nil)` when the
    /// user has not entered it yet; the host then asks them for it.
    case secret(name: String)
    /// An HTTP request to a declared domain, made by the host.
    case http(HTTPRequest)
    /// A current access token for a declared OAuth provider, signing in or
    /// refreshing as needed.
    case oauthToken(provider: String, forceRefresh: Bool)
    /// Sends `payload` to every plugin listening on `topic`.
    case publish(topic: String, payload: String)
    /// A user notification, with up to three buttons that open URLs.
    /// Clicking the notification itself opens the plugin's panel.
    case notify(title: String, body: String?, actions: [NotificationAction]? = nil)
    /// A full-screen alert that stays until dismissed, for what must not be
    /// missed (a meeting starting). Buttons open URLs, like notification
    /// buttons; Esc or Dismiss closes it. At most one a minute.
    case alert(title: String, body: String?, actions: [NotificationAction])
    /// Plays a macOS system sound. At most 10 a minute. Protocol 11.
    case playSound(SystemSound)
    /// Opens a URL with the default app (https, mailto, or a file URL).
    case openURL(String)
    /// Opens a URL or an absolute path, with an app by bundle id when given.
    /// Schemes beyond the safe defaults need `.openURLs(schemes:)`.
    case open(url: String, app: String?)
    /// Puts text on the clipboard.
    case copy(String)
    /// What is on the clipboard now (`ClipboardItem` as JSON, or `nil` when
    /// it is empty). Needs `.clipboard`.
    case clipboardRead
    /// Puts text, files or a kept image on the clipboard. Needs `.clipboard`.
    case clipboardWrite(ClipboardContent)
    /// Puts the content on the clipboard and pastes it into the app the user
    /// was in. Needs `.clipboard`, and Accessibility access for the host;
    /// without it the content is still copied and the call fails saying so.
    /// `options` (protocol 10) restore the clipboard afterwards and place
    /// the caret.
    case paste(ClipboardContent, options: PasteOptions? = nil)
    /// Keeps the Mac awake for this plugin until called with `nil`, or until
    /// the plugin stops or crashes. Needs `.power`.
    case keepAwake(KeepAwakeRequest?)
    /// Battery, power and running apps (`SystemStatus` as JSON). Needs `.power`.
    case systemStatus
    /// Events overlapping `from..<to`, at most 31 days (`[CalendarEvent]` as
    /// JSON). Needs `.calendar`; the host asks the user for calendar access.
    case calendarEvents(from: Date, to: Date)
    /// Runs a command the manifest declares in `.run(commands:)`. Answers
    /// with `RunResult` as JSON, or, when `stream` is set, `.ok` once it
    /// started, followed by `runOutput` and `runExit` messages carrying this
    /// request's id.
    case run(RunRequest)
    /// Stops the streamed run started by the request with this id.
    case cancelRun(id: Int)
    /// The frontmost app, its window title and the selected text, now
    /// (`InvocationContext` as JSON). Needs `.context`.
    case context
    /// The paths selected in Finder (`[String]` as JSON). Needs `.context`;
    /// macOS asks the user once to let Stackbar control Finder.
    case finderSelection
    /// Shows an Open panel for a file of these types (extensions such as
    /// `json`, or empty for any) and answers with `ChosenFile` as JSON, or
    /// `nil` when the user cancelled. At most 5 MB. Needs nothing: the user
    /// picks the file.
    case chooseFile(types: [String])
    /// Shows a Save panel with `name` filled in and writes `data` where the
    /// user says; answers with the path, or `nil` when they cancelled.
    case saveFile(name: String, data: Data)
    /// The bundle id of an installed app named by its name ("Safari"), its
    /// path or its bundle id, or `nil` when there is none.
    case resolveApplication(String)
    /// The displays and the regular apps' windows, front to back
    /// (`WindowSnapshot` as JSON). Needs `.windows`, and Accessibility
    /// access for the host. Protocol 13.
    case windows
    /// Moves and resizes windows to these placements, matching them by app,
    /// title and order; with `launch`, opens apps that aren't running first.
    /// Answers `ArrangeResult` as JSON. Needs `.windows`. Protocol 13.
    case arrangeWindows([WindowPlacement], launch: Bool)
    /// The regular apps that are running, in launch order (`[RunningApp]` as
    /// JSON). Needs `.apps`. Protocol 14.
    case runningApps
    /// Brings a running app to the front, unhiding it; with `launch`, opens
    /// it when it isn't running. Needs `.apps`. Protocol 14.
    case activateApp(String, launch: Bool)
    /// Hides a running app. Needs `.apps`. Protocol 14.
    case hideApp(String)
    /// Registers the plugin's key layer, replacing the last one; `nil`
    /// removes it. Answers `KeyLayerStatus` as JSON. Needs `.keyLayer`.
    /// Protocol 14.
    case setKeyLayer(KeyLayer?)
    /// Whether the plugin's key layer is listening (`KeyLayerStatus` as
    /// JSON). Needs `.keyLayer`. Protocol 14.
    case keyLayerStatus
    /// Whether Stackbar may use Reminders (`ReminderAccess` as JSON); with
    /// `ask`, macOS asks the user when they haven't been asked yet. Needs
    /// `.reminders`. Protocol 15.
    case reminderAccess(ask: Bool)
    /// The Reminders lists (`[ReminderList]` as JSON). Needs `.reminders`.
    case reminderLists
    /// Makes a Reminders list in the default account (`ReminderList` as
    /// JSON). Needs `.reminders`.
    case createReminderList(title: String, color: String?)
    /// The reminders the query asks for (`[Reminder]` as JSON, at most
    /// `ReminderQuery.limit`). Needs `.reminders`.
    case reminders(ReminderQuery)
    /// Creates the reminder (empty id) or writes `fields` of it (nil for
    /// all) onto the current one; answers the saved `Reminder` as JSON.
    /// Needs `.reminders`.
    case saveReminder(Reminder, fields: [Reminder.Field]?)
    /// Deletes a reminder. Needs `.reminders`.
    case deleteReminder(id: String)
    /// The installed apps and System Settings panes, by name
    /// (`[InstalledApp]` as JSON). Needs `.apps`. Protocol 16.
    case installedApps
    /// Files and folders in the user's home whose names hold every word,
    /// from Spotlight's index, most recently used first (`[FoundFile]` as
    /// JSON). Needs `.fileSearch`. Protocol 16.
    case findFiles(FileQuery)
    /// A short message in the HUD over the screen, as a command result's
    /// message shows; at most 30 a minute. Needs nothing. Protocol 18.
    case hud(String, isError: Bool)
    /// Locks, sleeps, restarts the Mac and the like. Needs
    /// `.systemActions`. Protocol 18.
    case system(SystemAction)
    /// Registers the plugin's keywords, replacing the last set; an empty
    /// list removes them. Typing one in any app deletes it and runs its
    /// command. Answers `ExpansionStatus` as JSON. Needs `.textExpansion`.
    /// Protocol 19.
    case setExpansions([TextExpansion])
    /// Whether the plugin's keywords expand (`ExpansionStatus` as JSON).
    /// Needs `.textExpansion`. Protocol 19.
    case expansionStatus
    /// Brings one window to the front: unminimizes it, raises it and
    /// activates its app. Needs `.windows`. Protocol 20.
    case focusWindow(WindowTarget)
    /// The menu bar of the app the user was in before Stackbar
    /// (`MenuSnapshot` as JSON). Needs `.menus`. Protocol 20.
    case menuItems
    /// Chooses a menu item of a running app by its path of titles, after
    /// bringing the app to the front. Needs `.menus`. Protocol 20.
    case pressMenuItem(appID: String, path: [String])
    /// Shows the system's magnifier so the user can pick a color anywhere on
    /// screen (`PickedColor` as JSON, or nil when they press Escape). Needs
    /// nothing: nothing is read until the user clicks. Protocol 21.
    case pickColor
    /// The definition the Mac's own Dictionary has for a word or phrase
    /// (`Definition` as JSON, or nil when it has none). Needs nothing; the
    /// lookup stays on the Mac. Protocol 21.
    case define(String)
    /// Adds an event to a calendar (or changes one, with an id), answering
    /// the saved `CalendarEvent` as JSON. Needs `.calendarWrite`. Protocol 21.
    case saveCalendarEvent(CalendarEventDraft)
    /// The calendars events can be added to (`[CalendarInfo]` as JSON).
    /// Needs `.calendarWrite`. Protocol 21.
    case writableCalendars
    /// Opens the user's terminal app running `command` (a program and its
    /// arguments, never through the plugin's shell). Needs `.terminal`.
    /// Protocol 21.
    case openInTerminal(command: [String], title: String?)
    /// The text in a kept image (a clipboard image id), read on the Mac
    /// with Vision (`RecognizedText` as JSON). Needs `.clipboard`.
    /// Protocol 21.
    case recognizeText(imageID: String, languages: [String]?)
    /// Lets the user drag over part of the screen and answers the text in
    /// it (`RecognizedText` as JSON, or nil when they press Esc). Needs
    /// `.screenText`. Protocol 21.
    case captureScreenText(languages: [String]?)
    /// Temperatures and fan speeds (`[SensorReading]` as JSON). Needs
    /// `.sensors`. Protocol 21.
    case sensors
    /// Shows an Open panel for a folder and, when the user picks one, lets
    /// the plugin's commands run there (`Stackbar.run(workingDirectory:)`)
    /// until the user removes it in Settings. Answers `ChosenFolder` as JSON,
    /// or nil when they cancelled. `startingAt` opens the panel there. Needs
    /// nothing: the user picks the folder. Protocol 24.
    case chooseFolder(prompt: String?, startingAt: String?)
    /// The folders the user chose for this plugin and hasn't removed
    /// (`[String]` as JSON, full paths). Protocol 24.
    case grantedFolders
}

public enum HostResult: Codable, Equatable, Sendable {
    case ok
    case value(String?)
    case http(HTTPResponse)
    case failure(String)
}

public struct HTTPRequest: Codable, Equatable, Sendable {
    /// Longest the host lets one call take from start to last byte, whatever
    /// its `timeout` (which only measures silence). The plugin's wait for the
    /// answer is based on this.
    public static let maxCallSeconds: Double = 300
    public var url: String
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    public var timeout: Double

    public init(url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil, timeout: Double = 30) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Codable, Equatable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

/// A tool an agent can call, described the way MCP describes tools.
public struct ToolSpec: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var parameters: [ToolParameter]
    /// Off until the user turns it on in Settings → Agents, for tools that
    /// return private data (clipboard contents). A plugin with one also keeps
    /// its panel from `stackbar_read` until then. Protocol 17.
    public var optIn: Bool

    public init(name: String, description: String, parameters: [ToolParameter] = [], optIn: Bool = false) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.optIn = optIn
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, parameters, optIn
    }

    // Written by hand so specs from plugins built before protocol 17, which
    // have no `optIn`, still decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        parameters = try container.decodeIfPresent([ToolParameter].self, forKey: .parameters) ?? []
        optIn = try container.decodeIfPresent(Bool.self, forKey: .optIn) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(parameters, forKey: .parameters)
        if optIn { try container.encode(optIn, forKey: .optIn) }
    }
}

public struct ToolParameter: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case string, number, boolean
    }

    public var name: String
    public var description: String
    public var kind: Kind
    public var required: Bool

    public init(_ name: String, _ kind: Kind = .string, description: String = "", required: Bool = true) {
        self.name = name
        self.kind = kind
        self.description = description
        self.required = required
    }
}

public enum LogLevel: String, Codable, Sendable {
    case debug, info, warning, error
}

/// Newline-delimited JSON: one message per line on the plugin's stdin/stdout.
///
/// JSON keeps a misbehaving plugin debuggable with nothing but a terminal, and
/// the encoder never emits a raw newline inside a value, so a line is always
/// exactly one message.
public enum LineCodec {
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }

    /// Like `encode`, but a NaN or infinite number, which JSON can't hold
    /// and which makes `encode` throw, is written as 0. `replaced` says
    /// whether there was one. Try `encode` first: this is the slow path.
    public static func encodeReplacingNonFinite(_ value: some Encodable) throws -> (data: Data, replaced: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let marker = nonFiniteMarker
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: marker, negativeInfinity: marker, nan: marker)
        let text = String(decoding: try encoder.encode(value), as: UTF8.self)
        let quoted = "\"\(marker)\""
        let replaced = text.contains(quoted)
        var data = Data((replaced ? text.replacingOccurrences(of: quoted, with: "0") : text).utf8)
        data.append(0x0A)
        return (data, replaced)
    }

    /// Stands in for a non-finite number until it is replaced; random, so
    /// no text a plugin shows can match it.
    private static let nonFiniteMarker = "non-finite-\(UUID().uuidString)"
}

/// Splits a byte stream into lines, holding a partial line across reads.
///
/// A line longer than `maxLineBytes` is dropped (and counted) rather than
/// buffered without bound, the same cap Vee puts on a plugin's stdout, so a
/// plugin that never writes a newline can't grow the host's memory forever.
public struct LineBuffer: Sendable {
    public static let defaultMaxLineBytes = 8 * 1024 * 1024

    public let maxLineBytes: Int
    public private(set) var droppedLines = 0
    private var pending = Data()
    private var discarding = false

    public init(maxLineBytes: Int = LineBuffer.defaultMaxLineBytes) {
        self.maxLineBytes = maxLineBytes
    }

    /// Appends a chunk and returns every line it completed, without newlines.
    public mutating func append(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            let piece = chunk[start..<newline]
            if discarding {
                discarding = false
            } else if pending.count + piece.count <= maxLineBytes {
                var line = pending
                line.append(piece)
                if !line.isEmpty { lines.append(line) }
            } else {
                droppedLines += 1
            }
            pending.removeAll(keepingCapacity: true)
            start = chunk.index(after: newline)
        }
        let rest = chunk[start...]
        if discarding {
            return lines
        }
        if pending.count + rest.count > maxLineBytes {
            pending.removeAll()
            discarding = true
            droppedLines += 1
        } else {
            pending.append(rest)
        }
        return lines
    }
}
