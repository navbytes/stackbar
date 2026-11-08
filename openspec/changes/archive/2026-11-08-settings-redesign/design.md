# Design

## Shell

`SettingsView` is a `NavigationSplitView` whose selection is `SettingsTab`:
`general`, `commands`, `agents`, `privacy`, `store` or `plugin(id)`. The
window keeps being an `NSWindow` (it opens from the menu bar app), with
`.fullSizeContentView`, a unified toolbar and `sceneBridgingOptions =
[.toolbars, .title]` so the sidebar, search field and page titles come from
SwiftUI. Its frame is remembered.

## Pages

Pages are a scrolling column (max 680 pt) of `SettingsGroup`s rather than a
grouped `Form`, because a plugin's own settings are `ViewNode`s and must sit
in the same boxes as the host's rows. `SettingsGroup` lives in StackbarUI and
draws a title, a rounded box with hairlines between its rows (`Group(subviews:)`)
and a footer. `NodeView` draws `.section` with it, and toggles and pickers
trailing, when `stackbarGroupedSections` is set.

## What the page says

`SettingsPresentation` (StackbarHostCore, tested on Linux) turns state into
words: a capability into an icon row (access kind, symbol, hue, short title,
full detail, pending), a supervisor state into a status line and tone, and
the overview of access and secrets across plugins.

## Kept

Secrets rows (Change, Clear), the uninstall dialog, command rows and the
hotkey recorder are reused as they were.
