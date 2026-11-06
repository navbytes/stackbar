# Changelog

Each release's section is its release notes on GitHub and in the update
window. Write for people who use Stackbar, not for the code.

## Unreleased

### Fixed
- **The desktop widget lists your plugins.** In the downloaded app, choosing a plugin for the Stackbar widget showed an empty list, because macOS kept the widget out of the folder where Stackbar leaves each plugin's widget. Stackbar now uses a shared folder that the signed download is allowed to open. After updating, open Stackbar once so it fills the widget's list, then edit the widget and pick a plugin.

## 0.26.0

### New
- **Notification buttons that do something.** A plugin's notification can carry buttons that run its own commands, so you can snooze a meeting reminder or start your break right from the notification. A command that needs more opens in the palette.
- **Plugins can do more for you,** each only after you allow it: add events to your calendar, open a command in your terminal app, read the text in a copied image or in a part of the screen you drag over (on your Mac, with Apple's text recognition), and show your Mac's temperatures and fan speeds. Store updates to Up Next, Pomodoro, Docker, Clipboard History, Translate and System Monitor use them.
- **Get beta versions.** Settings › Store & Updates has a switch to try new versions before everyone else. Turn it off to go back to the next regular release.
- **VoiceOver reads every button** in plugin panels, the palette and the Store, including the ones that show only an icon.
- **Community plugins in the Store.** Plugins people publish under their own name get a Community section, and their page says who wrote them with a link to their GitHub.
- For plugin authors (protocol 21): `Stackbar.pickColor()` and `Stackbar.define(_:)` (no capability; Color Picker and Dictionary in the Store use them); `NotificationAction(title, command:, arguments:)`; `Stackbar.saveCalendarEvent` and `writableCalendars` (`.calendarWrite`); `Stackbar.openInTerminal`, every word quoted by Stackbar (`.terminal`); `Stackbar.recognizeText` on a kept clipboard image (`.clipboard`) and `Stackbar.captureScreenText` (`.screenText`); `Stackbar.sensors` (`.sensors`).

## 0.25.1

### Fixed
- **Return on the palette's first result works while you type.** If a plugin was still answering your latest letters, Return could act on a result from the earlier answer that the plugin had already dropped, close the palette and do nothing. The palette now waits for the answer and runs the same result, or says it went away.
- In ⌘K, a shortcut such as ⌘⇧C now runs the action shown in the list, not something on the row behind it. ⌘⌫ clears an open command's search field too.
- Better ordering: a plugin's name no longer pushes all its rows above results whose own title matches, a whole match always ranks above a scattered one, ties keep a stable order, and an alias no longer takes over when you type another command's full name.
- **An open command survives its plugin restarting.** The list says it is reconnecting and comes back with what you typed, instead of spinning until you reopen it; a plugin that fails or is turned off says so, and its results leave the root list.
- A command that is slow to open no longer appears after you closed the palette or pressed Esc, and Esc now cancels it.
- Rows that share a title (two "Untitled" notes) can each be reached with the arrows.
- In compact mode, Return and the arrows do nothing until results show, so Return no longer runs a command you can't see.
- A command whose only arguments are pickers opens its form with Return working, and the first text field takes focus.
- Before you type, the root lists every command again, so Stackbar Settings and the Store aren't cut off. "Recent" means used in the last week, and how often you use something can lift it among similar matches but no longer above a better match.
- Two plugins whose root sections share a name are both shown, under their plugin's name; a plugin's root results are timed from when it answers, not from its start, so a slow launch doesn't hide them; Store suggestions match every word you type.

## 0.25.0

### New
- **Keys you know from Raycast in the palette.** ⌃N and ⌃J move down, ⌃P and ⌃K move up, ⌘, opens the selected plugin's settings, and ⌘⌫ clears the search.
- **Move to Applications.** Opened from Downloads or a disk image, Stackbar offers to move itself, so it can update and open at login.
- **Install the command-line tool** from Settings › General: it puts `stackbarctl` in /usr/local/bin.
- **Remove all data** in Settings › General moves Stackbar's plugins, data, caches and logs to the Trash, deletes its secrets and settings, and quits.
- For plugin authors: `Stackbar.focusWindow` brings any open window forward, and the new `.menus` capability reads the front app's menu items (`Stackbar.menuItems()`) and chooses one (`Stackbar.pressMenuItem`) (protocol 20). Switch Windows and Search Menu Items in the Store use them.
- **Merged plugins hand over cleanly.** When a plugin takes another one over (Window Layouts and Workspaces are now one plugin, Windows), your hotkeys, aliases and favourites for its commands move across, the old plugin is turned off, and its Settings page offers to uninstall it. The Store stops listing it. For plugin authors: `replaces:` in the manifest, and `Stackbar.open` takes `stackbar://store/<plugin-id>` and `stackbar://settings` links without asking for the scheme.

### Fixed
- **Typing "settings" in the palette opens Stackbar Settings.** Return used to open whatever file or System Settings pane came first. The palette now has Stackbar Settings, Commands & Hotkeys, Privacy & Secrets and Plugin Store, and typing a command's whole name or keyword puts it first. `stackbar://settings` (or `stackbar://settings/commands`) and `stackbar://store` links open them too.

## 0.24.0

### New
- **Snippets expand as you type.** Give a snippet a keyword like `;sig`, type it in any app, and Stackbar replaces it with the snippet. Stackbar watches only for the keywords you set up, never in password fields, and plugins never see what you type. Settings › Privacy & Secrets has a switch to stop it and a list of apps to skip (password managers are skipped from the start).
- For plugin authors: `Stackbar.setExpansions` and the `.textExpansion` capability (protocol 19).

## 0.23.0

### New
- **Stackbar updates itself.** It checks once a day and asks before it installs a new version. Settings › Store & Updates has Check for Updates… and a switch to stop the daily check. Stackbar's menus have Check for Updates… too.
- **The desktop widget ships in the download.** Releases are now the full build, with the widget and App Intents for Shortcuts.
- **Move to another Mac.** Settings › General exports your plugins, what they saved, aliases, hotkeys and favourites to one file, and imports it on the other Mac. Secrets and plugin permissions never go in the file. Coming from Raycast? The same place imports Raycast's snippet and quicklink exports.
- **Crash reports, if you want them.** Off unless you turn them on in the welcome window or Settings › Privacy. A report has where Stackbar crashed and the versions, never plugin names, logs or files.
- **Report a Problem…** in the Help menu opens a GitHub issue with your Stackbar and macOS versions and a health check filled in. You read it before anything is sent.

### Fixed
- Stackbar no longer crashes on first launch while showing the welcome window (0.22.0).

## 0.22.0

### New
- **Choose the palette's hotkey**, including ⌘Space. If Spotlight still holds ⌘Space, Stackbar says so and opens the setting that frees it.
- **A welcome window** on first launch: pick the hotkey and a few starter plugins, and turn on Open at Login.
- **System Commands** in the Store: lock, sleep, restart, shut down, log out, empty the Trash, toggle dark mode, hide or quit other apps, eject disks.
- **Calculator converts currencies** (daily rates) and time zones.
- Plugins can show a brief HUD (`Stackbar.hud`) and run system actions (`Stackbar.system`).
- Settings › General lists what the palette replaces Spotlight for.

## 0.21.0

### New
- Plugins can draw on more surfaces: more ways to show the same plugin in the menu bar, a panel, a window and the widget.

## 0.20.1

### Fixed
- File Search no longer crashes Stackbar.

## 0.20.0

### New
- Applications, Calculator and File Search are now plugins, installed for you. Clipboard, Quicklinks, Window Layouts and Emoji work in the palette's root search.

Earlier releases are on [GitHub Releases](https://github.com/navbytes/stackbar/releases).
