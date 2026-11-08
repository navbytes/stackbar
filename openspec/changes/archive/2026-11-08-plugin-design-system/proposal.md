# Plugin design system

## Why

Naveen wants every store plugin to look best in class, with no duplicated
code. A plugin is one file that imports StackbarKit only, so a look shared by
eighteen plugins can only live in StackbarKit. Today each plugin that wants
style (Pomodoro) carries its own palette and helper views, and the rest use
bare rows.

## What changes

- StackbarKit gains `Design.swift`: a `Theme` (eleven contrast-checked hues
  plus success, warning, critical, neutral and info), a type ramp
  (`Typography`, `.typography(_:)`), spacing and radius scales, surface
  paints, and components built only from protocol 11 nodes: `PanelHeader`,
  `HeroCard`, `Card`, `CardTitle`, `StatTile`, `Metric`, `Gauge`, `Meter`, `DayBar`, `TagChips`,
  `Pill`, `StatusDot`, `Banner`, `EmptyState`, `IconButton`, `ActionButton`,
  `Chip`. No protocol change.
- The contrast lint measures see-through backgrounds over what is behind
  them, checks gradient stops, and checks colored text against the
  background it sits on.
- Charts and `LabeledContent` take a styled `.foreground`, so a chart can use
  the plugin's hue.
- Stackbar 0.13.0. Store plugins that use the design system set
  `minimumStackbar: "0.13.0"`.

The per-plugin redesign happens in navbytes/stackbar-plugins.
