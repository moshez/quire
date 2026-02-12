// bridge_load.test.mjs — WASM instantiation tests

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('loadWard', () => {
  it('returns exports with memory', async () => {
    const { ward } = await createWardInstance();
    assert.ok(ward.memory instanceof WebAssembly.Memory);
  });

  it('node registry has root element at id 0', async () => {
    const { nodes } = await createWardInstance();
    assert.ok(nodes.get(0));
  });

  it('exports ward_node_init function', async () => {
    const { ward } = await createWardInstance();
    assert.equal(typeof ward.ward_node_init, 'function');
  });
});
