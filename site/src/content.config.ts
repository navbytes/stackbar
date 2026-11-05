import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';
import { fetchStore } from '../scripts/store.mjs';
import { readDocs } from '../scripts/docs.mjs';
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
    /** Renders of this version's surfaces, from the store's site.json. */
    gallery: z.array(z.object({ surface: z.string(), light: z.url().optional(), dark: z.url().optional() })),
    /** Scenes with sample data (Stackbar 0.17.0), in the plugin's order; `hero` first by convention. */
    /** A demo loop (animated PNG) of one surface, and how long a pass lasts. */
    demo: z.object({ surface: z.string(), seconds: z.number(), light: z.url().optional(), dark: z.url().optional() }).optional(),
    previews: z.array(z.object({ name: z.string(), title: z.string(), surface: z.string(), light: z.url().optional(), dark: z.url().optional() })).default([]),
    capabilities: z.array(z.string()),
    readme: z.object({
      description: z.string(),
      facts: z.array(z.object({ label: z.string(), text: z.string() })),
      /** `## What's new in <version>` sections, newest first. */
      changes: z.array(z.object({ version: z.string(), notes: z.array(z.string()) })).default([]),
      /** `## Highlights`: feature stories, each optionally pictured by a preview. */
      highlights: z.array(z.object({ title: z.string(), text: z.string(), preview: z.string().optional() })).default([]),
      /** `## FAQ`: questions and answers. */
      faq: z.array(z.object({ question: z.string(), answer: z.string() })).default([]),
    }),
  }),
});

// The docs: the user guide in src/docs/*.md and the plugin reference, which is
// the repository's llms.txt (so it never drifts from what agents read).
const docs = defineCollection({
  loader: {
    name: 'stackbar-docs',
    async load({ store, parseData, renderMarkdown, generateDigest, watcher }) {
      store.clear();
      const base = import.meta.env.BASE_URL.replace(/\/$/, '');
      for (const doc of readDocs()) {
        const { body, ...fields } = doc;
        const data = await parseData({ id: doc.slug, data: fields });
        const rendered = await renderMarkdown(body);
        // Links in the Markdown are written from the site root.
        rendered.html = rendered.html.replace(/href="\/(?!\/)/g, `href="${base}/`);
        store.set({ id: doc.slug, data, body, digest: generateDigest({ data, body }), rendered });
      }
      watcher?.add('src/docs');
    },
  },
  schema: z.object({
    slug: z.string(),
    title: z.string(),
    description: z.string(),
    group: z.enum(['Use Stackbar', 'Build plugins']),
    order: z.number(),
  }),
});

export const collections = { plugins, docs };
