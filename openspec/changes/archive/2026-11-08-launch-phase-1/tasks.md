# Tasks

> Archived 2026-11-08. The unticked Mac checks below are tracked in `openspec/mac-checks.md`.

## 1. Host (stackbar)
- [x] 1.1 `PaletteHotKey`: stored spec, default ⌃⌥Space, re-register on change
- [x] 1.2 `SpotlightShortcut`: read whether Spotlight's ⌘Space is on; helper to open its settings
- [x] 1.3 Recorder in Settings › General
- [x] 1.4 Welcome window on first launch (hotkey, starter plugins, launch at login, open palette)
- [x] 1.5 `HostCall.hud`, `Stackbar.hud(_:)`, rate limit, protocol 18
- [x] 1.6 `SystemAction`, `.systemActions` capability, `HostCall.system`, `Stackbar.system(_:)`, Mac implementation
- [x] 1.7 "Stackbar replaces" section instead of "Use macOS for These"
- [x] 1.8 Authoring guide, llms.txt, Stackbar 0.22.0
- [x] 1.9 Tests: hotkey spec storage, Spotlight shortcut parsing, hud limit, system action capability and description
- [x] 1.10 CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, issue and PR templates, README rewrite

## 2. Plugins (stackbar-plugins)
- [x] 2.1 System Commands plugin
- [x] 2.2 Calculator: currency and time zones
- [x] 2.3 Pin to the merged stackbar commit (fdb5042); System Commands `minimumStackbar` 0.22.0 (stackbar-plugins #36)

## 3. Release
- [x] 3.1 Release 0.22.0 (Naveen says "release") (v0.22.0 released)
- [ ] 3.2 Mac check: ⌘Space flow on a Mac with Spotlight's shortcut on and off, welcome on a fresh user, each system action
