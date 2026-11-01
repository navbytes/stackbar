# Marketing site

## Why

Naveen wants a best-in-class site for Stackbar and its plugin store: vibrant,
playful and professional, with every store plugin presented as an app on its
own page. The architecture was agreed in the doc "Stackbar marketing sites:
architecture" (https://claude.ai/artifact/VqX9XZcvZM8BFMtnGt8eG4); Naveen chose
one site for both on 2026-11-01.

## What changes

- `site/`: an Astro site served at stackbar.navbytes.io (until DNS exists,
  navbytes.github.io/stackbar/): the product home, `/plugins/` (the store),
  `/plugins/<slug>/` (one app page per plugin), category pages and `/download/`.
- Nothing is typed twice. The site reads the design-system hues, spacing and
  radii from `StackbarKit/Design.swift`, the brand gradients from the app icon,
  and the store URL, publisher key and version from the app's sources, and
  fails the build if their shape changes. Plugins come from the signed store
  index, verified with the key the app trusts, plus each plugin's README.
  Screenshots are the store's own renders. The home page's code sample is
  `Examples/ClockPlugin/Clock.swift`.
- `.github/workflows/site.yml` tests, checks types and links, builds, and
  deploys to GitHub Pages from main, daily, and on the store's
  `store-published` dispatch.
- The store keeps serving `index.json` and bundles from
  navbytes.github.io/stackbar-plugins; its Pages root gets a redirect to
  `/plugins/` (stackbar-plugins change).

Later, separately: optional manifest `accent` and `symbol` (plugin pages take
the plugin's own hue and icon instead of its category's), StackbarKit
previews with `render --preview` for believable screenshot data, every
surface rendered light and dark at publish time, and a `stackbar://store/<id>`
link behind "Get it in Stackbar".

## Not changing

The app, the plugin protocol and the store's signing. The site is read-only
over what the store already publishes.
