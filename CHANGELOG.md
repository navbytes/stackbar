# Changelog

Each release's section is its release notes on GitHub and in the update
window. Write for people who use Stackbar, not for the code.

## 0.25.0

### New
- **Keys you know from Raycast in the palette.** ⌃N and ⌃J move down, ⌃P and ⌃K move up, ⌘, opens the selected plugin's settings, and ⌘⌫ clears the search.
- **Move to Applications.** Opened from Downloads or a disk image, Stackbar offers to move itself, so it can update and open at login.
- **Install the command-line tool** from Settings › General: it puts `stackbarctl` in /usr/local/bin.
- **Remove all data** in Settings › General moves Stackbar's plugins, data, caches and logs to the Trash, deletes its secrets and settings, and quits.
- For plugin authors: `Stackbar.focusWindow` brings any open window forward, and the new `.menus` capability reads the front app's menu items (`Stackbar.menuItems()`) and chooses one (`Stackbar.pressMenuItem`) (protocol 20). Switch Windows and Search Menu Items in the Store use them.

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
