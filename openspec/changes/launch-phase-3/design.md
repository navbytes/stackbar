# Design

## Hero palette

`PaletteScene.astro`: a Liquid Glass–style panel with a search field and
grouped results. A small script types three queries in turn ("term", "12*12",
"pomo") and swaps the result list for each; with `prefers-reduced-motion` it
shows the first state only. The results are plain markup, so the hero is
readable without JavaScript and costs no video download.

## Compare

One data table in `src/lib/compare.ts`, rendered as a table on wide screens
and as cards on phones. Each competitor row cites its source (vendor pricing
or manual pages, checked 2026-11-05). Wording stays factual: no claims about
speed we have not measured; Stackbar's own numbers come from the Benchmark
workflow.

## Docs

A `docs` content collection with its own loader (`scripts/docs.mjs`): the
user guide in `src/docs/*.md` (front matter: title, description, group,
order) and the plugin reference read straight from the repository's
`llms.txt`, so it never drifts from what agents read. Root-relative links in
the Markdown get the site base. `/docs/` lists the pages; `/docs/<slug>/`
renders one with a side navigation and an on-page table of contents.

## Social card

`public/og.png` is redrawn with the new headline (same layout and fonts).
