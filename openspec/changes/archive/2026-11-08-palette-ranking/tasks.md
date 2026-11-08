# Tasks

> Archived 2026-11-08. The unticked Mac checks below are tracked in `openspec/mac-checks.md`.

## 1. Host
- [x] 1.1 `TextMatch.match` with tiers and quality; tests
- [x] 1.2 `PalettePicks`: per-query decayed picks, prefix lookup at half weight, cap, reset, clear; tests
- [x] 1.3 `PaletteRanker` score; `PaletteIndex.search` uses it; alias prefix; tests
- [x] 1.4 `Entry.rankKey` for root-search rows; record use and picks on activate
- [x] 1.5 `PaletteSection.group`: Top Hit, sections by best score; tests
- [x] 1.6 ⌘K Reset Ranking; Settings Clear Search History
- [x] 1.7 Golden ranking cases (#114, #116, #118, launcher basics)
- [x] 1.8 Authoring guide note: the host ranks root rows; llms.txt

## 2. Plugins (stackbar-plugins)
- [x] 2.1 Applications 1.2.0: `TextMatch.match` instead of its own matcher (plugins #49). It keeps its open counts, which choose the three rows the palette shows

## 3. Check
- [ ] 3.1 Mac check: `s` then pick a non-first app twice; it leads for `s`
