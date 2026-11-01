# Tasks

## 1. Template engine (StackbarKit)
- [ ] 1.1 Parser: placeholders, options, modifiers, escapes, unknown names kept
- [ ] 1.2 Renderer with injected environment; URL encoding; errors naming the placeholder
- [ ] 1.3 `arguments` to `ArgumentSpec`
- [ ] 1.4 Tests, including samples from Raycast's manual

## 2. Host
- [ ] 2.1 `HostCall.open(OpenRequest)` with app; `Capability.openURLs(schemes:)`; executable and `.app` refusal
- [ ] 2.2 `HostCall.chooseFile`, `saveFile`, `resolveApplication`; simulated versions
- [ ] 2.3 `RowNode.icon = .app(bundleID)`; parity ledger row
- [ ] 2.4 Install sheet wording for `.openURLs(["*"])`

## 3. Plugin (`Plugins/QuicklinksPlugin`)
- [ ] 3.1 Model, storage, commands per link
- [ ] 3.2 Search Quicklinks view with ⌘K actions and tag filter
- [ ] 3.3 Create and edit form with validation
- [ ] 3.4 Import and export (Raycast JSON)
- [ ] 3.5 Settings page: import, export, default browser note
- [ ] 3.6 Bundle it (BundledPlugins), headless by default

## 4. Docs
- [ ] 4.1 README bundled table; authoring guide for `Template` and `Stackbar.open(_:with:)`
- [ ] 4.2 `swift build && swift test`
