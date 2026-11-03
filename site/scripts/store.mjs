// The plugin store as the site sees it: the signed index Stackbar itself
// trusts, verified with the same key, plus each plugin's README. Nothing here
// is written by hand; a plugin appears on the site once it is published.
import crypto from 'node:crypto';

/** What the signature covers: "stackbarindex/1\n" + the index without its
 *  signature as compact JSON with sorted keys (PluginIndex.signedBytes). */
export function signedBytes(index) {
  const { signature: _signature, ...unsigned } = index;
  const canonical = (value) => {
    if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
    if (value && typeof value === 'object') {
      return `{${Object.keys(value).sort().map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`).join(',')}}`;
    }
    return JSON.stringify(value);
  };
  return Buffer.from(`stackbarindex/1\n${canonical(unsigned)}`);
}

export function verifyIndex(index, publicKeyBase64) {
  if (!index.signature) throw new Error('store: the index is not signed');
  const spki = Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(publicKeyBase64, 'base64')]);
  const key = crypto.createPublicKey({ key: spki, format: 'der', type: 'spki' });
  if (!crypto.verify(null, signedBytes(index), key, Buffer.from(index.signature, 'base64'))) {
    throw new Error('store: the index signature does not verify with the navbytes key');
  }
  return index;
}

/** `io.navbytes.stackbar.plugins.world-clock` → `world-clock`. */
export const slugOf = (id) => id.split('.').at(-1);

/** The README's raw URL from the manifest homepage (a GitHub tree URL). */
export function readmeURL(homepage) {
  const match = homepage?.match(/^https:\/\/github\.com\/([^/]+\/[^/]+)\/tree\/([^/]+)\/(.+?)\/?$/);
  return match ? `https://raw.githubusercontent.com/${match[1]}/${match[2]}/${match[3]}/README.md` : null;
}

/**
 * Splits a store README (CONTRIBUTING rule 9) into its description and its
 * facts: the `- **Label:** text` bullets saying what it needs, its surfaces,
 * settings and so on. The first `# Title` is dropped; the page has its own.
 */
export function parseReadme(markdown) {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  if (lines[0]?.startsWith('# ')) lines.shift();
  const facts = [];
  const rest = [];
  const changes = [];
  const highlights = [];
  const faq = [];
  for (let i = 0; i < lines.length; i++) {
    // `## Highlights`: `### Title`, a paragraph, and an optional
    // `<!-- preview: name -->` naming the scene that pictures it.
    if (/^## Highlights\s*$/.test(lines[i])) {
      while (i + 1 < lines.length && !/^## /.test(lines[i + 1])) {
        const title = lines[++i].match(/^### (.+?)\s*$/);
        if (title) highlights.push({ title: title[1], text: '' });
        else if (highlights.length) {
          const marker = lines[i].match(/^<!--\s*preview:\s*([a-z0-9-]+)\s*-->\s*$/);
          const last = highlights[highlights.length - 1];
          if (marker) last.preview = marker[1];
          else last.text = `${last.text}\n${lines[i]}`.trim();
        }
      }
      continue;
    }
    // `## FAQ`: `### Question` then its answer.
    if (/^## (FAQ|Questions)\s*$/.test(lines[i])) {
      while (i + 1 < lines.length && !/^## /.test(lines[i + 1])) {
        const question = lines[++i].match(/^### (.+?)\s*$/);
        if (question) faq.push({ question: question[1], answer: '' });
        else if (faq.length) faq[faq.length - 1].answer = `${faq[faq.length - 1].answer}\n${lines[i]}`.trim();
      }
      continue;
    }
    // `## What's new in 1.2.0` and its bullets: release notes, newest first.
    const heading = lines[i].match(/^## What's new in (\S+)\s*$/);
    if (heading) {
      const notes = [];
      while (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
        const line = lines[++i];
        if (line.startsWith('- ')) notes.push(line.slice(2).trim());
        else if (/^\s{2,}\S/.test(line) && notes.length) notes[notes.length - 1] += ` ${line.trim()}`;
      }
      changes.push({ version: heading[1], notes });
      continue;
    }
    const fact = lines[i].match(/^- \*\*(.+?):\*\*\s*(.*)$/);
    if (!fact) { rest.push(lines[i]); continue; }
    let text = fact[2];
    while (i + 1 < lines.length && /^\s{2,}\S/.test(lines[i + 1])) text += ` ${lines[++i].trim()}`;
    facts.push({ label: fact[1], text });
  }
  return { description: rest.join('\n').trim(), facts, changes, highlights, faq };
}

/** Fetches with a few retries, since GitHub Pages sometimes drops a request. */
export async function fetchWithRetry(fetch, url, init, tries = 3) {
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(url, init);
      if (response.ok || response.status === 404 || attempt >= tries) return response;
    } catch (error) {
      if (attempt >= tries) throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 500 * attempt));
  }
}

/** Compares dotted versions numerically: negative when a is older. */
export function compareVersions(a, b) {
  const pa = String(a).split('.').map(Number);
  const pb = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d) return d;
  }
  return 0;
}

