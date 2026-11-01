# Architecture deepening

## Why
On 2026-11-01 Naveen asked for the aihero "improve codebase architecture"
method to be run over Stackbar. He cares about having no duplicate or redundant
code and about following best practices. The review
(https://claude.ai/artifact/R2mCfpSKrYDZoLBCVrGfBf) found nine places where a
single concept is spread across several files, or is copied, or sits where the
Linux CI can't test it. Naveen approved all nine and asked for them to be
fixed.

## What changes
1. **One plugin loader.** The steps that turn a source file into a running
   plugin (build, read the manifest, check it, sign it into the sandbox) move
   into one `PluginLoader` in HostCore. The app, `PluginSession` (stackbarctl
   render and the authoring MCP server) and `stackbarctl soak`/`agent` all
   call it. On macOS the CLI now runs plugins sandboxed, as the app does.
2. **View-tree logic in the protocol.** `RowFilter`, the widget's trimming,
   the menu bar's blank check, the palette's list items and the form-error
   check move out of StackbarUI and the app and into StackbarProtocol, where
   they are tested on Linux. `ViewNode.mapChildren` replaces rebuilding each
   container case by hand.
3. **No second copy of the first-party plugins.** `Tests/Fixtures/BundledPlugins`
   is replaced by small fixtures that each exercise one host feature. The
   real plugins are already tested against stackbar main by
   stackbar-plugins' nightly canary.
4. **Host calls described once.** `HostCall.label` and `HostCall.requirement`
   (the capability a call needs and what it does) live in StackbarProtocol.
   HostServices checks the requirement before its switch, and the kit's error
   labels come from the same table.
5. **One affordance walk.** `ViewNode.affordances` lists what a user can press,
   with a title and kind. The palette, the agent text and soak use it instead
   of walking the tree themselves.
6. **No pre-1.0 migration code.** The Fluid-to-Stackbar data move, the
   `FluidKit` handling, and the `Plugins/`-to-store migration are removed;
   no version has been released. Plugin ids and the protocol version history
   stay as they are, because changing them would lose settings and break the
   store's version gating for no benefit.
7. **Store lint from the real manifest.** `stackbarctl manifest --json` prints
   the manifest. The store rules (id prefix, version format) become
   `Manifest.storeProblems`, which `stackbarctl index build` enforces.
   stackbar-plugins' `lint.py` reads that JSON instead of using a regex.
8. **Authenticated JSON helper in the kit.** `Stackbar.getJSON(_:auth:)` with
   `.bearer(secret:)` and `.header(_:secret:)` replaces the
   secret-then-header boilerplate. A missing secret throws
   `StackbarError.missingSecret`, which the panel shows in a standard way.
   Plugins adopt it during the plugin redesign.
9. **One copy of the authoring guide in git.** `llms.txt` is generated from
   `AuthoringGuide.text` by `scripts/generate-docs.sh`. The existing equality
   test now tells you to run that script.
