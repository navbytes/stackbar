# Confirm destructive actions in the host

## Why

`Role.critical` only colours an action. The host runs it on the first press,
and `SystemActions.swift` tells plugins to ask first. So every plugin that has
something destructive writes its own "press again within 10 s" state machine.

On main (stackbar-plugins 40339ac) 15 plugins carry a copy: Docker, Ports,
Script Commands, System Monitor, Kill Process, System Commands, Windows,
Clipboard, Color Picker, App Switcher, Timers, Git Sync, Linear, PR Cockpit
and Pomodoro. They come in four shapes (one armed string id, a `[key: Date]`
map, a single `Date?`, and Pomodoro's inline banner), and the store uses
`role: .critical` 37 times.

The 11-08 plugin audit found about a dozen bugs of one kind, because each copy
got a different detail wrong:

- **Stale label.** Nothing redraws when the 10 s runs out, so a row keeps
  saying "Click again to …" and the next press silently arms again (System
  Commands, Windows, Clipboard, Color Picker).
- **Wrong key.** Ids built by hand (`stop:<port:pid>`, `rm:<id>`, a single
  armed layout plus `"all"`) can collide, and a collision means confirming A
  runs B.
- **Silent arming.** Ports' palette views never showed the notice, so the
  first press did nothing visible and the second killed.
- **Stale arm.** Pomodoro's arm survived into a new session.
- **Wrong scope.** Docker's confirm row showed one list and Prune acted on
  another.
- **Wrong order.** Script Commands armed before checking the interpreter, so
  the confirm could never succeed. (Plugin logic; this change does not fix it.)

A plugin cannot fix the first two on its own: it draws only when the host
sends it something, so it cannot redraw at T+10 s.

`stackbarctl soak --press` presses panel buttons about once a second, so it
lands the second press itself. 0.33.0 skips buttons whose id contains a
destructive word, but a confirm button with a harmless key still runs:
Pomodoro's banner button is `key: "confirm"`.

## What changes

- **Protocol 25.** An optional `confirm: String?` on `ActionRef` (row actions)
  and on `ViewNode.button`. It is the object of the sentence the host writes:
  `confirm: "stop web (pid 412)"` becomes "Press again within 10 s to stop web
  (pid 412)". Absent means no confirmation, so every existing plugin decodes
  and behaves as today.
- **`ActionConfirmer` in StackbarHostCore.** The host holds the first press:
  it arms `(plugin, surface, action id)`, shows the HUD, redraws the control
  as armed and sends nothing to the plugin. A second press within 10 s sends
  the event as today. At 10 s, or when the action disappears or its `confirm`
  text changes in a new render, the arm is dropped and the control redrawn.
- **Every surface.** Panel, window, settings and command views draw the armed
  state and announce it to VoiceOver. The palette's derived row actions use
  the same arm (Return twice). A **widget** does not arm: a confirmable button
  opens the plugin's panel, since widget redraws are rationed and an armed
  look cannot be shown reliably. `SurfaceParity` and its ledger cover it.
- **Soak.** `soak --press` never presses an action that has `confirm`. The
  word avoid-list stays as a second guard.
- **StackbarKit.** `confirm:` on `Row.action`, `Button`, `ActionButton` and
  `IconButton`, so a call site stays one line. When the host is older than
  protocol 25 the kit arms the press itself, with the same wording, so a
  plugin built against the new kit is never less safe on an old host (the
  host's decoder ignores fields it does not know, which would otherwise run
  the action on the first press).
- **Store check.** `scripts/check.sh` in stackbar-plugins fails a `.critical`
  action that has neither `confirm:` nor an explicit `confirm: .none`
  opt-out. CONTRIBUTING drops "copy System Commands' arm pattern".
- **Migration.** One stackbar-plugins PR after the release: the 15 plugins
  delete their arm state and guard blocks and pass `confirm:`. Action ids do
  not change, so aliases, hotkeys, links and saved state are unaffected.

## Not in this change, on purpose

- **A native sheet.** A sheet over the non-activating panel or the palette
  takes focus and closes it, and a widget cannot host one. Press-again only;
  revisit if a plugin needs a two-choice question.
- **Palette commands.** System Commands, Docker and Clipboard confirm a command
  with a one-row "Restart Now" view, so Return is pressed twice on a row that
  says what happens. That works and stays the documented pattern.
- **Agents and notifications.** Agents call tools (`callTool`), never action
  ids, and have their own per-tool consent. Notification buttons only open
  URLs. Neither path reaches the confirmer.
- **`.critical` implying confirm.** Kept explicit; the store check makes the
  choice visible instead.

## Cost

About 1–2 days in the host with tests: one protocol field in two places, the
confirmer, four renderers plus the widget rule, soak, kit sugar and fallback,
docs. Then one store PR touching 15 plugins (a few lines each, since several
change titles and rows while armed) with `minimumStackbar` unchanged thanks to
the kit fallback.
