# Tasks

## 1. Site scaffold
- [x] 1.1 Astro site in `site/`, static, base path configurable for the custom domain
- [x] 1.2 Kit readers: hues, spacing, radii, brand gradients, store URL and key, version; tests that fail on drift
- [x] 1.3 Store loader: fetch and verify the signed index, read READMEs, one page per plugin; tests with a signed fixture and a forged index
- [x] 1.4 Home page: hero with a drawn menu bar and a real render, one-file code sample, surfaces, AI authoring, safety, store shelf
- [x] 1.5 Store page with search and categories; category pages; plugin app pages (hero, about, what it asks for, features, install, details, related)
- [x] 1.6 Download page from the latest GitHub release, with a build-from-source fallback
- [x] 1.7 Light and dark themes following the system, with a toggle
- [x] 1.8 Pages workflow: tests, `astro check`, build, internal link check, deploy from main, daily and on dispatch

## 2. Going live (Naveen)
- [ ] 2.1 Settings → Pages → Source: GitHub Actions
- [ ] 2.2 DNS: `stackbar` CNAME to `navbytes.github.io`; custom domain in Pages settings; repository variables `SITE_URL=https://stackbar.navbytes.io`, `SITE_BASE=/`
- [ ] 2.3 Optional: fine-grained token with Actions write on navbytes/stackbar as `SITE_DISPATCH_TOKEN` in stackbar-plugins

## 3. Plugin content (after stackbar-plugins PR #7)
- [ ] 3.1 Manifest `accent` (Theme hue) and `symbol`, carried into the signed index; site uses them over the category hue
- [ ] 3.2 StackbarKit previews and `stackbarctl render --preview <name>`
- [ ] 3.3 `publish.sh`: render every surface light and dark per version, write `site.json`, add the redirect `index.html`, send `store-published`
- [ ] 3.4 Gallery on plugin pages: every surface, both appearances, with a light/dark switch
- [ ] 3.5 `stackbar://store/<id>` opens the plugin in Settings → Store; "Get it in Stackbar" uses it

## 4. Polish
- [ ] 4.1 Open Graph cards per plugin in its hue
- [ ] 4.2 Lighthouse CI (95+ in all four) and a Playwright smoke at phone and desktop widths
- [ ] 4.3 Copy pass with Naveen; switch to stackbar.navbytes.io
