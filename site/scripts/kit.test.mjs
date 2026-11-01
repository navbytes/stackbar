import test from 'node:test';
import assert from 'node:assert/strict';
import { readDesign, readStore, readVersion, readBrand, designCSS } from './kit.mjs';

test('the design system is read from StackbarKit', () => {
  const design = readDesign();
  assert.equal(Object.keys(design.hues).length, 11);
  assert.equal(design.aliases.success, 'green');
  assert.match(designCSS(design), /--kit-violet: light-dark\(#[0-9A-F]{6}, #[0-9A-F]{6}\);/i);
});

test('a reshaped Design.swift fails loudly instead of drifting', () => {
  assert.throws(() => readDesign('public enum Space {}'), /couldn't read/);
});

test('the store and version are read from the app', () => {
  assert.match(readStore().indexURL, /index\.json$/);
  assert.match(readVersion(), /^\d+\.\d+\.\d+$/);
});

test('the brand gradients come from the app icon', () => {
  const brand = readBrand();
  assert.equal(Object.keys(brand).length, 3);
  assert.match(designCSS(readDesign(), brand), /--brand-3-to: #[0-9A-F]{6};/i);
});
