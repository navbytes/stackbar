---
title: The palette
description: Search apps, files, sums and every plugin's commands from one hotkey, and make it yours with aliases, hotkeys and favourites.
group: Use Stackbar
order: 2
---

Press your hotkey. Before you type, it shows Favorites, the apps you open
most (Frequently Used), Recent and Commands.
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
| ⌘⇧F | Add the selection to Favorites, or take it off. Apps and files can be favourites too |
| Tab | With text typed, hands it to Ask AI when that plugin is installed, as Raycast's Quick AI does. Settings › Command Palette › Tab with text picks another fallback, such as Search Google, or none |
| Esc | Close ⌘K, go back a step, then close |

If you close the palette and open it again within a minute, it comes back
where you were. After that it starts fresh.

## Aliases and hotkeys

Settings › Commands lists every command. Give one an alias (type `gh` for
GitHub search, say) or a hotkey of its own that runs it without opening the
palette. You can also press ⌘K on a command and choose **Set Alias and Hotkey…**
An alias is saved as soon as you click away; you don't have to press Return.

You don't need an alias to pass text to a command. Type its name and then
the text, and Return opens it with the text filled in: `search pull requests
react` or `jira ABC-123` (a plugin's name works when it has only one command
that takes text).

## Links and scripts

Every command has a link: ⌘K › **Copy Link**, or the ⋯ menu in Settings ›
Commands. Arguments go in the query string:

```
stackbar://commands/io.navbytes.stackbar.stay-awake/keep-awake?for=2h
```

Open it from a browser, Shortcuts, a Stream Deck or `open` in Terminal. A
command that shows a list opens in the palette. A command that does
something asks once (**Run Once** or **Always Allow**), unless you turned on
**Links May Run It Without Asking** for it in Settings › Commands.

From a script, `stackbarctl call` does the same and prints what happened, so
a cron job or a git hook can wait for the result:

```sh
stackbarctl call stay-awake keep-awake --arg for=2h
stackbarctl call stay-awake allow-sleep
```

The plugin can be its full id or the id's last part. A command a plugin
keeps to Stackbar itself can't be started from outside.

## What it searches

- **Applications** (plugin): apps and System Settings panes.
- **File Search** (plugin): files and folders by name, from Spotlight's index.
- **Calculator** (plugin): sums, units, currency and time zones, such as
  `12 * 12`, `5 km in miles`, `100 usd in eur` or `5pm london in tokyo`.
- **Every installed plugin's commands.** Clipboard History, Snippets,
  Quicklinks, Windows, Emoji, System Commands and the rest add their
  own. Some take arguments, which the palette asks for after you pick them.

When nothing matches, fallback commands at the bottom offer to search the web
with what you typed (Quicklinks adds these).

## Turning parts off

Each plugin can be turned off on its page in Settings. To hide a single
command, press ⌘K on it and choose **Disable Command**.

## Outside the palette

Plugin commands also show in Spotlight's results, and Shortcuts has a **Run
Stackbar Command** action that takes any of them.

## A Hyper key

Many Raycast and Hammerspoon users turn Caps Lock into a Hyper key that
presses ⌃⌥⇧⌘ at once, so every shortcut on it is free. Turn on
**Settings › General › Keyboard › Caps Lock is a Hyper key**, then press
Caps Lock with a key when you record a hotkey in Settings › Commands. Tapped
alone, Caps Lock is Escape (you can switch that off).

It needs Accessibility access. While it's on, Caps Lock no longer locks
capitals; turning it off or quitting Stackbar puts Caps Lock back. Under the
hood Stackbar remaps Caps Lock to F18 with `hidutil`, keeping any other
remaps you made there. In a password field macOS hides keys from every app,
so Hyper shortcuts don't fire there.

Already use [Karabiner-Elements](https://karabiner-elements.pqrs.org) for
this? Leave Stackbar's setting off: hotkeys take all four modifiers, so
Karabiner's Hyper works with every command hotkey and the palette's own.

Hotkeys can use letters, digits, punctuation (`-`, `.`, `/` and the rest of a
US keyboard's), space, F1 to F12, the arrows, Return, Tab, Escape and Delete.
That covers a Rectangle-style window keymap such as ⌃⌥← and ⌃⌥→ for halves.
