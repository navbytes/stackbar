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
  for (let i = 0; i < lines.length; i++) {
    const fact = lines[i].match(/^- \*\*(.+?):\*\*\s*(.*)$/);
    if (!fact) { rest.push(lines[i]); continue; }
    let text = fact[2];
    while (i + 1 < lines.length && /^\s{2,}\S/.test(lines[i + 1])) text += ` ${lines[++i].trim()}`;
    facts.push({ label: fact[1], text });
  }
  return { description: rest.join('\n').trim(), facts };
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

export async function fetchStore({ indexURL, publicKey, fetch = globalThis.fetch, log = console.warn }) {
  const response = await fetchWithRetry(fetch, indexURL);
  if (!response.ok) throw new Error(`store: ${indexURL} answered ${response.status}`);
  const index = verifyIndex(await response.json(), publicKey);
  const base = new URL('.', indexURL);
  const renders = await fetchRenders(fetch, new URL('site.json', base).href, log);
  const revoked = new Set((index.revoked ?? []).map((r) => `${r.id}@${r.version}`));
  const seen = new Map();
  const plugins = [];
  for (const entry of index.plugins) {
    if (revoked.has(`${entry.id}@${entry.version}`)) continue;
    const slug = slugOf(entry.id);
    if (seen.has(slug) && seen.get(slug) !== entry.id) throw new Error(`store: ${entry.id} and ${seen.get(slug)} share the page /plugins/${slug}`);
    seen.set(slug, entry.id);
    const url = readmeURL(entry.homepage);
    let readme = { description: entry.summary ?? '', facts: [] };
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
    const gallery = await galleryOf(fetch, renders[entry.id]?.[entry.version], base, log);
    plugins.push({
      ...entry,
      slug,
      screenshot,
      gallery,
      bundle: new URL(entry.bundle, base).href,
      readme,
    });
  }
  return { name: index.name, generated: index.generated, plugins };
}

/** The order the gallery shows surfaces in. */
export const surfaceOrder = ['menuBar', 'panel', 'window', 'widget', 'palette', 'settings'];

/** The store's site.json (renders per plugin version), or none yet. */
async function fetchRenders(fetch, url, log) {
  const response = await fetchWithRetry(fetch, url).catch(() => undefined);
  if (!response?.ok) { log(`store: no renders yet (${url} answered ${response?.status ?? 'nothing'})`); return {}; }
  const site = await response.json();
  return site.format === 1 && site.plugins ? site.plugins : {};
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
