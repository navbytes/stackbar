# Design

## Why fixed intents with dynamic entities

App Intents are Swift types that the build extracts into metadata
(`Metadata.appintents`), so new intents can't appear at runtime. Entities can.
An `AppEntity` query answers at runtime, and indexed entities are donated at
runtime. Every plugin command is therefore a `CommandEntity`, and three fixed
intents act on them. This is the pattern Apple shows for app content, such as
landmarks in its WWDC25 sessions 244 and 260 and the "Making app entities
available in Spotlight" article.

## Types (Sources/Stackbar/Intents, macOS only)

```swift
struct CommandEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stackbar Command"
    static let defaultQuery = CommandEntityQuery()
    let id: String                                   // "dev.navbytes.pr-cockpit/search-prs"
    @Property(indexingKey: \.displayName) var title: String
    @Property(indexingKey: \.contentDescription) var summary: String   // "PR Cockpit · Search pull requests"
    var symbol: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(summary)", image: .init(systemName: symbol))
    }
    var attributeSet: CSSearchableItemAttributeSet { /* keywords, alias */ }
}

struct CommandEntityQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for ids: [String]) async throws -> [CommandEntity]       // registry lookup
    func entities(matching text: String) async throws -> [CommandEntity]   // CommandSearch, same ranking as the palette
    func suggestedEntities() async throws -> [CommandEntity]               // top 20 by frecency
    func reindexAllEntities(indexDescription:) async throws                // index everything again
    func reindexEntities(for:indexDescription:) async throws
}

struct RunCommandIntent: AppIntent, PredictableIntent {
    static let title: LocalizedStringResource = "Run Stackbar Command"
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Command") var command: CommandEntity
    @Parameter(title: "Input") var input: String?          // first argument
    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$command)") { \.$input } }
    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent
}

struct OpenCommandIntent: OpenIntent {          // Spotlight runs this when an indexed command is opened
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Command") var target: CommandEntity
}

struct OpenPluginIntent: OpenIntent { @Parameter(title: "Plugin") var target: PluginEntity }

struct StackbarShortcuts: AppShortcutsProvider { /* "Run \(\.$command) in \(.applicationName)", "Open \(\.$target) in \(.applicationName)" */ }
```

- The parameter summary names the one required parameter (`command`), which
  WWDC25 session 260 says is the condition for appearing in Spotlight on Mac.
  `input` is optional, so leaving it out of the summary doesn't hide the
  intent.
- `RunCommandIntent.perform`:
  - A *run* command maps `input` to the command's first argument, runs it
    through `CommandRunner` and returns the result message as the dialog.
  - A *view* command, or a run command with more than one required argument,
    returns `opensIntent: OpenCommandIntent`. The palette then opens at that
    command, with `input` filled in, to collect the rest. Spotlight can't hold
    several dynamic arguments for one intent, and the palette can.
- Failures throw an error whose message is the `CommandRunner` failure, such
  as "PR Cockpit is waiting for your approval", so Spotlight shows it.
- `AppDependencyManager.shared.add { model.commandRunner }` runs at launch.
  If the intent launched the app, `CommandRunner` waits up to 10 seconds for
  the plugin.

## Index

- `CommandSpotlightIndexer` observes the registry and preferences. It indexes
  changed entities into `CSSearchableIndex(name: "io.navbytes.stackbar.commands")`
  and deletes removed ones with `deleteAppEntities(identifiedBy:ofType:)`.
- Priority comes from frecency, so the commands you use rank higher.
- Excluded: `stackbarOnly` commands, commands the user switched off, and every
  command when the overall switch is off. Turning it off deletes the index.
- After any registry change, the indexer also calls
  `StackbarShortcuts.updateAppShortcutParameters()`.

## Shortcuts and Quick Keys

- In Shortcuts, "Run Stackbar Command" appears with a command picker backed by
  `entities(matching:)`. So any command can be scheduled, automated or bound
  to a key through Shortcuts.
- Quick Keys belong to Spotlight. The spike checks whether a Quick Key can be
  saved for `RunCommandIntent` with a specific command chosen. If it can't,
  Stackbar's own aliases and hotkeys (from `plugin-commands`) remain the way to
  reach a command with a few keys. The docs then show how to make a one-step
  Shortcut, which can take a Quick Key.

## Builds

- The metadata is produced only by Xcode's "Extract App Intents Metadata"
  build step. `swift build` and `swift run Stackbar` compile the intents but
  register nothing, which is fine for development.
- `scripts/install.sh` already uses `xcodebuild`. `scripts/bundle.sh` moves
  to `xcodebuild` without the widget (release task 3.3).
- The intents stay in the app target, not in a package library, so no
  `AppIntentsPackage` wiring is needed.

## What is shared and tested on Linux

The entity mapping (`CommandSpec` to title, summary, keywords and
identifier), the search and the index diff (what to add and what to delete)
are plain functions in StackbarHostCore with tests. The intents are thin
wrappers. A manual checklist on Naveen's Mac covers ⌘Space results, ⌘3
actions, Quick Keys, Shortcuts, running with the app quit, and a plugin that
is waiting for approval.

## Security

- Spotlight and Shortcuts run commands as the user. That is the same trust as
  a click, because the user chose the command.
- Shortcuts automations can run commands with no prompt, because the user
  built the automation.
- Commands that should never be run from outside declare `stackbarOnly`.
- The index holds only titles, plugin names and keywords, never data from a
  command's results.
