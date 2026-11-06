# Design

## Matcher (`StackbarProtocol/TextMatch.swift`)

`TextMatch.match(_ query:, in text:) -> Match?`, `Match { tier, quality }`.
Query and text are lowercased with runs of whitespace collapsed. Tiers, best
first:

| Tier | Rule |
| --- | --- |
| exact | text == query, or equal with spaces removed |
| prefix | text starts with query (also with spaces removed) |
| wordStart | a word starts with query (words split on space, `-_/.:()`) |
| initials | the words' first letters start with query (2+ letters) |
| substring | text contains query |
| inOrder | the letters appear in order within the first 500 characters |

`quality` is 0...60: one point less per character of text for the first five tiers; runs
and word starts for `inOrder`.

## Score (`StackbarHostCore/PaletteRanker.swift`)

```
score = tierPoints + quality + learned + frecency + kind
tierPoints: exact 600, prefix 500, wordStart 400, initials 300, substring 200, inOrder 100
learned  = min(150, 80 × picks)          picks = same text + ½ × longer text starting with it
frecency = min(40, 16 × log2(1 + use))   use = PaletteUsage's decayed count
kind     = 5 for commands, Stackbar's places and plugins' root rows
```

- Title matches count fully. Subtitle and keywords count one tier lower at
  half the quality, except a keyword typed whole, which counts as exact (#114: "settings").
- The plugin's name counts at most as `substring` with quality 0 (#116:
  "git" must not list every GitHub row first).
- An exact alias scores 100,000; an alias that starts with the text 580
  (over any prefix, under any exact name).
- Ties keep the source order (#118: stable).
- Learning never adds a row: only rows that match are scored.
- An empty query keeps today's order: most used first.

## Sections (`PaletteSection.group`)

Takes the scored results and scored plugin rows. Pattern-led sections
(`leads`, e.g. calculator `2+2`) come first. Then the single best row of all
(Results' first or a plugin row) leads: when it is a plugin row it gets a
"Top Hit" section of its own and leaves its section. The remaining sections,
Results among them, are ordered by their best row's score; ties keep Results
first, then the given order. Rows inside a section keep the plugin's order.

A plugin row whose title doesn't match the text (a file found by content)
scores only its learning and use, so it can still be a learned Top Hit.

## Ids

`Entry.rankKey`: root-search rows set `pluginID|row|commandID|rowKey`;
everything else uses `id`. Usage and picks are keyed by `learnID`
(`rankKey ?? id`).

## Recording

`PaletteSession.activate` records a pick for (query, learnID) when the query
is not empty, and root rows record use too. Recorded once per activation.

## Controls

- ⌘K on any root row: "Reset Ranking" clears that item's use and picks.
- Settings, General, Palette: "Clear Search History…" clears both files.
