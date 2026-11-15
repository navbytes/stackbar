# Mac checks

Manual checks left over from openspec changes that are archived because
everything else in them shipped. Each one needs a real Mac (usually
Naveen's). Tick a box here when it passes; if a check fails, open an issue
or a new change rather than reopening the archived one.

The full plan for each change is in `openspec/changes/archive/<date>-<name>/`.

**Covered by CI instead (trust-first 1.5, 15 Nov 2026).** Items ticked with
"CI:" are now checked on every app change: the `app` job
(`scripts/app-check.sh`, `AppCheck.swift`) drives the real app on a fresh
macos-26 home and on a home the last release left behind, and uploads light
and dark screenshots of Welcome, the palette, every Settings page and the
Store. "Tests:" means a Linux test covers it. An item that was only partly
covered is reworded to the part a person still has to try.

## The owner's pass before a stable release (about 15 minutes)

Everything below that is still open, in one walk on a real Mac. Do it on the
build that is about to go stable, tick what passes in its section, and
open an issue for what fails.

1. **Update and first launch.** Check for Updates from the previous stable; it installs and relaunches (launch-phase-2 4.2). Plugins, hotkeys and notes are still there (notes-editor 3.4, plugin-handover 3.2).
2. **⌘Space.** Take it over from Spotlight, then give it back (launch-phase-1 3.2).
3. **Palette keys.** An argument field, a command hotkey, a command of a plugin waiting for approval, from the palette and its hotkey, a `stackbar://` link, a hidden menu-bar item (plugin-commands 4.8, first-minute 4.6). "git sync" Tab, "what is swift" Tab (palette-scope). Arrow through PR Cockpit checks with the preview open; Return and ⌘K still act on the row (preview-views).
4. **Apps and files on this Mac.** Simulator, an app in ~/Applications and one on another drive; a file in iCloud Drive and in Dropbox (first-minute 4.1, 4.3).
5. **Keyboard listeners.** `;sig` in TextEdit, Slack and Terminal but not a password field; ⌘⇧V in TextEdit opens Clipboard History at the cursor, ↓↓ Return pastes, a 1Password copy is skipped; ⌃⌥← / ⌃⌥→ snap windows; a Karabiner Hyper key fires a hotkey (snippets, fluid-plugins 4.2/4.6/4.14, first-minute 4.4/4.5).
6. **Menu bar.** Left click on Stay Awake's cup toggles it (`pmset -g assertions`), right click opens the panel; Up Next asks for Calendar once and Join opens a call; a full-screen alert shows over a full-screen app (fluid-plugins).
7. **Settings and Store.** The gear and ⌘, open the right plugin's page; a toggle takes effect at once; a hotkey recorded there works; the glass in both sidebars; install, Update All and uninstall from the Store window (plugin-settings, settings-redesign, store-window).
8. **Destructive actions.** Restart from the palette asks a second time, then expires; VoiceOver reads it (confirm-destructive-actions).

Items that need an account or setup this pass doesn't have (PR Cockpit tokens,
Git Sync remotes, signing and Keychain, the Spotlight spike, each coding
agent) stay in their sections for when that setup is at hand.

## confirm-destructive-actions

Plan: [`archive/2026-11-08-confirm-destructive-actions`](changes/archive/2026-11-08-confirm-destructive-actions/)

- [ ] 3.2 On Naveen's Mac: arm and expire in panel, palette and a command view; VoiceOver reads the armed state

## git-sync

Plan: [`archive/2026-11-08-git-sync`](changes/archive/2026-11-08-git-sync/)

- [ ] 3.3 Check on Naveen's Mac: SSH remote, HTTPS remote, a dirty repo, a diverged repo

## host-run-and-context

Plan: [`archive/2026-11-08-host-run-and-context`](changes/archive/2026-11-08-host-run-and-context/)

- [ ] 3.3 Manual checklist on Naveen's Mac (the checklist is in its design.md)

## launch-phase-1

Plan: [`archive/2026-11-08-launch-phase-1`](changes/archive/2026-11-08-launch-phase-1/)

- [x] 3.2 (part) CI: Welcome on a fresh home; Tests: every system action from the palette (stackbar-plugins `SystemCommandsTests`)
- [ ] 3.2 ⌘Space flow on a Mac with Spotlight's shortcut on and off

## launch-phase-2

Plan: [`archive/2026-11-08-launch-phase-2`](changes/archive/2026-11-08-launch-phase-2/)

