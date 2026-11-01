# Design

## The plugin API

```swift
var commands: [Command] {
    // A run command: does something and says what happened.
    Command("toggle", title: "Toggle Stay Awake", symbol: "cup.and.saucer") { _ in
        try await self.toggle()
        return .message(self.awake ? "Awake until you stop it" : "Sleep allowed")
    }

    // A view command: a list that follows the query.
    Command("search-prs", title: "Search Pull Requests", symbol: "arrow.triangle.pull")
        .argument("repo", placeholder: "owner/repo", required: false)
        .view(search: { query in
            self.results = try await self.github.search(query.text, repo: query.arguments["repo"])
        }) { query in
            List(self.results) { pr in
                Row(pr.title, subtitle: pr.repo, key: pr.id)
                    .action("Open", shortcut: "return") { Stackbar.open(pr.url) }
                    .action("Copy Link", shortcut: "cmd+c") { Stackbar.copy(pr.url) }
                    .navigate("Checks", to: "pr-checks", arguments: ["id": pr.id])
            }
        }
}
```

- `Command(id:)` ids are stable, lowercase letters, digits and `-`, and
  unique within the plugin. They are what aliases, hotkeys, Spotlight and
  deeplinks remember, so renaming a title never breaks them.
- `.view(search:body:)` splits the async part from the render, as `refresh()`
  and the view properties do today. `search` runs on every query change and
  `body` is a plain render, so actions in the view re-render it the same way
  panel actions do.
- `@CommandBuilder` works like `@ToolBuilder`, so `for` and `if` work. The
  Quicklinks plugin writes `for link in links { Command("ql-\(link.id)", ...) }`.

## Protocol 7

```text
plugin → host  commands([CommandSpec])                  when the list changes (after ready, after any render)
host → plugin  runCommand(id, command, arguments, context?)
plugin → host  commandResult(id, CommandResult)
host → plugin  openView(session, command, arguments, query, seq, context?)
host → plugin  updateView(session, query, arguments, seq)
plugin → host  view(session, seq, root: ViewNode)
host → plugin  closeView(session)
```

- `CommandSpec`: `id`, `title`, `subtitle?`, `symbol?`, `keywords`, `kind`
  (`run` or `view`), `arguments: [ArgumentSpec]`, `exposure` (`everywhere`, or
  `stackbarOnly` to keep it out of Spotlight, Shortcuts and links).
- `ArgumentSpec`: `name`, `placeholder`, `required`, `defaultValue?`, and
  `options?` for a fixed choice. At most 3 per command, the same limit as
  Raycast, so the inline argument fields fit on one line.
- `CommandResult`: `message(String?)`, `open(url, app: bundleID?)`,
  `copy(String)`, `paste(String)`, `failure(String)`. The host acts on `open`,
  `copy` and `paste` under the plugin's capabilities. For example, `paste`
  needs `.clipboard`, exactly as `Stackbar.paste` does.
- `context` is `InvocationContext?`. It stays `nil` until
  `host-run-and-context` fills it.
- **Events inside a view** use the existing `event(action:value:)`. The
  runtime registers a view's handlers under `view/<session>/…`, so they never
  collide with panel handlers, and closing the session drops them.
- **Views are re-rendered** after any action or refresh, so state changes show
  up in an open view without a new query.

### Queries stay ordered without cancellation

The runtime handles messages one at a time, and that guarantee stays. The
host keeps at most one `updateView` in flight per session, plus the newest
pending query. Typing "react" quickly sends `r`, then `react` once `r` is
answered, never `re`, `rea` and `reac`. The plugin echoes `seq`, and the host
drops any view older than the newest one it showed. After 1 second without a
reply, the palette shows "Searching…" over the last results. A plugin that
needs faster answers caches. The authoring guide says so.

## Forms

```swift
Form(submit: "Save") {
    TextField("Name", name: "name", text: link.name)
    TextField("Link", name: "link", text: link.link, placeholder: "https://github.com/search?q={argument}")
    TextEditor("Text", name: "text", text: snippet.text)            // multi-line
    AppField("Open with", name: "app", bundleID: link.openWith)     // host shows an app picker
    Picker("Tag", name: "tag", options: tags, selection: link.tag)
    Toggle("Pinned", name: "pinned", isOn: link.pinned)
} onSubmit: { fields in ... }
```

