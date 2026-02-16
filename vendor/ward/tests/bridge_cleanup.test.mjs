// bridge_cleanup.test.mjs — Minimal reproduction of REMOVE_CHILDREN memory leak
//
// Demonstrates that ward_bridge.mjs case 3 (REMOVE_CHILDREN) leaks entries
// in the `nodes` Map and `blobUrls` Map. After clearing a container's
// children via innerHTML='', descendant node references remain in the Map
// forever, preventing garbage collection of detached DOM elements.
//
// See: ward-crash-bug-report.md

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

describe('REMOVE_CHILDREN cleanup (ward bridge bug)', () => {

  it('nodes Map leaks entries after REMOVE_CHILDREN', () => {
    // Simulate the exact behavior of wardDomFlush cases 4 and 3
    // from ward_bridge.mjs:
    //   case 4 (CREATE_ELEMENT): nodes.set(nodeId, el)
    //   case 3 (REMOVE_CHILDREN): el.innerHTML = ''
    //                              (nodes Map NOT cleaned up — BUG)

    const dom = new JSDOM('<!DOCTYPE html><div id="root"></div>');
    const document = dom.window.document;
    const root = document.getElementById('root');

    // Mirror bridge's node registry
    const nodes = new Map();
    nodes.set(0, root);

    const CYCLES = 100;
    const CHILDREN_PER_CYCLE = 50;

    for (let cycle = 0; cycle < CYCLES; cycle++) {
      // CREATE_ELEMENT for children (bridge case 4)
      for (let i = 0; i < CHILDREN_PER_CYCLE; i++) {
        const nodeId = 1000 + cycle * CHILDREN_PER_CYCLE + i;
        const el = document.createElement('p');
        nodes.set(nodeId, el);
        root.appendChild(el);
      }

      // REMOVE_CHILDREN (bridge case 3) — current behavior
      // This is the exact code from ward_bridge.mjs line 101-105:
      //   const el = nodes.get(nodeId);
      //   if (el) el.innerHTML = '';
      // Note: NO cleanup of nodes Map entries!
      root.innerHTML = '';
    }

    // After 100 cycles x 50 children = 5000 child entries leaked
    // Plus 1 entry for root = 5001 total
    // If cleanup worked: nodes.size would be 1 (just root, since last
    // cycle's children were removed too)
    const leaked = nodes.size - 1; // subtract root
    assert.ok(leaked >= CYCLES * CHILDREN_PER_CYCLE,
      `BUG CONFIRMED: ${leaked} leaked node entries in Map ` +
      `(expected 0 after cleanup, got ${leaked}). ` +
      `Each REMOVE_CHILDREN cycle leaks ${CHILDREN_PER_CYCLE} entries. ` +
      `These hold references to detached DOM elements, preventing GC.`);
  });

  it('blobUrls leak after REMOVE_CHILDREN on image containers', () => {
    // When <img> elements have blob URLs set via wardJsSetImageSrc,
    // REMOVE_CHILDREN clears the DOM but never revokes the blob URLs
    // or removes their entries from the blobUrls Map.

    const dom = new JSDOM('<!DOCTYPE html><div id="root"></div>');
    const document = dom.window.document;
    const root = document.getElementById('root');

    const nodes = new Map();
    const blobUrls = new Map();
    nodes.set(0, root);

    const CYCLES = 20;
    const IMAGES_PER_CYCLE = 10;

    for (let cycle = 0; cycle < CYCLES; cycle++) {
      // Create img elements with blob URLs (simulates wardJsSetImageSrc)
      for (let i = 0; i < IMAGES_PER_CYCLE; i++) {
        const nodeId = 1000 + cycle * IMAGES_PER_CYCLE + i;
        const el = document.createElement('img');
        nodes.set(nodeId, el);
        root.appendChild(el);
        // wardJsSetImageSrc stores: blobUrls.set(nodeId, url)
        blobUrls.set(nodeId, `blob:fake-url-${nodeId}`);
      }

      // REMOVE_CHILDREN — does NOT walk descendants to revoke blob URLs
      root.innerHTML = '';
      // Compare with REMOVE_CHILD (case 5) which does:
      //   const oldUrl = blobUrls.get(nodeId);
      //   if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(nodeId); }
    }

    const leakedUrls = blobUrls.size;
    assert.ok(leakedUrls >= CYCLES * IMAGES_PER_CYCLE,
      `BUG CONFIRMED: ${leakedUrls} leaked blob URL entries ` +
      `(expected 0 after cleanup). ` +
      `Each blob URL holds a reference to its underlying Blob data in memory. ` +
      `Over ${CYCLES} chapter transitions with ${IMAGES_PER_CYCLE} images each, ` +
      `this accumulates ${leakedUrls} unrevoked blob URLs.`);
  });

  it('proposed fix: REMOVE_CHILDREN should clean up descendants', () => {
    // Demonstrates the correct behavior after the fix is applied.
    // This test should PASS after fixing ward_bridge.mjs case 3.

    const dom = new JSDOM('<!DOCTYPE html><div id="root"></div>');
    const document = dom.window.document;
    const root = document.getElementById('root');

    const nodes = new Map();
    const blobUrls = new Map();
    nodes.set(0, root);

    // Helper: proposed fix for REMOVE_CHILDREN
    function removeChildrenFixed(parentId) {
      const el = nodes.get(parentId);
      if (!el) return;

      // Walk all nodes and remove descendants of this parent
      const toRemove = [];
      for (const [id, node] of nodes) {
        if (id !== parentId && el.contains(node)) {
          toRemove.push(id);
        }
      }
      for (const id of toRemove) {
        const oldUrl = blobUrls.get(id);
        if (oldUrl) {
          // URL.revokeObjectURL(oldUrl); // Can't call in jsdom, but would revoke
          blobUrls.delete(id);
        }
        nodes.delete(id);
      }
      el.innerHTML = '';
    }

    const CYCLES = 100;
    const CHILDREN_PER_CYCLE = 50;

    for (let cycle = 0; cycle < CYCLES; cycle++) {
      for (let i = 0; i < CHILDREN_PER_CYCLE; i++) {
        const nodeId = 1000 + cycle * CHILDREN_PER_CYCLE + i;
        const el = document.createElement('p');
        nodes.set(nodeId, el);
        root.appendChild(el);
        if (i % 5 === 0) {
          blobUrls.set(nodeId, `blob:fake-${nodeId}`);
        }
      }

      // Use the fixed version
      removeChildrenFixed(0);
    }

    // After cleanup: only root remains
    assert.equal(nodes.size, 1,
      `After fix: nodes Map should have 1 entry (root), got ${nodes.size}`);
    assert.equal(blobUrls.size, 0,
      `After fix: blobUrls Map should be empty, got ${blobUrls.size}`);
  });
});
