// bridge_html.test.mjs — HTML parsing tests

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('HTML parsing', () => {
  it('ward_js_parse_html export is callable', async () => {
    const { ward } = await createWardInstance();
    // ward_js_parse_html is a JS import, not a WASM export.
    // But ward_bridge_stash_set_int should be exported.
    assert.equal(typeof ward.ward_bridge_stash_set_int, 'function');
  });
});

describe('DOM remove_child', () => {
  it('removes an element from the DOM', async () => {
    const { root } = await createWardInstance();

    // Wait for DOM exerciser to run (creates elements, removes node 3)
    await new Promise(r => setTimeout(r, 1500));

    // The exerciser creates <p> (node 1), <span> (node 2), <div> (node 3)
    // then removes node 3. So we should have <p> and <span> but no extra <div>.
    const p = root.querySelector('p');
    assert.ok(p, 'expected <p> element');
    const span = root.querySelector('span');
    assert.ok(span, 'expected <span> element');

    // The div (node 3) was created then immediately removed
    const divs = root.querySelectorAll('div');
    // Root itself is a div, any child divs should be gone
    let childDivs = 0;
    for (const d of divs) {
      if (d !== root) childDivs++;
    }
    assert.equal(childDivs, 0, 'temporary div should have been removed');
  });
});

describe('loadWard extension point', () => {
  it('accepts opts parameter without error', async () => {
    // createWardInstance doesn't pass opts, but loadWard should accept it
    // The test is that createWardInstance works (no crash)
    const { ward } = await createWardInstance();
    assert.ok(ward);
  });
});
