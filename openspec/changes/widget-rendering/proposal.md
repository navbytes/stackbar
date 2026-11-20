# Widget rendering: draw the desktop widget the way its preview does

## Why

Naveen (2026-11-20): desktop widgets don't render content properly; take
inspiration from Scriptable, whose widgets look good. The widget extension
drew plugin trees as the live panel does, not as `stackbarctl render`'s
snapshot does, so what an author checked was not what reached the desktop:

1. Remote images never showed. The app didn't fetch the widget tree's
   images and the extension can't, so Music's cover was a placeholder.
2. Fields, pickers, sliders, forms and the widget toggle were real AppKit
   controls, which WidgetKit can't draw; app and file icons waited on a
   `.task` that never runs in a widget.
3. Content was padded twice (12 pt inside the system margins) on a fixed
   grey fill, so a full-colour card (Music's `Backdrop`) sat as a small card
   inside a grey frame instead of filling the widget like Scriptable's
   `backgroundColor` / `backgroundGradient` / `backgroundImage`.
4. Clocks and timed progress froze until the next (rationed) reload.
5. One tree served every size; lists showed 4 rows even in a large widget.

## What changes (no protocol change)

- The app fetches a widget tree's remote images (same domain checks and
  budget as the panel), scales them to at most 800 px and writes them beside
  the snapshot in the app group; the snapshot lists which ones it has.
- The widget draws in snapshot mode: look-alike controls, icons looked up at
  once, a switch look-alike for widget toggles, forms as look-alikes.
- `ViewNode.widgetLayers`: a root depth stack that opens with shapes or
  remote images (a `Backdrop`), or a root `styled` background, becomes the
  widget's full-bleed container background. The extension disables
  WidgetKit's content margins and applies them itself, except for a
  backdrop's content, which pads itself.
- A tree that `changesWithTime` (clock, timed progress) gets a timeline entry
  for each of the next 60 minutes, drawn as of that entry (`stackbarNow`).
- Rows by size: 3 small, 4 medium, 9 large.
- `render --surface widget --png` draws small, medium and large side by side
  with the same views the extension uses.

## Not in this change

Separate layouts per widget size need the plugin to know the size, which is
a protocol change (31). Asked Naveen on 2026-11-20.
