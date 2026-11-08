# Tasks

> Archived 2026-11-08. The unticked Mac checks below are tracked in `openspec/mac-checks.md`.

## 1. Protocol and host (navbytes/stackbar)
- [x] 1.1 `confirm` on `ActionRef` and `ViewNode.button`, `ViewNode.confirmations`, protocol 25, decoding tests for old payloads
- [x] 1.2 `ActionConfirmer` with injected clock and tests (arm, send, expire, vanish, text change, one arm per surface)
- [x] 1.3 Hook into `PluginController.send`, `CommandView.perform`, palette rows; HUD and `onChange` redraw
- [x] 1.4 Armed drawing in `NodeView` for rows and buttons; VoiceOver label and announcement; Esc disarms
- [x] 1.5 Widget: confirmable buttons open the panel
- [x] 1.6 `SurfaceParity` entries and regenerated `docs/surface-parity.md`
- [x] 1.7 Soak skips confirmable actions; `render --event` arms, `--confirm` sends the second press
- [x] 1.8 StackbarKit `confirm:` on `Row.action`, `Button`, `ActionButton`, `IconButton`; `Confirm.none`; old-host fallback; duplicate-id warning
- [x] 1.9 `SystemActions.swift` comment, authoring guide + `llms.txt`, release notes

## 2. Plugins (navbytes/stackbar-plugins)
- [x] 2.1 `scripts/check.sh` rule and CONTRIBUTING wording
- [x] 2.2 Migrate the 15 plugins in one PR after the release (pin bump, versions raised)

## 3. Check
- [x] 3.1 `swift build && swift test` in both repos
- [ ] 3.2 On Naveen's Mac: arm and expire in panel, palette and a command view; VoiceOver reads the armed state
