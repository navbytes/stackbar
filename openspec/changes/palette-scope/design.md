# Design

## Where Tab enters
`PaletteScope.target(of:commands:preference:)` (HostCore, tested on Linux)
maps the selected row to a root-search command:
- `.command` whose spec is a root-search view the user hasn't disabled;
- `.showPanel` ("Open <Plugin>"): the plugin's first such command.
Any other row: nil, and Tab falls through to `tabToFallback()`.

The conflict with Tab → Ask AI is settled by the row, not the text: typing
"git" with Git Sync's search on top enters Git Sync; the action bar says so
before the press ("Search Git Sync ⇥"). Picking another row with the arrows
gets Ask AI back.

## The scoped root
`PaletteSession.scope` holds the command. `scopedRootSearch()` returns it
with the whole field, so `feedRootSearch()` feeds only that command (empty
text included). `load()` builds `PaletteRoot.scoped(rows)`: one section, the
plugin's rows up to `scopedRowLimit` (50), roles as in the main search so
Return, ⌘K and pinning behave the same. `PaletteRootCache.Key.scope` keeps
the two lists apart.

## Leaving
`back()` at the root with a scope clears it (before closing the palette);
Delete with an empty field does too (`Palette.handle`). `reset()` clears it
when the palette closes. One `TextField` either way, so focus stays put as
the chip comes and goes.

## Not running
Root search never starts a plugin; neither does this. The empty list says
"<Plugin> isn't running" rather than "No matches".
