// bridge_wasm.test.mjs -- tests for ward.wasm (wasm_exerciser functions)

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

async function loadSimpleWasm() {
  const wasmBytes = await readFile(
    new URL('../build/ward.wasm', import.meta.url)
  );
  const { instance } = await WebAssembly.instantiate(wasmBytes, {});
  return instance.exports;
}

describe('ward.wasm exerciser', () => {
  it('ward_test_raw returns 1', async () => {
    const exports = await loadSimpleWasm();
    assert.equal(exports.ward_test_raw(), 1);
  });

  it('ward_test_borrow returns 42', async () => {
    const exports = await loadSimpleWasm();
    assert.equal(exports.ward_test_borrow(), 42);
  });

  it('ward_test_typed returns 183', async () => {
    const exports = await loadSimpleWasm();
    assert.equal(exports.ward_test_typed(), 183);
  });

  it('ward_test_safe_text returns 196', async () => {
    const exports = await loadSimpleWasm();
    assert.equal(exports.ward_test_safe_text(), 196);
  });

  it('ward_test_large_alloc triggers memory.grow and returns 391', async () => {
    const exports = await loadSimpleWasm();
    // Initial memory is 16MB (256 pages). Two 12MB allocations force memory.grow.
    const initialPages = exports.memory.buffer.byteLength / 65536;
    const result = exports.ward_test_large_alloc();
    const finalPages = exports.memory.buffer.byteLength / 65536;
    assert.equal(result, 391);
    assert.ok(finalPages > initialPages,
      `memory should have grown: ${initialPages} -> ${finalPages} pages`);
  });
});
