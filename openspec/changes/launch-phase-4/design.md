# Design

## Focusing a window

`HostCall.focusWindow(WindowTarget)` names a window by app id, title and its
place among that app's windows (`WindowTarget(window, in: snapshot)`), the
same way layouts match windows: titles change less than order, and order
breaks ties. The host reads the windows again, unminimizes the match, sets
it main, raises it and activates its app. It shares the 120-a-minute app
switch limit. Windows on other Spaces are not listed by most apps through
Accessibility, so Switch Windows covers the current Space plus minimized
windows.

## Menus

`.menus` is a capability of its own, not part of `.windows`: choosing a menu
item can do anything the app can (Delete, Quit, Send). The host reads the
menu bar of the app the user was in (the front app, or the one before
Stackbar when the palette is in front) through Accessibility: leaves only,
the Apple menu left out, at most 3000 items and 5 levels. Each item has its
path of titles, its shortcut drawn as glyphs from `AXMenuItemCmdChar` and
`AXMenuItemCmdModifiers` (`MenuSnapshot.shortcut`, tested on Linux), enabled
and checked. `pressMenuItem(appID:path:)` activates the app, walks the path
by title and presses the item, failing when it is gone or dimmed; titles are
the address because element references don't survive between calls.

## Palette keys

⌃N/⌃J and ⌃P/⌃K move like the arrows (a whole line in a grid); ⌘, opens the
current command's plugin settings when it has a settings page, else
Stackbar's; ⌘⌫ clears the search field when it has focus and text.

## Install hygiene

`AppLocation.shouldOfferMove` (tested) offers the move when the bundle is
translocated, on a mounted volume, or outside /Applications and
~/Applications. Moving copies to /Applications (an older copy goes to the
Trash), trashes the original unless it is translocated or on a disk image,
opens the new copy and quits. "Don't ask again" is remembered.

The command-line tool is a symlink from /usr/local/bin/stackbarctl to the
copy inside the app, made with an administrator prompt
(`AppLocation.linkCommand`, quoted for the shell and tested).

"Remove all data" stops every plugin, moves the data folder (plugins,
storage, approvals), the caches and the logs to the Trash rather than
deleting them, so plugins someone wrote can still be recovered; deletes the
Keychain items under Stackbar's service, unregisters the login item, clears
its defaults, and quits.
