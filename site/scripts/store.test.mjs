import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { verifyIndex, parseReadme, readmeURL, slugOf, fetchStore, galleryOf, previewsOf, demoOf, listed } from './store.mjs';
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

test('the site lists each plugin once, newest first, and none that are withdrawn', () => {
  const entry = (id, version) => ({ id, version });
  const listing = listed({
    plugins: [entry('a', '1.2.0'), entry('a', '1.10.0'), entry('a', '1.9.0'), entry('gone', '1.0.0'), entry('b', '2.0.0'), entry('b', '2.1.0')],
    revoked: [{ id: 'gone', reason: 'Merged into a' }, { id: 'b', versions: ['2.1.0'], reason: 'Broken' }],
  });
  assert.deepEqual(listing, [entry('a', '1.10.0'), entry('b', '2.0.0')]);
});

test('a README splits into its description and facts', () => {
  const { description, facts } = parseReadme('# Pomodoro\n\nA focus timer.\n\n- **Needs:** nothing.\n- **In the panel:** the tag chip\n  cycles tags.\n');
  assert.equal(description, 'A focus timer.');
  assert.deepEqual(facts, [{ label: 'Needs', text: 'nothing.' }, { label: 'In the panel', text: 'the tag chip cycles tags.' }]);
});

test("a README's What's new sections become release notes, not description", () => {
  const { description, facts, changes } = parseReadme("# T\n\nIntro.\n\n- **Needs:** nothing.\n\n## What's new in 1.2.0\n\n- Faster\n  and calmer.\n- **Fixed:** a crash.\n\n## What's new in 1.1.0\n\n- First.\n");
  assert.equal(description, 'Intro.');
  assert.deepEqual(facts, [{ label: 'Needs', text: 'nothing.' }]);
  assert.deepEqual(changes, [{ version: '1.2.0', notes: ['Faster and calmer.', '**Fixed:** a crash.'] }, { version: '1.1.0', notes: ['First.'] }]);
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
  assert.equal(store.plugins.length, new Set(index.plugins.map((p) => p.id)).size);
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

test("a README's Highlights and FAQ become stories and questions, not description", () => {
  const readme = parseReadme([
    '# Clipboard', '', 'Everything you copy.', '',
    '## Highlights', '',
    '### Search everything', 'Type to filter.', 'Return pastes.', '<!-- preview: search -->', '',
    '### Secrets stay secret', 'Tokens are masked.', '',
    '## FAQ', '', '### Does it sync?', 'No, it stays on this Mac.', '',
    "## What's new in 1.5.0", '', '- Previews.', '',
  ].join('\n'));
  assert.equal(readme.description, 'Everything you copy.');
  assert.deepEqual(readme.highlights, [
    { title: 'Search everything', text: 'Type to filter.\nReturn pastes.', preview: 'search' },
    { title: 'Secrets stay secret', text: 'Tokens are masked.' },
  ]);
  assert.deepEqual(readme.faq, [{ question: 'Does it sync?', answer: 'No, it stays on this Mac.' }]);
  assert.deepEqual(readme.changes, [{ version: '1.5.0', notes: ['Previews.'] }]);
});

test('previews keep their order and drop renders that are missing', async () => {
  const base = new URL('https://navbytes.github.io/stackbar-plugins/');
  const scenes = [
    { name: 'hero', title: 'In use', surface: 'panel', light: 'S/shots/a/1/light/previews/hero/panel.png', dark: 'S/shots/a/1/dark/previews/hero/panel.png' },
    { name: 'gone', title: 'Missing', surface: 'window', dark: 'S/shots/a/1/dark/previews/gone/window.png' },
  ];
  const fake = async (url) => (url.includes('gone') ? { ok: false, status: 404 } : { ok: true, status: 200 });
  const warnings = [];
  const previews = await previewsOf(fake, scenes, base, (m) => warnings.push(m));
  assert.deepEqual(previews, [{ name: 'hero', title: 'In use', surface: 'panel',
    light: 'https://navbytes.github.io/stackbar-plugins/S/shots/a/1/light/previews/hero/panel.png',
    dark: 'https://navbytes.github.io/stackbar-plugins/S/shots/a/1/dark/previews/hero/panel.png' }]);
  assert.match(warnings.join(), /missing preview .*gone/);
  assert.deepEqual(await previewsOf(fake, undefined, base), []);
});

test('a demo keeps the renders that answer and how long it lasts', async () => {
  const base = new URL('https://navbytes.github.io/stackbar-plugins/');
  const demo = { surface: 'panel', seconds: 6.75, light: 'S/shots/a/1/light/demo/abc/panel.png', dark: 'S/shots/a/1/dark/demo/abc/gone.png' };
  const fake = async (url) => (url.includes('gone') ? { ok: false, status: 404 } : { ok: true, status: 200 });
  const warnings = [];
  assert.deepEqual(await demoOf(fake, demo, base, (m) => warnings.push(m)), {
    surface: 'panel', seconds: 6.75, light: 'https://navbytes.github.io/stackbar-plugins/S/shots/a/1/light/demo/abc/panel.png' });
  assert.match(warnings.join(), /missing demo .*gone/);
  assert.equal(await demoOf(fake, undefined, base), undefined);
  assert.equal(await demoOf(async () => ({ ok: false, status: 404 }), demo, base, () => {}), undefined);
});
