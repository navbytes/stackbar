# Tasks

## 1. App check (workstream A)
- [x] 1.1 `AppCheck.swift`: first minute, golden queries, Return, ⌘K, Settings, Store, light/dark screenshots
- [x] 1.2 Upgrade mode: the latest release's home opened by this build
- [x] 1.3 `scripts/app-check.sh` and the `app` job in `ci.yml`
- [x] 1.4 Green on macos-26; budgets tuned from the first runs (first open 1 s, then median 100 ms and max 250 ms; a search 1.5 s)
- [ ] 1.5 Tick or convert the `mac-checks.md` items the app check now covers

## 2. Golden path (workstream B)
- [x] 2.1 Ranking golden cases in HostCore tests (query to expected top row, learned picks), against the store's real commands (`scripts/palette-corpus.py`); found keywords beating app names, fixed in the ranker
- [ ] 2.2 Leftover palette-review items: usage for root rows, selection kept on back

## 3. Core plugins (workstream C)
- [ ] 3.1 Scenario tests for the core plugins through `stackbarctl render --event`
- [x] 3.2 Fuzz the protocol decoders: a plugin's message never crashes the host (`DecoderFuzzTests`: mutated values, flipped bytes, views nested 100k deep; the decoder refuses deep nesting instead of overflowing)

## 4. Finish or close open plans (workstream D)
- [x] 4.1 Archive the 11 changes whose code shipped; their hand checks join `mac-checks.md`
- [x] 4.2 At most two changes open: trust-first and launch-phase-4

## 5. Calm down (workstream E)
- [x] 5.1 Stable at most weekly, pre-releases between (README "Cadence")
- [x] 5.2 Settings: fewer toggles on the first page (General keeps what a new user looks for first; plugins folder, examples, command-line tool, terminal and command folders move into one "For Plugin Authors" group at the bottom)

## 6. Failures you can read (workstream F)
- [x] 6.1 Already covered, nothing new built: a plugin that fails shows "didn't build or start" with the reason and Rebuild (Settings, panel), the palette shows failure states, and Report a Problem fills in `stackbarctl doctor`
- [x] 6.2 Plugin settings pages (Naveen picked option B, 11-12): an activity line under the header (Applying… until the plugin settles the change, the latest error with Try Again, last update), secrets the plugin asked for under "Needs you" and the rest without alarm, a filter, section links and folding for long settings surfaces (`PluginSettingsOutline`), Permissions folded, the log in Diagnostics. Host only, no protocol change. The sticky "Needs" mark itself is #200.
