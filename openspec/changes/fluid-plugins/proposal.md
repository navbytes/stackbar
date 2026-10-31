## Why

Naveen asked for the popular menu-bar utilities as Fluid plugins (2026-10-31):
a clipboard history manager, a keep-awake tool, a meeting bar fed by the
calendar, and a GitHub pull-request view of his own PRs and the ones waiting on
his review, plus ideas for what to build next. They should be original
plugins with comparable features, not copies of existing apps.

A plugin can only reach the system through the host, and the host could not
read the clipboard, hold a power assertion or read the calendar. So this
change adds those host services as well as the plugins.

## What Changes

- **Where plugins live:** first-party plugins go in `Plugins/` in this
  repository, next to the teaching `Examples/`. They ship inside Fluid.app and
  install from the menu. See design.md for why not a separate repository yet.
- **Protocol 3, system services**, each behind a capability the user approves:
  - `.clipboard`: `Fluid.clipboard()`, the `.clipboard` trigger,
    `Fluid.setClipboard` (text, files, images the host keeps), `Fluid.paste`.
  - `.power`: `Fluid.keepAwake` / `allowSleep` (released by the host whenever
    the plugin stops or crashes) and `Fluid.systemStatus()` (battery, power,
    Low Power Mode, running apps).
  - `.calendar`: `Fluid.calendarEvents(from:to:)` through EventKit.
- **Manifest `hotkey`:** a system-wide shortcut that opens the plugin's panel.
- **Simulated system** in `fluidctl` and tests, so all of this builds, renders
  and is tested on Linux: `fluidctl render --copy`, `fluid_simulate_copy`,
  `FLUID_CALENDAR`.
- **Plugins:** Clipboard History, Stay Awake, Up Next, and PR Cockpit (moved
  from Examples and extended with your own PRs, checks, review state and
  conflicts).

## Impact

- Plugins built against protocol 2 keep working; the host logs a rebuild
  warning. The app needs calendar usage strings in its Info.plist (added).
- PR Cockpit's id changes from `dev.fluid.example.pr-cockpit` to
  `dev.fluid.pr-cockpit`, so it asks for approval and its token again once.
- Vee is untouched.

## Next plugins

Ideas, by what they need from the host:

- **No new host work:** Snippets (saved text, pasted from the palette, now
  that paste exists), World Clock (time zones and a meeting planner), Uptime
  (watch URLs and status pages), Issue tracker queue (Linear/Jira over OAuth),
  Public IP and VPN status, Currency and market ticker.
- **Small host additions:** System Monitor (CPU, memory, network, disk; a
  `systemMetrics` call), Dev Servers (what's listening on which port, with
  kill; needs the `.run` capability wired up), Docker and Kubernetes context
  switcher (same), Homebrew updates (same), Bluetooth device batteries
  (IOBluetooth).
- **Bigger host additions:** Window layouts (Accessibility window API), screen
  color picker and OCR grab (screen capture), quick notes (a multi-line text
  view in the vocabulary).
