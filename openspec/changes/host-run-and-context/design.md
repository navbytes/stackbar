# Design

## `Stackbar.run`

```swift
let result = try await Stackbar.run("brew", ["outdated", "--json=v2"], timeout: .seconds(120))
// result.status, result.stdout (Data), result.stderr, result.text (stdout as UTF-8), result.truncated

for try await event in Stackbar.stream("docker", ["logs", "-f", id]) {
    switch event { case .stdout(let data): ...; case .stderr(let data): ...; case .exit(let status): ... }
}   // leaving the loop cancels the process
```

### Protocol

```text
HostCall.run(RunRequest)            command, arguments, input?, workingDirectory?, environment, timeout, stream
  → response: value(RunResult as JSON)                    when stream == false
  → HostMessage.runOutput(id, channel, data) … runExit(id, status, truncated)   when stream == true
HostCall.cancelRun(id)
```

### Enforcement (HostServices + CommandRunGate)

- **Declared names.** `.run(commands: ["brew", "docker", "/usr/bin/git"])`.
  A bare name resolves against one fixed search path:
  `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`. The
  user's PATH is not used, because it can be changed by a dotfile or a
  directory the user can write to.
- **The capability ledger stores resolved paths.** The approval sheet shows
  "Runs /opt/homebrew/bin/brew". If the name later resolves to a different
  file (for example, the tool was reinstalled elsewhere), the call fails with
  "brew moved; approve again" and the plugin's approval reopens.
- **Calls are checked against the approved set.** The plugin passes the name
  it declared, and the host runs the approved absolute path.
- **Interpreters and shells** (sh, bash, zsh, fish, env, osascript, python*,
  node, ruby, perl, swift) are allowed, but flagged on the sheet as "can run
  any program". The official store's review checklist asks why one is needed.
- **No shell.** The host spawns with `posix_spawn` through the existing
  `ChildProcess`, with argv exactly as given.
- **Environment:**
  - The host sets `PATH` (the fixed search path), `HOME`, `LANG`, and
    `TMPDIR` (the plugin's own temporary folder).
  - The plugin adds variables explicitly (`environment:`). Nothing else from
    Stackbar's environment leaks through.
- **Working directory.** The plugin's data folder by default. Any other
  folder must be inside a granted `.files` path.
- **Limits:**
  - At most 4 concurrent runs per plugin.
  - 8 MB per output channel, after which output is truncated and `truncated`
    is set.
  - Timeout of 60 seconds by default, 10 minutes at most.
  - On timeout, plugin stop or cancel, the host sends SIGTERM to the process
    group, then SIGKILL after 2 seconds.
- **Audit.** Every run is logged to the host log with the command, exit
  status, duration and byte counts, but not the output. The plugin's Settings
  page lists recent runs, like the network audit lists hosts.

This all lives in StackbarHostCore, so it runs and is tested on Linux.

## Context

```swift
let context = try await Stackbar.context()          // needs .context
context.frontmostApp      // AppInfo(bundleID: "com.apple.dt.Xcode", name: "Xcode")
context.windowTitle       // "Package.swift — stackbar"
context.selectedText      // String? (nil when the app doesn't expose it)
let files = try await Stackbar.finderSelection()     // [String] paths; needs .context
```

In a command, `invocation.context` carries the same data as captured at the
moment of invocation. For example, "translate selection" works from Spotlight
or a hotkey even though Stackbar's palette took focus afterwards.

- **Capture timing.** The host captures when the trigger fires: the global
  hotkey handler, palette open, deeplink receipt, or `RunCommandIntent.perform`
  (Spotlight is an overlay, so the user's app is still frontmost). It captures
  once, before any Stackbar window becomes key.
- **Selected text** comes through Accessibility: `kAXFocusedUIElementAttribute`,
  then `kAXSelectedTextAttribute`. Stackbar already holds Accessibility to
  paste. It is capped at 100 KB.
- **Window title** is `kAXFocusedWindowAttribute`, then `kAXTitleAttribute`.
- **Finder selection** uses Apple Events to Finder. It needs the
  `com.apple.security.automation.apple-events` entitlement and an
  `NSAppleEventsUsageDescription`, and macOS asks the user once.
- **Privacy.** Context goes only to the plugin being invoked, only when it
  holds `.context`, and is never logged. The install sheet says "Reads the
  text you select and which app you're in."
- **Coverage.** The manual checklist records which apps expose selected text
  through Accessibility: Safari, Chrome, Xcode, VS Code, Slack, Notes, Mail,
  Terminal and iTerm. The authoring guide lists the results.

## Simulation

`SystemServices` gains `context()` and `finderSelection()`. The simulated
system reads `STACKBAR_CONTEXT` (JSON) or the `--selected-text` and
`--frontmost-app` flags, so plugins that use context build and render on
Linux.
