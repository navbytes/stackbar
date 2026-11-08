# Tasks

## 1. Template engine (StackbarKit)
- [x] 1.1 Parser: placeholders, options, modifiers, escapes, unknown names kept
- [x] 1.2 Renderer with injected environment; URL encoding; errors naming the placeholder
- [x] 1.3 `arguments` to `ArgumentSpec`
- [x] 1.4 Tests, including samples from Raycast's manual

## 2. Host
- [x] 2.1 `HostCall.open(OpenRequest)` with app; `Capability.openURLs(schemes:)`; executable and `.app` refusal
- [x] 2.2 `HostCall.chooseFile`, `saveFile`, `resolveApplication`; simulated versions
- [x] 2.3 `RowNode.icon = .app(bundleID)`; parity ledger row
- [x] 2.4 Install sheet wording for `.openURLs(["*"])`

## 3. Plugin (`Plugins/QuicklinksPlugin`)
- [x] 3.1 Model, storage, commands per link
- [x] 3.2 Search Quicklinks view with ⌘K actions and tag filter (no one-off "Open With…": the app is set per quicklink, in Edit)
- [x] 3.3 Create and edit form with validation
- [x] 3.4 Import and export (Raycast JSON)
- [x] 3.5 Settings page: import, export, default browser note
- [x] 3.6 Bundle it (BundledPlugins), headless by default

## 4. Docs
- [x] 4.1 README bundled table; authoring guide for `Template` and `Stackbar.open(_:with:)`
- [x] 4.2 `swift build && swift test`
