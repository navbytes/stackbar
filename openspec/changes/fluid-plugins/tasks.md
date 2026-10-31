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

## 4. On a Mac

- [ ] 4.1 The app compiles with `MacSystem` (self-hosted runner)
- [ ] 4.2 Clipboard History records copies, skips a 1Password copy, pastes with Accessibility granted
- [ ] 4.3 Stay Awake shows in `pmset -g assertions` and disappears when the plugin is quit
- [ ] 4.4 Up Next asks for calendar access once and shows real events
- [ ] 4.5 PR Cockpit with a real token
- [ ] 4.6 Keyboard: ⌘⇧V, type, ↓↓, Return pastes; ⌘2 pastes the second row; the filter has focus each time the panel opens
