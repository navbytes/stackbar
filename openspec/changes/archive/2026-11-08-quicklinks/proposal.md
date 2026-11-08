# Quicklinks

## Why

Naveen chose Quicklinks from the optional list (2026-11-01). A quicklink is a
named link with placeholders: `https://github.com/search?q={argument}`,
`~/Projects/{argument name="repo"}`, `slack://channel?id=C123`, optionally
opened with a chosen app. Raycast users have dozens. Shortcuts can do the same
with "Ask for Input" and "Open URL", but each link takes a whole shortcut,
there is no shared library, and nothing imports a Raycast export.

## What changes

- **`Template`** in StackbarKit: one placeholder engine, shared with
  `snippets`. It uses Raycast's syntax, so imported links work unchanged.
- **A bundled Quicklinks plugin** (`Plugins/QuicklinksPlugin`):
  - Every quicklink becomes a command, so it shows in the palette and
    Spotlight with its arguments, and can have an alias, a hotkey and a
    deeplink with no extra work.
  - "Search Quicklinks" lists and manages them.
  - "Create Quicklink" is a form.
  - Import and export of Raycast JSON.
- **`Stackbar.open(_:with:)`** opens a URL or path with a chosen app.
- **A new `.openURLs(schemes:)` capability** for schemes beyond the safe
  default set. `"*"` means any scheme or file path, with a warning on the
  install sheet. Quicklinks declares `"*"`, because opening arbitrary links is
  its whole purpose.
- **`Stackbar.chooseFile` and `Stackbar.saveFile`.** The user picks the file
  in a standard open or save dialog, so the plugin reaches only that one file
  and needs no `.files` grant. Import and export use them.
- **No menu-bar item by default**, through headless plugins from
  `plugin-commands`. It is reached from the palette, Spotlight, its hotkey and
  Settings.

## Depends on

`plugin-commands`, for commands, arguments, forms, ⌘K, aliases, hotkeys and
headless plugins. It also works without `spotlight-commands` and
`host-run-and-context`, and gains Spotlight and `{selection}` once those land.
