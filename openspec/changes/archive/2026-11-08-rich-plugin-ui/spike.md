# Tier 2 spike: native plugin views with ExtensionKit

Run on Naveen's Mac on 2026-11-01 (macOS 27.2, Xcode 27.2, Swift 6.4.2,
arm64). The code lives in `~/stackbar-spike` on that Mac, not in this repo.

## Verdict: go, with one product caveat

ExtensionKit shows a plugin's own SwiftUI view out of process inside an
`NSPopover` from a status item. Both sides were ad-hoc signed and sandboxed,
the plugin was installed outside /Applications, and no Xcode project was
needed for the extension. The view is interactive, keeps its own state, and
is crash-isolated.

**Caveat:** an extension shipped in a separate app is off by default. The
user switches it on once in `EXAppExtensionBrowserViewController`, and
there is no programmatic pre-approval (`pluginkit -e use` has no effect).
Extensions inside the host's own bundle are on automatically, but adding
plugins to Stackbar.app would break its signature.

| Question | Answer |
| --- | --- |
| `.appex` in a container app, ad-hoc signed, sandboxed | Yes |
| Registered from Application Support and discovered | Yes, with `lsregister -f -R -trusted` |
| Discovered without a user step | No: one switch per plugin in the extensions browser |
| Renders once switched on | Yes (2026-11-01): a running host sees it within seconds, no restart; 149–164 ms to connect cold, 194–208 ms to first frame, 12 MB, within about 20 ms of the in-bundle one |
| Shown in a popover with `EXHostViewController` | Yes, interactive |
| Host survives `kill -9` of the extension | Yes; placeholder until the configuration is set again (143 ms) |
| Time to first frame, cold | About 135 ms to activate, 180 ms to first `onAppear` |
| Memory per extension | 11–12 MB footprint |

## What it means for the design
- The install flow gets an **Enable** step for native plugins. Stackbar
  shows the extensions browser right after install and on the plugin's
  settings page while it is off. Plugins without a native view don't
  change.
- `stackbarctl build` builds the native view as
  `<Plugin>.app/Contents/Extensions/<Plugin>.appex`. It links with
  `-application-extension -Xlinker -e -Xlinker _NSExtensionMain`, because a
  plain `@main` traps at launch. It signs the extension first, then the
  container, and registers the container with `lsregister -f -R -trusted`.
  Extension and container versions must match.
- The host declares the extension point with a classic
  `.appextensionpoint` plist in `Contents/Extensions`, which needs no Xcode
  metadata step.
- The host chooses the extension by its identity, never the first one
  discovered, because the in-bundle and plugin extensions share the
  extension point.
- The host must pin the placeholder's size, and after a crash set the
  configuration again on the next show.
- The extension process stays alive while the popover is closed, so
  reopening is instant and keeps the view's state.

## Still open
- A Developer ID host loading an ad-hoc signed extension, and notarized
  builds.
- The data channel between host and extension
  (`makeXPCConnection`/`onConnection`), several scenes at once, Spaces and
  full screen.
