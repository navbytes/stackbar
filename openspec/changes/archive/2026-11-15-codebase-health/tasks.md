# Tasks

Gate: `swift build && swift test`. Items 3 and 4 are both moves with no
rewriting, so they landed together.

- [x] 1 `JSONFile` in HostCore; the stores read and write through it; tests pin the file formats (#195)
- [x] 2 `HostServices.handle`: one open path, one notification check, one notes cut; `RateLimiter` in its own file (#196)
- [x] 3 `SystemServices.swift` split into the protocol, `SimulatedSystem` and `ClipboardImageStore` (#197)
- [x] 4 `stackbarctl`: `main.swift` split into a file per group of commands (#197)
- [x] 5 `PendingCalls`: the supervisor's tool and command calls share one table of waiting calls and timeouts
- [x] 6 stackbar-plugins: the Jira, GitHub and LiteLLM tests share one loopback HTTP stub (navbytes/stackbar-plugins#80, tests only)

- [x] 7 `AppDriver`: `AppCheck` and `Benchmark` share `waitUntil`, `nextFrame` and the palette open timing (the app check job runs both paths on macos-26)

## Waiting for someone at a Mac
Moved to `openspec/mac-checks.md` when this change was archived.

- One event-tap lifecycle for `MacKeyLayer`, `MacTextExpansion` and `MacHyperKey` (needs Accessibility to try)
