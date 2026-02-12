// bridge_promise.test.mjs — Promise chain tests

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('Promise chain', () => {
  it('done promise resolves without error', async () => {
    const { done } = await createWardInstance();
    // The exerciser chains: timer → DOM → IDB put → get → delete → timer → exit
    // If any step fails, done will never resolve (test will timeout)
    await done;
  });

  it('final DOM state matches expected after full chain', async () => {
    const { root, done } = await createWardInstance();
    await done;

    // After the full chain completes, DOM should have the elements created
    // in the first timer callback (before dom_fini clears state)
    const p = root.querySelector('p');
    assert.ok(p, 'expected <p> element');
    assert.equal(p.textContent, 'hello-ward');

    const span = root.querySelector('span');
    assert.ok(span, 'expected <span> element');
    assert.equal(span.textContent, 'it-works');
    assert.equal(span.getAttribute('class'), 'demo');
  });
});
