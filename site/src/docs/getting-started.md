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

Applications, Calculator and File Search are already installed, so the
palette finds apps, files and sums straight away.

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
- [Write your first plugin](/docs/first-plugin/) in one Swift file.
