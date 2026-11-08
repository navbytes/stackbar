# Design

## Command buttons

The notification's `userInfo` keeps each button's command and arguments
next to the URLs. On a click `AppDelegate.runNotificationCommand` looks the
command up in the registry (it may have gone since the post: then nothing
runs). It runs with source `.panel`, not `.link`: a `.link` source refuses
`stackbarOnly` commands, and a new `CommandSource` case would not decode in
older helpers. View commands and ones still missing a required argument
open in the palette instead, the same as a hotkey.

## Calendar writes

`CalendarEvent.id` is the EventKit identifier, `@`, and the occurrence's
start in seconds. A save with that id finds the occurrence by searching the
day after its start, so a repeating event changes on that day only
(`span: .thisEvent`); without a match it falls back to
`event(withIdentifier:)`. Only calendars that allow content modifications
are listed or accepted. Reading and writing are separate capabilities, so a
plugin that only shows the day never gets to change it.

## Terminal

The host writes a temporary `#!/bin/zsh -l` `.command` file (mode 0700)
that removes itself and runs the single-quoted words, then hands it to
NSWorkspace, so the user's own terminal app (Terminal, iTerm, Ghostty)
opens it with their login PATH. A backstop removes it after 60 seconds.
The plugin never writes shell text.

## Text recognition

`VNRecognizeTextRequest` at `.accurate`, with language correction and
automatic language detection unless the plugin names languages. Lines are
sorted top to bottom, then left to right, and capped at 2000. The screen
capture is `/usr/sbin/screencapture -i -x` into a temporary file, removed
afterwards; macOS asks for Screen Recording the first time.

## Sensors

Apple Silicon reports temperatures through the HID event system
(IOHIDEventSystemClient, vendor page 0xFF00, usage 5, event type 15). The
calls are private, so they are found with `dlsym` at run time and a Mac
without them answers no temperatures. Readings are grouped by product name
(`tdie` is the CPU, `GPU`, `NAND` is the SSD, `battery`) and averaged.
Fans come from the AppleSMC user client (`FNum`, `F<i>Ac`, `F<i>Mx`;
`flt `, `fpe2`, `ui8 `, `ui16`), read only. The struct is checked to be
80 bytes, C's `SMCKeyData_t`, before any call.
