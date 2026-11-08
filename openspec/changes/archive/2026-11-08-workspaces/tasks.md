# Tasks

## 1. Protocol and host (navbytes/stackbar)
- [x] 1.1 Wire types, `HostCall.windows` / `arrangeWindows`, `.windows`, `.displays`, protocol 13
- [x] 1.2 `WindowMatcher` with tests
- [x] 1.3 `HostServices` checks and rate limit; `SimulatedSystem` windows; `STACKBAR_WINDOWS`
- [x] 1.4 `MacSystem` windows over Accessibility and Core Graphics; launching apps
- [x] 1.5 Displays trigger from the app, debounced
- [x] 1.6 StackbarKit `Stackbar.windows()` / `arrangeWindows`; authoring guide rows; Stackbar 0.15.0

## 2. Plugin (navbytes/stackbar-plugins)
- [x] 2.1 `Productivity/Workspaces`: save, restore, delete, default per setup
- [x] 2.2 Auto-restore on displays and wake; reopen apps setting
- [x] 2.3 Commands per layout, agent tools
- [x] 2.4 Tests; raise the Stackbar pin (stackbar-plugins #19)

## 3. Check
- [x] 3.1 `swift build && swift test`
- [x] 3.2 On Naveen's Mac: Accessibility prompt, restore across a dock and undock
