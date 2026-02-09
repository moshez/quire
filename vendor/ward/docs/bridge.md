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

The bridge parses a binary protocol from WASM memory via the `ward_dom_flush(bufPtr, len)` import. Each message starts with a 1-byte opcode followed by a 4-byte little-endian node_id.

### Opcodes

| Opcode | Name | Layout |
|--------|------|--------|
| 4 | CREATE_ELEMENT | `[4][node_id:i32][parent_id:i32][tag_len:u8][tag:bytes]` |
| 1 | SET_TEXT | `[1][node_id:i32][text_len:u16le][text:bytes]` |
| 2 | SET_ATTR | `[2][node_id:i32][name_len:u8][name:bytes][val_len:u16le][value:bytes]` |
| 3 | REMOVE_CHILDREN | `[3][node_id:i32]` |

All integers are little-endian. Text is UTF-8 (safe text characters are all ASCII).

## WASM imports (env)

The bridge provides these functions as WASM imports under the `env` namespace:

### Core

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_dom_flush` | `(bufPtr, len) → void` | Parse binary diff protocol, apply to DOM |
| `ward_set_timer` | `(delayMs, resolverPtr) → void` | `setTimeout` + call `ward_timer_fire(resolverPtr)` on expiry |
| `ward_exit` | `() → void` | Resolve the `done` promise |

### IndexedDB

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_idb_js_put` | `(keyPtr, keyLen, valPtr, valLen, resolverPtr) → void` | Put key-value pair |
| `ward_idb_js_get` | `(keyPtr, keyLen, resolverPtr) → void` | Get value by key |
| `ward_idb_js_delete` | `(keyPtr, keyLen, resolverPtr) → void` | Delete key |

### Window

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_focus_window` | `() → void` | Focus the window |
| `ward_js_get_visibility_state` | `() → i32` | 1=visible, 0=hidden |
| `ward_js_log` | `(level, msgPtr, msgLen) → void` | Console log (0=debug..3=error) |

### Navigation

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_get_url` | `(outPtr, maxLen) → i32` | Get current URL, returns bytes written |
| `ward_js_get_url_hash` | `(outPtr, maxLen) → i32` | Get URL hash |
| `ward_js_set_url_hash` | `(hashPtr, hashLen) → void` | Set URL hash |
| `ward_js_replace_state` | `(urlPtr, urlLen) → void` | history.replaceState |
| `ward_js_push_state` | `(urlPtr, urlLen) → void` | history.pushState |

### DOM read

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_measure_node` | `(nodeId) → i32` | Measure DOM node, fill stash |
| `ward_js_query_selector` | `(selectorPtr, selectorLen) → i32` | Query selector, returns node_id or -1 |

### Event listener

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_add_event_listener` | `(nodeId, typePtr, typeLen, listenerId) → void` | Register event listener |
| `ward_js_remove_event_listener` | `(listenerId) → void` | Remove event listener |
| `ward_js_prevent_default` | `() → void` | Prevent default on current event |

### Fetch

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_fetch` | `(urlPtr, urlLen, resolverPtr) → void` | Fetch URL |

### Clipboard

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_clipboard_write_text` | `(textPtr, textLen, resolverPtr) → void` | Write text to clipboard |

### File

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_file_open` | `(inputNodeId, resolverPtr) → void` | Open file from input |
| `ward_js_file_read` | `(handle, fileOffset, len, outPtr) → i32` | Read from file |
| `ward_js_file_close` | `(handle) → void` | Close file |

### Decompress

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_decompress` | `(dataPtr, dataLen, method, resolverPtr) → void` | Decompress data |
| `ward_js_blob_read` | `(handle, blobOffset, len, outPtr) → i32` | Read from blob |
| `ward_js_blob_free` | `(handle) → void` | Free blob |

### Notification/Push

| Import | Signature | Purpose |
|--------|-----------|---------|
| `ward_js_notification_request_permission` | `(resolverPtr) → void` | Request notification permission |
| `ward_js_notification_show` | `(titlePtr, titleLen) → void` | Show notification |
| `ward_js_push_subscribe` | `(vapidPtr, vapidLen, resolverPtr) → void` | Subscribe to push |
| `ward_js_push_get_subscription` | `(resolverPtr) → void` | Get existing subscription |

## WASM exports expected

The bridge calls these WASM exports:

| Export | When called |
|--------|-------------|
| `ward_node_init(root_id)` | On startup after instantiation |
| `ward_timer_fire(resolverPtr)` | When a timer fires |
| `ward_idb_fire(resolverPtr, status)` | When IDB put/delete completes |
| `ward_idb_fire_get(resolverPtr, dataPtr, dataLen)` | When IDB get completes |
| `malloc(len)` | To allocate WASM memory for IDB get results |
| `ward_on_event(listenerId, payloadLen)` | When DOM event fires |
| `ward_measure_set(index, value)` | To fill measure stash |
| `ward_on_fetch_complete(resolverPtr, status, bodyPtr, bodyLen)` | When fetch completes |
| `ward_on_clipboard_complete(resolverPtr, success)` | When clipboard op completes |
| `ward_on_file_open(resolverPtr, handle, size)` | When file opens |
| `ward_on_decompress_complete(resolverPtr, handle, len)` | When decompression completes |
| `ward_on_permission_result(resolverPtr, granted)` | When notification permission resolves |
| `ward_on_push_subscribe(resolverPtr, jsonPtr, jsonLen)` | When push subscribe completes |

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
