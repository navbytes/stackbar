/// A command a plugin offers: something found by name and run, from the
/// palette, a hotkey, a `stackbar://` link, Spotlight or Shortcuts.
///
/// A *run* command does its work and returns a `CommandResult`. A *view*
/// command opens a live view in the palette that follows what the user types.
/// Ids are what aliases, hotkeys and links remember, so they stay stable while
/// titles change.
public struct CommandSpec: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case run, view
    }

    /// Where the command may be started from.
    public enum Exposure: String, Codable, Sendable {
        /// Stackbar, Spotlight, Shortcuts and links.
        case everywhere
        /// Only from inside Stackbar (the palette and hotkeys).
        case stackbarOnly
    }

    /// Lowercase letters, digits and `-`, unique within the plugin.
    public var id: String
    public var title: String
    public var subtitle: String?
    public var symbol: String?
    /// Extra words the command is found by.
    public var keywords: [String]
    public var kind: Kind
    public var arguments: [ArgumentSpec]
    public var exposure: Exposure

    public init(id: String, title: String, subtitle: String? = nil, symbol: String? = nil, keywords: [String] = [], kind: Kind = .run, arguments: [ArgumentSpec] = [], exposure: Exposure = .everywhere) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.keywords = keywords
        self.kind = kind
        self.arguments = arguments
        self.exposure = exposure
    }

    /// At most this many arguments, so their fields fit on one line.
    public static let maxArguments = 3
    /// At most this many commands per plugin.
    public static let maxCommands = 200

    public static func isValidID(_ id: String) -> Bool {
        (1...64).contains(id.utf8.count) && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// Problems that make the command unusable, in words. Empty means valid.
    public var problems: [String] {
        var result: [String] = []
        if !Self.isValidID(id) { result.append("command id \"\(id)\" must be 1 to 64 lowercase letters, digits or -") }
        if title.trimmingCharacters(in: .whitespaces).isEmpty { result.append("command \(id) has no title") }
        if title.count > 100 { result.append("command \(id): the title is longer than 100 characters") }
        if arguments.count > Self.maxArguments { result.append("command \(id) has \(arguments.count) arguments; at most \(Self.maxArguments)") }
        var names = Set<String>()
        for argument in arguments {
            if argument.name.isEmpty || !names.insert(argument.name).inserted {
                result.append("command \(id): argument names must be unique and not empty")
            }
            if let options = argument.options, options.isEmpty {
                result.append("command \(id): argument \(argument.name) has an empty options list")
            }
        }
        return result
    }

    /// The arguments a caller must give (required and without a default).
    public var requiredArguments: [ArgumentSpec] {
        arguments.filter { $0.required && $0.defaultValue == nil }
    }
}

/// One input a command takes, filled in the palette's inline fields, by
/// Spotlight, or from a link's query string.
public struct ArgumentSpec: Codable, Equatable, Sendable {
    public var name: String
    public var placeholder: String
    public var required: Bool
    public var defaultValue: String?
    /// A fixed choice instead of free text.
    public var options: [String]?

    public init(_ name: String, placeholder: String? = nil, required: Bool = true, defaultValue: String? = nil, options: [String]? = nil) {
        self.name = name
        self.placeholder = placeholder ?? name
        self.required = required
        self.defaultValue = defaultValue
        self.options = options
    }
}

/// What a run command says it did. The host performs `open`, `copy` and
/// `paste` under the plugin's capabilities, exactly like the matching calls.
public enum CommandResult: Codable, Equatable, Sendable {
    /// Done; the message, if any, is shown briefly (and by Spotlight).
    case message(String?)
    /// Open a URL or path, with an app by bundle id when given.
    case open(url: String, app: String?)
    case copy(String)
    /// Paste into the app the user was in. `cursorFromEnd` moves the caret
    /// left by that many characters afterwards. Needs `.clipboard`.
    case paste(String, cursorFromEnd: Int)
    case failure(String)
}

/// A command in the same plugin, with arguments: where a row's navigate
/// action goes.
public struct CommandTarget: Codable, Equatable, Sendable {
    public var command: String
    public var arguments: [String: String]

    public init(command: String, arguments: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
    }
}

/// What the user was in when a command started, captured before Stackbar's
/// own UI took focus. Only plugins granted `.context` receive it.
public struct InvocationContext: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        public var bundleID: String
        public var name: String
        public init(bundleID: String, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    public var frontmostApp: App?
    public var windowTitle: String?
    /// `nil` when the app does not share its selection through Accessibility.
    public var selectedText: String?
    /// Paths selected in Finder, when Finder was frontmost.
    public var finderSelection: [String]?

    public init(frontmostApp: App? = nil, windowTitle: String? = nil, selectedText: String? = nil, finderSelection: [String]? = nil) {
        self.frontmostApp = frontmostApp
        self.windowTitle = windowTitle
        self.selectedText = selectedText
        self.finderSelection = finderSelection
    }
}

/// How a command was started, so a plugin can tell a hotkey from Spotlight.
public enum InvocationSource: String, Codable, Sendable {
    case palette, hotkey, link, spotlight, shortcuts, panel, agent, cli
}

/// The query of a view command: the text typed after it and the arguments.
public struct CommandQuery: Codable, Equatable, Sendable {
    public var text: String
    public var arguments: [String: String]

    public init(text: String = "", arguments: [String: String] = [:]) {
        self.text = text
        self.arguments = arguments
    }
}
