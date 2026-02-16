// crash_repro_runner.mjs — Run crash reproduction exerciser
// Tests REMOVE_CHILDREN + async re-render cycles with images.

import 'fake-indexeddb/auto';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';
import { loadWard } from './../lib/ward_bridge.mjs';

const dom = new JSDOM('<!DOCTYPE html><div id="ward-root"></div>');
const document = dom.window.document;
const root = document.getElementById('ward-root');

async function main() {
  console.log('==> Crash repro exerciser started');
  const wasmBytes = await readFile(new URL('../build/crash_repro.wasm', import.meta.url));

  const { exports, nodes, done } = await loadWard(wasmBytes, root);

  // Print DOM state periodically
  const interval = setInterval(() => {
    const container = root.firstElementChild;
    console.log(`  nodes: ${nodes.size}, children: ${container?.childElementCount ?? 0}`);
  }, 150);

  await done;
  clearInterval(interval);

  console.log('\n==> Final state:');
  console.log(`  nodes Map size: ${nodes.size}`);
  const container = root.firstElementChild;
  console.log(`  container children: ${container?.childElementCount ?? 0}`);
  console.log(`  Root innerHTML length: ${root.innerHTML.length}`);
  console.log('\n==> Crash repro exerciser completed successfully');
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
