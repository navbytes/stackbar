# Design

**Opt-in surface.** The host offers `.settings` only when the manifest lists
it, so plugins built before protocol 4 never see a surface they can't decode,
and the gear appears only where there is something behind it.

**One form, one place.** Settings render through the same `NodeView` as the
panel and window, on a resizable page in the Settings window. Plugins group
their preferences with `Section`s. Rendering is identical to the window, so
`SurfaceParity` gains a Settings column that reuses the panel treatment.

**Actions keep working.** All surfaces resolve in one render pass and share
one handler table, so a toggle on the settings page runs the same closure it
did in the panel; nothing in the plugin's state model changes.

**Considered:** a collapsible Settings section in the panel (cheaper, but the
clutter stays and the popover still grows); settings only in each plugin's
window (two places to look, and not every plugin has a window).
