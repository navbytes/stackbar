## Gap review (2026-10-31)

Each plugin against the apps people reach for in its category, by feature,
not by copying any of them. "Done" landed with this review; "Later" needs host
work and is listed so it isn't forgotten.

### Clipboard History (vs Maccy, Paste, Raycast, Alfred)

- Done: full keyboard use (the filter takes focus; ↑↓, Return, ⌘1–⌘9 follow
  the filter; ⌥Return plain text; ⌘P pin; ⌥⌫ delete). Formatted copies keep
  every pasteboard type and paste back exactly. Paste as plain text, per item
  or always. Ignore copies matching a regex (tokens, one-time codes). Clear
  everything including pins. Pasting from history no longer bumps the count or
  rewrites the source app.
- Already there: search, pins, images, files, ignored apps (password managers
  by default), concealed and transient types skipped, ordering, history size,
  pause and ignore-next, global hotkey, agent tools.
- Later: a preview pane for long text and images (needs an image/detail node
  in the vocabulary), opening the list at the text cursor, fuzzy search.

### Stay Awake (vs Amphetamine, KeepingYouAwake, Lungo)

- Done: always awake while plugged in, typed durations (90m, 1h30), a warning
  five minutes before a timed session ends.
- Already there: indefinite, presets, until a time, while an app runs, weekday
  schedule, display on or off, battery floor, Low Power Mode, notifications,
  daily stats, agent tools; the host releases the assertion if the plugin dies.
- Later: closed-lid mode (needs a privileged helper), while a download or a
  process runs, while an external display or a VPN is connected, one-click
  toggle on the menu-bar icon (needs a "primary action" for the status item).

### Up Next (vs MeetingBar, Dato, Fantastical)

- Done: Zoom and Teams open in their apps instead of a browser tab, start an
  instant Meet, Zoom or Teams call, hide finished events and events without
  other people, show the menu-bar countdown only within N hours, events that
  cross midnight, next meeting first so ⌃⌥J then Return joins it.
- Already there: countdown, 18 call services, reminders, auto-join, today and
  tomorrow, calendar filters, declined, all-day, tentative badges, agent tools.
- Later: a Join button inside the notification (needs notification actions),
  a full-screen "meeting starting" alert, dial-in numbers.

### PR Cockpit (vs Gitify, Trailer, GitHub's web dashboard)

- Done: "New" markers for activity since you last opened a PR (mark seen or
  new), snooze until it changes, hide a repository, comment counts, "Ready to
  merge" with a notification when one of yours gets there.
- Already there: review queue (with team requests) and your PRs in one
  request, checks, review decision, conflicts, size, drafts, notifications for
  new requests, approvals, changes requested and failing checks, agent tools.
- Later: GitHub notifications inbox (mentions, issues), GitHub Enterprise
  hosts (needs a per-user network host), signing in with OAuth instead of a
  token, merged/closed notifications.
