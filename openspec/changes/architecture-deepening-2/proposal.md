# Architecture deepening, round two

## Why
On 2026-11-06 Naveen ran Matt Pocock's "improve codebase architecture" skill
over Stackbar again, after the palette ranking and widget releases. The
review (https://claude.ai/artifact/4CYLFe3TtdLubZEuYG5PqZ) found six places
where one concept is spread across files or sits in the macOS-only app target
where Linux CI can't test it. Two of them are visible bugs. Naveen asked for
items 1 to 5, built in the order the review recommended: 2, 1, 3, 4, 5.
Item 6 (one version source) was not chosen.

## What changes
1. **Store permissions from the capability kind (review #2).** `Capability.Kind`
   names each case once. The plugin index carries each capability's kind next
   to its summary, and the Store builds its permission cards from the kind.
   Today Terminal shows as "Opening Links" and six capabilities are missing
   from "Asks for", because the kind is guessed from the summary's first words.
2. **One command-start planner (review #1).** A pure `CommandStart` in HostCore
   decides, for every entry point (palette, alias, hotkey, link, intent,
   Spotlight, text expansion, notification button), whether a command runs
   now, asks for its arguments, opens its view, or is refused. The entry
   points carry out the plan. Today they disagree on optional-only arguments
   and on where typed text goes.
3. **Palette root list in HostCore (review #3).** Merging results, favourites,
   Store suggestions, plugin rows and fallbacks, the alias rule and section
   naming move out of `PaletteSession` into a tested HostCore module that
   gives every row a role.
4. **Typed host-call replies (review #4).** Each host call's reply type is
   declared once in StackbarProtocol and both the host and the kit use it.
   System calls share one rate-limit wrapper whose message comes from the
   limiter.
5. **One keyboard shortcut type (review #5).** One shortcut value in
   StackbarProtocol parses, normalises, draws glyphs and validates. The
   manifest hotkey, row action shortcuts, the palette and Settings use it, and
   `publishingProblems`/`render` report a shortcut that can't be parsed.

## Impact
No protocol break. The index gains one optional field, so older apps keep
reading it. Plugins need no change; stackbar-plugins raises `stackbarRevision`
once item 1 ships so the next index build carries kinds.
