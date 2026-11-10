# Search inside a plugin: name, then Tab

## Why
Naveen (2026-11-10), after 0.37.0's commands-only main search: aliases
(`gs stackbar`) search one plugin, but you have to know the alias. Spotlight
on macOS 26 does the same thing by name: type an app's name, press Tab, and
what you type next searches inside that app, under a chip with its name. It
was parked as "option D" in the palette-root-commands analysis; Naveen asked
for it.

## What changes
- **Tab on a plugin's search enters it.** When the selected root row is a
  plugin's root-search command (`.rootSearch()`) or its "Open <Plugin>" row
  and that plugin has one, Tab clears the field and shows the plugin's name
  as a chip. The field asks "Search <Plugin>".
- **Only that plugin answers.** Its rows are the whole list (up to 50, not
  the main search's 3), with no commands, fallbacks or Store suggestions. An
  empty field still asks it, so it can list what it shows before any text.
  It works when the plugin is off for the main search, as an alias does.
- **Leaving:** Esc, or Delete in the empty field, goes back to the main
  search. Esc from a view opened from a scoped row comes back to the scope.
- **Tab elsewhere is unchanged:** from any other row it hands the text to
  Ask AI (or the chosen fallback). The action bar shows "Search <Plugin> ⇥"
  whenever Tab would enter, so the two never surprise.

## Not changing
- Aliases keep working as before.
- No protocol change: plugins already declare everything this needs.
