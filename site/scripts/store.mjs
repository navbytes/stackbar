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

export async function fetchStore({ indexURL, publicKey, fetch = globalThis.fetch }) {
  const response = await fetch(indexURL);
  if (!response.ok) throw new Error(`store: ${indexURL} answered ${response.status}`);
  const index = verifyIndex(await response.json(), publicKey);
  const base = new URL('.', indexURL);
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
      const page = await fetch(url);
      if (page.ok) readme = parseReadme(await page.text());
    }
    plugins.push({
      ...entry,
      slug,
      screenshot: entry.screenshot ? new URL(entry.screenshot, base).href : undefined,
      bundle: new URL(entry.bundle, base).href,
      readme,
    });
  }
  return { name: index.name, generated: index.generated, plugins };
}
