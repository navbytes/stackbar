# Workspaces

## Why

Naveen asked (2026-11-02) whether Snapset (snapset.co) is worth building, and
chose the save-and-restore MVP. Snapset is a paid menu-bar app that saves
where every window is, and puts them back when the same displays are plugged
in or the Mac wakes. Docking and undocking a laptop scrambles windows every
day, and macOS has nothing that remembers a layout per monitor setup.

`command-platform` left out window thirds and tiling because Rectangle and
macOS cover them. That still holds: this change is about remembering and
restoring layouts, not snapping.

## What changes

- **A windows API in the host** (protocol 13, Stackbar 0.15.0):
  - `Stackbar.windows()` lists the displays and the regular apps' windows
    (app, title, frame, display, front-to-back order, minimized).
  - `Stackbar.arrangeWindows(_:launch:)` moves and resizes windows to saved
    frames, matching them by app, title and order, and opens apps that are not
    running when asked. It answers with what it moved, opened and missed.
  - Both need a new `.windows` capability. The host already asks for
    Accessibility access (for paste); without it the call fails saying so.
  - A `.displays` trigger: the plugin refreshes when a display is plugged
    in, unplugged or rearranged.
- **A Workspaces store plugin** (`Productivity/Workspaces` in
  stackbar-plugins):
  - Save the current layout under a name. Layouts belong to the display
    setup they were saved on, so "Desk" and "Laptop" can share names.
  - Restore from the panel, the palette, a hotkey or an agent: every layout
    is a command.
  - Restore the setup's default layout on its own when the displays change
    or the Mac wakes (on by default, a setting turns it off).
  - Open apps that aren't running (a setting).

## Not in this change, on purpose

- Snapping, keyboard tiling, drag-to-shape. macOS and Rectangle cover them.
- Voice control.
- Moving windows between Spaces. It needs private SkyLight calls that break
  between macOS releases.
- Browser tabs and Finder folders. They need Apple Events per browser; they
  can come once window restore proves reliable.
- Switching layouts when an app opens.
