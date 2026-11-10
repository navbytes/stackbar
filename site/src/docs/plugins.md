---
title: Plugins and the Store
description: Install plugins from the signed store, approve what they can reach, and keep them up to date.
group: Use Stackbar
order: 3
---

Almost everything Stackbar does comes from plugins, including the parts that
feel built in, such as Applications and Calculator. Each plugin is one Swift
file, runs in its own sandboxed process, and can show up in the palette, the
menu bar, a panel, a window and a desktop widget.

## The Store

Open it from the Stackbar menu (**Plugin Store…**) or Settings › Store. Every plugin in it
was reviewed, built in CI and signed, and Stackbar checks the signature
before installing. Pages on [stackbar.app/plugins](/plugins/) open the same
plugin in the app.

## Approvals

A plugin declares what it needs: network hosts, files, the clipboard, your
calendar, secrets. The first time, and whenever a new version asks for more,
Stackbar shows the list in plain English and waits for you. Settings ›
Privacy & Secrets shows what each plugin can reach.

A plugin that works in your code folders (Git Sync, Script Commands) asks
you to pick each folder with an Open panel, and can run commands only there.
Its Settings page lists the folders you chose, with **Remove**.

## Things you can't undo

Stopping a process, removing containers or clearing history takes a second
press. The first press turns the button or row into "Press again to …" and
does nothing else; after 10 seconds, or if what it would do changes, it goes
back to normal. In the palette, Return twice runs it and Esc forgets it.

## Settings and secrets

Each plugin has its own page in Settings with its options, its commands and a
Secrets section for tokens (stored in your Keychain, never exported).

## Updates

Store plugins update themselves once a day; turn that off in Settings ›
Store. A version its publisher withdraws is removed from every Mac that
installed it.

## Your own plugins

Drop a `.swift` file into the plugins folder (Settings › General › Plugins
folder) and Stackbar builds and runs it. Writing one needs Xcode or the
Command Line Tools (`xcode-select --install`). Start with
[Your first plugin](/docs/first-plugin/).
