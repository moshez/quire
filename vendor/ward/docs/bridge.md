# JS Bridge

The JS bridge (`lib/ward_bridge.mjs`) connects ward WASM to any DOM -- browser or Node.js via jsdom. It has no Node.js-specific dependencies and works in any ES module environment.

## API

### `loadWard(wasmBytes, root)`

```javascript
import { loadWard } from './ward_bridge.mjs';

const { exports, nodes, done } = await loadWard(wasmBytes, root);
```

**Parameters:**
- `wasmBytes` (`BufferSource`) -- compiled WASM bytes
- `root` (`Element`) -- root element for ward to render into (assigned node_id 0)

**Returns:**
- `exports` -- the WASM instance exports (includes `memory`, `ward_node_init`, etc.)
- `nodes` -- `Map<number, Element>` mapping node IDs to DOM elements
- `done` -- `Promise` that resolves when WASM calls `ward_exit`

After instantiation, the bridge calls `exports.ward_node_init(0)` to start the WASM program.

## Binary DOM protocol

The bridge parses a binary protocol from WASM memory via the `ward_dom_flush(bufPtr, len)` import. Each flush call can carry **multiple ops** batched into the 256KB diff buffer. The bridge loops through all ops in a single call, reading from `mem[bufPtr + pos]` and advancing `pos` after each op.

Each op starts with a 1-byte opcode followed by a 4-byte little-endian node_id.

### Opcodes

| Opcode | Name | Layout |
|--------|------|--------|
| 4 | CREATE_ELEMENT | `[4][node_id:i32][parent_id:i32][tag_len:u8][tag:bytes]` |
| 1 | SET_TEXT | `[1][node_id:i32][text_len:u16le][text:bytes]` |
| 2 | SET_ATTR | `[2][node_id:i32][name_len:u8][name:bytes][val_len:u16le][value:bytes]` |
| 3 | REMOVE_CHILDREN | `[3][node_id:i32]` |

All integers are little-endian. Text is UTF-8 (safe text characters are all ASCII).

### Batching

