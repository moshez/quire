// bridge_image.test.mjs — Image display tests

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('Image display', () => {
  it('sets blob URL on img element after timer fires', async () => {
    const { root, done } = await createWardInstance();

    // Wait for 1s timer to fire + some margin
    await new Promise(r => setTimeout(r, 1500));

    const img = root.querySelector('img');
    assert.ok(img, 'expected <img> element');
    assert.ok(img.src, 'expected src attribute on <img>');
    assert.ok(img.src.startsWith('blob:'), `expected blob: URL, got ${img.src}`);
  });
});
