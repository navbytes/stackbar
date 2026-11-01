#if os(macOS)
import AppIntents
@preconcurrency import CoreSpotlight
import Foundation
import StackbarHostCore
import StackbarProtocol

// Plugin commands in Spotlight and Shortcuts. App Intents are compiled in and
// plugin commands are not, so a few fixed intents take a command entity whose
// query reads the registry at run time. The Xcode build (scripts/install.sh)
// extracts their metadata; `swift build` compiles them but registers nothing.

/// One plugin command, as Spotlight and Shortcuts see it.
struct CommandEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Stackbar Command" }
    static var defaultQuery: CommandEntityQuery { CommandEntityQuery() }

    /// `plugin-id/command-id`
    let id: String
    let title: String
    let summary: String
    let symbol: String
    let keywords: [String]

    init(_ item: CommandIndexItem) {
        id = item.id
        title = item.title
        summary = item.summary
        symbol = item.symbol
        keywords = item.keywords
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(summary)", image: .init(systemName: symbol))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.displayName = title
        attributes.title = title
        attributes.contentDescription = summary
        attributes.keywords = keywords
        return attributes
    }
}

struct CommandEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CommandEntity] {
        let items = try await StackbarIntents.items()
        let wanted = Set(identifiers)
        return items.filter { wanted.contains($0.id) }.map(CommandEntity.init)
    }

    func entities(matching string: String) async throws -> [CommandEntity] {
        try await StackbarIntents.search(string).map(CommandEntity.init)
    }

    func suggestedEntities() async throws -> [CommandEntity] {
        try await StackbarIntents.search("").map(CommandEntity.init)
    }
}

/// A plugin, for "Open <plugin> in Stackbar".
struct PluginEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Stackbar Plugin" }
    static var defaultQuery: PluginEntityQuery { PluginEntityQuery() }

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "puzzlepiece.extension"))
    }
}

struct PluginEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PluginEntity] {
        let wanted = Set(identifiers)
        return try await StackbarIntents.plugins().filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [PluginEntity] {
        try await StackbarIntents.plugins().filter { string.isEmpty || TextMatch.score(string, in: $0.name) != nil }
    }

    func suggestedEntities() async throws -> [PluginEntity] {
        try await StackbarIntents.plugins()
    }
}

/// Runs a command. A run command runs here and its message is the dialog;
/// a view command, or one that needs more than the one input, opens the
/// palette to collect the rest.
struct RunCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Stackbar Command"
    static let description = IntentDescription("Runs a command from one of your Stackbar plugins.")

    @Parameter(title: "Command")
    var command: CommandEntity

    @Parameter(title: "Input", description: "The command's first argument, when it takes one")
    var input: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command)") {
            \.$input
        }
    }

    init() {}

    init(command: CommandEntity, input: String? = nil) {
        self.command = command
        self.input = input
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let center = try await StackbarIntents.center()
        let message = try await center.runFromIntent(command.id, input: input)
        return .result(dialog: IntentDialog("\(message)"))
    }
}

/// What Spotlight runs when an indexed command is opened: the palette, at
/// that command.
struct OpenCommandIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Stackbar Command"
    static let description = IntentDescription("Opens a command in Stackbar's palette.")

    @Parameter(title: "Command")
    var target: CommandEntity

    init() {}

    init(target: CommandEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let center = try await StackbarIntents.center()
        try await center.openFromIntent(target.id, input: nil)
        return .result()
    }
}

/// Opens a plugin's panel.
struct OpenPluginIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Stackbar Plugin"
    static let description = IntentDescription("Opens a Stackbar plugin's panel.")

    @Parameter(title: "Plugin")
    var target: PluginEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await StackbarIntents.center()
        guard let delegate = AppDelegate.shared, delegate.model.controller(for: target.id) != nil else {
            throw CommandIntentError("\(target.name) is not installed")
        }
        delegate.showPanel(pluginID: target.id)
        return .result()
    }
}

struct StackbarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunCommandIntent(),
            phrases: [
                "Run \(\.$command) in \(.applicationName)",
                "Run a command in \(.applicationName)",
            ],
            shortTitle: "Run Command",
            systemImageName: "command"
        )
        AppShortcut(
            intent: OpenPluginIntent(),
            phrases: ["Open \(\.$target) in \(.applicationName)"],
            shortTitle: "Open Plugin",
            systemImageName: "puzzlepiece.extension"
        )
    }
}

/// A failure Spotlight and Shortcuts show as it is.
struct CommandIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// Where the intents reach the running app.
@MainActor
enum StackbarIntents {
    /// The app's commands, waiting a little when the intent launched it.
    static func center() async throws -> CommandCenter {
        for _ in 0..<100 {
            if let center = AppDelegate.shared?.model.commands { return center }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CommandIntentError("Stackbar is still starting")
    }

    static func items() async throws -> [CommandIndexItem] {
        let center = try await center()
        return CommandIndexing.items(registry: center.registry, preferences: center.preferences, usage: center.usage)
    }

    static func search(_ text: String) async throws -> [CommandIndexItem] {
        let center = try await center()
        return CommandIndexing.search(text, registry: center.registry, preferences: center.preferences, usage: center.usage)
    }

    static func plugins() async throws -> [PluginEntity] {
        _ = try await center()
        return (AppDelegate.shared?.model.controllers ?? [])
            .filter { $0.manifest?.surfaces.contains(.panel) == true }
            .map { PluginEntity(id: $0.pluginID, name: $0.name) }
    }
}

/// Keeps the Spotlight index equal to the exposed commands, and Shortcuts'
/// phrases up to date. Each sync is a diff against what was indexed.
@MainActor
final class CommandSpotlightIndexer {
    nonisolated static let indexName = "io.navbytes.stackbar.commands"
    private var indexed: [CommandIndexItem] = []
    private var started = false
    private var task: Task<Void, Never>?

    func sync(_ items: [CommandIndexItem]) {
        let previous = task
        let starting = !started
        started = true
        let old = indexed
        indexed = items
        task = Task {
            await previous?.value
            // A launch starts from a clean index, so nothing a previous run
            // left behind (a plugin since removed) lingers.
            await Self.apply(reset: starting, old: starting ? [] : old, new: items)
        }
    }

    nonisolated private static func apply(reset: Bool, old: [CommandIndexItem], new: [CommandIndexItem]) async {
        let index = CSSearchableIndex(name: indexName)
        if reset { try? await index.deleteAllSearchableItems() }
        let (upsert, delete) = CommandIndexing.diff(from: old, to: new)
        if !delete.isEmpty {
            try? await index.deleteAppEntities(identifiedBy: delete, ofType: CommandEntity.self)
        }
        for (priority, items) in Dictionary(grouping: upsert, by: \.priority) {
            try? await index.indexAppEntities(items.map(CommandEntity.init), priority: priority)
        }
        StackbarShortcuts.updateAppShortcutParameters()
    }
}
#endif
