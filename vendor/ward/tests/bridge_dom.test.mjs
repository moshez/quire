// bridge_dom.test.mjs — DOM protocol tests

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('DOM operations', () => {
  it('creates elements and sets text after timer fires', async () => {
    const { root, done } = await createWardInstance();

    // Wait for 1s timer to fire + some margin
    await new Promise(r => setTimeout(r, 1500));

    // Root should have a <p> child with text "hello-ward"
    const p = root.querySelector('p');
    assert.ok(p, 'expected <p> element');
    assert.equal(p.textContent, 'hello-ward');

    // Root should have a <span> child with text "it-works"
    const span = root.querySelector('span');
    assert.ok(span, 'expected <span> element');
    assert.equal(span.textContent, 'it-works');
  });

  it('sets attributes on elements', async () => {
    const { root } = await createWardInstance();

    // Wait for 1s timer to fire + some margin
    await new Promise(r => setTimeout(r, 1500));

    const span = root.querySelector('span');
    assert.ok(span, 'expected <span> element');
    assert.equal(span.getAttribute('class'), 'demo');
  });
});
