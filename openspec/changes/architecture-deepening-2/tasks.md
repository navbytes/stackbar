# Tasks

Order agreed with Naveen 2026-11-06: 2, 1, 3, 4, 5. One PR each.

- [x] 1.1 `Capability.Kind`; `capabilityKinds` in the index; `Access(kind)`; Store page reads it; complete and test the prefix fallback
- [x] 2.1 `CommandStart` planner in HostCore with table tests
- [x] 2.2 Palette, aliases, hotkeys, links, intents, Spotlight, expansion and notification buttons use it
- [x] 3.1 Palette root list and row roles in HostCore with tests
- [x] 3.2 `PaletteSession` uses it; section kinds replace title lookups; ⌘K shortcuts drive the key handling
- [x] 4.1 Reply types declared once (`HostReplies`); host, kit and tests use them; round-trip tests in `HostReplyTests`
- [x] 4.2 Shared rate-limit wrapper with the limit in its message
- [x] 5.1 `KeyCombo` in StackbarProtocol with tests (StackbarUI already has a `KeyShortcut` matcher)
- [x] 5.2 Manifest hotkey (`HotKeySpec`), row action shortcuts (`KeyShortcut`), palette and Settings keycaps use it; `render` flags a row shortcut it can't read (manifest hotkeys were already a manifest problem)
- [x] 6.1 stackbar-plugins raises `stackbarRevision` so the index carries kinds (stackbar-plugins #53)
