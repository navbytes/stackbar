# Design

## Types (StackbarProtocol/Reminders.swift)

- `ReminderList`: `id` (calendar identifier), `title`, `color` (`#RRGGBB`),
  `account` (source title, like iCloud), `allowsChanges`, `isDefault`.
- `Reminder`: `id` (calendar item identifier, empty for a new one),
  `externalID`, `list`, `title`, `notes`, `due`, `dueHasTime`, `priority`
  (`none`, `low`, `medium`, `high`), `completed`, `recurrence`, `alarm`,
  `url`, `modified`.
- `ReminderRecurrence`: `frequency` (daily, weekly, monthly, yearly),
  `interval`, `weekdays` (1 = Sunday … 7 = Saturday, weekly only).
- `ReminderQuery`: `lists` (nil = all), `completedSince` (nil = open only).
- `ReminderAccess`: `granted`, `denied`, `notDetermined`, `unavailable`.

## Saving

`saveReminder(reminder, fields:)`: with an empty `id` the host creates the
reminder (in `list`, or the default list) from every field. Otherwise it
loads the current reminder and copies only `fields` (nil means all). It
answers with the saved `Reminder`.

`dueHasTime == false` writes date components without hour and minute, which
is how Reminders stores an all-day due date.

## Repeats

Completing a repeating reminder through EventKit is not documented to roll
it forward. Plugins advance the due date themselves (Todo already does), so
the host doesn't guess.

## Change trigger

The Mac observes `EKEventStoreChanged` and tells plugins with the
`.reminders` trigger once things have been quiet for a second. The
notification fires for calendar changes too; plugins refetch, which is
cheap.

## Limits

At most 2000 reminders per query; notes cut to 4000 characters.
