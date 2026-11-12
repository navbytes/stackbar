# Tasks

## 1. Site scaffold
- [x] 1.1 Astro site in `site/`, static, base path configurable for the custom domain
- [x] 1.2 Kit readers: hues, spacing, radii, brand gradients, store URL and key, version; tests that fail on drift
- [x] 1.3 Store loader: fetch and verify the signed index, read READMEs, one page per plugin; tests with a signed fixture and a forged index
- [x] 1.4 Home page: hero with a drawn menu bar and a real render, one-file code sample, surfaces, AI authoring, safety, store shelf
- [x] 1.5 Store page with search and categories; category pages; plugin app pages (hero, about, what it asks for, features, install, details, related)
- [x] 1.6 Download page from the latest GitHub release, with a build-from-source fallback
- [x] 1.7 Light and dark themes with a toggle
- [x] 1.7a Dark first, light on the toggle (Naveen, 2026-11-01)
- [x] 1.8 Pages workflow: tests, `astro check`, build, internal link check, deploy from main and hourly

## 2. Going live (Naveen)
- [x] 2.1 Settings → Pages → Source: GitHub Actions
- [x] 2.2 DNS: `stackbar` CNAME to `navbytes.github.io`; custom domain in Pages settings; repository variables `SITE_URL=https://stackbar.navbytes.io`, `SITE_BASE=/`

## 3. Plugin content (after stackbar-plugins PR #7)
- [x] 3.1 Manifest `accent` (Theme hue) and `symbol`, carried into the signed index; site uses them over the category hue (Stackbar 0.14.0)
- [x] 3.1a The app verifies an index's signature over the bytes as published, so a field an older app does not know stays signed and no longer breaks verification there
- [x] 3.2 StackbarKit previews and `stackbarctl render --preview <name>` (openspec/changes/archive/2026-11-08-site-refresh)
- [x] 3.3 `publish.sh`: render every surface light and dark per version, write `site.json`, add the redirect `index.html` (stackbar-plugins #8)
- [x] 3.4 Gallery on plugin pages: every surface, both appearances, with a light/dark switch
- [x] 3.5 `stackbar://store/<id>` opens the plugin's page in Settings → Store (a native detail view from the index and the store's site.json, which now carries each README); "Get it in Stackbar" uses it and falls back to the install steps (Stackbar 0.15.0)

## 4. Polish
- [x] ~~4.1~~ not planned during the trust-first freeze: Open Graph cards per plugin in its hue
- [x] ~~4.2~~ not planned during the trust-first freeze: Lighthouse CI (95+ in all four) and a Playwright smoke at phone and desktop widths
- [x] 4.3 Copy pass with Naveen (site copy brought up to 0.39, #190)
- [x] 4.3a Live at stackbar.navbytes.io (2026-11-01); HTTPS enforced once GitHub issues the certificate
