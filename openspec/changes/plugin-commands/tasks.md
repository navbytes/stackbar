# Tasks

## 1. Protocol 7
- [x] 1.1 `CommandSpec`, `ArgumentSpec`, `CommandResult`, `CommandTarget`, `InvocationContext` (empty for now)
- [x] 1.2 Messages: `commands`, `runCommand`/`commandResult`, `openView`/`updateView`/`view`/`closeView`
- [x] 1.3 `ViewNode.form`, field kinds (text, multi-line, app, picker, toggle), `EventValue.fields`
- [x] 1.4 `ActionRef.navigate`
- [x] 1.5 `StackbarProtocolVersion.current = 7`; protocol 6 plugins still load

## 2. StackbarKit
- [x] 2.1 `Command`, `@CommandBuilder`, `.argument`, `.view(search:body:)`, `StackbarPlugin.commands`
- [x] 2.2 Runtime: send command list on change; run; view sessions with `view/<session>/` handler namespace; re-render open views
- [x] 2.3 `Form`, `Row.navigate(_:to:arguments:)`; fields are `FormField.text`, `.multiline`, `.application`, `.picker` and `.toggle`

## 3. Host core
- [x] 3.1 `CommandRegistry` with validation, `commands.json`, uninstall cleanup
- [x] 3.2 `CommandPreferences` (alias, hotkey, enabled, Spotlight, links)
- [x] 3.3 Command search in `PaletteIndex`: alias, fuzzy, frecency (`PaletteUsage`, `palette-usage.json`)
- [x] 3.4 `CommandRunner`: start or wait for the plugin, approval, timeouts, perform results under capabilities
- [x] 3.5 View session manager: one in flight plus newest pending, stale drops
- [x] 3.6 `SurfaceParity`: `form` row, command-view column; regenerate `docs/surface-parity.md`

## 4. App (macOS)
- [x] 4.1 Palette: command entries first, alias entry, argument fields, view stack, breadcrumb, Esc, Searching…, HUD
- [x] 4.2 ⌘K action panel
- [x] 4.3 Form renderer, app picker
- [x] 4.4 Settings → Commands: search, alias, hotkey recorder with conflict check, enable, link permission (the Spotlight switch lands with spotlight-commands)
- [x] 4.5 Per-command global hotkeys (`HotKey`)
- [x] 4.6 `stackbar://` scheme in both Info.plists; deeplink handler; "Allow links to run" prompt
- [x] 4.7 No status item without `.menuBar`; "Show in menu bar" per plugin; centered panel for headless plugins
- [ ] 4.8 Manual check on a Mac: typing speed, ⌘K, Esc, argument fields, hotkeys, a `stackbar://` link, a hidden menu-bar item

## 5. Tools and docs
- [x] 5.1 `stackbarctl commands`, `stackbarctl run <file> <command> --arg k=v`, `render --command id --query q`
- [x] 5.2 MCP authoring tools `stackbar_list_commands`, `stackbar_run_command`, `stackbar_render_command`
- [x] 5.3 Authoring guide and `llms.txt`: commands, views, forms, navigation, "keep search fast"
- [x] 5.4 Port PR Cockpit (search PRs view, open, review) and Clipboard History (search view, paste) to commands
- [x] 5.5 Tests listed in design.md; `swift build && swift test`
