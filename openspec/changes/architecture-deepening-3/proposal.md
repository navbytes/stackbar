# Architecture deepening, round three

## Why
On 2026-11-07, after v0.28.0 shipped, Naveen ran Matt Pocock's "improve
codebase architecture" skill over Stackbar a third time. The review
(https://claude.ai/artifact/N45d2NE5ejTkRMrdHCRz7a) found six candidates, and
two of them come with real bugs. Naveen asked for items 1 to 3 to be built in
order, and for items 4 and 5 to be explored and reported back before anything
is built. Item 6 (one link router) was not chosen.

## What changes
1. **PluginInstallation (review #1).** One HostCore module installs, updates,
   withdraws and uninstalls a plugin: the install record, the prebuilt helper,
   approvals, switches, data and sign-ins. The app, the Store window and
   `stackbarctl` use it. Today removing a plugin from the Store window or as a
   withdrawal leaves its approvals behind, and only `stackbarctl` checks that
   a store plugin's built manifest is the signed one.
2. **PaletteMemory (review #2).** One HostCore module over the palette's usage,
   picks and favourites: record a choice, forget a row, clear, hand a plugin's
   memory to the one that replaces it, and a revision the palette's cache keys
   on. Today a plugin handover drops what the ranker learned, and clearing the
   search history doesn't reach an open palette's cache.
3. **RootSearch (review #3).** The live root-search rules (feeding views, the
   race after an open, closing views whose pattern stopped matching, answer
   timing for the budget, running a row from the freshest answer) move out of
   `PaletteSession` into a HostCore module with a small seam to live views.
4. **Explore only (review #4, #5).** One command-view lifecycle shared by the
   app and the headless session, and each host call's rate budget declared
   beside its requirement. A written proposal comes back to Naveen first.

## Impact
No protocol change. Plugins need no change. The performance audit thread works
on the same palette code; its ranking fix lands after item 3.
