# Codebase health: less duplication, same behaviour

## Why
Naveen asked for a pass over the whole codebase during the freeze: improve
the architecture, remove duplication, and keep to the principles that fit the
code (12 Nov 2026). Three architecture rounds already moved the big concepts
into HostCore (`openspec/changes/archive/2026-11-08-architecture-deepening*`),
so what is left is smaller: the same few lines copied between stores, branches
of one switch that repeat each other, and files that hold several things.

The freeze applies. Nothing here changes what a user or a plugin sees: no new
feature, protocol version or view, the wire format and StackbarKit's public
API stay as they are, and the palette's ranking is untouched.

## What changes
Ranked by value against risk.

1. **One way to keep a JSON file.** Fourteen stores (approvals, folder
   grants, command preferences and registry, the palette's memory, install
   records, publisher pins, hand-overs, agent consent, widget snapshots) each
   read "the file, or start empty" and write "make the folder, encode, write
   atomically" in their own words, with small differences nobody chose (one
   forgot the folder, three spelled the same encoder). `JSONFile` in HostCore
   does both; the files on disk keep their bytes.
2. **`HostServices.handle` says each rule once.** `openURL` and `open`, and
   `notify` and `alert`, are the same checks written twice, and the 4,000
   character cut for notes is written three times. Each becomes one helper.
   `RateLimiter` moves to its own file.
3. **`SystemServices.swift` is three files.** The protocol the app
   implements, the 630-line `SimulatedSystem` that `stackbarctl` and the tests
   use, and the clipboard image store are split; nothing but the file a type
   lives in changes.
4. **`stackbarctl` is a file per group of commands.** `main.swift` is 779
   lines of top-level code. The usage text, the shared set-up, `render`, the
   publishing commands and the rest each get a file; `main.swift` keeps the
   dispatch.
5. **One table of calls waiting on a plugin.** `PluginSupervisor` kept two
   hand-written copies of "calls waiting for an answer, each with a timeout,
   each answered once": one for agent tools, one for run commands. Found
   while landing the items above. `PendingCalls` is that table once, with its
   own tests; the supervisor keeps one per kind of call.

## Left alone, and why
- **The three keyboard listeners** (`MacKeyLayer`, `MacTextExpansion`,
  `MacHyperKey`) copy the same event-tap lifecycle: create, wait for
  Accessibility, remove. One helper would hold it, but it can only be built
  and tried on a Mac with Accessibility granted, and the app check in CI does
  not reach it. It needs a hand check, so it waits for someone at a Mac.
- **`AppCheck` and `Benchmark`** share a `waitUntil` and the open-time
  measurement. Small, app-only, and the app check is the freeze's safety net;
  not worth disturbing now.
- **The large SwiftUI files** (`NodeView`, `Palette`, `SettingsView`). They
  are long but each is one view family; splitting them is churn that can't be
  compiled off a Mac.
- **Plugins.** Each store plugin is one file by design, so helpers repeated
  across plugins (number formatting, `kill`) stay. A source change there also
  means a new version of the plugin for every user, which a tidy-up doesn't
  justify. Their tests are another matter: three test files carried the same
  loopback HTTP server, which is now one (navbytes/stackbar-plugins#80).
- **The read loops** in `PluginProcess`, `CommandRunGate` and `UnixSocket`
  ("read a handle until it closes, a pool per read") look alike, but the pool
  per read is there for memory, and that investigation is someone else's.
- **The memory-leak investigation's code.** Another effort owns it.

## Impact
No protocol change, no plugin change, no user-visible change. Stores write
the same files they did; a test pins the formats.
