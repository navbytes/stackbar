## 1. Phase 1: services and surfaces

- [x] 1.1 Protocol 2: host calls, topics, tools, tool calls
- [x] 1.2 Storage, secrets, HTTP, OAuth broker, bus, notifications in `HostServices`
- [x] 1.3 Capability enforcement and `NetworkAudit`
- [x] 1.4 Vocabulary: labeled content, chart, text field, picker, slider, link, empty state
- [x] 1.5 `FluidUI` renderers for menu bar, panel, window, widget; `SurfaceParity` ledger
- [x] 1.6 Authoring MCP server (`fluidctl mcp`) and `llms.txt`

## 2. Phase 2: reach

- [x] 2.1 Command palette index and hot key
- [x] 2.2 Runtime MCP gateway (`fluidctl agent`, Unix socket)
- [x] 2.3 Widget snapshots and the WidgetKit extension
- [x] 2.4 File and topic triggers
- [x] 2.5 Examples: Pomodoro, Todo, Weather, CI Status

## 3. Phase 3: trust and distribution

- [x] 3.1 Capability ledger and approval sheets
- [x] 3.2 Signed bundles, publisher pinning
- [x] 3.3 Plugin index, install, uninstall, fork

## 4. Hardening

- [x] 4.1 Shared build workspace with locking and pruning
- [x] 4.2 Process-group spawning; stopping a plugin stops its children
- [x] 4.3 Host call, HTTP, in-flight and log limits
- [x] 4.4 Rolling host log; `fluidctl logs`, `doctor`, `version`
- [x] 4.5 `fluidctl soak` memory gate
- [x] 4.6 CI: Linux on GitHub, macOS on a self-hosted runner only
- [x] 4.7 On a Mac: the app, `FluidUI` and the CryptoKit and Security code compile; Clock runs in the menu bar (the widget project is not built yet)
- [ ] 4.8 On a Mac: signing, Keychain and sandbox checks (README "Status")
- [ ] 4.9 App writes plugin logs to the host log and shows `doctor` problems in Settings
- [x] 4.10 A day-long soak of PR Cockpit: ran 2026-10-31 on a build before #33 and showed a leak (13 MB to 594 MB over 16 h, then compressed by macOS). #33 fixed the cause (autorelease pools in reader threads); the soak now measures the physical footprint and fails on mid-run climbs. Re-run on current main to confirm.
- [x] 4.11 Audit fixes: secret names can't reach OAuth tokens, per-id storage files, no environment secrets in the app, no http redirect downgrade, OAuth callback state check, reload races, coalesced timer triggers, a single app instance, SHA-256 build keys that cover FluidKit
