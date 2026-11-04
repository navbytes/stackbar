# The palette as a launcher: files, plugins in the root, fallbacks, grids

## Why

Naveen asked (2026-11-04) for the remaining Raycast-style palette items in
one go: file search, clipboard history and snippets in the palette, fallback
commands, window layouts, an emoji picker with grid and split views, and a
compact mode. He also asked that the work follow Stackbar's architecture
rather than pile features into the host.

Stackbar's ethos (README, `command-platform`): plugins are one Swift file,
the host supplies surfaces, capabilities and services, and anything a plugin
can do is not special-cased in the host. So each item is either a generic
host surface any plugin can use, or a plugin.

## What changes

Host (Stackbar 0.19.0, protocol 16):

- **File search** (stackbar #93): a Files section from Spotlight's index for
  typed queries of three or more characters. Host-side, like Applications,
  because it reads `NSMetadataQuery`, which plugin sandboxes can't.
- **Root search** (`Command.rootSearch()`, `CommandSpec.rootSearch`): a view
  command whose top three rows show in the palette's own results while the
  user types, as a section under the command's title. The host opens the view
  for each running plugin that asks, feeds it the typed text, and closes it
  when the palette resets. Choosing a row runs its primary action.
- **Fallback commands** (`Command.fallback()`, `CommandSpec.fallback`):
  offered under every typed query in a "Use “…” with" section; the text fills
  the first argument (a run command) or the search (a view).
- **Grids in command views**: a view whose list is a `Grid` of rows is drawn
  as tiles; the arrow keys move in two dimensions. Single-glyph titles (an
  emoji) are drawn large.
- **Split view**: a selected row's `preview` (already in the protocol for
  panels) shows beside the list in the palette.
- **Compact mode** (Settings › Command Palette): only the search field shows
  until the user types, like Spotlight; the window grows downward.

Plugins (stackbar-plugins, `minimumStackbar` 0.19.0):

- Clipboard History and Snippets opt into root search.
- **Web Search**: fallback commands for Google, DuckDuckGo, Wikipedia and
  more, each also a command with an argument.
- **Window Layouts**: halves, quarters, thirds, maximize, center and
  next-display for the front window, using the existing windows API (no new
  host code).
- **Emoji**: a searchable emoji grid that pastes or copies the pick.

## Not changing

- Apps, Settings panes and the calculator stay in the host for now (#92). They
  could become plugins once a plugin can read app icons and Spotlight; that is
  a follow-up for Naveen to decide.
- No keyword expansion (still held from `snippets`).
