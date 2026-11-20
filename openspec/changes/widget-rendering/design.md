# Design

**Snapshot mode in the widget.** `WidgetContentView` sets
`stackbarSnapshot`, the flag `Snapshot.png` already uses for "one frame, no
AppKit, no tasks". The two places where snapshot mode and widget buttons
disagree now check `stackbarWidgetButton`: a widget toggle acts (drawn as
`SnapshotToggle` inside the intent button) and a widget link stays a `Link`.
`TimedFraction` and the snapshot clock read `stackbarNow` so a timeline
entry drawn ahead shows its own minute.

**Images.** `PluginController` calls `loadImages` for widget renders too and
re-announces the widget when new images arrive. `AppModel.widgetChanged`
lists the fetched URLs (at most `WidgetImages.maxPerWidget`) in
`WidgetSnapshot.images`, so the publish queue writes again when an image
lands. `flushWidgets` writes the images before the snapshot (downsampled
with ImageIO) and prunes images no snapshot names. Files are named by a
64-bit FNV-1a of the URL, stable across processes.

**Backgrounds.** `widgetLayers` is pure (StackbarProtocol) and tested on
Linux. Lifting is conservative: a styled wrapper is unwrapped only when it
sets nothing but frame, padding, clip, border, shadow and text styling; a
fade, blur, hover or animation on the card keeps the tree as drawn. Text
styling (font, foreground, symbol) carries to both layers.

**Margins.** `.contentMarginsDisabled()` on the configuration, then
`@Environment(\.widgetContentMargins)` padded back in by
`WidgetContentView` unless the layers are edge to edge.
