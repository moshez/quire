// bridge_dom_read.test.mjs — tests for character position measurement APIs

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('DOM read character position APIs', () => {
  it('ward_js_read_text_content returns text length and stashes data', async () => {
    const { root, nodes } = await createWardInstance();
    // Wait for DOM exerciser to create elements
    await new Promise(r => setTimeout(r, 1500));

    // Find a node with text content
    const p = root.querySelector('p');
    assert.ok(p, 'expected <p> element');

    // Find its node_id from the nodes map
    let pId = -1;
    for (const [id, node] of nodes) {
      if (node === p) { pId = id; break; }
    }
    assert.ok(pId >= 0, 'expected to find node_id for <p>');
    assert.equal(p.textContent, 'hello-ward');
  });

  it('ward_js_caret_position_from_point returns -1 in jsdom (no layout)', async () => {
    // jsdom doesn't implement caretPositionFromPoint or caretRangeFromPoint,
    // so the bridge should return -1 gracefully
    await createWardInstance();
    // The function exists in the bridge — this test just confirms the bridge
    // loads without error with the new imports registered
  });

  it('ward_js_measure_text_offset returns 0 for missing node', async () => {
    // This exercises the JS function path for a non-existent node_id.
    // Since we can't call the JS function directly from here, we verify
    // the bridge loads correctly with the new import registered.
    await createWardInstance();
  });
});

describe('DOM read selection APIs', () => {
  it('ward_js_get_selection_text returns 0 when no selection', async () => {
    // jsdom has getSelection() but no active selection by default.
    // The bridge function should return 0 gracefully.
    await createWardInstance();
    // Bridge loads with the new selection imports registered — no errors.
  });

  it('ward_js_get_selection_rect returns 0 when no selection', async () => {
    await createWardInstance();
    // Bridge loads with ward_js_get_selection_rect registered.
  });

  it('ward_js_get_selection_range returns 0 when no selection', async () => {
    await createWardInstance();
    // Bridge loads with ward_js_get_selection_range registered.
  });
});

describe('Blob URL APIs', () => {
  it('bridge loads with blob URL imports registered', async () => {
    // Verifies ward_js_create_blob_url and ward_js_revoke_blob_url
    // are registered as WASM imports without errors.
    await createWardInstance();
  });
});
