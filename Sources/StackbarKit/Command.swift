/// A command the plugin offers: found by name in the palette, run from a
/// hotkey, a `stackbar://` link, Spotlight or Shortcuts.
///
/// ```swift
/// var commands: [Command] {
///     // A run command: does something and says what happened.
///     Command("toggle", title: "Toggle Stay Awake", symbol: "cup.and.saucer") { _ in
///         try await self.toggle()
///         return .message(self.awake ? "Awake until you stop it" : "Sleep allowed")
///     }
///
///     // A view command: a list that follows what the user types.
///     Command("search", title: "Search Pull Requests", symbol: "magnifyingglass")
///         .argument("repo", placeholder: "owner/repo", required: false)
///         .view(search: { query in
///             self.results = try await self.find(query.text, repo: query["repo"])
///         }) { _ in
///             List(self.results) { pr in
///                 Row(pr.title, key: pr.id).action("Open") { Stackbar.open(pr.url) }
///             }
///         }
/// }
/// ```
///
/// Ids are what aliases, hotkeys and links remember: lowercase letters,
/// digits and `-`, unique in the plugin. Titles can change freely.
public struct Command: Sendable {
    public typealias Run = @MainActor @Sendable (CommandInvocation) async throws -> CommandResult
    public typealias Search = @MainActor @Sendable (CommandInvocation) async throws -> Void
    public typealias Body = @MainActor @Sendable (CommandInvocation) -> ViewContent

    public private(set) var spec: CommandSpec
    var run: Run?
    var search: Search?
    var body: Body?

    /// A run command.
    public init(_ id: String, title: String, subtitle: String? = nil, symbol: String? = nil, keywords: [String] = [], run: @escaping Run) {
        spec = CommandSpec(id: id, title: title, subtitle: subtitle, symbol: symbol, keywords: keywords, kind: .run)
        self.run = run
    }

    /// A command that becomes a view once `.view(search:body:)` is added.
    public init(_ id: String, title: String, subtitle: String? = nil, symbol: String? = nil, keywords: [String] = []) {
        spec = CommandSpec(id: id, title: title, subtitle: subtitle, symbol: symbol, keywords: keywords, kind: .view)
    }

    /// An input the command takes. At most three.
    public func argument(_ name: String, placeholder: String? = nil, required: Bool = true, default defaultValue: String? = nil, options: [String]? = nil) -> Command {
        var copy = self
        copy.spec.arguments.append(ArgumentSpec(name, placeholder: placeholder, required: required, defaultValue: defaultValue, options: options))
        return copy
    }

    /// Makes this a view command. `search` runs whenever the query or an
    /// argument changes (fetch here); `body` renders like a panel and runs
    /// again after every action, so it should only read state.
    public func view(search: Search? = nil, @ViewBuilder body: @escaping Body) -> Command {
        var copy = self
        copy.spec.kind = .view
        copy.search = search
        copy.body = body
        copy.run = nil
        return copy
    }

    /// Keeps the command out of Spotlight, Shortcuts and links.
    public func stackbarOnly() -> Command {
        var copy = self
        copy.spec.exposure = .stackbarOnly
        return copy
    }
}

extension CommandResult {
    /// Done, with nothing to say.
    public static var done: CommandResult { .message(nil) }
}

/// What a command was started with.
public struct CommandInvocation: Sendable, Equatable {
    /// The text typed in a view command's search field.
    public var text: String
    public var arguments: [String: String]
    public var source: InvocationSource
    /// The app and selection the user was in. Only for plugins with `.context`.
    public var context: InvocationContext?

    public init(text: String = "", arguments: [String: String] = [:], source: InvocationSource = .palette, context: InvocationContext? = nil) {
        self.text = text
        self.arguments = arguments
        self.source = source
        self.context = context
    }

    /// An argument's value, or `nil` when it was left empty.
    public subscript(_ name: String) -> String? {
        guard let value = arguments[name], !value.isEmpty else { return nil }
        return value
    }
}

@resultBuilder
public enum CommandBuilder {
    public static func buildExpression(_ command: Command) -> [Command] { [command] }
    public static func buildBlock(_ parts: [Command]...) -> [Command] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [Command]?) -> [Command] { part ?? [] }
    public static func buildEither(first part: [Command]) -> [Command] { part }
    public static func buildEither(second part: [Command]) -> [Command] { part }
    public static func buildArray(_ parts: [[Command]]) -> [Command] { parts.flatMap { $0 } }
}
