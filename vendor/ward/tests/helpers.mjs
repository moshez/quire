// helpers.mjs — shared test utilities for ward bridge tests

import 'fake-indexeddb/auto';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';
import { loadWard } from './../lib/ward_bridge.mjs';

/**
 * Create a fresh ward instance with jsdom backing.
 * Returns { ward, root, dom, done } where:
 * - ward: WASM exports
 * - root: the root DOM element
 * - dom: the jsdom instance
 * - done: promise that resolves when ward calls ward_exit
 */
export async function createWardInstance() {
  const dom = new JSDOM('<!DOCTYPE html><div id="ward-root"></div>');
  const root = dom.window.document.getElementById('ward-root');

  const wasmBytes = await readFile(
    new URL('../build/node_ward.wasm', import.meta.url)
  );

  const { exports, nodes, done } = await loadWard(wasmBytes, root);

  return { ward: exports, root, dom, nodes, done };
}
