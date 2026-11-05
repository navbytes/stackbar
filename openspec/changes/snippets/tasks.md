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

## 4. Keyword expansion
- [x] 4.1 Decision (Naveen, 2026-11-01): no system-wide keyboard monitor yet. Reversed 2026-11-05: Naveen asked to build it.
- [x] 4.2 `TextExpansionMatcher` and `TextExpansionRegistry` (HostCore, tested), `.textExpansion`, `Stackbar.setExpansions` and `expansionStatus` (protocol 19, 0.24.0)
- [x] 4.3 `MacTextExpansion`: listen-only tap, backspaces, runs the command; Settings › Privacy & Secrets switch and skipped apps
- [x] 4.4 Snippets registers its keywords (stackbar-plugins)
- [ ] 4.5 Mac check: `;sig` expands in TextEdit, Mail, Slack, VS Code and Terminal; not in 1Password or a password field; a snippet with an argument opens the palette
