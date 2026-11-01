# Tasks

## Phase 1: protocol 11
- [x] 1.1 `Style`, `Paint`, `HexColor` (luminance, contrast), `FontSpec`, `ShapeKind`, `TimeRange`, `SystemSound` in StackbarProtocol
- [x] 1.2 `ViewNode`: `styled`, `shape`, `image`, `timer`, `spacer`, `tappable`; `StackAxis.depth`; stack alignment; segmented pickers; ring and timed progress
- [x] 1.3 `Style.folding(_:)` and its tests
- [x] 1.4 Kit: modifiers, `ZStack`, `Spacer`, `Image`, shapes, `TimerText`, `Button { label }`, picker style, ring and timed `ProgressBar`, `Stackbar.play`
- [x] 1.5 Host: `playSound` call with rate limit; render node cap
- [x] 1.6 Panel, menu bar and widget renderers; `TreeTextRenderer`; palette index
- [x] 1.7 `SurfaceParity` and docs/surface-parity.md
- [x] 1.8 `stackbarctl render` lint: contrast, missing accessibility labels
- [x] 1.9 Authoring guide and llms.txt
- [x] 1.10 Protocol version 11 and Stackbar 0.12.0
- [ ] 1.11 Pomodoro plugin in stackbar-plugins (Productivity/Pomodoro)
- [ ] 1.12 Look at the Pomodoro panel on a Mac (stackbarctl render --png)

## Tier 2 spike
- [ ] 2.1 Build an `.appex` in a container app, ad-hoc signed
- [ ] 2.2 Register and discover it through ExtensionKit
- [ ] 2.3 Host its scene in a popover with `EXHostViewController`
- [ ] 2.4 Sandbox, enablement, latency and memory
- [ ] 2.5 Write `spike.md` with the go/no-go
