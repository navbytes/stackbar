# Reminders for plugins

## Why

Naveen asked on 2026-11-04 for the Todo plugin to keep its tasks in Apple
Reminders, so they reach the iPhone, iPad and Watch and work with Siri.
Plugins run in their own sandboxed helper, so a plugin can't use EventKit
itself without its own privacy prompt, entitlement and a build that only
works on the Mac. The host already reads the calendar for plugins
(`.calendar`); Reminders follows the same pattern.

## What changes

- **A `.reminders` capability** (protocol 15, Stackbar 0.18.0): "Reads and
  changes your reminders". The host asks macOS for full Reminders access the
  first time a plugin needs it.
- **Host calls**: `reminderAccess(ask:)`, `reminderLists()`,
  `createReminderList(title:color:)`, `reminders(ReminderQuery)`,
  `saveReminder(_:fields:)` and `deleteReminder(id:)`.
- **Field-level saves.** `saveReminder` takes the fields the plugin changed;
  the host reads the reminder fresh and writes only those, so an edit on the
  Mac doesn't undo a date changed on the phone a moment ago.
- **A `.reminders` trigger**, fired (debounced) when the Reminders database
  changes, from any app or device.
- `SimulatedSystem` keeps reminders in memory (`STACKBAR_REMINDERS`), so
  plugins build, render and are tested on Linux.

EventKit has no public API for Reminders' sections, tags, flags or subtasks,
so they are not offered. Lists are, and they are what plugins should use
for categories.
