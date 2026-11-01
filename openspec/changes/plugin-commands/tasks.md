# Tasks

## 1. Protocol 7
- [ ] 1.1 `CommandSpec`, `ArgumentSpec`, `CommandResult`, `CommandTarget`, `InvocationContext` (empty for now)
- [ ] 1.2 Messages: `commands`, `runCommand`/`commandResult`, `openView`/`updateView`/`view`/`closeView`
- [ ] 1.3 `ViewNode.form`, field kinds (text, multi-line, app, picker, toggle), `EventValue.fields`
- [ ] 1.4 `ActionRef.navigate`
- [ ] 1.5 `StackbarProtocolVersion.current = 7`; protocol 6 plugins still load

## 2. StackbarKit
- [ ] 2.1 `Command`, `@CommandBuilder`, `.argument`, `.view(search:body:)`, `StackbarPlugin.commands`
- [ ] 2.2 Runtime: send command list on change; run; view sessions with `view/<session>/` handler namespace; re-render open views
- [ ] 2.3 `Form`, `TextField(name:)`, `TextEditor`, `AppField`, `Row.navigate(_:to:arguments:)`

## 3. Host core
- [ ] 3.1 `CommandRegistry` with validation, `commands.json`, uninstall cleanup
- [ ] 3.2 `CommandPreferences` (alias, hotkey, enabled, Spotlight, links)
- [ ] 3.3 `CommandSearch`: alias, fuzzy, frecency (`palette-usage.json`)
- [ ] 3.4 `CommandRunner`: start or wait for the plugin, approval, timeouts, perform results under capabilities
- [ ] 3.5 View session manager: one in flight plus newest pending, stale drops
- [ ] 3.6 `SurfaceParity`: `form` row, command-view column; regenerate `docs/surface-parity.md`

## 4. App (macOS)
- [ ] 4.1 Palette: command entries first, alias entry, argument fields, view stack, breadcrumb, Esc, Searching…, HUD
- [ ] 4.2 ⌘K action panel
- [ ] 4.3 Form renderer, app picker
- [ ] 4.4 Settings → Commands: search, alias, hotkey recorder with conflict check, enable, Spotlight switch
- [ ] 4.5 Per-command global hotkeys (`HotKey`)
- [ ] 4.6 `stackbar://` scheme in both Info.plists; deeplink handler; "Allow links to run" prompt
- [ ] 4.7 No status item without `.menuBar`; "Show in menu bar" per plugin; centered panel for headless plugins

## 5. Tools and docs
- [ ] 5.1 `stackbarctl commands`, `stackbarctl run <file> <command> --arg k=v`, `render --command id --query q`
- [ ] 5.2 MCP authoring tools `stackbar_list_commands`, `stackbar_run_command`, `stackbar_render_command`
- [ ] 5.3 Authoring guide and `llms.txt`: commands, views, forms, navigation, "keep search fast"
- [ ] 5.4 Port PR Cockpit (search PRs view, open, review) and Clipboard History (search view, paste) to commands
- [ ] 5.5 Tests listed in design.md; `swift build && swift test`
