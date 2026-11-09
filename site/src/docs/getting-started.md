---
title: Getting started
description: Install Stackbar, pick your hotkey and find your way around in five minutes.
group: Use Stackbar
order: 1
---

Stackbar needs an Apple Silicon Mac on macOS 26 or later.

## Install

With Homebrew:

```sh
brew install --cask navbytes/tap/stackbar
```

Or without it:

```sh
curl -fsSL https://stackbar.app/install.sh | bash
```

You can also download the notarized app from the [download page](/download/).
Each way puts Stackbar.app in /Applications and `stackbarctl` on your PATH.
You don't need Xcode: store plugins come prebuilt.

## The first run

The Welcome window asks two things:

- **Your hotkey.** It starts as ⌃⌥Space. Most people coming from Raycast or
  Alfred choose **Use ⌘Space**. Spotlight keeps ⌘Space until you turn its
  shortcut off, so Stackbar shows a button that opens the right place in
  System Settings. Until then, ⌃⌥Space keeps working.
- **Crash reports.** Off unless you turn them on. See [Privacy](/docs/privacy/).

Applications, Calculator and File Search are already installed and
approved, so the palette finds apps, files and sums straight away. Other
features ask macOS for a permission the first time you use them;
[Permissions](/docs/permissions/) lists which and why.

## Coming from Spotlight

If Stackbar takes ⌘Space, Spotlight is still there: give it another shortcut
instead of turning it off, such as ⌥⌘Space (System Settings › Keyboard ›
Keyboard Shortcuts › Spotlight). That keeps what only Spotlight does: Mail,
Messages and Notes content, live answers like flights and sports, and its
⌘3 Actions and ⌘4 Clipboard views.

What carries over without setup: apps, files (including iCloud Drive and
Dropbox), sums and unit conversions. Clipboard History (⌘⇧V), Snippets and
Windows are in the Store and do more than Spotlight's versions.

## Where things are

- **The palette:** your hotkey. Type to search; see [The palette](/docs/palette/).
- **The menu bar:** each plugin with a menu bar item shows it there. Click it
  for its panel.
- **Settings:** from the Stackbar menu (⌘,). General holds the hotkey and
  moving to another Mac; Commands holds aliases and hotkeys; Store holds
  plugins and updates.
- **Widgets:** plugins with a widget show up in the macOS widget gallery
  under Stackbar.

## Next

- [Install more plugins](/docs/plugins/) from the Store.
- [Move from Raycast](/switch-from-raycast/): snippets, quicklinks and ⌘Space.
- [Move from Spotlight](/switch-from-spotlight/), [Rectangle and rcmd](/switch-from-rectangle/) or [Hammerspoon](/switch-from-hammerspoon/).
- [Write your first plugin](/docs/first-plugin/) in one Swift file.
