import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { verifyIndex, parseReadme, readmeURL, slugOf, fetchStore } from './store.mjs';
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
  const fake = async (url) => url.endsWith('index.json')
    ? { ok: true, json: async () => index }
    : { ok: true, text: async () => '# X\n\nLong text.\n\n- **Needs:** nothing.' };
  const store = await fetchStore({ indexURL: 'https://navbytes.github.io/stackbar-plugins/index.json', publicKey, fetch: fake });
  assert.equal(store.plugins.length, index.plugins.length);
  const first = store.plugins[0];
  assert.match(first.bundle, /^https:\/\/navbytes\.github\.io\/stackbar-plugins\/.+\.stackbarplugin$/);
  assert.equal(first.readme.description, 'Long text.');
  const forged = async () => ({ ok: true, json: async () => ({ ...index, name: 'Evil' }) });
  await assert.rejects(fetchStore({ indexURL: 'https://x/index.json', publicKey, fetch: forged }), /does not verify/);
});
