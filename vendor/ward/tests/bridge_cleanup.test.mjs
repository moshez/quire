// bridge_cleanup.test.mjs — Verify nodes Map cleanup on REMOVE_CHILD

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('DOM remove_child cleanup', () => {
  it('removes node 3 from nodes Map after REMOVE_CHILD', async () => {
    const { nodes } = await createWardInstance();

    // Wait for 1s timer to fire
    await new Promise(r => setTimeout(r, 1500));

    // Node 3 was created then removed via ward_dom_stream_remove_child.
    // The bridge should delete it from the nodes Map.
    assert.ok(!nodes.has(3), 'node 3 should be removed from nodes Map');

    // Nodes 0 (root), 1 (p), 2 (span), 4 (img) should still exist
    assert.ok(nodes.has(0), 'root node 0 should exist');
    assert.ok(nodes.has(1), 'node 1 (p) should exist');
    assert.ok(nodes.has(2), 'node 2 (span) should exist');
    assert.ok(nodes.has(4), 'node 4 (img) should exist');
    assert.equal(nodes.size, 4, 'nodes Map should have exactly 4 entries');
  });
});
