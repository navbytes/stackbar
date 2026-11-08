# Design

- `StoreModel` (app, `@Observable`) holds the loaded catalogs, what is
  installing and the toast. `AppModel.store` shares it between the Store
  window and Settings → Store & Updates. Install, update all and uninstall
  moved there from `StoreView`.
- `StoreBrowser` is a `NavigationSplitView` with `StoreSection`
  (`discover`, `category`, `installed`, `updates`) in the sidebar and a
  `NavigationStack` of `StorePage`s in the detail. Changing section or typing
  a search pops to the root. A `stackbar://store/<id>` link sets
  `storeFocus`, and the window pushes that page once the stores are loaded.
- `StoreListing.featured` (Linux-tested) picks the hero.
  `SettingsPresentation.Access(summary:)` maps an index's capability text
  back to its kind, so privacy cards and the info strip have icons.
- The window is an `NSWindow` like Settings, with bridged toolbar and title
  and a remembered frame.
