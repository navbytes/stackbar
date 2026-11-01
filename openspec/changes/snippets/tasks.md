# Tasks

## 1. Host
- [x] 1.1 `PasteOptions` (restore, cursor from end); transient marking; restore guarded by change count
- [x] 1.2 `Capability.storage(megabytes:)`; quota from the grant; install sheet wording

## 2. Plugin (`Plugins/SnippetsPlugin`)
- [x] 2.1 Model, storage, one command per snippet with template arguments
- [x] 2.2 Search Snippets view with live preview and ⌘K actions
- [x] 2.3 Create and edit form with validation; `{snippet}` nesting rules
- [x] 2.4 Import and export (Raycast JSON, `{date: …}` shorthand)
- [x] 2.5 Bundle it, headless, default hotkey

## 3. Docs and tests
- [x] 3.1 README bundled table; placeholder reference page shared with Quicklinks
  (the authoring guide's Templates section; both plugins' forms list the placeholders)
- [ ] 3.2 Tests from design.md (done); Mac checklist (paste and cursor in TextEdit, Xcode, Slack, VS Code and Terminal; Clipboard History skips snippet pastes) waits on Naveen's Mac

## 4. Keyword expansion (not now)
- [x] 4.1 Decision (Naveen, 2026-11-01): no system-wide keyboard monitor yet; it would worry many users. Snippets ships with pick-and-paste only.
- [ ] 4.2 (deferred) `ExpansionMonitor`, `.textExpansion`, `Stackbar.setExpansions`, Settings switch and excluded apps
