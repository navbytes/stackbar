---
title: The palette
description: Search apps, files, sums and every plugin's commands from one hotkey, search inside one plugin with Tab, and make it yours with aliases, hotkeys and favourites.
group: Use Stackbar
order: 2
---

Press your hotkey. Before you type, it shows Favorites, the apps you open
most (Frequently Used), Recent and Commands.
As you type, results come in sections: Applications, Files, Calculator and
others that plugins add, then the matching commands. Store plugins you haven't
installed show only when nothing you have matches. Press Return to run the
selected result, Esc to go back or close.

Like Raycast, the main search lists commands, apps, files and sums, not the
buttons and rows on your plugins' panels. Those stay on the panel, and every
plugin with one has an **Open <Plugin>** row to get there.

## Keys

| Key | What it does |
| --- | --- |
| ↑ ↓ | Move the selection |
| Return | Run the selected result |
| ⌘Return | The second action, when there is one (shown in the bar at the bottom) |
| ⌘K | Every action for the selection, with its own search |
| ⌘1 … ⌘9 | Run the first nine results |
| ⌘⇧F | Add the selection to Favorites, or take it off. Apps and files can be favourites too |
| Tab | On a plugin's row (the bar shows "Search <Plugin> ⇥"), searches inside that plugin. Otherwise, with text typed, hands it to Ask AI when that plugin is installed, as Raycast's Quick AI does. Settings › Command Palette › Tab with text picks another fallback, such as Search Google, or none |
| Esc | Close ⌘K, leave a plugin's search, go back a step, then close |

If you close the palette and open it again within a minute, it comes back
where you were. After that it starts fresh.

## Search inside one plugin

Type a plugin's name and press Tab, as in Spotlight. Its name becomes a chip
in the field, and what you type next searches only that plugin, with all its
results rather than the top few. Esc, or Delete in the empty field, takes you
back to the main search.

An alias does the same in one go: type the alias, a space and the text (`gs
stackbar` for Git Sync), and only that plugin answers, even when it is off
for the main search.

## Previews

When a result has more to show, a preview pane opens beside the list as you
move through it: a copied image or text in Clipboard History, a note in Notes,
a check list, the steps of a release, a color swatch. It is only to look at;
Return and ⌘K still act on the row.

## Aliases and hotkeys

Settings › Commands lists every command. Give one an alias (type `gh` for
GitHub search, say; a symbol such as `#` works too) or a hotkey of its own that runs it without opening the
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
- **Plugins you let answer as you type.** Settings › General › Main Search
  lists every plugin that can add its own results, with a switch each.
  Applications, Calculator and File Search are on, as are plugins that only
  answer text of their own shape (`ABC-123` for Jira, `#123` for a pull
  request). Others, like Git Sync and Recent Projects, start off.

When fewer than three results match, fallback commands at the bottom offer to
use what you typed elsewhere: Search Google and Ask AI to start. Settings ›
General › Fallbacks picks which ones show and in what order.

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
