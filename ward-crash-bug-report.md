# Ward Bug Report: Renderer crash during sustained REMOVE_CHILDREN + re-render cycles

## Summary

Using `ward_dom_stream_remove_children` followed by re-rendering content into the same container causes the browser renderer process to crash after repeated cycles. The crash manifests as "Target crashed" in Playwright (Chromium renderer process killed). This makes it impossible to implement chapter-based navigation in an EPUB reader — sustained forward navigation through a multi-chapter book crashes the tab.

## Root Cause Analysis

### Bug 1: `REMOVE_CHILDREN` leaks `nodes` Map entries (bridge memory leak)

In `ward_bridge.mjs`, the `REMOVE_CHILDREN` diff op (case 3) clears the element's innerHTML but does not remove child node references from the `nodes` Map:

```js
case 3: { // REMOVE_CHILDREN
  const el = nodes.get(nodeId);
  if (el) el.innerHTML = '';  // children removed from DOM...
  pos += 5;
  break;
  // ...but their entries remain in `nodes` Map forever
}
```

Each `CREATE_ELEMENT` adds to `nodes`. `REMOVE_CHILDREN` never removes them. So `nodes` grows without bound. Since `nodes` holds references to detached DOM elements, they cannot be garbage collected.

Compare with `REMOVE_CHILD` (case 5) which at least handles blob URL cleanup for the specific node (but not its descendants):

```js
case 5: { // REMOVE_CHILD
  const el = nodes.get(nodeId);
  if (el) el.remove();
  const oldUrl = blobUrls.get(nodeId);
  if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(nodeId); }
  pos += 5;
  break;
}
```

### Bug 2: `blobUrls` Map leaks on `REMOVE_CHILDREN`

When `REMOVE_CHILDREN` clears a container that had `<img>` descendants with blob URLs (set via `ward_dom_stream_set_image_src`), those blob URLs are never revoked:

- `wardJsSetImageSrc` stores `blobUrls.set(nodeId, url)` for each image
- `REMOVE_CHILDREN` does `el.innerHTML = ''` but never walks descendants to revoke their blob URLs
- Blob URLs accumulate indefinitely, holding their underlying `Blob` data in memory

### Bug 3: `__builtin_trap()` on allocator OOM

In `runtime.c`, when WASM `memory.grow` fails:

```c
if (__builtin_wasm_memory_grow(0, pages) == (unsigned long)(-1))
    __builtin_trap(); /* memory.grow failed — hit 256 MB max */
```

And when the resolver table is full:

```c
__builtin_trap(); /* resolver table full — 64 concurrent async ops exceeded */
```

`__builtin_trap()` generates a WASM `unreachable` instruction, which terminates the entire renderer process. Ward should never crash — OOM should be handled gracefully (return NULL, log error, etc.).

### Combined effect

Bugs 1 and 2 cause memory to leak on every `REMOVE_CHILDREN` + re-render cycle. Bug 3 turns eventual OOM into an unrecoverable crash instead of a graceful failure. The result: after enough chapter transitions, the renderer process is killed.

## Reproduction

### Environment
- Chromium (via Playwright)
- WASM: 16MB initial, 256MB max, 256KB stack

### Steps to reproduce
1. Build a quire EPUB reader with the latest ward
2. Import the conan-stories.epub (3 deflate-compressed chapters, ~20KB each, one chapter with an 18KB stored JPEG illustration)
3. Open the book
4. Click "Next" 50 times with 200ms between clicks
5. The browser tab crashes ("Target crashed")

### Minimal ward-level reproduction

Here's a standalone ward bridge test that demonstrates the `nodes` Map leak:

```js
// Test: REMOVE_CHILDREN leaks nodes Map entries
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('REMOVE_CHILDREN cleanup', () => {
  it('should not leak nodes Map entries', async () => {
    const { exports, nodes } = await createWardInstance();

    // Create a container
    const dom = exports.ward_dom_init();
    const s = exports.ward_dom_stream_begin(dom);
    // Container node ID = 1000
    exports.ward_dom_stream_create_element(s, 1000, 0, /* tag args */);
    const dom2 = exports.ward_dom_stream_end(s);
    exports.ward_dom_fini(dom2);

    const initialSize = nodes.size;

    // Simulate 100 chapter transitions
    for (let cycle = 0; cycle < 100; cycle++) {
      const dom = exports.ward_dom_init();
      const s = exports.ward_dom_stream_begin(dom);

      // Remove children from container
      exports.ward_dom_stream_remove_children(s, 1000);

      // Create 50 child elements
      for (let i = 0; i < 50; i++) {
        const nodeId = 2000 + cycle * 50 + i;
        exports.ward_dom_stream_create_element(s, nodeId, 1000, /* tag args */);
      }

      const dom2 = exports.ward_dom_stream_end(s);
      exports.ward_dom_fini(dom2);
    }

    // After 100 cycles of 50 elements each, nodes Map should NOT have 5000+ entries
    // It should only have the container + current 50 children = ~51 entries
    console.log(`nodes.size after 100 cycles: ${nodes.size}`);
    console.log(`expected: ~${initialSize + 50}, actual: ${nodes.size}`);
    assert.ok(nodes.size < initialSize + 200,
      `nodes Map leaked: ${nodes.size} entries (expected ~${initialSize + 50})`);
  });
});
```

### Note on the allocator issue

A separate test can trigger `__builtin_trap()` by exhausting WASM memory:

```js
// Allocate memory in a loop until OOM
// Expected: graceful error
// Actual: __builtin_trap() → renderer crash
for (let i = 0; i < 1000; i++) {
  const arr = exports.ward_arr_alloc(1024 * 1024); // 1MB each
  // Don't free — accumulate until memory.grow fails
  // This will crash the renderer instead of returning an error
}
```

## Proposed Fix

### Fix 1: Clean up `nodes` Map in `REMOVE_CHILDREN`

```js
case 3: { // REMOVE_CHILDREN
  const parentId = nodeId;
  const el = nodes.get(parentId);
  if (el) {
    // Walk all descendant nodes and clean up
    const toRemove = [];
    for (const [id, node] of nodes) {
      if (id !== parentId && el.contains(node)) {
        toRemove.push(id);
      }
    }
    for (const id of toRemove) {
      const oldUrl = blobUrls.get(id);
      if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(id); }
      nodes.delete(id);
    }
    el.innerHTML = '';
  }
  pos += 5;
  break;
}
```

**Performance note:** `el.contains(node)` is O(depth) per call, making this O(nodes * depth). For containers with many descendants, a more efficient approach would be to mark child node IDs at creation time and use a Set lookup. But the simple `contains` approach is correct and sufficient for most real-world cases.

### Fix 2: Handle OOM gracefully

Instead of `__builtin_trap()`, return NULL from malloc and let callers handle it:

```c
if (__builtin_wasm_memory_grow(0, pages) == (unsigned long)(-1))
    return (void*)0; /* let caller handle OOM */
```

Or, log an error and continue with degraded functionality rather than crashing.

## Impact

Any ward application that repeatedly clears and re-renders content (pagination, tab switching, list scrolling with recycling) will crash after enough cycles. This is a fundamental lifecycle management issue in the bridge.
