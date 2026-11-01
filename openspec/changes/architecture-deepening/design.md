# Design

## Order of work
Items 1, 2 and 5, 3, 4 and 9, and 6 touch different files, so they are built
in parallel in separate worktrees. They land one pull request at a time on the
thread's branch, each rebased on the one before. Items 7 and 8 touch
`stackbarctl/main.swift` and `HostClient.swift`, which items 1 and 4 also
change, so they start after those have landed. The stackbar-plugins change
(lint reading the JSON, raising the pin) comes last, and is coordinated with
the plugin-redesign thread, which owns every plugin source file.

## PluginLoader
```swift
public struct PluginLoader: Sendable {
    public init(builder: PluginBuilder?, sandbox: Bool)
    /// Builds a .swift source (or takes a helper as is), reads and checks the
    /// manifest, and signs the helper into the sandbox when `sandbox` is set.
    public func load(_ source: URL) throws -> LoadedPlugin   // binary, manifest
}
```
The app keeps its own checks for duplicate ids and approvals, because those
depend on other installed plugins and on the user. `sandbox` is true on macOS
in the CLI unless `--no-sandbox` is passed, and false on Linux, where there
is nothing to sign.

## Where view-tree logic lives
Everything that answers a question about a `ViewNode` without drawing it goes
in `StackbarProtocol/ViewNodeQueries.swift`: `filtered(query:)`,
`trimmed(maxRows:)`, `hasMenuBarContent`, `hasFormErrors`, `listItems(query:)`,
`affordances` and `mapChildren`. StackbarUI and the app only draw.

## Fixtures
Each removed plugin copy was used by a host test for one feature. That test
moves to a feature fixture: `FixturePlugin` gains the modes it needs, and
plugin-specific behaviour (the Snippets template expansion, the Quicklinks
URL building) stays tested in stackbar-plugins.
