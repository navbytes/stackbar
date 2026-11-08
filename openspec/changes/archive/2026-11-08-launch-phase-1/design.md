# Design

## Palette hotkey

- Stored in `UserDefaults` under `paletteHotKey` as a hotkey spec, the same
  syntax manifests and Settings › Commands use. Anything `HotKeySpec` can't
  parse falls back to `ctrl+option+space` (`PaletteHotKey.spec(stored:)`).
- Spotlight's "Show Spotlight search" is symbolic hot key 64 in
  `com.apple.symbolichotkeys`. Stackbar only reads it
  (`SpotlightShortcut.holdsCommandSpace`); writing those preferences needs a
  log-out or a private call to take effect, so the user turns it off in
  Keyboard › Keyboard Shortcuts › Spotlight, which the picker opens.
- While Spotlight still holds ⌘Space and the user chose it, the palette
  registers ⌃⌥Space as well (`PaletteHotKey.registered`), so it is never
  unreachable. The check runs again each time Stackbar becomes active, which
  is when someone comes back from System Settings.

## Welcome

Shown once (`welcomeSeen`). It offers the carried bundles except the core
ones (which every Mac gets), with Clipboard History, Quicklinks, Snippets
and System Commands on. Skip installs nothing and leaves login alone.
Permissions are not asked up front: each plugin asks when it first needs
something, as it does today.

## HUD

`HostCall.hud(String, isError:)` reaches the HUD a command result already
uses (`HUD.shared`). It needs no capability, like a notification, and is
limited to 30 a minute per plugin. Text is trimmed and cut at 200
characters.

## System actions

One call, `HostCall.system(SystemAction)`, behind `.systemActions`, limited to
10 a minute. Public APIs only:

| Action | How |
| --- | --- |
| Lock Screen | posts ⌃⌘Q (needs Accessibility, as paste does) |
| Sleep, Sleep Displays | `pmset sleepnow`, `pmset displaysleepnow` |
| Screen Saver | opens ScreenSaverEngine.app |
| Restart, Shut Down, Log Out | System Events through `osascript` (macOS asks once) |
| Empty Trash | Finder through `osascript` |
| Toggle Dark Mode | System Events appearance preferences |
| Hide / Quit Other Apps | `NSRunningApplication`, keeping Finder, Stackbar and the app the user was in |
| Eject All Disks | ejectable or removable volumes, `unmountAndEjectDevice` |

The host does not ask before destructive actions; the plugin does
(`SystemAction.isDestructive`), so the question reads like the rest of the
plugin's UI and a hotkey the user set up on purpose doesn't nag.

## "In the Palette"

`SpotlightReplacements` lists what to type for each thing people used
Spotlight or Raycast for, and the plugin that does it, with Install when it
is missing. Text Replacements stay in the footer: keyword expansion is still
held (`snippets` 4.2).
