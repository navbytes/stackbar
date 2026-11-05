---
title: The palette
description: Search apps, files, sums and every plugin's commands from one hotkey, and make it yours with aliases, hotkeys and favourites.
group: Use Stackbar
order: 2
---

Press your hotkey. Before you type, it shows Favorites, Recent and Commands.
As you type, results come in sections: Applications, Files, Calculator and
others that plugins add, then the matching commands, then plugins from the
Store you haven't installed yet. Press Return to
run the selected result, Esc to go back or close.

## Keys

| Key | What it does |
| --- | --- |
| ↑ ↓ | Move the selection |
| Return | Run the selected result |
| ⌘Return | The second action, when there is one (shown in the bar at the bottom) |
| ⌘K | Every action for the selection, with its own search |
| ⌘1 … ⌘9 | Run the first nine results |
| ⌘⇧F | Add the selection to Favorites, or take it off |
| Esc | Close ⌘K, go back a step, then close |

If you close the palette and open it again within a minute, it comes back
where you were. After that it starts fresh.

## Aliases and hotkeys

Settings › Commands lists every command. Give one an alias (type `gh` for
GitHub search, say) or a hotkey of its own that runs it without opening the
palette. You can also press ⌘K on a command and choose **Set Alias and Hotkey…**

## What it searches

- **Applications** (plugin): apps and System Settings panes.
- **File Search** (plugin): files and folders by name, from Spotlight's index.
- **Calculator** (plugin): sums, units, currency and time zones, such as
  `12 * 12`, `5 km in miles`, `100 usd in eur` or `5pm london in tokyo`.
- **Every installed plugin's commands.** Clipboard History, Snippets,
  Quicklinks, Window Layouts, Emoji, System Commands and the rest add their
  own. Some take arguments, which the palette asks for after you pick them.

When nothing matches, fallback commands at the bottom offer to search the web
with what you typed (Quicklinks adds these).

## Turning parts off

Each plugin can be turned off on its page in Settings. To hide a single
command, press ⌘K on it and choose **Disable Command**.

## Outside the palette

Plugin commands also show in Spotlight's results, and Shortcuts has a **Run
Stackbar Command** action that takes any of them.
