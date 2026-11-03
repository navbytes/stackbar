# Site refresh: plugins shown as the apps they are

## Why

Naveen (2026-11-03): the home hero shows Pomodoro, which few people use, and
each plugin page makes a full app look like a small plugin, while the sites of
the apps these plugins rival (Paste, iStat Menus, Raycast's store, Dato,
Sleeve) show far more. Proposal, with a working hero prototype:
https://claude.ai/artifact/1FHych2FbKZBQjF9u1QJKv. Naveen picked the full plan
with the live menu bar hero.

The biggest cause was the pictures: 12 of the 20 published panel renders were
first-run or sign-in screens ("0 items", "Connect Jira"), because publish
renders run with no data, and the hero showed one at 300 points inside a large
gradient. Some renders also carried AppKit placeholder blocks (links, sliders).

## What changes

1. **Previews** (Stackbar 0.17.0). `static let previews: [Preview<Self>]`:
   named scenes with sample data. `--previews` on a plugin binary lists them;
   `STACKBAR_PREVIEW=<name>` launches into one, after which triggers only
   re-render. `stackbarctl previews` and `stackbarctl render --preview`. The
   app never sets the variable. Snapshots draw links, sliders and toggles
   themselves instead of AppKit's placeholder.
2. **Store renders** (stackbar-plugins). Every plugin gets two to five
   previews; `publish.sh` renders each in light and dark into `site.json`
   (`previews`), and the existing per-surface renders use `hero` when there is
   one, so the in-app store improves too.
3. **Live menu bar hero** (site). The home hero's menu bar cycles through six
   plugins, each dropping its real panel; pause on hover, click to jump,
   still with reduced motion.
4. **Plugin page** (site). Hero at full size with the plugin's real menu bar
   render; Highlights from the README (`## Highlights`, `### Title`, text,
   `<!-- preview: name -->`); every surface; commands and hotkeys; agent tools;
   what it asks for; full version history; FAQ; install; related.
5. **Demo loops**, later: frames from `render --preview --event …` stitched
   into short silent loops for flagship heroes.
