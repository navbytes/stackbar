// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Until stackbar.navbytes.io points here the site lives at
// navbytes.github.io/stackbar/. Switching is these two values (see README).
const site = process.env.SITE_URL ?? 'https://navbytes.github.io';
const base = process.env.SITE_BASE ?? '/stackbar';

export default defineConfig({
  site,
  base,
  trailingSlash: 'always',
  integrations: [sitemap()],
  image: {
    // Plugin screenshots come from the store's GitHub Pages.
    domains: ['navbytes.github.io'],
  },
  markdown: {
    shikiConfig: { themes: { light: 'github-light', dark: 'github-dark' } },
  },
  vite: {
    // The home page shows a real example plugin from ../Examples.
    server: { fs: { allow: ['..'] } },
  },
});
