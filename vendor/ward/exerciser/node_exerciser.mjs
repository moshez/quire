// node_exerciser.mjs — Node.js exerciser for ward DOM
// Provides jsdom as the document, then verifies ward's DOM output.

import 'fake-indexeddb/auto';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';
import { loadWard } from './../lib/ward_bridge.mjs';

const dom = new JSDOM('<!DOCTYPE html><div id="ward-root"></div>');
const document = dom.window.document;
const root = document.getElementById('ward-root');

async function main() {
  console.log('==> Node DOM exerciser started');
  const wasmBytes = await readFile(new URL('../build/node_ward.wasm', import.meta.url));
  const { done } = await loadWard(wasmBytes, root);

  // Print DOM at 2 seconds to verify elements were created
  setTimeout(() => {
    console.log('\n==> DOM at 2s:');
    console.log(root.innerHTML);
  }, 2000);

  await done;
  console.log('\n==> Final DOM state:');
  console.log(root.innerHTML);
  console.log('\n==> Node DOM exerciser completed');
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
