## 1. Host services

- [x] 1.1 Protocol 3: clipboard, paste, keep-awake, system status and calendar calls; `.clipboard` trigger; `.clipboard`, `.power`, `.calendar` capabilities
- [x] 1.2 `SystemServices` with capability checks in `HostServices`; released on stop and crash
- [x] 1.3 `SimulatedSystem` for fluidctl and tests; `--copy`, `fluid_simulate_copy`, `FLUID_CALENDAR`
- [x] 1.4 `MacSystem`: NSPasteboard, CGEvent paste, IOPMAssertion, IOPowerSources, EventKit
- [x] 1.5 Manifest `hotkey`, parsed by `HotKeySpec`, registered by the status item
- [x] 1.6 Authoring guide and llms.txt

## 2. Plugins

- [x] 2.1 Clipboard History
- [x] 2.2 Stay Awake
- [x] 2.3 Up Next
- [x] 2.4 PR Cockpit: your PRs, checks, review state, conflicts, notifications
- [x] 2.5 Bundled in Fluid.app and installed from the menu

## 3. Gap review against the leading apps (review.md)

- [x] 3.1 Keyboard-driven searchable lists in the host: focus on open, ↑↓, Return, ⌘1–⌘9, action shortcuts
- [x] 3.2 Clipboard History: formatting kept (`contentID`, `.stored`), paste as plain text, ignore patterns, clear all, own pastes not counted
- [x] 3.3 Stay Awake: while plugged in, typed durations, 5-minute warning
- [x] 3.4 Up Next: Zoom and Teams open in their apps (`zoommtg`, `msteams` allowed), instant meetings, hide finished and solo events, menu-bar look-ahead, events across midnight, next meeting first
- [x] 3.5 PR Cockpit: new-activity markers, snooze until changed, hide repositories, comment counts, ready to merge
- [x] 3.6 App signed with the calendar entitlement (hardened runtime)

## 3b. Second gap pass (protocol 5)

- [x] 3b.1 Menu-bar click action (`menuBarClick`, `MenuBarAction`); right click opens the panel. Stay Awake: click the cup to start or stop, with a setting
- [x] 3b.2 Notification buttons that open URLs (`NotificationAction`, at most three, same schemes as `openURL`); clicking a notification opens the plugin's panel. Up Next: Join; PR Cockpit: Review, Open, See checks
- [x] 3b.3 Row previews (`RowPreview`): full text or a kept clipboard image under a searchable list for the selected row; images only for plugins with `.clipboard`. Clipboard History previews long text, images and files
- [x] 3b.4 Fuzzy, ranked list filtering (`TextMatch`, shared with the palette); sections filtered inside; search covers preview text

## 3c. Charts and visual polish

- [x] 3c.1 Chart vocabulary: `.area` and `.donut`, `ChartOptions` (labels, unit, goal, highlight); axis labels, value summary, legend for donuts
- [x] 3c.2 Sections without rows drawn as cards
- [x] 3c.3 Stay Awake: hours awake this week (bar, today highlighted), average, battery while awake (area), 14-day activity in settings
- [x] 3c.4 Clipboard History window: copies per day, top source apps and kinds of copies (donuts)
- [x] 3c.5 Up Next: time left in the current meeting, meetings-today gauge; window: hours in meetings for 7 days with a 4h goal line, today by calendar
- [x] 3c.6 PR Cockpit window: your PRs by state, review wait times, reviews by repository, queue over time

## 3d. Third gap pass (protocol 6)

- [x] 3d.1 Full-screen alerts (`HostCall.alert`, `Stackbar.alert`): a blurred cover above full-screen apps with the plugin's buttons, Esc dismisses, one a minute
- [x] 3d.2 `tel:` allowed for `openURL` and buttons
- [x] 3d.3 Up Next: dial-in numbers (tel: links, +numbers with Zoom's ",,PIN#"), Call in and Copy; "Cover the screen when a meeting starts" setting
- [x] 3d.4 PR Cockpit: merged and closed alerts for your PRs, a "Closed in the last two days" section, and an optional GitHub notifications inbox tab (classic token with the notifications scope), with mention alerts and mark as read

## 3e. Fourth gap pass

- [x] 3e.1 `SystemStatus` gains `externalDisplays`, `networkBytesReceived` and `vpnActive` (optional, so older plugins decode)
- [x] 3e.2 Stay Awake: stay awake while an external display or a VPN is connected, or while a download runs (over 100 KB/s, until quiet for 2 minutes), with a download speed chart
- [x] 3e.3 A pasting plugin's hotkey (one with the clipboard capability) opens its panel at the text cursor, through Accessibility; the menu bar when the app doesn't report a caret

## 3f. Windows that don't get lost

- [x] 3f.1 Stackbar shows in the Dock and ⌘Tab while a plugin window or Settings is open, back to menu-bar only when the last closes; a General setting turns it off. A main menu (Edit, Window) comes with it
- [x] 3f.2 Clicking a plugin's icon brings its buried or minimized window to the front; with the window in front, or a right click, opens the panel
- [x] 3f.3 The panel's window button reads "Show Window" while the window is open
- [ ] 3f.4 A per-window "Keep on top" pin, remembered per plugin

## 4. On a Mac

- [ ] 4.1 The app compiles with `MacSystem` (self-hosted runner)
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
- [ ] 4.15 Open PR Cockpit's window, switch apps: ⌘Tab and the Dock find it; closing it removes the Dock icon; the icon click brings it back
- [ ] 4.14 ⌘⇧V in TextEdit, Notes and Xcode opens Clipboard History under the cursor; in a browser it falls back to the menu bar
