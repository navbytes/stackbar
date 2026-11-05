# Launch phase 3: tell the launcher story

## Why

Stackbar now does what a Raycast switcher expects (phases 1 and 2), but the
site still sells a menu-bar host: "Your menu bar, rewritten in Swift." People
looking for a Spotlight replacement or a Raycast alternative don't find
themselves on it, and there are no pages answering "how is this different" or
"how do I move over".

## What changes

- **Home page leads with the launcher.** Headline "Your Mac, one keystroke
  away." and the sub "A native launcher you extend in one Swift file. Free,
  open source, no account." The hero shows the command palette searching
  (apps, a sum, a plugin command), drawn in HTML and CSS, not a video. The
  menu bar, panels and widgets follow as "and it does more".
- **/compare/**: Stackbar next to Raycast, Alfred and Spotlight on price,
  account, extension language, open source, platforms, AI, plugin isolation
  and surfaces. Facts link to each vendor's own pages, and Stackbar's gaps
  are listed honestly.
- **/switch-from-raycast/**: install, take ⌘Space, import snippets and
  quicklinks, and a table of Raycast features with the Stackbar plugin or
  setting for each.
- **/docs/**: a user guide (getting started, the palette, plugins and the
  store, settings, updates and moving Macs, privacy) and the plugin authoring
  reference, rendered from `llms.txt` so it never drifts.
- **Header and footer** link Docs, Compare and Switch; the meta description
  and social card match the new headline.

## Impact

Site only (`site/`). No app, protocol or plugin changes.
