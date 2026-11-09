import Foundation

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
    /// A view command whose top rows also show in the palette's results
    /// while the user types, as its own section. Protocol 16.
    public var rootSearch: Bool
    /// The heading over a root-search command's rows ("Applications");
    /// the command's title when nil. Protocol 16.
    public var rootSection: String?
    /// Offered under the palette's results for whatever was typed: the text
    /// fills the first argument, or a view's search. Protocol 16.
    public var fallback: Bool
    /// A regular expression the whole typed text must match before the host
    /// sends it to a root-search command (`^[A-Z]+-\d+$` for an issue key).
    /// Text that doesn't match never reaches the plugin, and a section that
    /// matched comes before the other results. Protocol 17.
    public var rootPattern: String?
    /// How long a run command may take, in seconds, when that is more than
    /// the host's 30 (a script, a build). At most `maxTimeout`. 0.36.0.
    public var timeout: Double?

    public init(id: String, title: String, subtitle: String? = nil, symbol: String? = nil, keywords: [String] = [], kind: Kind = .run, arguments: [ArgumentSpec] = [], exposure: Exposure = .everywhere,
                rootSearch: Bool = false, rootSection: String? = nil, fallback: Bool = false, rootPattern: String? = nil, timeout: Double? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.keywords = keywords
        self.kind = kind
        self.arguments = arguments
        self.exposure = exposure
        self.rootSearch = rootSearch
        self.rootSection = rootSection
        self.fallback = fallback
        self.rootPattern = rootPattern
        self.timeout = timeout
    }

    // Written by hand so specs from plugins built before protocol 16, which
    // have no `rootSearch` or `fallback`, still decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        kind = try container.decode(Kind.self, forKey: .kind)
        arguments = try container.decodeIfPresent([ArgumentSpec].self, forKey: .arguments) ?? []
        exposure = try container.decodeIfPresent(Exposure.self, forKey: .exposure) ?? .everywhere
        rootSearch = try container.decodeIfPresent(Bool.self, forKey: .rootSearch) ?? false
        rootSection = try container.decodeIfPresent(String.self, forKey: .rootSection)
        fallback = try container.decodeIfPresent(Bool.self, forKey: .fallback) ?? false
        rootPattern = try container.decodeIfPresent(String.self, forKey: .rootPattern)
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
    }

    /// At most this many arguments, so their fields fit on one line.
    public static let maxArguments = 3
    /// The longest a run command may ask to take: ten minutes.
    public static let maxTimeout: Double = 600

    /// The time the host gives a run, within 1 second and `maxTimeout`;
    /// `standard` when the command names none.
    public func runTimeout(standard: Double) -> Double {
        guard let timeout else { return standard }
        return min(max(timeout, 1), Self.maxTimeout)
    }

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
        if rootSearch, kind != .view { result.append("command \(id): only a view command can search from the palette's root") }
        if let rootPattern {
            if !rootSearch { result.append("command \(id): a root pattern needs .rootSearch()") }
            if (try? NSRegularExpression(pattern: rootPattern)) == nil { result.append("command \(id): the root pattern \"\(rootPattern)\" is not a valid regular expression") }
        }
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

    /// Selected text is cut to this many UTF-8 bytes.
    public static let maxSelectedText = 100 * 1024

    /// `text` cut to `maxSelectedText` bytes, on a character boundary.
    public static func capped(_ text: String) -> String {
        guard text.utf8.count > maxSelectedText else { return text }
        var result = ""
        var bytes = 0
        for character in text {
            bytes += character.utf8.count
            if bytes > maxSelectedText { break }
            result.append(character)
        }
        return result
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
