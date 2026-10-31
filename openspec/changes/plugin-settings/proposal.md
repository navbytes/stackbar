# Plugin settings out of the panel

## Why

Every bundled plugin ended its panel with a "Settings" section of toggles and
sliders. The panel opens many times a day to do something; those preferences
are set once. They took most of the popover's height and pushed the content
people came for out of view. The leading Mac menu-bar apps keep the menu for
actions and put preferences in a Settings window.

## What changes

- A new surface, `.settings` (protocol 4). A plugin lists it in its manifest
  and implements `var settings: ViewContent`.
- Fluid's Settings window → Plugins shows the plugin's page with two tabs,
  Settings (the plugin's own view) and About (what Fluid knows about it).
- The panel footer shows a gear for plugins that have settings. It opens that
  page, and ⌘, does the same while the panel is open.
- The four bundled plugins move their preferences there. Quick controls used
  mid-task stay in the panel: Pause and Ignore next copy, the keep-awake
  choices and Keep the display on, the PR tabs, Start a meeting now.
