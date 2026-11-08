# The Store in its own window

## Why

The Store lived in a Settings tab, which left no room for a featured
plugin, a category sidebar or a plugin page you navigate into. Browsing sat
under two rows of filters, every card carried Turn Off and a red Uninstall,
plugin pages opened as a sheet with Done, and results were a grey caption.
Naveen picked this after `settings-redesign` (2026-11-03).

Proposal with mockups: https://claude.ai/artifact/2DqRFPNSEP4bbD1GsAu45c

## What changes

- A "Plugin Store" window, opened from the app menu, the panel's menu, the
  empty-state menu, Settings and `stackbar://store` links.
- A sidebar replaces the filter rows: Discover, the categories, then
  Installed and Updates (with a count). Search is in the toolbar, with Update
  All and Reload beside it.
- Discover leads with a featured plugin on its own colour, then New and
  Updated, then each category's first six plugins.
- Rows have one capsule button (Get, Update or Open) that turns into a
  spinner while installing. Turn off, Uninstall, Copy Link, Open Web Page and
  View Source are in the right-click and "…" menus.
- A plugin's page is pushed, with a back button, and shows an info strip
  (version, category, what it asks for, where it shows, what it needs), big
  renders, What's New beside About, privacy cards, what it does and
  information.
- Results show as a toast that names the plugin and offers Open.
- Settings → Store & Updates keeps automatic updates, the waiting updates and
  plugin sources.

## Featured

Indexes don't name a featured plugin yet. Discover features the most
recently published plugin you can install and don't have. A `featured`
field in the index can replace this later.
