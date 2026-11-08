# Plugin rivals, wave 3: host calls the plugins asked for

## Why

The plugin-rivals research (2026-11-02) ranked what each store plugin lacks
against the apps people would otherwise use. Naveen asked on 2026-11-06 to
build every open item. Wave 2 was plugin-only. The rest needs the host,
because plugins run sandboxed and can't use EventKit writes, Vision, a
terminal or the Mac's sensors themselves:

- Up Next (vs Fantastical, Itsycal) can't add an event or snooze a meeting.
- Pomodoro (vs Session) can't offer Start Break or +5 min on its alert.
- Docker (vs OrbStack) can't open a shell in a container.
- Clipboard (vs Paste, Raycast) can't search the text in copied images.
- Translate (vs Raycast, DeepL) can't translate text on the screen.
- System Monitor (vs iStat Menus, Stats) shows no temperatures or fans.

## What changes (protocol 21, Stackbar 0.26.0)

- **Command buttons on notifications.** `NotificationAction(title,
  command:, arguments:)` runs one of the posting plugin's own commands when
  clicked. A view command, or one with a required argument missing, opens
  in the palette. At most 3 arguments of up to 500 characters; the command
  id is checked when the notification is posted. Old URL buttons decode as
  before.
- **`.calendarWrite`**: `saveCalendarEvent(CalendarEventDraft)` adds an
  event or changes one (`CalendarEvent.id`, one occurrence of a repeating
  event), with an optional alert; `writableCalendars()` lists the calendars
  that take events. 30 changes a minute.
- **`.terminal`**: `openInTerminal(command, title:)` opens whatever app
  opens `.command` files, running a program and its arguments. The host
  quotes every word; no newlines or NULs; at most 64 words; 5 a minute.
- **`.screenText`**: `captureScreenText(languages:)` runs the ⇧⌘4
  crosshair and reads the text with Vision; nil on Esc.
  `recognizeText(imageID:languages:)` reads a kept clipboard image and
  needs `.clipboard`, which already hands out the image.
- **`.sensors`**: `sensors()` returns CPU, GPU, SSD and battery
  temperatures and fan speeds.

None of these needs a sandbox entitlement on the helper.
