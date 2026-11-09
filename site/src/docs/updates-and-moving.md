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
**Import…**, then **Merge** or **Replace**. Stackbar installs the plugins,
restores the rest and restarts. Enter your tokens again and approve each
plugin once.

**Merge** keeps what is already on this Mac: your own aliases, favourites and
plugin data stay, and the file wins only where both have a value. **Replace**
puts the file's copies in their place, as when restoring a backup.

## Two Macs, or a team baseline

The same file works from Terminal, so you can keep it in iCloud Drive or a
dotfiles repository. Quit Stackbar first, then:

```sh
# On the Mac you set up: only aliases, hotkeys and preferences
stackbarctl settings export ~/Library/Mobile\ Documents/com~apple~CloudDocs/stackbar.stackbarsettings \
  --only commands,preferences

# On the other Mac (or a teammate's)
stackbarctl settings import ~/Library/Mobile\ Documents/com~apple~CloudDocs/stackbar.stackbarsettings
```

`--only` takes any of `plugins`, `data`, `commands`, `palette` and
`preferences`. An import merges unless you add `--replace`. Stackbar doesn't
sync on its own: export again when you change something you want on the other
Mac. Install the command-line tool from Settings › General first.

## Coming from Raycast

The same section has **Snippets…** and **Quicklinks…**, which read the JSON
files Raycast exports. The [switching guide](/switch-from-raycast/) walks
through the rest.
