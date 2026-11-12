# stackbar.app

The Stackbar website: the product pages and the plugin store, one page per
plugin. Astro, static, deployed to GitHub Pages by `.github/workflows/site.yml`.
The plan is `openspec/changes/archive/2026-11-12-marketing-site/`.

```sh
cd site
npm ci
npm run dev       # http://localhost:4321/stackbar/
npm run check     # types and the content schema
npm test          # the store loader and the kit readers
npm run build     # dist/
```

Nothing about Stackbar or a plugin is typed twice:

- **Colours, spacing and radii** are read from `Sources/StackbarKit/Design.swift`,
  the brand gradients from `Packaging/Icon/AppIcon.svg`, and the store URL,
  publisher key and version from the app's Swift sources
  (`scripts/kit.mjs`, written to the git-ignored `src/generated/`). If the Swift
  changes shape, the build fails instead of drifting.
- **Plugins** come from the signed store index, verified with the key the app
  trusts (`scripts/store.mjs`), and each plugin's README. A plugin gets its page
  once it is published; change the README in navbytes/stackbar-plugins, not here.
- **Screenshots** are the renders the store publishes with each version.
- **The code on the home page** is `Examples/ClockPlugin/Clock.swift`.
- **`/llms.txt`** is the repository's `llms.txt`, the authoring guide.

Search and link previews: every page sets a canonical URL, Open Graph and
Twitter tags, and schema.org JSON-LD (`src/lib/seo.ts`: the app, each plugin
as a SoftwareApplication, breadcrumbs, FAQs). `robots.txt` and the sitemap are
generated. `public/og.png` (1200×630) and `public/apple-touch-icon.png` are
committed images; redraw them if the brand or headline changes.

The site rebuilds on a push that touches it and every hour, so a newly
published plugin shows up within the hour. Until `stackbar.app` points at GitHub Pages it is served at
`navbytes.github.io/stackbar/`; to switch, set the custom domain in the
repository's Pages settings and the `SITE_URL=https://stackbar.app` and
`SITE_BASE=/` variables in the workflow.