- `ViewNode.form(FormNode)`: fields, a submit title and an action. Submitting
  sends `EventValue.fields([String: EventValue])`.
- Each field can carry an `error`. The plugin validates, and re-renders with
  the error to keep the form open. A clean submit lets the palette pop the
  view, and a panel shows the result.
- The host fills an `AppField` from the installed apps (bundle id, name,
  icon), so a plugin never lists `/Applications` itself.
- Surface parity: forms render on the panel, window, settings and command
  view. They are hidden in the menu bar, drawn disabled in the widget, and
  rendered as `[field____]` lines for agents. `SurfaceParity` and
  `docs/surface-parity.md` gain the `form` row and a *Command view* column.

## Navigation and ⌘K

- `ActionRef` gains an optional `navigate: CommandTarget`, which holds a
  command id (in the same plugin) and arguments. The host handles it alone:
  it pushes a new session and never calls a closure. In a panel, a navigate
  action opens the palette at that command.
- In a command view, ⌘K opens the selected row's actions with their
  shortcuts. Return runs the first one. Action shortcuts work without ⌘K.
  This is the same keyboard model as searchable panel lists, so there is only
  one model to learn.

## The host side

- **`CommandRegistry`** (StackbarHostCore). It holds each plugin's validated
  specs and saves them to `commands.json` in the data directory. It drops a
  plugin's entries on uninstall and publishes changes to the palette, hotkeys,
  deeplinks and (later) the Spotlight indexer. It caps 200 commands per plugin
  and rejects bad ids and duplicates with a log line naming the command.
- **`CommandPreferences`**: alias, hotkey, enabled, show in Spotlight, and
  whether links may run it, keyed by `plugin-id/command-id`. These belong to
  the user, not the plugin, so they live in the host settings file and survive
  plugin updates.
- **`CommandSearch`**: one ranking shared by the palette and, later,
  Spotlight's entity query. An exact alias match comes first, then fuzzy score
  (`TextMatch`) plus a frecency bonus. Usage is kept in `palette-usage.json`
  as counts with a 14-day half-life.
- **`CommandRunner`**: runs a command for any caller (palette, hotkey,
  deeplink, Spotlight). If the plugin isn't running, it starts or waits for it
  for up to 10 seconds. If the plugin is waiting for approval, it opens the
  approval sheet. It applies the 30-second result timeout, then performs the
  result.

## The palette

- Entries are commands first, then today's panel-derived actions, so protocol
  6 plugins still show up.
- Typing an alias and a space enters the command, and the rest of the line
  fills its first argument (`gh react`). Tab moves between argument fields.
- A view command pushes onto a stack with the command's title as a
  breadcrumb. Esc pops the stack and closes the palette at the root.
- A run command closes the palette and shows its message as a small HUD near
  the top of the screen. Spotlight uses the same text as its dialog.

## Deeplinks

`stackbar://commands/dev.navbytes.pr-cockpit/search-prs?repo=apple/swift`

The app registers the `stackbar` scheme in both Info.plists (XcodeGen and
`bundle.sh`). The source of a URL open is unknown. So the first time a link
tries to run a *run* command, Stackbar asks "Allow links to run Toggle Stay
Awake?" with Always, Once and Cancel. A *view* command just opens, since the
user sees it before anything happens. `stackbarOnly` commands refuse links.

## Plugins without a menu-bar item

`AppDelegate.syncItems` creates a status item only for plugins that list
`.menuBar` and that the user hasn't hidden. A headless plugin's panel opens in
a centered floating panel, from its hotkey, its command, or "Open <Plugin>" in
the palette, using the window chrome the palette already uses.

## Testing (Linux unless noted)

- Runtime: command list diffing, run, view sessions, `seq` echo, handler
  isolation between sessions, re-render after an action.
- Host: registry validation and persistence, preferences, ranking with aliases
  and frecency, query coalescing (a scripted fake plugin), the deeplink
  parser, CommandRunner timeouts and the not-running cases.
- The parity ledger test covers `form` and the command-view column.
- macOS CI builds the palette UI. A manual checklist on Naveen's Mac covers
  typing speed, ⌘K, Esc and argument fields.
