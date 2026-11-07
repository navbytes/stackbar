---
title: Permissions
description: Which macOS permissions Stackbar asks for, which feature needs each one, and how to give or take it back.
group: Use Stackbar
order: 5
---

Stackbar asks macOS for a permission only when you first use a feature that
needs it, so you won't see every prompt on day one. This page lists them all,
so you know what to expect and where to fix one that was refused.

There are two layers:

- **macOS permissions** belong to Stackbar.app. You grant them in System
  Settings › Privacy & Security, once for the whole app.
- **Plugin approvals** belong to each plugin. When a plugin asks to use the
  network, your calendar or the clipboard, Stackbar shows what it asks for and
  waits for you. Run one of its commands from the palette and the palette
  asks right there: Return allows it and the command carries on.
  Applications, Calculator and File Search come with Stackbar
  and are approved as they are installed. Each plugin's page in
  Settings › Plugins lists what it can do and can take it back.

## macOS permissions

| Permission | What needs it | Where to turn it on |
| --- | --- | --- |
| **Accessibility** | Moving and snapping windows (Windows), switching windows, searching menu items, pasting (Clipboard, Snippets), reading selected text, text expansion keywords, the App Switcher key layer, locking the screen | Privacy & Security › Accessibility |
| **Automation** | Reading Finder's selection, browser tabs, controlling Music or Spotify. macOS asks once for each app Stackbar talks to | Privacy & Security › Automation › Stackbar |
| **Screen Recording** | Reading the text in a part of the screen you drag over (Translate's Screen Text command) | Privacy & Security › Screen & System Audio Recording |
| **Calendars** | Up Next reading your events, and adding events | Privacy & Security › Calendars |
| **Reminders** | Todo's Reminders lists | Privacy & Security › Reminders |
| **Notifications** | Plugins that tell you something, such as Pomodoro and Timers | Notifications › Stackbar |

The palette itself, Applications, Calculator and File Search need none of
these.

## When a permission was refused

macOS asks only once. If you clicked Don't Allow, the feature says what it
needs and names the place in System Settings. Turn Stackbar on there; for
Accessibility, text expansion notices within a few seconds and starts
listening without a restart.

After an update, macOS sometimes keeps an old Stackbar entry in the
Accessibility list that no longer works. Remove it with the minus button and
turn the new one on.

## Secure Input

While a password field has focus, or an app such as a terminal has turned on
Secure Input, macOS stops every app from seeing keystrokes. Text expansion and
the App Switcher key layer pause until it ends. Their status in Settings names
the app holding Secure Input, so you can tell a stuck app from a broken
setting.
