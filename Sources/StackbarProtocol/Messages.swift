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
    public static let current = 8
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
    case launch, interval, wake, manual, file, topic, clipboard
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
public struct NotificationAction: Codable, Equatable, Sendable {
    public var title: String
    public var url: String

    public init(_ title: String, url: String) {
        self.title = title
        self.url = url
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
    case paste(ClipboardContent)
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
}

public enum HostResult: Codable, Equatable, Sendable {
    case ok
    case value(String?)
    case http(HTTPResponse)
    case failure(String)
}

public struct HTTPRequest: Codable, Equatable, Sendable {
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

    public init(name: String, description: String, parameters: [ToolParameter] = []) {
        self.name = name
        self.description = description
        self.parameters = parameters
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
