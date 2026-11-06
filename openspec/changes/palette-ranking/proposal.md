# One ranker for the command palette

## Why

Naveen asked (2026-11-06) whether the palette needs a dedicated search
ranking, then chose "Build the full ranker" after the research
(doc: https://claude.ai/artifact/9hJkyRrb46ETKN3MB1nDWC).

Raycast, Alfred and LaunchBar all learn which result you pick for what you
type: pick Slack twice after typing `s`, and Slack leads for `s`. Stackbar
only counts how often each item is used, and only for commands and panel
rows; apps, files and clipboard rows (root-search rows) are never recorded.
Ranking also lives in three places with their own scales
(`PaletteIndex.search`, `PaletteSection.rank`, each plugin), which is why
#116 and #118 fixed ranking one case at a time.

## What changes

Host only (StackbarHostCore, the app's palette session). No protocol change.

- **Tiered matcher.** `TextMatch.match` returns a tier (exact, prefix, word
  start, initials, substring, letters in order) and a quality. `score` stays
  for the panel filter and ⌘K. StackbarKit already re-exports it, so plugins
  can use the same matcher.
- **Per-query learning.** `PalettePicks` (palette-picks.json) keeps decayed
  picks per (query, item), 14-day half-life, about 2,000 pairs. A lookup
  counts picks for the same text fully and picks for longer text that starts
  with it at half weight.
- **One score** (`PaletteRanker`) for every row: commands, panel rows,
  Stackbar's places and root-search rows from plugins.
- **Top Hit.** The best row from any source leads; the other sections follow
  ordered by their best row. A matched root pattern still leads.
- **Root-search rows learn.** They get a stable id from their plugin, command
  and row key, and record use and picks.
- **Alias prefix** ranks just under an exact name.
- **Reset Ranking** in ⌘K and **Clear Search History** in Settings.
- **Golden tests** (`PaletteRankerTests`) with the cases from #114, #116 and
  #118 plus launcher basics.

Out of scope: typo tolerance, semantic search, syncing history.