The ATS2 stream API accumulates ops into a 256KB buffer. When the buffer fills (next op wouldn't fit), it auto-flushes the current batch and resets the cursor. At `stream_end`, any remaining ops are flushed. This means the JS bridge typically receives many ops per flush call, reducing WASM/JS boundary crossings.

## JS-side data stash

When JS needs to pass variable-length data to WASM (IDB results, event payloads, parsed HTML), it stashes the data in a JS-side `Map<int, Uint8Array>` and WASM pulls it:

1. JS receives data (e.g. IDB get result)
2. JS calls `stashData(data)` which stores the `Uint8Array` and returns an integer stash ID
3. JS sets the stash ID via `ward_bridge_stash_set_int(1, stashId)`
4. JS fires the WASM callback (e.g. `ward_idb_fire_get(resolverId, dataLen)`)
5. WASM calls `ward_bridge_recv(stashId, len)` which allocates a buffer and calls back to JS via `ward_js_stash_read(stashId, destPtr, len)`
6. JS copies the data into the WASM-allocated buffer and deletes the stash entry

WASM controls the allocation and the copy happens in a single synchronous round-trip, so there is no window for memory growth to invalidate the buffer view.

## WASM imports (env)

The bridge provides these functions as WASM imports under the `env` namespace:

### Core

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_dom_flush` | `(bufPtr, len) -> void` | Parse binary diff protocol, apply to DOM (multi-op loop) |
| `ward_set_timer` | `(delayMs, resolverId) -> void` | `setTimeout` + call `ward_timer_fire(resolverId)` on expiry |
| `ward_exit` | `() -> void` | Resolve the `done` promise |

### IndexedDB

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_idb_js_put` | `(keyPtr, keyLen, valPtr, valLen, resolverId) -> void` | Put key-value pair |
| `ward_idb_js_get` | `(keyPtr, keyLen, resolverId) -> void` | Get value by key |
| `ward_idb_js_delete` | `(keyPtr, keyLen, resolverId) -> void` | Delete key |

### Window

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_focus_window` | `() -> void` | Focus the window |
| `ward_js_get_visibility_state` | `() -> i32` | 1=visible, 0=hidden |
| `ward_js_log` | `(level, msgPtr, msgLen) -> void` | Console log (0=debug..3=error) |

### Navigation

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_get_url` | `(outPtr, maxLen) -> i32` | Get current URL, returns bytes written |
| `ward_js_get_url_hash` | `(outPtr, maxLen) -> i32` | Get URL hash |
| `ward_js_set_url_hash` | `(hashPtr, hashLen) -> void` | Set URL hash |
| `ward_js_replace_state` | `(urlPtr, urlLen) -> void` | history.replaceState |
| `ward_js_push_state` | `(urlPtr, urlLen) -> void` | history.pushState |

### DOM read

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_measure_node` | `(nodeId) -> i32` | Measure DOM node, fill stash |
| `ward_js_query_selector` | `(selectorPtr, selectorLen) -> i32` | Query selector, returns node_id or -1 |

### Event listener

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_add_event_listener` | `(nodeId, typePtr, typeLen, listenerId) -> void` | Register event listener |
| `ward_js_remove_event_listener` | `(listenerId) -> void` | Remove event listener |
| `ward_js_prevent_default` | `() -> void` | Prevent default on current event |

### Fetch

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_fetch` | `(urlPtr, urlLen, resolverId) -> void` | Fetch URL |

### Clipboard

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_clipboard_write_text` | `(textPtr, textLen, resolverId) -> void` | Write text to clipboard |

### File

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_file_open` | `(inputNodeId, resolverId) -> void` | Open file from input |
| `ward_js_file_read` | `(handle, fileOffset, len, outPtr) -> i32` | Read from file |
| `ward_js_file_close` | `(handle) -> void` | Close file |

### Decompress

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_decompress` | `(dataPtr, dataLen, method, resolverId) -> void` | Decompress data |
| `ward_js_blob_read` | `(handle, blobOffset, len, outPtr) -> i32` | Read from blob |
| `ward_js_blob_free` | `(handle) -> void` | Free blob |

### Notification/Push

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_notification_request_permission` | `(resolverId) -> void` | Request notification permission |
| `ward_js_notification_show` | `(titlePtr, titleLen) -> void` | Show notification |
| `ward_js_push_subscribe` | `(vapidPtr, vapidLen, resolverId) -> void` | Subscribe to push |
| `ward_js_push_get_subscription` | `(resolverId) -> void` | Get existing subscription |

### Data stash

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_stash_read` | `(stashId, destPtr, len) -> void` | Pull stashed data into WASM-allocated buffer |

## WASM exports expected

The bridge calls these WASM exports:

| Export | When called |
|--------|-------------|
| `ward_node_init(root_id)` | On startup after instantiation |
| `ward_timer_fire(resolverId)` | When a timer fires |
| `ward_idb_fire(resolverId, status)` | When IDB put/delete completes |
| `ward_idb_fire_get(resolverId, dataLen)` | When IDB get completes |
| `ward_bridge_stash_set_int(slot, value)` | Set int stash slot (e.g. stash_id before fire) |
| `ward_on_event(listenerId, payloadLen)` | When DOM event fires |
| `ward_measure_set(index, value)` | To fill measure stash |
| `ward_on_fetch_complete(resolverId, status, bodyLen)` | When fetch completes |
| `ward_on_clipboard_complete(resolverId, success)` | When clipboard op completes |
| `ward_on_file_open(resolverId, handle, size)` | When file opens |
| `ward_on_decompress_complete(resolverId, handle, len)` | When decompression completes |
| `ward_on_permission_result(resolverId, granted)` | When notification permission resolves |
| `ward_on_push_subscribe(resolverId, jsonLen)` | When push subscribe completes |

## Browser wiring

```html
<!DOCTYPE html>
<html>
<body>
  <div id="ward-root"></div>
  <script type="module">
    import { loadWard } from './ward_bridge.mjs';

    const root = document.getElementById('ward-root');
    const wasm = await (await fetch('ward.wasm')).arrayBuffer();
    const { done } = await loadWard(wasm, root);
    await done;
  </script>
</body>
</html>
```

## Node.js wiring

```javascript
import 'fake-indexeddb/auto';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';
import { loadWard } from './ward_bridge.mjs';

const dom = new JSDOM('<!DOCTYPE html><div id="root"></div>');
const root = dom.window.document.getElementById('root');

const wasmBytes = await readFile('ward.wasm');
const { done } = await loadWard(wasmBytes, root);
await done;
```

Node.js requires `jsdom` for DOM and `fake-indexeddb` for IndexedDB.
