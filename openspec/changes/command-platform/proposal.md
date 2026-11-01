# Command platform: what a Raycast user needs, without rebuilding macOS

## Why

A developer who uses Raycast daily should be able to switch to Stackbar. The
gap review (https://claude.ai/artifact/BZN5Usx1k3KeFg6KdKr2eu, 2026-11-01)
found that macOS 26 already does most of what Raycast is used for: Spotlight
launches apps, searches files, does math, runs App Intents and Shortcuts, has
Quick Keys and searches menus. Naveen's rule: don't reinvent what macOS does
well in daily use. Skip a feature only when the system's version is as good in
practice, not just because it exists. That is why Clipboard History stays:
Spotlight's needs ⌘Space then ⌘4, and Stackbar's opens on ⌘⇧V at the cursor.

What macOS lacks, and Naveen approved building (2026-11-01):

1. Plugin commands that Spotlight, Shortcuts and Quick Keys can run.
2. Live plugin lists that update as you type, with an action panel (⌘K).
3. Host services that plugins need: running declared commands, and the
   context the user was in (selected text, frontmost app, Finder selection).
4. Snippets with placeholders.
5. Quicklinks: URL templates with arguments (chosen from the optional list).
6. About ten starter developer plugins in navbytes/stackbar-plugins.

## What changes

This change is the map. Each part has its own change with its own proposal,
design and tasks, built in this order because each depends on the one before:

| Order | Change | Delivers |
| --- | --- | --- |
| 1 | `plugin-commands` | Protocol 7: commands declared by plugins, live command views in the palette, forms, ⌘K, aliases, per-command hotkeys, `stackbar://` deeplinks |
| 2 | `spotlight-commands` | App Intents: every command in Spotlight, Shortcuts and Quick Keys, indexed in Core Spotlight |
| 3 | `host-run-and-context` | `Stackbar.run` behind `.run`, the `.context` capability, invocation context |
| 4 | `quicklinks` | Shared placeholder engine (StackbarKit `Template`), bundled Quicklinks plugin, Raycast import |
| 5 | `snippets` | Bundled Snippets plugin on the same engine, paste with `{cursor}`, Raycast import; keyword expansion as a separate opt-in |
| 6 | starter plugins | Built in navbytes/stackbar-plugins against 1 and 3 |

Quicklinks comes before Snippets because it is smaller and proves the
template engine and the "items become commands" pattern first.

## Not in this change, on purpose

- A launcher, app or file search, a calculator, system commands, menu search,
  window halves, an emoji picker, notes, AI chat. macOS 26 covers them. For AI,
  `stackbarctl agent` already gives any MCP client every plugin's tools.
- Window thirds and layouts: Rectangle covers them.
- Cloud sync. It can come later through iCloud Drive if the beta asks.

## The pattern that ties it together

User-defined items become commands. A quicklink, a snippet or a saved search
is a command its plugin publishes. Every command then shows up everywhere: in
the palette, in Spotlight, in Shortcuts, with an alias and a hotkey, and as a
deeplink. Nothing about quicklinks or snippets is special-cased in the host.
