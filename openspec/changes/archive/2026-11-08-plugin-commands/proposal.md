# Plugin commands

## Why

Raycast extensions are made of commands. A command is something you can find
by name and run, often with arguments, and it either does a thing or shows a
list that updates as you type. Stackbar's palette (⌃⌥Space) can't do this
today. It only replays the buttons and rows that panels already rendered
(`PaletteIndex`). Those entries have no stable identity, no arguments, and
can't answer a query. So nothing outside a plugin's panel (Spotlight,
Shortcuts, a hotkey, a link) can name a plugin action reliably.

This change gives plugins first-class commands. `spotlight-commands`,
`quicklinks` and `snippets` all build on it.

## What changes

- **Protocol 7.** A plugin declares commands in code, with a `@CommandBuilder`
  like tools. The runtime sends them as `commands([CommandSpec])` whenever the
  list changes, so a plugin can publish user-defined items (one command per
  quicklink) as commands.
- **Two kinds of command.**
  - A *run* command takes arguments, does its work and returns a
    `CommandResult`: a message, open a URL, copy, or paste.
  - A *view* command opens a live view in the palette. The host sends the
    query as the user types, and the plugin answers with a `ViewNode` tree.
- **Forms.** A new `form` node holds several fields that are submitted
  together, including a multi-line field and an application field. They are
  used for "Create Quicklink", "Create Snippet" and settings.
- **Navigation.** A row can push another command (`Row.navigate(to:)`). The
  palette keeps a stack and Esc goes back.
- **Action panel.** ⌘K lists every action of the selected row, with its
  shortcut.
- **Command registry in the host.** It holds the last-known commands of every
  installed plugin, saved to disk. Commands can then be indexed, given aliases
  and run even while their plugin is restarting.
- **Aliases, hotkeys, frecency.** Settings gets a Commands page. Any command
  can get an alias and a global hotkey, and can be switched off. The palette
  ranks by how often and how recently each entry was used.
- **Deeplinks.** `stackbar://commands/<plugin-id>/<command-id>?name=value`.
  Run commands ask once before a link may run them.
- **Plugins without a menu-bar item.** A plugin that does not list `.menuBar`
  gets no status item, and its panel opens centered from the palette or a
  hotkey. Any plugin can also be hidden from the menu bar in Settings.
- **Authoring.** `stackbarctl commands`, `stackbarctl run` and
  `render --command`, matching MCP authoring tools, and updates to the
  authoring guide and `llms.txt`.

## Compatibility

- Plugins built for protocol 6 keep working. They send no commands, and their
  panel actions still show in the palette as today.
- `EventValue` gains a `fields` case. Older plugins never receive it, because
  forms only come from plugins that rendered one.

## Not in this change

- Spotlight, Shortcuts and App Intents (`spotlight-commands`).
- Invocation context such as selected text (`host-run-and-context`). This
  change reserves the field in its messages.
