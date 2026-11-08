# Design

## 1. Capability kinds in the index
- `Capability.Kind: String, CaseIterable` in StackbarProtocol, one case per
  `Capability` case; `Capability.kind` replaces `caseName`.
- `PluginIndex.Entry.capabilityKinds: [String]?`, the kinds in the same order
  as `capabilities`. Optional so published indexes and older apps keep working.
- `SettingsPresentation.Access(_ kind:)` is an exhaustive switch;
  `Access(_ capability:)` calls it.
- `SettingsPresentation.storePermissions(entry)` returns each summary with its
  access. It reads the kind when present and falls back to the summary prefix
  table for indexes built before this change. The prefix table is completed
  and tested over every `Kind` so the fallback is right too.

## 2. CommandStart
Pure function in HostCore:
`CommandStart.plan(entry, preference, source, input) -> Plan` where
`Plan` is `.run(arguments)`, `.ask(prefilled)`, `.openView(query, arguments)`
or `.refuse(message)`. One rule set:
- Disabled or not exposed to this source: refuse.
- View commands open their view; free text fills the first argument when the
  view declares arguments, else the view's search.
- Run commands fill defaults; they run when every required argument is
  filled and either arguments were passed or none are required and the source
  is not interactive-asking (palette Enter with only optional arguments asks).
The exact rule is settled while writing the table tests; the tests are the spec.

## 3. Palette root list
`PaletteRootList.build(...)` in HostCore returns `[PaletteSection]` where
sections carry a `Kind` (results, store, favorites, recent, commands, panel
actions, fallbacks) and rows carry a `Role`. PaletteSession keeps live work.

## 4. Typed replies
`HostCall` reply types declared via a `HostReply<T>` key in StackbarProtocol;
the host encodes with it and `HostClient` decodes with it. `RateLimiter`
gains a `description` used by a shared `limited { }` helper in HostServices.

## 5. Shortcut
`KeyShortcut` value in StackbarProtocol: `init?(parsing:)`, `normalized`,
`glyphs`, `problems`. `HotKeySpec` and StackbarUI's matcher wrap it.