/** Whether a withdrawal covers this version: no `versions` withdraws them all. */
export function isWithdrawn(index, entry) {
  return (index.revoked ?? []).some((r) => r.id === entry.id && (!r.versions || r.versions.some((v) => compareVersions(v, entry.version) === 0)));
}

/**
 * What the site lists, like the app's store: withdrawn versions left out, then
 * one entry per plugin, its newest version. A plugin whose every version is
 * withdrawn (one retired or replaced) has no page.
 */
export function listed(index) {
  const best = new Map();
  for (const entry of index.plugins) {
    if (isWithdrawn(index, entry)) continue;
    const current = best.get(entry.id);
    if (!current || compareVersions(entry.version, current.version) > 0) best.set(entry.id, entry);
  }
  return [...best.values()];
}

export async function fetchStore({ indexURL, publicKey, fetch = globalThis.fetch, log = console.warn }) {
  const response = await fetchWithRetry(fetch, indexURL);
  if (!response.ok) throw new Error(`store: ${indexURL} answered ${response.status}`);
  const index = verifyIndex(await response.json(), publicKey);
  const base = new URL('.', indexURL);
  const renders = await fetchRenders(fetch, new URL('site.json', base).href, log);
  const seen = new Map();
  const plugins = [];
  for (const entry of listed(index)) {
    const slug = slugOf(entry.id);
    if (seen.has(slug) && seen.get(slug) !== entry.id) throw new Error(`store: ${entry.id} and ${seen.get(slug)} share the page /plugins/${slug}`);
    seen.set(slug, entry.id);
    const url = readmeURL(entry.homepage);
    let readme = { description: entry.summary ?? '', facts: [], changes: [], highlights: [], faq: [] };
    if (url) {
      const page = await fetchWithRetry(fetch, url);
      if (page.ok) readme = parseReadme(await page.text());
    }
    // A screenshot that can't be fetched leaves the page without one rather
    // than failing the whole build (the image pipeline would).
    let screenshot = entry.screenshot ? new URL(entry.screenshot, base).href : undefined;
    if (screenshot) {
      const head = await fetchWithRetry(fetch, screenshot, { method: 'HEAD' }).catch(() => undefined);
      if (!head?.ok) { log(`store: no screenshot for ${entry.id} (${head?.status ?? 'unreachable'})`); screenshot = undefined; }
    }
    const gallery = await galleryOf(fetch, renders.plugins[entry.id]?.[entry.version], base, log);
    const previews = await previewsOf(fetch, renders.previews[entry.id]?.[entry.version], base, log);
    plugins.push({
      ...entry,
      slug,
      screenshot,
      gallery,
      previews,
      bundle: new URL(entry.bundle, base).href,
      readme,
    });
  }
  return { name: index.name, generated: index.generated, plugins };
}

/** The order the gallery shows surfaces in. */
export const surfaceOrder = ['menuBar', 'panel', 'window', 'widget', 'palette', 'settings'];

/**
 * The store's site.json: renders per plugin version, and previews (sample-data
 * scenes, Stackbar 0.17.0) per plugin version, or none yet.
 */
async function fetchRenders(fetch, url, log) {
  const none = { plugins: {}, previews: {} };
  const response = await fetchWithRetry(fetch, url).catch(() => undefined);
  if (!response?.ok) { log(`store: no renders yet (${url} answered ${response?.status ?? 'nothing'})`); return none; }
  const site = await response.json();
  if (site.format !== 1) return none;
  return { plugins: site.plugins ?? {}, previews: site.previews ?? {} };
}

/** One version's previews, in the plugin's order, each with the renders that answer. */
export async function previewsOf(fetch, scenes = [], base, log = console.warn) {
  const previews = [];
  for (const scene of scenes) {
    const item = { name: scene.name, title: scene.title, surface: scene.surface ?? 'panel' };
    for (const appearance of ['light', 'dark']) {
      if (!scene[appearance]) continue;
      const url = new URL(scene[appearance], base).href;
      const head = await fetchWithRetry(fetch, url, { method: 'HEAD' }).catch(() => undefined);
      if (head?.ok) item[appearance] = url; else log(`store: missing preview ${url}`);
    }
    if (item.light || item.dark) previews.push(item);
  }
  return previews;
}

/** One version's renders, each surface's light and dark image that answers. */
export async function galleryOf(fetch, shots = {}, base, log = console.warn) {
  const gallery = [];
  const surfaces = Object.keys(shots).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
  for (const surface of surfaces) {
    const item = { surface };
    for (const appearance of ['light', 'dark']) {
      const path = shots[surface][appearance];
      if (!path) continue;
      const url = new URL(path, base).href;
      const head = await fetchWithRetry(fetch, url, { method: 'HEAD' }).catch(() => undefined);
      if (head?.ok) item[appearance] = url; else log(`store: missing render ${url}`);
    }
    if (item.light || item.dark) gallery.push(item);
  }
  return gallery;
}

const rank = (surface) => { const at = surfaceOrder.indexOf(surface); return at < 0 ? surfaceOrder.length : at; };
