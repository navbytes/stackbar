---
title: Updates and moving Macs
description: How Stackbar updates itself, and how to take your setup to another Mac or bring it from Raycast.
group: Use Stackbar
order: 4
---

## App updates

Stackbar 0.23.0 and later update themselves. Choose **Check for Updates…**
from the Stackbar menu, or let it check once a day (Settings › Store ›
Stackbar). Each update is notarized by Apple and signed with Stackbar's own
key, which the app checks before installing.

If you installed with Homebrew, `brew upgrade` works too.

## Move to another Mac

Settings › General › Move to Another Mac › **Export…** writes one
`.stackbarsettings` file with:

- the plugins you installed and where they came from,
- each plugin's settings and saved data,
- favourites, aliases and command hotkeys,
- Stackbar's own preferences, such as the palette hotkey.

Secrets and approvals are never in the file. On the new Mac, choose
**Import…**; Stackbar installs the plugins, restores the rest and restarts.
Enter your tokens again and approve each plugin once.

## Coming from Raycast

The same section has **Snippets…** and **Quicklinks…**, which read the JSON
files Raycast exports. The [switching guide](/switch-from-raycast/) walks
through the rest.
