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

## 3. On a Mac

- [ ] 3.1 The app compiles with `MacSystem` (self-hosted runner)
- [ ] 3.2 Clipboard History records copies, skips a 1Password copy, pastes with Accessibility granted
- [ ] 3.3 Stay Awake shows in `pmset -g assertions` and disappears when the plugin is quit
- [ ] 3.4 Up Next asks for calendar access once and shows real events
- [ ] 3.5 PR Cockpit with a real token
