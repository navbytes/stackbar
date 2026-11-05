---
title: Privacy and safety
description: What Stackbar and its plugins can reach, what it sends, and how to report a problem.
group: Use Stackbar
order: 5
---

Stackbar has no account and no analytics.

## Plugins are sandboxed

Every plugin runs in its own process inside the macOS App Sandbox, so a crash
or a hang in one never takes down the others. A plugin reaches only what its
manifest declares and you approved: named network hosts, files you picked,
the clipboard, your calendar, its own secrets. Settings › Privacy & Secrets
shows all of it, and the network audit shows which declared hosts a plugin
actually used.

## What leaves your Mac

- **Update checks** fetch the release feed from GitHub once a day, if
  automatic checks are on.
- **Store checks** fetch the signed plugin index from GitHub Pages.
- **Crash reports** are off unless you turn them on (Welcome window or
  Settings › Privacy & Secrets). A report carries the crash, the Stackbar and
  macOS versions, and nothing about your plugins, files or logs.
- **Plugins** reach the hosts they declared, such as GitHub for PR Cockpit.

## Report a problem

Help › **Report a Problem…** opens a new GitHub issue with
`stackbarctl doctor` output filled in (versions, toolchain, folders). Read it
before you send it; nothing is posted until you do.

Security issues go to the address in
[SECURITY.md](https://github.com/navbytes/stackbar/blob/main/SECURITY.md)
rather than a public issue.
