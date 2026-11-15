# Trust first: verify before we ship

## Why
Naveen asked Claude Fable 5.2 for a high-level plan to make Stackbar the best
app in its category without making it more complicated (11 Nov 2026). Its
diagnosis: breadth is no longer the limit, trust is. Releases 0.22 to 0.39
shipped in six days, while `openspec/mac-checks.md` held 20 unticked hand
checks and no test drove the app itself. The bugs users actually met were
first-minute bugs: Return on the first result did nothing, Safari was
missing, core plugins waited for an approval.

Naveen chose a feature freeze of about two weeks and weekly stable releases
while this lands. The whole plan is in the project files
(`best-in-category/plan.md`).

## What changes
- **App check.** `STACKBAR_APPCHECK=<folder>` makes the app walk a new user's
  first minute on its own (`AppCheck.swift`): Welcome at a usable size, the
  starter set, core plugins answering without an approval, golden queries
  (`saf` puts Safari first, `12*12` gives 144), Return copies a sum, ⌘K and
  ⎋, every Settings page and the Store. It writes `results.json` and light
  and dark screenshots. With `STACKBAR_APPCHECK_MODE=upgrade` it opens a home
  the latest release left and checks that the plugins survived.
- **Speed budgets as tests.** The app check fails when palette open (median
  and max) or a golden search goes over its budget on the CI runner.
- **CI.** A new `app` job in `ci.yml` runs `scripts/app-check.sh --upgrade`
  on macos-26 for every change that touches the app, and is part of
  "CI ok".
- Later tasks: ranking golden cases on Linux, core plugin scenario tests,
  protocol decoder fuzzing, then converting `mac-checks.md` items.

## Not in scope
New features, protocol versions or plugins (the freeze).
