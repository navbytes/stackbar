# Tasks

## 1. App check (workstream A)
- [x] 1.1 `AppCheck.swift`: first minute, golden queries, Return, ⌘K, Settings, Store, light/dark screenshots
- [x] 1.2 Upgrade mode: the latest release's home opened by this build
- [x] 1.3 `scripts/app-check.sh` and the `app` job in `ci.yml`
- [ ] 1.4 Green on macos-26; budgets tuned from the first runs
- [ ] 1.5 Tick or convert the `mac-checks.md` items the app check now covers

## 2. Golden path (workstream B)
- [ ] 2.1 Ranking golden cases in HostCore tests (query to expected top row, learned picks)
- [ ] 2.2 Leftover palette-review items: usage for root rows, selection kept on back

## 3. Core plugins (workstream C)
- [ ] 3.1 Scenario tests for the core plugins through `stackbarctl render --event`
- [ ] 3.2 Fuzz the protocol decoders: a plugin's message never crashes the host
