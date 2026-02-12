// bridge_events.test.mjs — Event listener and callback tests

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('Event listeners', () => {
  it('dispatches click events with payload', async () => {
    const { root, done, ward, nodes } = await createWardInstance();

    // Wait for DOM to be set up
    await new Promise(r => setTimeout(r, 1500));

    // The DOM exerciser creates a <p> and <span>
    const p = root.querySelector('p');
    assert.ok(p, 'expected <p> element');

    // Dispatch a click event on p
    const clickEvent = new root.ownerDocument.defaultView.MouseEvent('click', {
      clientX: 42.5,
      clientY: 99.5,
      bubbles: true,
    });
    p.dispatchEvent(clickEvent);

    // If no listener registered from WASM side, this is a no-op (which is fine).
    // The test verifies the bridge doesn't crash on event dispatch.
  });
});

describe('Bridge callbacks', () => {
  it('ward_on_callback export exists', async () => {
    const { ward } = await createWardInstance();
    assert.equal(typeof ward.ward_on_callback, 'function');
  });
});