- [x] 4.2 (part) CI: a home the latest release left behind opens in this build with its plugins, no Welcome and no approvals asked again (upgrade mode)
- [ ] 4.2 Sparkle's in-place update itself: Check for Updates installs the next release and relaunches

## palette-everywhere

Plan: [`archive/2026-11-08-palette-everywhere`](changes/archive/2026-11-08-palette-everywhere/)

- [ ] 4.2 Mac checklist from design.md (Naveen's Mac) (see its design.md)

## palette-ranking

Plan: [`archive/2026-11-08-palette-ranking`](changes/archive/2026-11-08-palette-ranking/)

- [x] 3.1 Tests: `PaletteRankerTests` (two picks lift a row a tier) and stackbar-plugins `ApplicationsTests` (Spotify picked twice for `s` leads `s`, also after a restart)

## plugin-commands

Plan: [`archive/2026-11-08-plugin-commands`](changes/archive/2026-11-08-plugin-commands/)

- [x] 4.8 (part) CI: typing speed (search budget 1.5 s on the runner), ⌘K, Esc
- [ ] 4.8 Argument fields, hotkeys, a `stackbar://` link, a hidden menu-bar item (details in its design.md)

## plugin-handover

Plan: [`archive/2026-11-08-plugin-handover`](changes/archive/2026-11-08-plugin-handover/)

- [ ] 3.2 On Naveen's Mac: hotkeys carry over, Window Layouts turns off

## plugin-rivals-wave-3

Plan: [`archive/2026-11-08-plugin-rivals-wave-3`](changes/archive/2026-11-08-plugin-rivals-wave-3/)

- [ ] Check on Naveen's Mac

## plugin-settings

Plan: [`archive/2026-11-08-plugin-settings`](changes/archive/2026-11-08-plugin-settings/)

- [ ] 5.1 Gear and ⌘, open the right plugin's page
- [ ] 5.2 Toggles on the page take effect without reopening the panel

## plugin-store

Plan: [`archive/2026-11-08-plugin-store`](changes/archive/2026-11-08-plugin-store/)

- [ ] 9.5 Check the store front, a deep link and Update All on a Mac with 0.15.0

## settings-redesign

Plan: [`archive/2026-11-08-settings-redesign`](changes/archive/2026-11-08-settings-redesign/)

- [x] 4.1 (part) CI: every Settings page in light and dark (screenshots reviewed 15 Nov)
- [ ] 4.1 Sidebar and toolbar get the macOS 26 glass (the window server draws it, so screenshots can't show it)
- [ ] 4.2 A plugin's settings sections draw grouped and still act
- [ ] 4.3 Hotkeys recorded on a plugin's page work

## snippets

Plan: [`archive/2026-11-08-snippets`](changes/archive/2026-11-08-snippets/)

- [ ] 3.2 Tests from design.md (done); Mac checklist (paste and cursor in TextEdit, Xcode, Slack, VS Code and Terminal; Clipboard History skips snippet pastes) waits on Naveen's Mac
- [ ] 4.5 Mac check: `;sig` expands in TextEdit, Mail, Slack, VS Code and Terminal; not in 1Password or a password field; a snippet with an argument opens the palette

## store-window

Plan: [`archive/2026-11-08-store-window`](changes/archive/2026-11-08-store-window/)

- [x] 3.1 (part) CI: the Store in light and dark; hero and thumbnails crop well (screenshots reviewed 15 Nov)
- [ ] 3.1 The sidebar's glass
- [ ] 3.2 Install, update, Update All, uninstall and links work from the window

## first-minute

Plan: [`archive/2026-11-12-first-minute`](changes/archive/2026-11-12-first-minute/)

- [ ] 4.1 Safari, Finder, Simulator, an app in ~/Applications and one on another drive show in Applications; no Helper apps
- [x] 4.2 CI: on a fresh home `saf`, `calendar`, `terminal` and `12*12` come first and File Search answers the same first search, with no approval asked
- [ ] 4.3 A file in iCloud Drive and one in Dropbox show in File Search
- [ ] 4.4 ⌃⌥← and ⌃⌥→ as Windows hotkeys, 30 snaps in a minute
- [ ] 4.6 A plugin waiting for approval: run its command from the palette, Allow, and it runs; the same from its hotkey (not in CI: a fresh home has no waiting plugin whose commands are known yet)
- [ ] 4.5 A Karabiner Hyper key records and fires a command hotkey

## fluid-1-0

Plan: [`archive/2026-11-12-fluid-1-0`](changes/archive/2026-11-12-fluid-1-0/)

- [ ] 4.8 On a Mac: signing, Keychain and sandbox checks (README "Status")

## fluid-plugins

Plan: [`archive/2026-11-12-fluid-plugins`](changes/archive/2026-11-12-fluid-plugins/)

- [ ] 4.2 Clipboard History records copies, skips a 1Password copy, pastes with Accessibility granted
- [ ] 4.3 Stay Awake shows in `pmset -g assertions` and disappears when the plugin is quit
- [ ] 4.4 Up Next asks for calendar access once and shows real events
- [ ] 4.5 PR Cockpit with a real token
- [ ] 4.6 Keyboard: ⌘⇧V, type, ↓↓, Return pastes; ⌘2 pastes the second row; the filter has focus each time the panel opens
- [ ] 4.7 Left click on the cup toggles Stay Awake, right click opens the panel
- [ ] 4.8 An Up Next reminder's Join button opens the call; clicking the notification opens the panel
- [ ] 4.9 Clipboard preview shows long text and images for the selected row
- [ ] 4.10 Charts read well in light and dark mode, in the panel, window and Settings
- [ ] 4.11 Full-screen alert appears over a full-screen app; Join opens the call; Esc dismisses
- [ ] 4.12 PR Cockpit inbox with a classic token; mark as read clears it on github.com
- [ ] 4.13 Stay Awake holds while a display is plugged in, while a VPN is up and during a large download, and lets go after
- [ ] 4.14 ⌘⇧V in TextEdit, Notes and Xcode opens Clipboard History under the cursor; in a browser it falls back to the menu bar

## notes-editor

Plan: [`archive/2026-11-12-notes-editor`](changes/archive/2026-11-12-notes-editor/)

- [ ] 3.1 Hotkey toggles the Notes window above other apps; typing never jumps
- [ ] 3.2 Markdown styling, ⌘B/⌘I, Return continues lists, ⌘Return and clicks tick tasks
- [ ] 3.3 Closing the window mid-sentence keeps the text
- [ ] 3.4 Notes survive a restart and an app update

## palette-scope

Plan: [`archive/2026-11-12-palette-scope`](changes/archive/2026-11-12-palette-scope/)

- [ ] 2.1 Type "git sync", Tab: chip shows, repos list; type to filter; Esc back
- [ ] 2.2 Type "what is swift", Tab: still asks AI

## plugin-editor-choice

Plan: [`archive/2026-11-12-plugin-editor-choice`](changes/archive/2026-11-12-plugin-editor-choice/)

- [ ] 4.1 Mac check: each installed agent opens in the plugin folder and reads AGENTS.md

## preview-views

Plan: [`archive/2026-11-12-preview-views`](changes/archive/2026-11-12-preview-views/)

- [ ] 3.1 Arrowing through PR Cockpit checks redraws the pane with no lag
- [ ] 3.2 Nothing in the pane takes focus; Return and ⌘K still act on the row
- [ ] 3.3 Light and dark look right; long views scroll

## spotlight-commands

Plan: [`archive/2026-11-12-spotlight-commands`](changes/archive/2026-11-12-spotlight-commands/)

- [ ] 1.1 A throwaway `RunCommandIntent` over a two-item `EntityStringQuery`: shows in Spotlight ⌘3, entity search as you type
- [ ] 1.2 Quick Key saved for the intent with one entity chosen
- [ ] 1.3 `IndexedEntity` donated to a named index shows in ⌘Space results; opening it runs the `OpenIntent`
- [ ] 1.4 Running with the app quit; `opensIntent` from a background intent
- [ ] 1.5 Record results in design.md and adjust the plan
- [ ] 4.3 Manual checklist from design.md on Naveen's Mac

## usage-charts

Plan: [`archive/2026-11-12-usage-charts`](changes/archive/2026-11-12-usage-charts/)

- [ ] 1.7 Look at the panel on a Mac (stackbarctl render --png)

## codebase-health

Plan: [`archive/2026-11-15-codebase-health`](changes/archive/2026-11-15-codebase-health/)

- [ ] One event-tap lifecycle for `MacKeyLayer`, `MacTextExpansion` and `MacHyperKey`: a refactor that needs a Mac with Accessibility granted to try (hotkeys, text expansion and the Hyper key still fire after it)
