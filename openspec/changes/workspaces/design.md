# Design

## Wire types (`StackbarProtocol/Windows.swift`)

- `WindowRect`: x, y, width, height in global screen points with the origin
  at the top-left of the main display (the Accessibility and Core Graphics
  space, not AppKit's flipped one).
- `DisplayInfo`: `id` (the display's UUID, stable across reboots and ports),
  `name`, `frame`, `visibleFrame` (without menu bar and Dock), `isMain`,
  `isBuiltIn`.
- `WindowInfo`: `appID`, `appName`, `title`, `frame`, `displayID`, `order`
  (0 is frontmost), `isMinimized`.
- `WindowSnapshot`: displays and windows, plus `setupID`: the sorted display
  ids joined, which names a monitor setup.
- `WindowPlacement`: `appID`, `title`, `ordinal` (this window's place among
  the app's saved windows, front first), `frame`, `isMinimized`.
- `ArrangeResult`: `moved`, `opened`, `missing` (placements with no window),
  `failed` (windows that refused to move, by app name).

## Calls

- `HostCall.windows` answers `WindowSnapshot` as JSON.
- `HostCall.arrangeWindows([WindowPlacement], launch: Bool)` answers
  `ArrangeResult` as JSON. At most 200 placements; 10 calls a minute.
- Both need `.windows`. No sandbox entitlement: the host does the work.

## Matching (`StackbarHostCore/WindowMatcher.swift`)

Pure, so it is tested on Linux. For each app, saved placements are matched to
current windows first by equal title, then by order among the rest. A
placement with no window left is `missing`. Windows that match nothing are
left where they are.

Applying sets position, then size, then position again (a window moved to a
smaller display is clamped by its old size otherwise). Windows are raised
back to front, so the saved frontmost window ends on top.

## Launching

With `launch`, apps with placements that aren't running are opened (in the
background, without activating), and the host waits up to 8 seconds for
their windows before matching. Apps that restore their own windows then land
where they were.

## Displays trigger

`Trigger.displays` and `TriggerReason.displays`. The app listens for
`NSApplication.didChangeScreenParametersNotification`, which fires several
times per change, and sends one trigger 1.5 seconds after the last one.

## Simulated system

`SimulatedSystem` keeps a list of displays and windows (`simulate(windows:)`,
`STACKBAR_WINDOWS` for `stackbarctl`) and applies arrangements to it, so the
plugin renders and is tested on Linux.

## Plugin

Layouts are stored with the setup id and display names they were saved on.
The panel shows the current setup's layouts first, with the default marked,
and the others collapsed below. Restoring on display change or wake applies
the setup's default once per change, never while the user is mid-save. Every
layout is a command (`restore-<id>`), so it gets palette, alias and hotkey
for free; agent tools list, save and restore.
