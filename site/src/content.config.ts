import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';
import { fetchStore } from '../scripts/store.mjs';
import kit from './generated/kit.json';

// One entry per published plugin, from the signed store index (verified with
// the key the app trusts) and the plugin's README.
const plugins = defineCollection({
  loader: {
    name: 'stackbar-store',
    async load({ store, parseData, renderMarkdown, generateDigest, logger }) {
      const { plugins } = await fetchStore(kit.store);
      store.clear();
      for (const plugin of plugins) {
        const data = await parseData({ id: plugin.slug, data: plugin });
        store.set({ id: plugin.slug, data, digest: generateDigest(data), rendered: await renderMarkdown(plugin.readme.description) });
      }
      logger.info(`${plugins.length} plugins from ${kit.store.indexURL}`);
    },
  },
  schema: z.object({
    id: z.string(),
    slug: z.string(),
    name: z.string(),
    version: z.string(),
    summary: z.string(),
    category: z.string(),
    publisher: z.string(),
    updated: z.string(),
    minimumStackbar: z.string().optional(),
    homepage: z.url(),
    /** The plugin's own Theme hue, from its manifest (Stackbar 0.14.0). */
    accent: z.string().optional(),
    /** An SF Symbol name. Apple's licence keeps SF Symbols off the web, so the site draws a monogram. */
    symbol: z.string().optional(),
    bundle: z.url(),
    sha256: z.string(),
    screenshot: z.url().optional(),
    surfaces: z.array(z.string()),
    capabilities: z.array(z.string()),
    readme: z.object({
      description: z.string(),
      facts: z.array(z.object({ label: z.string(), text: z.string() })),
    }),
  }),
});

export const collections = { plugins };
