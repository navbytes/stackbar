import test from 'node:test';
import assert from 'node:assert/strict';
import { authoringDoc, parseDoc, readDocs } from './docs.mjs';

test('front matter is split from the body, numbers parsed', () => {
  const doc = parseDoc('---\ntitle: A: b\norder: 2\n---\n\nHello\n', 'a');
  assert.equal(doc.title, 'A: b');
  assert.equal(doc.order, 2);
  assert.equal(doc.body, '\nHello\n');
});

test('a doc without front matter fails the build', () => {
  assert.throws(() => parseDoc('Hello', 'a'), /no front matter/);
});

test('the reference drops llms.txt\'s own title', () => {
  assert.equal(authoringDoc('# Stackbar plugin authoring\n\nText\n').body, 'Text\n');
});

test('every doc has a title, a description and a known group, in order', () => {
  const docs = readDocs();
  assert.ok(docs.some((d) => d.slug === 'authoring'));
  for (const d of docs) {
    assert.ok(d.title && d.description, d.slug);
    assert.ok(['Use Stackbar', 'Build plugins'].includes(d.group), d.slug);
  }
  assert.equal(docs[0].slug, 'getting-started');
});
