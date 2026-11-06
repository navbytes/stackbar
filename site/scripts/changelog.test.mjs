import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseChangelog, readChangelog } from './changelog.mjs';

test('splits released versions and skips Unreleased', () => {
  const releases = parseChangelog('# Changelog\n\nIntro\n\n## Unreleased\n- soon\n\n## 1.2.0\n### New\n- a\n\n## 1.1.0 (2026-01-01)\n- b\n');
  assert.deepEqual(releases.map((r) => r.version), ['1.2.0', '1.1.0']);
  assert.equal(releases[0].body, '### New\n- a');
});

test('the real changelog has releases', () => {
  assert.ok(readChangelog().length > 0);
});
