# Design

## Wire types (`StackbarProtocol/KeyLayer.swift`)

- `KeyLayerTrigger`: `rightCommand` (default), `rightOption`, `rightControl`,
  `rightShift`. Only right-hand modifiers, so the left ones keep their
  shortcuts.
- `KeyBinding`: `key` (one lowercase letter or digit), `apps` (bundle ids in
  cycle order), `launch` (open `apps[0]` when none of them is running).
- `SecondPress`: `hide`, `cycleWindows`, `stay`. This is what happens when the
  letter's only running app is already in front.
- `KeyLayer`: `trigger`, `bindings` (at most 36, one per key), `secondPress`,
  `assignCommand` (a command id of the plugin's, or nil), `overlay` (Bool).
- `RunningApp`: `id` (bundle id), `name`, `path`, `isActive`, `isHidden`.
- `KeyLayerStatus`: `listening`, `needsAccessibility`, `secureInputApp`
  (a name, or nil), `conflict` (the other plugin's name when it holds the
  same trigger).

## Calls (protocol 14)

- `HostCall.setKeyLayer(KeyLayer?)` answers `KeyLayerStatus` as JSON. `nil`
  removes the plugin's layer. It needs `.keyLayer`. Each plugin has one
  layer, and two plugins can't hold the same trigger: the second one gets
  `conflict` and isn't listened to. A layer is dropped when its plugin stops.
- `HostCall.keyLayerStatus` answers `KeyLayerStatus`. It needs `.keyLayer`.
- `HostCall.runningApps` answers `[RunningApp]` (regular apps only, in the
  order they launched). It needs `.apps`.
- `HostCall.activateApp(id, launch: Bool)` and `HostCall.hideApp(id)` need
  `.apps`. They are limited to 120 a minute.
- `Trigger.apps` / `TriggerReason.apps` fire when a regular app opens or
  quits, 0.5 seconds after the last such change.

## Routing (`StackbarHostCore/KeyLayerRouter.swift`)

The routing is pure code, so it is tested on Linux. Given the layers, which
modifiers are held, the key, the running apps and the frontmost app, it
returns one of these:

- `passThrough`: no layer is active, or the key has no binding.
- `activate(id)`: the next running app on the key after the frontmost one,
  or the first running one.
- `launch(id)`: none of the key's apps is running and `launch` is set.
- `hide(id)` or `cycleWindows(id)`: the key's only running app is in front
  and `secondPress` asks for it.
- `assign(pluginID, command, key, frontmostID)`: the assign key is held too.
- `swallow`: the key is bound but there's nothing to do, so it isn't passed
  through as a ⌘-shortcut either.

Its key-up partner is swallowed too, so the app in front never sees half a
shortcut.

## The tap (`Stackbar/MacKeyLayer.swift`)

- A single `CGEventTap` at the session level (`.defaultTap`, head insert)
  watching key down, key up and flags changed. It exists only while some
  layer is registered. Without one, nothing listens and nothing asks for
  permission.
- The right-hand modifiers are read from the device flags (`NX_DEVICERCMDKEYMASK`
  and the others). The letter comes from `NSEvent(cgEvent:)
  .charactersIgnoringModifiers`, which follows the keyboard layout.
- The callback runs on the main run loop and only routes. It activates
  synchronously inside the press: the spike showed that is enough. If the
  app isn't in front 150ms later, it falls back once to
  `NSWorkspace.openApplication(activates: true)`.
- When the tap is disabled by timeout or user input, it is switched back on
  and the count is logged.
- Secure Input: `CGSessionCopyCurrentDictionary()["kCGSSessionSecureInputPID"]`,
  resolved to an app name, reported in the status.
- Accessibility: registering a layer asks for it with the system prompt (as
  the windows API does). Without it, the status says `needsAccessibility`.
  The layer is kept, and the tap is created once access is granted. It is
  checked again every 2 seconds while missing.
- `cycleWindows` raises the app's backmost standard window through
  Accessibility (`AXRaise`, then `AXMain`).

## Overlay

When the trigger is held alone for 0.4 seconds, a non-activating HUD panel
centred on the screen with the mouse shows the layer's letters, each with the
first app's icon and name. Running apps are bold. It hides on release or on
the next key.

## Assigning

The assign chord runs the plugin's `assignCommand` through `CommandCenter`
with the arguments `key` and `app`, from the `.hotkey` source. The plugin
saves the pin and sets its layer again.

## Simulated system

`SimulatedSystem` keeps a list of running apps (`STACKBAR_APPS` for
`stackbarctl`) and the registered layers. `pressKeyLayer(key:assign:)` runs
the router and applies the result, so the plugin and the routing are tested
on Linux.

## Plugin (`Productivity/AppSwitcher`)

- Automatic letters: the first letter of each running app's name. Apps that
  share a letter cycle in launch order.
- Pinned letters (`[key: [bundleID]]` in storage) come before the automatic
  apps on that key and open when they aren't running (a setting, on by
  default). A pinned app is left off its automatic letter.
- Triggers: `.launch` and `.apps`. Each refresh reads the running apps,
  builds the bindings and sets the layer. It skips the call when nothing
  changed.
- The panel shows a letter grid with app icons, the status (and the fix when
  it isn't listening), and how to pin.
- Settings: trigger key, second press, open pinned apps, overlay, and Clear
  pins.
- Commands: `assign` (from the chord) and `clear-pins`.
