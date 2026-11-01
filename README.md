# Stackbar

Stackbar is a native macOS host for small, live apps that you (or an AI) write in
Swift. A plugin is one `.swift` file. It declares what it shows in a
SwiftUI-like syntax, and Stackbar builds it, runs it in its own process, and draws
it natively in the menu bar, a panel, a window, a desktop widget and the
command palette. Agents can call its tools over MCP. It is the successor to Vee
for developers who want apps rather than scripts; Vee keeps serving script and
xbar plugins.

The vision and architecture are in the design doc
([Stackbar: the successor to Vee](https://claude.ai/artifact/FKTDdAHT9q76TojhZkS2K9)).
All four phases of its roadmap are built. What still needs a real Mac is listed
under "Status".

## A plugin

```swift
import StackbarKit
import Foundation

@main
final class Clock: StackbarPlugin {
    static let manifest = Manifest(
        id: "dev.example.clock",
        name: "Clock",
        surfaces: [.menuBar, .panel],
        triggers: [.launch, .every(.seconds(1))]
    )

    var now = Date()
    @Stored("laps") var laps: [Date] = []      // saved by the host across restarts

    func refresh() async throws { now = Date() }

    var menuBar: ViewContent {
        Label(now.formatted(date: .omitted, time: .standard), symbol: "clock")
    }

    var panel: ViewContent {
        Text(now.formatted(date: .complete, time: .omitted)).style(.headline)
        Button("Lap", symbol: "flag") { self.laps.insert(Date(), at: 0) }
        List(laps, searchable: true) { lap in
            Row(lap.formatted(date: .omitted, time: .standard), key: "\(lap.timeIntervalSince1970)")
        }
    }

    var tools: [AgentTool] {
        AgentTool("laps", description: "How many laps were recorded") { _ in "\(self.laps.count)" }
    }
}
```

State is ordinary properties. `refresh()` runs when a trigger fires, and action
closures run when the user clicks. After each, Stackbar re-renders and sends only
the surfaces that changed. Messages are handled one at a time, so plugin code
never runs concurrently with itself and needs no locks.

`stackbarctl docs` (or [`llms.txt`](llms.txt)) is the full authoring reference:
the view vocabulary, triggers, capabilities, host services and agent tools.
It is written for coding agents, and the authoring MCP server serves it too.

## Bundled plugins

`Plugins/` holds the utilities that ship with the app (install them from the
Stackbar menu or Settings). `Examples/` are small plugins that each teach one idea.

| Plugin | What it does | Needs |
| --- | --- | --- |
| Clipboard History | Everything you copy, searchable, with pins, ⌘1–⌘9 to paste into the app you were in, images, ignored apps (password managers by default) and a pause. ⌘⇧V opens it. | `.clipboard` |
| Stay Awake | Keeps the Mac awake indefinitely, for a while, until a time, while an app runs, or on a weekday schedule. Lets go below a battery level or in Low Power Mode. | `.power` |
| Up Next | The meeting on now or next in the menu bar with a countdown, one-click join for Zoom, Meet, Teams, Webex and more, reminders, auto-join, calendar filters. ⌃⌥J opens it. | `.calendar` |
| Quicklinks | Links and folders you open by name: each is a command (palette, Spotlight, hotkeys, links) whose placeholders ask for input or take the clipboard, the selection or the date. Imports and exports Raycast's quicklinks. No menu-bar item. | `.openURLs(["*"])`, `.clipboard`, `.context` |
| PR Cockpit | Pull requests waiting on your review and your own, with checks, review decision and conflicts; notifies on new requests, approvals and failing checks. | GitHub token |

## What the host provides

- **Surfaces:** menu bar, panel (popover), window, desktop widget (WidgetKit,
  from snapshots), and the command palette (Control-Option-Space) that searches
  every plugin's commands and actions. `docs/surface-parity.md` says what each
  surface does with each view, and a test keeps it in sync with the code.
- **Commands:** a plugin's `commands` are found by name in the palette, with
  up to three inline arguments, or open a live view (a list that follows what
  you type, a detail, a form). Each can have an alias and a global hotkey
  (Settings → Commands) and a `stackbar://commands/<plugin>/<command>` link.
  A plugin can have commands and no menu-bar item at all. Commands also show
  in Spotlight (⌘Space) and in Shortcuts as "Run Stackbar Command", so they
  can be automated, scheduled or given a Quick Key; `.stackbarOnly()` keeps
  one inside Stackbar. Spotlight and Shortcuts need the Xcode build
  (`scripts/install.sh`), which extracts the App Intents metadata.
- **Services:** per-plugin storage (`@Stored`), secrets (Keychain), HTTP to
  declared hosts only, an OAuth broker (authorization code with PKCE, refresh,
  tokens in the Keychain), pub/sub between plugins, notifications, opening URLs
  and the clipboard. Behind their own capabilities: clipboard history and
  paste, keeping the Mac awake with battery and running apps, calendar
  events, running declared command-line tools (`Stackbar.run` and
  `Stackbar.stream`, by the path the user approved, with no shell), and the
  selected text and frontmost app. Outside the app these are simulated, so
  plugins that use them are tested on Linux too.
- **Triggers:** launch, intervals, wake from sleep, watched files, topics,
  clipboard changes. A manifest can also declare a global `hotkey` that opens
  its panel.
- **Capabilities are enforced.** A plugin can only reach the hosts, secrets and
  OAuth providers its manifest declares and the user approved. New or changed
  capabilities need approval before they apply, and the network audit shows
  which declared hosts a plugin actually used.
- **Agents:** `stackbarctl mcp` is an authoring MCP server (scaffold, build,
  render, press buttons, read logs). `stackbarctl agent` is the runtime gateway: it
  exposes every running plugin's tools to an agent through the app.
- **Distribution:** signed `.stackbarplugin` bundles (Ed25519, publisher pinned on
  first use), static plugin indexes, one-click fork into your own plugins
  folder, and an "edit with Claude" script. The store lists the official
  index from [navbytes/stackbar-plugins](https://github.com/navbytes/stackbar-plugins)
  first, verified against the navbytes key, hides versions that need a newer
  Stackbar or that their publisher withdrew, and updates installed plugins daily.

## Running it

On a Mac with Xcode 26 or its Command Line Tools:

```sh
scripts/install.sh                       # signed app + widget into /Applications, stackbarctl, bundled plugins
swift run Stackbar                          # run from source; offers to install the examples
scripts/bundle.sh                        # build/Stackbar.app and a zip for distribution (no widget)
```

`install.sh` needs xcodegen and Xcode signed in to the team in `project.yml`
(59J9RQXYYP). The first run on a new Mac may need
`STACKBAR_ALLOW_PROVISIONING=1` so Xcode can register the App IDs.

Plugins live in `~/Library/Application Support/Stackbar/Plugins/*.swift`. All
plugins build in one shared workspace, so StackbarKit compiles once and each new
plugin builds in seconds. Builds are cached by content.

### stackbarctl

`stackbarctl` builds and drives plugins without the app, on macOS or Linux.

```sh
stackbarctl new MyPlugin.swift --name "My Plugin"
stackbarctl build MyPlugin.swift                     # helper path, or compiler errors mapped to your file
stackbarctl render MyPlugin.swift --surface panel --event button/Lap
stackbarctl soak MyPlugin.swift --minutes 60 --press # fails if memory grows
stackbarctl doctor                                   # toolchain, StackbarKit and data directories
stackbarctl logs -n 200                              # the host log
stackbarctl secret set GITHUB_TOKEN <value>
stackbarctl sign MyPlugin.swift --publisher me       # a .stackbarplugin bundle (macOS)
stackbarctl install https://example.com/index.json   # or a bundle path
```

`render` prints each surface as text with the action id next to every
control, which is what you pass to `--event`. `stackbarctl` with no arguments
lists every command.

## How it fits together

| Module | What it does |
| --- | --- |
| `StackbarProtocol` | The wire contract: `ViewNode`, `Manifest`, capabilities, and the host and plugin messages (newline-delimited JSON, protocol 2). Depends on nothing. |
| `StackbarKit` | What plugins import: the DSL, `StackbarPlugin`, `@Stored`, `AgentTool`, the `Stackbar` service calls, and the runtime loop. A stray `print` goes to stderr and can't corrupt the protocol. |
| `StackbarHostCore` | Everything in the host that has no UI: building, supervising, services, capability enforcement and approvals, MCP servers, palette index, bundles and the index, the host log and the soak runner. |
| `StackbarUI` | SwiftUI renderers for every surface, shared by the app, the widget and PNG snapshots. |
| `Stackbar` | The AppKit/SwiftUI app: status items, panels, windows, palette, settings, approval sheets. |
| `StackbarWidget` | The WidgetKit extension (built through `project.yml`). |
| `stackbarctl` | The CLI above. |

Each plugin runs as its own helper process, launched as a process-group
leader. A crash or leak in one plugin can't take the host down: the supervisor
keeps the last view on screen while it restarts the helper with backoff, and
gives up after repeated crashes. Stopping a plugin also stops anything it
started.

**Limits that keep one plugin from hurting the rest:** 1200 host calls and 300
HTTP requests a minute, 32 calls in flight, 10 notifications a minute, 200 log
lines per 10 seconds, 1 MB of storage, 64 KB per bus message, 16 MB per HTTP
response, and a capped line length on the protocol.

## Tests and CI

```sh
scripts/check.sh                 # what CI runs: build, every test, and a release build of the app on a Mac
swift build && swift test        # quick loop
STACKBAR_BUILD_TESTS=1 swift test   # also compiles real plugins through PluginBuilder
```

Everything except the app, `StackbarUI` and the widget builds and is tested on
Linux. GitHub Actions runs the Linux job in a Swift container. The macOS job runs on GitHub's `macos-26` runner, which is free for public
repositories.

## Status

Built and tested on Linux: the protocol, SDK, host core, services, OAuth,
capability enforcement and approvals, MCP servers, bundles and the index, the
soak runner, the five examples (Clock, Pomodoro, Todo, Weather, CI Status) and
the four bundled plugins against a simulated clipboard, battery and calendar.

Still to check on a Mac:

1. **The app** compiles and runs the examples, including the palette, windows,
   settings and approval sheets.
2. **The widget** shows snapshots after `xcodegen generate`.
3. **Signing:** Ed25519 bundles and the Keychain store (CryptoKit and Security
   only exist on Apple platforms).
4. **The sandbox:** every helper is signed ad hoc with App Sandbox
   entitlements from its manifest (`STACKBAR_SANDBOX=0` turns this off for
   debugging). `.files` paths become file exceptions and `.network` turns on
   outgoing connections; everything else goes through the host.
   `SandboxTests` checks this in the macOS CI job.
5. **The system services:** clipboard reads and paste (with Accessibility),
   power assertions, battery and EventKit (`openspec/changes/fluid-plugins`).
6. **The memory gate:** `stackbarctl soak` PR Cockpit for a day, and watch the
   host in Activity Monitor.

Known gaps are marked `ponytail:` in the code.

## License

MIT. See [LICENSE](LICENSE). Plugins you write against StackbarKit are yours to license however you like.
