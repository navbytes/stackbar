import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { verifyIndex, parseReadme, readmeURL, slugOf, fetchStore, galleryOf } from './store.mjs';
import { readStore } from './kit.mjs';

// A copy of the published index, signed by the navbytes key.
const index = JSON.parse(fs.readFileSync(new URL('./fixtures/index.json', import.meta.url)));
const { publicKey } = readStore();

test('the published index verifies with the key the app trusts', () => {
  assert.equal(verifyIndex(index, publicKey), index);
});

test('a changed index does not verify', () => {
  const tampered = structuredClone(index);
  tampered.plugins[0].summary = 'Something else';
  assert.throws(() => verifyIndex(tampered, publicKey), /does not verify/);
  assert.throws(() => verifyIndex({ ...index, signature: undefined }, publicKey), /not signed/);
});

test('slugs and README URLs come from the manifest', () => {
  assert.equal(slugOf('io.navbytes.stackbar.plugins.world-clock'), 'world-clock');
  assert.equal(readmeURL('https://github.com/navbytes/stackbar-plugins/tree/main/Productivity/Pomodoro'),
    'https://raw.githubusercontent.com/navbytes/stackbar-plugins/main/Productivity/Pomodoro/README.md');
  assert.equal(readmeURL('https://example.com'), null);
});

test('a README splits into its description and facts', () => {
  const { description, facts } = parseReadme('# Pomodoro\n\nA focus timer.\n\n- **Needs:** nothing.\n- **In the panel:** the tag chip\n  cycles tags.\n');
  assert.equal(description, 'A focus timer.');
  assert.deepEqual(facts, [{ label: 'Needs', text: 'nothing.' }, { label: 'In the panel', text: 'the tag chip cycles tags.' }]);
});

test('fetchStore resolves URLs, reads READMEs and refuses a forged index', async () => {
  let flaky = 1;
  const fake = async (url) => {
    if (url.endsWith('index.json')) {
      if (flaky-- > 0) return { ok: false, status: 503 };   // one dropped request, retried
      return { ok: true, json: async () => index };
    }
    if (url.endsWith('site.json')) return { ok: false, status: 404 };
    if (url.endsWith('.png')) return url.includes('clipboard') ? { ok: false, status: 404 } : { ok: true, status: 200 };
    return { ok: true, text: async () => '# X\n\nLong text.\n\n- **Needs:** nothing.' };
  };
  const warnings = [];
  const store = await fetchStore({ indexURL: 'https://navbytes.github.io/stackbar-plugins/index.json', publicKey, fetch: fake, log: (m) => warnings.push(m) });
  assert.equal(store.plugins.length, index.plugins.length);
  const first = store.plugins[0];
  assert.match(first.bundle, /^https:\/\/navbytes\.github\.io\/stackbar-plugins\/.+\.stackbarplugin$/);
  assert.equal(first.readme.description, 'Long text.');
  // A missing screenshot drops the image, not the build.
  assert.equal(store.plugins.find((p) => p.slug === 'clipboard').screenshot, undefined);
  assert.match(warnings.join(), /no screenshot for io\.navbytes\.stackbar\.clipboard/);
  assert.ok(store.plugins.find((p) => p.slug === 'pomodoro').screenshot);
  const forged = async () => ({ ok: true, json: async () => ({ ...index, name: 'Evil' }) });
  await assert.rejects(fetchStore({ indexURL: 'https://x/index.json', publicKey, fetch: forged }), /does not verify/);
});

test('a gallery lists surfaces in order and drops renders that are missing', async () => {
  const base = new URL('https://navbytes.github.io/stackbar-plugins/');
  const shots = {
    panel: { light: 'S/shots/a/1/light/panel.png', dark: 'S/shots/a/1/dark/panel.png' },
    menuBar: { light: 'S/shots/a/1/light/menuBar.png' },
    window: { dark: 'S/shots/a/1/dark/window.png' },
  };
  const fake = async (url) => (url.includes('window') ? { ok: false, status: 404 } : { ok: true, status: 200 });
  const warnings = [];
  const gallery = await galleryOf(fake, shots, base, (m) => warnings.push(m));
  assert.deepEqual(gallery.map((g) => g.surface), ['menuBar', 'panel']);
  assert.equal(gallery[1].dark, 'https://navbytes.github.io/stackbar-plugins/S/shots/a/1/dark/panel.png');
  assert.equal(gallery[0].dark, undefined);
  assert.match(warnings.join(), /missing render .*window/);
  assert.deepEqual(await galleryOf(fake, undefined, base), []);
});
