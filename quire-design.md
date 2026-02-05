# Quire — PWA E-Reader Design Document

## 1. Overview

Quire is a PWA e-reader built on a generic WASM bridge architecture. All application logic lives in an ATS2 module compiled to WASM. A thin JavaScript bridge provides DOM primitives and async I/O that WASM cannot access directly. Dependent types in ATS2 guarantee that DOM diff sequences are valid state transitions — if the code compiles, the diffs it emits are correct.

The reader uses CSS multi-column layout for pagination and maintains a three-chapter sliding window so page turns are always instantaneous. EPUBs are unzipped, processed, and stored in IndexedDB for offline reading.

```
┌─────────────────────────────────────────────┐
│  index.html                                 │
│  ┌──────────┐  ┌─────────────────────────┐  │
│  │ Loading… │  │ <script>                │  │
│  │ <div>    │  │   import { initBridge } │  │
│  │          │  │   await initBridge(url) │  │
│  └──────────┘  └─────────────────────────┘  │
├─────────────────────────────────────────────┤
│  bridge.js (generic, publishable as npm)    │
│  ┌──────────┐ ┌───────────┐ ┌────────────┐ │
│  │ Event    │ │ Diff      │ │ Async I/O  │ │
│  │ capture  │ │ apply     │ │ (fetch,    │ │
│  │ → WASM   │ │ ← WASM   │ │  IDB, fs)  │ │
│  └──────────┘ └───────────┘ └────────────┘ │
├─────────────────────────────────────────────┤
│  quire.wasm (ATS2 → C → WASM)              │
│  ┌──────────┐ ┌───────────┐ ┌────────────┐ │
│  │ DOM type │ │ EPUB      │ │ Reader     │ │
│  │ model    │ │ parser    │ │ state      │ │
│  │ + diffs  │ │           │ │ machine    │ │
│  └──────────┘ └───────────┘ └────────────┘ │
├─────────────────────────────────────────────┤
│  IndexedDB                                  │
│  books │ chapters │ resources               │
└─────────────────────────────────────────────┘
```

---

## 2. Bridge Protocol

### 2.1 Current Source (sans comments)

This is the starting point — the swiftlink bridge adapted for general use. All comments removed for clarity.

```javascript
const EVENT_BUFFER_SIZE = 256;
const DIFF_BUFFER_SIZE = 4096;
const FETCH_BUFFER_SIZE = 16384;

const EVENT_CLICK = 1;
const EVENT_INPUT = 2;
const EVENT_SUBMIT = 3;
const EVENT_KEYDOWN = 4;
const EVENT_KEYUP = 5;
const EVENT_FOCUS = 6;
const EVENT_BLUR = 7;
const EVENT_PUSH = 8;
const EVENT_NOTIFICATION_CLICK = 9;

const OP_SET_TEXT = 1;
const OP_SET_ATTR = 2;
const OP_SET_STYLE = 3;
const OP_ADD_CHILD = 4;
const OP_REMOVE_CHILD = 5;
const OP_NEED_FETCH = 6;

let wasm = null;
let memory = null;
let eventBuffer = null;
let diffBuffer = null;
let fetchBuffer = null;
let stringBuffer = null;

let vapidPublicKey = null;

const swEventListeners = new Set();

const nodeRegistry = new Map();
let nextNodeId = 1;

function registerNode(element) {
  if (element.dataset.nodeId) {
    const predefinedId = parseInt(element.dataset.nodeId);
    if (!isNaN(predefinedId) && predefinedId > 0) {
      nodeRegistry.set(predefinedId, element);
      if (predefinedId >= nextNodeId) {
        nextNodeId = predefinedId + 1;
      }
      return predefinedId;
    }
  }
  const id = nextNodeId++;
  nodeRegistry.set(id, element);
  element.dataset.nodeId = id;
  return id;
}

function getNode(id) {
  return nodeRegistry.get(id);
}

function getStringFromBuffer(offset, length) {
  if (!stringBuffer || length <= 0) return '';
  return decoder.decode(new Uint8Array(memory.buffer, stringBuffer.byteOffset + offset, length));
}

function getStringFromFetchBuffer(offset, length) {
  if (!fetchBuffer || length <= 0) return '';
  return decoder.decode(new Uint8Array(memory.buffer, fetchBuffer.byteOffset + offset, length));
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function readString(ptr, len) {
  return decoder.decode(new Uint8Array(memory.buffer, ptr, len));
}

function writeString(ptr, str, maxLen) {
  const bytes = encoder.encode(str);
  const len = Math.min(bytes.length, maxLen);
  new Uint8Array(memory.buffer, ptr, len).set(bytes.subarray(0, len));
  return len;
}

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  return Uint8Array.from(rawData, char => char.charCodeAt(0));
}

const PUSH_DB_NAME = 'swiftlink-push';
const PUSH_STORE_NAME = 'pending';
const PUSH_DB_VERSION = 1;

function openPushDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(PUSH_DB_NAME, PUSH_DB_VERSION);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains(PUSH_STORE_NAME)) {
        db.createObjectStore(PUSH_STORE_NAME, { keyPath: 'id', autoIncrement: true });
      }
    };
  });
}

function handleSwMessage(event) {
  if (!wasm) return;
  const { type, data, action } = event.data;
  if (!swEventListeners.has(type)) return;
  switch (type) {
    case 'push':
      if (data) {
        writeString(fetchBuffer.byteOffset, data, FETCH_BUFFER_SIZE);
      }
      writeEvent(EVENT_PUSH, 0);
      wasm.exports.process_event();
      applyDiffs();
      break;
    case 'notificationclick':
      writeEvent(EVENT_NOTIFICATION_CLICK, 0, action === 'dismiss' ? 1 : 0);
      wasm.exports.process_event();
      applyDiffs();
      break;
    case 'pushsubscriptionchange':
      wasm.exports.on_push_subscription_change();
      applyDiffs();
      break;
  }
}

const imports = {
  env: {
    js_log(level, ptr, len) {
      const msg = readString(ptr, len);
      const levels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
      console.log(`[WASM ${levels[level] || 'LOG'}]`, msg);
    },

    js_fetch(urlPtr, urlLen, method) {
      const url = readString(urlPtr, urlLen);
      const methods = ['GET', 'POST', 'PUT', 'DELETE'];
      fetch(url, { method: methods[method] || 'GET' })
        .then(async (response) => {
          const data = await response.arrayBuffer();
          const view = new DataView(fetchBuffer.buffer, fetchBuffer.byteOffset);
          view.setUint32(0, data.byteLength, true);
          new Uint8Array(fetchBuffer.buffer, fetchBuffer.byteOffset + 4).set(new Uint8Array(data));
          wasm.exports.on_fetch_complete(response.status, data.byteLength);
          applyDiffs();
        })
        .catch(() => {
          wasm.exports.on_fetch_complete(0, 0);
          applyDiffs();
        });
    },

    js_fetch_json(urlPtr, urlLen, method, bodyPtr, bodyLen) {
      const url = readString(urlPtr, urlLen);
      const body = readString(bodyPtr, bodyLen);
      const methods = ['GET', 'POST', 'PUT', 'DELETE'];
      fetch(url, {
        method: methods[method] || 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body,
        credentials: 'same-origin'
      })
        .then(async (response) => {
          const data = await response.arrayBuffer();
          const view = new DataView(fetchBuffer.buffer, fetchBuffer.byteOffset);
          view.setUint32(0, data.byteLength, true);
          new Uint8Array(fetchBuffer.buffer, fetchBuffer.byteOffset + 4).set(new Uint8Array(data));
          wasm.exports.on_fetch_complete(response.status, data.byteLength);
          applyDiffs();
        })
        .catch(() => {
          wasm.exports.on_fetch_complete(0, 0);
          applyDiffs();
        });
    },

    js_storage_get(keyPtr, keyLen) {
      const key = readString(keyPtr, keyLen);
      const value = localStorage.getItem(key);
      if (value === null) return 0;
      return writeString(fetchBuffer.byteOffset, value, FETCH_BUFFER_SIZE);
    },

    js_storage_set(keyPtr, keyLen, valPtr, valLen) {
      const key = readString(keyPtr, keyLen);
      const value = readString(valPtr, valLen);
      try {
        localStorage.setItem(key, value);
        return 1;
      } catch {
        return 0;
      }
    },

    js_storage_remove(keyPtr, keyLen) {
      const key = readString(keyPtr, keyLen);
      localStorage.removeItem(key);
    },

    js_storage_clear() {
      localStorage.clear();
    },

    js_set_timer(delay, callbackId) {
      setTimeout(() => {
        wasm.exports.on_timer_complete(callbackId);
        applyDiffs();
      }, delay);
    },

    js_push_subscribe() {
      if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
        return 0;
      }
      navigator.serviceWorker.ready
        .then(registration => registration.pushManager.getSubscription())
        .then(async (subscription) => {
          if (!subscription) {
            const permission = await Notification.requestPermission();
            if (permission !== 'granted') {
              wasm.exports.on_push_subscribe_complete(-1);
              applyDiffs();
              return;
            }
            const reg = await navigator.serviceWorker.ready;
            const options = { userVisibleOnly: true };
            if (vapidPublicKey) {
              options.applicationServerKey = urlBase64ToUint8Array(vapidPublicKey);
            }
            subscription = await reg.pushManager.subscribe(options);
          }
          const json = JSON.stringify(subscription.toJSON());
          const len = writeString(fetchBuffer.byteOffset, json, FETCH_BUFFER_SIZE);
          wasm.exports.on_push_subscribe_complete(len);
          applyDiffs();
        })
        .catch(() => {
          wasm.exports.on_push_subscribe_complete(0);
          applyDiffs();
        });
    },

    js_push_get_subscription() {
      if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
        return 0;
      }
      navigator.serviceWorker.ready
        .then(registration => registration.pushManager.getSubscription())
        .then((subscription) => {
          if (!subscription) {
            wasm.exports.on_push_subscription_result(0);
            applyDiffs();
            return;
          }
          const json = JSON.stringify(subscription.toJSON());
          const len = writeString(fetchBuffer.byteOffset, json, FETCH_BUFFER_SIZE);
          wasm.exports.on_push_subscription_result(len);
          applyDiffs();
        })
        .catch(() => {
          wasm.exports.on_push_subscription_result(0);
          applyDiffs();
        });
    },

    js_notification_show(titlePtr, titleLen, bodyPtr, bodyLen, tagPtr, tagLen) {
      const title = readString(titlePtr, titleLen);
      const body = readString(bodyPtr, bodyLen);
      const tag = tagLen > 0 ? readString(tagPtr, tagLen) : 'swiftlink';
      if (!('Notification' in window) || Notification.permission !== 'granted') {
        return 0;
      }
      new Notification(title, { body, tag });
      return 1;
    },

    js_window_focus() {
      window.focus();
    },

    js_set_vapid_key(keyPtr, keyLen) {
      vapidPublicKey = readString(keyPtr, keyLen);
    },

    js_sw_add_listener(typePtr, typeLen) {
      const eventType = readString(typePtr, typeLen);
      const wasEmpty = swEventListeners.size === 0;
      swEventListeners.add(eventType);
      if (wasEmpty && 'serviceWorker' in navigator) {
        navigator.serviceWorker.addEventListener('message', handleSwMessage);
      }
    },

    js_sw_remove_listener(typePtr, typeLen) {
      const eventType = readString(typePtr, typeLen);
      swEventListeners.delete(eventType);
      if (swEventListeners.size === 0 && 'serviceWorker' in navigator) {
        navigator.serviceWorker.removeEventListener('message', handleSwMessage);
      }
    },

    js_get_pending_pushes() {
      openPushDB()
        .then((db) => {
          return new Promise((resolve, reject) => {
            const tx = db.transaction(PUSH_STORE_NAME, 'readonly');
            const store = tx.objectStore(PUSH_STORE_NAME);
            const request = store.getAll();
            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve(request.result);
            tx.oncomplete = () => db.close();
          });
        })
        .then((entries) => {
          const json = JSON.stringify(entries);
          const len = writeString(fetchBuffer.byteOffset, json, FETCH_BUFFER_SIZE);
          wasm.exports.on_pending_pushes_result(len);
          applyDiffs();
        })
        .catch(() => {
          wasm.exports.on_pending_pushes_result(0);
          applyDiffs();
        });
    },

    js_clear_pending_pushes() {
      openPushDB()
        .then((db) => {
          return new Promise((resolve, reject) => {
            const tx = db.transaction(PUSH_STORE_NAME, 'readwrite');
            const store = tx.objectStore(PUSH_STORE_NAME);
            const request = store.clear();
            request.onerror = () => reject(request.error);
            request.onsuccess = () => resolve();
            tx.oncomplete = () => db.close();
          });
        })
        .then(() => {
          wasm.exports.on_pending_pushes_cleared(1);
          applyDiffs();
        })
        .catch(() => {
          wasm.exports.on_pending_pushes_cleared(0);
          applyDiffs();
        });
    },

    js_get_url_origin() {
      const origin = window.location.origin;
      return writeString(fetchBuffer.byteOffset, origin, FETCH_BUFFER_SIZE);
    },

    js_get_url_hash() {
      const hash = window.location.hash;
      if (!hash || hash.length <= 1) return 0;
      const fragment = hash.substring(1);
      return writeString(fetchBuffer.byteOffset, fragment, FETCH_BUFFER_SIZE);
    },

    js_set_url_hash(hashPtr, hashLen) {
      const hash = readString(hashPtr, hashLen);
      window.location.hash = hash;
    },

    js_clear_url_hash() {
      history.replaceState(null, '', window.location.pathname + window.location.search);
    },

    js_copy_to_clipboard(textPtr, textLen) {
      const text = readString(textPtr, textLen);
      navigator.clipboard.writeText(text)
        .then(() => {
          wasm.exports.on_clipboard_copy_complete(1);
          applyDiffs();
        })
        .catch(() => {
          wasm.exports.on_clipboard_copy_complete(0);
          applyDiffs();
        });
    }
  }
};

function writeEvent(type, nodeId, data1 = 0, data2 = 0) {
  const view = new DataView(eventBuffer.buffer, eventBuffer.byteOffset);
  view.setUint8(0, type);
  view.setUint32(1, nodeId, true);
  view.setUint32(5, data1, true);
  view.setUint32(9, data2, true);
}

function applyDiffs() {
  const view = new DataView(diffBuffer.buffer, diffBuffer.byteOffset);
  const numDiffs = view.getUint8(0);

  for (let i = 0; i < numDiffs; i++) {
    const offset = 1 + i * 12;
    const op = view.getUint8(offset);
    const nodeId = view.getUint32(offset + 1, true);
    const value1 = view.getUint32(offset + 5, true);
    const value2 = view.getUint32(offset + 9, true);

    const node = getNode(nodeId);

    switch (op) {
      case OP_SET_TEXT:
        if (node) {
          if (value1 > 0 && value1 < 1000) {
            const text = getStringFromFetchBuffer(0, value1);
            if (text && text.length > 0) {
              node.textContent = text;
            } else {
              node.textContent = String(value1);
            }
          } else if (value1 === 0) {
            node.textContent = '';
          } else {
            node.textContent = String(value1);
          }
        }
        break;
      case OP_SET_ATTR:
        if (node && value2 > 0) {
          const attrValue = getStringFromBuffer(value1, value2);
          // PLACEHOLDER: reads value but does nothing with it
        }
        break;
      case OP_SET_STYLE:
        if (node) {
          if (value1 === 1) {
            node.classList.remove('hidden');
          } else {
            node.classList.add('hidden');
          }
        }
        break;
      case OP_ADD_CHILD:
        if (value1 > 0 && value2 > 0) {
          const parent = getNode(value1);
          if (parent) {
            const contactItem = document.createElement('div');
            contactItem.className = 'contact-item';
            contactItem.dataset.nodeId = value2;
            contactItem.dataset.wasm = '';
            const avatar = document.createElement('div');
            avatar.className = 'contact-avatar';
            avatar.textContent = '?';
            const info = document.createElement('div');
            info.className = 'contact-info';
            const name = document.createElement('div');
            name.className = 'contact-name';
            name.textContent = 'Contact';
            info.appendChild(name);
            contactItem.appendChild(avatar);
            contactItem.appendChild(info);
            parent.appendChild(contactItem);
            registerNode(contactItem);
          }
        }
        break;
      case OP_REMOVE_CHILD:
        if (node && node.parentNode) node.parentNode.removeChild(node);
        break;
      case OP_NEED_FETCH:
        break;
    }
  }
}

function handleEvent(event, type) {
  const nodeId = parseInt(event.target.dataset?.nodeId) || 0;
  writeEvent(type, nodeId);
  wasm.exports.process_event();
  applyDiffs();
}

export async function initApp(wasmUrl) {
  const response = await fetch(wasmUrl);
  const bytes = await response.arrayBuffer();
  const module = await WebAssembly.instantiate(bytes, imports);

  wasm = module.instance;
  memory = wasm.exports.memory;

  eventBuffer = new Uint8Array(memory.buffer, wasm.exports.get_event_buffer_ptr(), EVENT_BUFFER_SIZE);
  diffBuffer = new Uint8Array(memory.buffer, wasm.exports.get_diff_buffer_ptr(), DIFF_BUFFER_SIZE);
  fetchBuffer = new Uint8Array(memory.buffer, wasm.exports.get_fetch_buffer_ptr(), FETCH_BUFFER_SIZE);
  stringBuffer = new Uint8Array(memory.buffer, wasm.exports.get_string_buffer_ptr(), 4096);

  document.querySelectorAll('[data-wasm]').forEach(el => registerNode(el));

  document.addEventListener('click', e => handleEvent(e, EVENT_CLICK));
  document.addEventListener('input', e => handleEvent(e, EVENT_INPUT));
  document.addEventListener('submit', e => { e.preventDefault(); handleEvent(e, EVENT_SUBMIT); });
  document.addEventListener('keydown', e => handleEvent(e, EVENT_KEYDOWN));
  document.addEventListener('keyup', e => handleEvent(e, EVENT_KEYUP));
  document.addEventListener('focus', e => handleEvent(e, EVENT_FOCUS), true);
  document.addEventListener('blur', e => handleEvent(e, EVENT_BLUR), true);

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      // Trigger state save in WASM
    }
  });

  wasm.exports.init();
  applyDiffs();

  console.log('[Bridge] App initialized');
}

export { registerNode, getNode };
```

### 2.2 Bugs in Current Bridge

#### Bug 1: Diff entry stride overlap

Each diff entry reads 13 bytes (1 op + 4 nodeId + 4 value1 + 4 value2) but the iteration stride is 12:

```javascript
const offset = 1 + i * 12;           // stride = 12
const op = view.getUint8(offset);     // +0
const nodeId = view.getUint32(offset + 1, true);  // +1..+4
const value1 = view.getUint32(offset + 5, true);  // +5..+8
const value2 = view.getUint32(offset + 9, true);  // +9..+12  ← 13 bytes total
```

Entry *i*'s last byte overlaps with entry *i+1*'s op byte. Fix: use 16-byte stride with uint32-aligned fields.

**New layout** (16 bytes per entry, 4-byte aligned):

| Offset | Size | Field  |
|--------|------|--------|
| +0     | 4    | op     |
| +4     | 4    | nodeId |
| +8     | 4    | value1 |
| +12    | 4    | value2 |

Header: byte 0 = entry count (uint8). Entries start at byte 4 for alignment.

```javascript
const offset = 4 + i * 16;
const op     = view.getUint32(offset, true);
const nodeId = view.getUint32(offset + 4, true);
const value1 = view.getUint32(offset + 8, true);
const value2 = view.getUint32(offset + 12, true);
```

Max entries in 4096-byte buffer: `(4096 - 4) / 16 = 255`. Plenty for any realistic frame.

#### Bug 2: OP_SET_ATTR is a no-op placeholder

```javascript
case OP_SET_ATTR:
  if (node && value2 > 0) {
    const attrValue = getStringFromBuffer(value1, value2);
    // reads value but never applies it
  }
  break;
```

**Fix:** Encoding: attr name and value are written consecutively in stringBuffer. `value1` = name length, `value2` = value length. Name at `stringBuffer[0..value1]`, value at `stringBuffer[value1..value1+value2]`. If `value2 === 0`, remove the attribute.

```javascript
case OP_SET_ATTR: {
  if (node && value1 > 0) {
    const name = getStringFromBuffer(0, value1);
    if (value2 > 0) {
      const val = getStringFromBuffer(value1, value2);
      node.setAttribute(name, val);
    } else {
      node.removeAttribute(name);
    }
  }
  break;
}
```

### 2.3 Modifications

All changes below transform the swiftlink bridge into a generic protocol.

#### 2.3.1 Replace OP_SET_STYLE → OP_SET_TRANSFORM

Remove the `hidden` class toggle. The new operation sets CSS transform:

```javascript
case OP_SET_TRANSFORM:
  if (node) {
    const x = value1 | 0;  // reinterpret uint32 as int32
    const y = value2 | 0;
    node.style.transform = `translate(${x}px, ${y}px)`;
  }
  break;
```

`value1` and `value2` are int32 (reinterpreted from uint32 via `| 0`). This enables negative offsets for scrolling left/up.

#### 2.3.2 Replace OP_ADD_CHILD → OP_CREATE_ELEMENT

Remove the hardcoded contact-item template. The new operation creates an arbitrary element:

```javascript
case OP_CREATE_ELEMENT: {
  // nodeId = ID to assign to new element
  // value1 = parent node ID
  // value2 = tag name length in string buffer (tag at stringBuffer[0..value2])
  const parent = getNode(value1);
  if (parent && value2 > 0) {
    const tagName = getStringFromBuffer(0, value2);
    const el = document.createElement(tagName);
    el.dataset.nodeId = nodeId;
    el.dataset.wasm = '';
    nodeRegistry.set(nodeId, el);
    if (nodeId >= nextNodeId) nextNodeId = nodeId + 1;
    parent.appendChild(el);
  }
  break;
}
```

Node ID is assigned by WASM (via the `nodeId` field of the diff entry), not auto-generated by the bridge. WASM owns the ID space.

#### 2.3.3 Add OP_SET_INNER_HTML

```javascript
case OP_SET_INNER_HTML:
  if (node) {
    node.innerHTML = getStringFromFetchBuffer(value1, value2);
  }
  break;
```

`value1` = offset in fetch buffer, `value2` = length. Used for injecting chapter XHTML.

#### 2.3.4 Simplify OP_SET_TEXT

Remove the backward-compatibility heuristic. Always read from fetch buffer:

```javascript
case OP_SET_TEXT:
  if (node) {
    node.textContent = value2 > 0 ? getStringFromFetchBuffer(value1, value2) : '';
  }
  break;
```

`value1` = offset in fetch buffer, `value2` = length. If `value2 === 0`, clear text.

#### 2.3.5 New op code table

| Code | Name              | nodeId            | value1          | value2          |
|------|-------------------|-------------------|-----------------|-----------------|
| 1    | SET_TEXT           | target            | fetch offset    | fetch length    |
| 2    | SET_ATTR           | target            | name length     | value length    |
| 3    | SET_TRANSFORM      | target            | x (int32)       | y (int32)       |
| 4    | CREATE_ELEMENT     | new element's ID  | parent node ID  | tag name length |
| 5    | REMOVE_CHILD       | target            | (unused)        | (unused)        |
| 6    | SET_INNER_HTML     | target            | fetch offset    | fetch length    |

String data locations:
- SET_TEXT, SET_INNER_HTML: data in **fetch buffer** at given offset
- SET_ATTR: attr name in **string buffer** at `[0..value1]`, attr value in string buffer at `[value1..value1+value2]`
- CREATE_ELEMENT: tag name in **string buffer** at `[0..value2]`

#### 2.3.6 Add js_measure_node import

```javascript
js_measure_node(nodeId) {
  const node = getNode(nodeId);
  if (!node) return 0;
  const rect = node.getBoundingClientRect();
  const view = new DataView(memory.buffer, fetchBuffer.byteOffset);
  view.setFloat64(0, rect.left, true);
  view.setFloat64(8, rect.top, true);
  view.setFloat64(16, rect.width, true);
  view.setFloat64(24, rect.height, true);
  view.setFloat64(32, node.scrollWidth, true);
  view.setFloat64(40, node.scrollHeight, true);
  return 1;
}
```

Writes 6 float64 values (48 bytes) to the start of fetch buffer. Returns 1 on success, 0 if node not found. Includes both bounding rect and scroll dimensions — the scroll dimensions are essential for calculating page count in CSS column layouts.

#### 2.3.7 Add file handle imports

EPUB files can be tens of megabytes. They must stay in JS memory with WASM requesting chunks through the fetch buffer.

```javascript
// JS-side state
const fileHandles = new Map();
let nextFileHandle = 1;

js_file_open(nodeId) {
  const node = getNode(nodeId);
  if (!node || !node.files || !node.files[0]) return 0;
  const file = node.files[0];
  const handle = nextFileHandle++;
  // Read entire file into ArrayBuffer
  file.arrayBuffer().then(buffer => {
    fileHandles.set(handle, buffer);
    wasm.exports.on_file_open_complete(handle, buffer.byteLength);
  }).catch(() => {
    wasm.exports.on_file_open_complete(0, 0);
  });
}

js_file_read_chunk(handle, offset, length) {
  const buffer = fileHandles.get(handle);
  if (!buffer) return 0;
  const chunk = new Uint8Array(buffer, offset, Math.min(length, FETCH_BUFFER_SIZE));
  new Uint8Array(memory.buffer, fetchBuffer.byteOffset, chunk.length).set(chunk);
  return chunk.length;
}

js_file_close(handle) {
  fileHandles.delete(handle);
}
```

`js_file_open` is async (result via `on_file_open_complete` callback). `js_file_read_chunk` is synchronous — the data is already in JS memory.

#### 2.3.8 Add decompression import

ZIP entries use DEFLATE. The browser provides `DecompressionStream` which is generic and efficient:

```javascript
// JS-side state for decompressed blobs
const blobHandles = new Map();
let nextBlobHandle = 1;

js_decompress(fileHandle, offset, compressedSize, method) {
  // method: 0 = deflate-raw, 1 = deflate, 2 = gzip
  const methods = ['deflate-raw', 'deflate', 'gzip'];
  const buffer = fileHandles.get(fileHandle);
  if (!buffer) {
    wasm.exports.on_decompress_complete(0, 0);
    return;
  }
  const compressed = new Uint8Array(buffer, offset, compressedSize);
  const ds = new DecompressionStream(methods[method] || 'deflate-raw');
  const writer = ds.writable.getWriter();
  writer.write(compressed);
  writer.close();
  new Response(ds.readable).arrayBuffer().then(decompressed => {
    const handle = nextBlobHandle++;
    blobHandles.set(handle, decompressed);
    wasm.exports.on_decompress_complete(handle, decompressed.byteLength);
  }).catch(() => {
    wasm.exports.on_decompress_complete(0, 0);
  });
}

js_blob_read_chunk(handle, offset, length) {
  const buffer = blobHandles.get(handle);
  if (!buffer) return 0;
  const chunk = new Uint8Array(buffer, offset, Math.min(length, FETCH_BUFFER_SIZE));
  new Uint8Array(memory.buffer, fetchBuffer.byteOffset, chunk.length).set(chunk);
  return chunk.length;
}

js_blob_size(handle) {
  const buffer = blobHandles.get(handle);
  return buffer ? buffer.byteLength : 0;
}

js_blob_free(handle) {
  blobHandles.delete(handle);
}
```

The pattern: WASM identifies a compressed region in the file (by parsing ZIP headers via chunk reads), hands the region to JS for decompression, gets back a blob handle, and reads decompressed data in chunks.

#### 2.3.9 Add IndexedDB key-value imports

Generic key-value store over IndexedDB. Any WASM app can use it. The bridge manages DB lifecycle.

```javascript
let kvDB = null;
const KV_DB_NAME_PREFIX = 'bridge-kv-';

js_kv_open(namePtr, nameLen, version) {
  const name = readString(namePtr, nameLen);
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(KV_DB_NAME_PREFIX + name, version);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => { kvDB = request.result; resolve(); };
    request.onupgradeneeded = (event) => {
      // WASM specifies store names via js_kv_create_store during upgrade
    };
  });
}

js_kv_put(storePtr, storeLen, keyPtr, keyLen, dataOffset, dataLen) {
  const store = readString(storePtr, storeLen);
  const key = readString(keyPtr, keyLen);
  const data = new Uint8Array(memory.buffer, fetchBuffer.byteOffset + dataOffset, dataLen).slice();
  const tx = kvDB.transaction(store, 'readwrite');
  tx.objectStore(store).put(data, key);
  tx.oncomplete = () => wasm.exports.on_kv_complete(1);
  tx.onerror = () => wasm.exports.on_kv_complete(0);
}

js_kv_put_blob(storePtr, storeLen, keyPtr, keyLen, blobHandle) {
  const store = readString(storePtr, storeLen);
  const key = readString(keyPtr, keyLen);
  const data = blobHandles.get(blobHandle);
  if (!data) { wasm.exports.on_kv_complete(0); return; }
  const tx = kvDB.transaction(store, 'readwrite');
  tx.objectStore(store).put(new Uint8Array(data), key);
  tx.oncomplete = () => wasm.exports.on_kv_complete(1);
  tx.onerror = () => wasm.exports.on_kv_complete(0);
}

js_kv_get(storePtr, storeLen, keyPtr, keyLen) {
  const store = readString(storePtr, storeLen);
  const key = readString(keyPtr, keyLen);
  const tx = kvDB.transaction(store, 'readonly');
  const request = tx.objectStore(store).get(key);
  request.onsuccess = () => {
    if (!request.result) {
      wasm.exports.on_kv_get_complete(0);
      return;
    }
    const data = new Uint8Array(request.result);
    // For small data (< FETCH_BUFFER_SIZE), copy to fetch buffer
    if (data.byteLength <= FETCH_BUFFER_SIZE) {
      new Uint8Array(memory.buffer, fetchBuffer.byteOffset, data.byteLength).set(data);
      wasm.exports.on_kv_get_complete(data.byteLength);
    } else {
      // For large data, create a blob handle
      const handle = nextBlobHandle++;
      blobHandles.set(handle, data.buffer);
      wasm.exports.on_kv_get_blob_complete(handle, data.byteLength);
    }
  };
  request.onerror = () => wasm.exports.on_kv_get_complete(0);
}

js_kv_delete(storePtr, storeLen, keyPtr, keyLen) {
  const store = readString(storePtr, storeLen);
  const key = readString(keyPtr, keyLen);
  const tx = kvDB.transaction(store, 'readwrite');
  tx.objectStore(store).delete(key);
  tx.oncomplete = () => wasm.exports.on_kv_complete(1);
  tx.onerror = () => wasm.exports.on_kv_complete(0);
}
```

`js_kv_put_blob` stores data directly from a blob handle without transiting through the fetch buffer. This is critical for storing decompressed EPUB chapters and resources efficiently.

#### 2.3.10 Add js_set_inner_html_from_blob import

For injecting large chapter HTML without fetch buffer transit:

```javascript
js_set_inner_html_from_blob(nodeId, blobHandle) {
  const node = getNode(nodeId);
  const buffer = blobHandles.get(blobHandle);
  if (!node || !buffer) return 0;
  node.innerHTML = decoder.decode(new Uint8Array(buffer));
  return 1;
}
```

#### 2.3.11 Auto-flush proxy wrapper

Every WASM export call automatically flushes the diff buffer:

```javascript
function wrapExports(instance) {
  return new Proxy(instance.exports, {
    get(target, prop) {
      const val = target[prop];
      if (typeof val !== 'function') return val;
      if (prop.startsWith('get_') && prop.endsWith('_ptr')) return val;
      if (prop === 'memory') return val;
      return (...args) => {
        const result = val.apply(target, args);
        applyDiffs();
        return result;
      };
    }
  });
}
```

This eliminates every manual `applyDiffs()` call in the bridge. The protocol invariant "every WASM→JS transition flushes diffs" is enforced in one place.

#### 2.3.12 initBridge() API

```javascript
export async function initBridge(wasmUrl) {
  const response = await fetch(wasmUrl);
  const bytes = await response.arrayBuffer();
  const module = await WebAssembly.instantiate(bytes, imports);

  const instance = module.instance;
  memory = instance.exports.memory;

  eventBuffer = new Uint8Array(memory.buffer, instance.exports.get_event_buffer_ptr(), EVENT_BUFFER_SIZE);
  diffBuffer = new Uint8Array(memory.buffer, instance.exports.get_diff_buffer_ptr(), DIFF_BUFFER_SIZE);
  fetchBuffer = new Uint8Array(memory.buffer, instance.exports.get_fetch_buffer_ptr(), FETCH_BUFFER_SIZE);
  stringBuffer = new Uint8Array(memory.buffer, instance.exports.get_string_buffer_ptr(), 4096);

  wasm = wrapExports(instance);

  document.querySelectorAll('[data-wasm]').forEach(el => registerNode(el));

  document.addEventListener('click', e => handleEvent(e, EVENT_CLICK));
  document.addEventListener('input', e => handleEvent(e, EVENT_INPUT));
  document.addEventListener('submit', e => { e.preventDefault(); handleEvent(e, EVENT_SUBMIT); });
  document.addEventListener('keydown', e => handleEvent(e, EVENT_KEYDOWN));
  document.addEventListener('keyup', e => handleEvent(e, EVENT_KEYUP));
  document.addEventListener('focus', e => handleEvent(e, EVENT_FOCUS), true);
  document.addEventListener('blur', e => handleEvent(e, EVENT_BLUR), true);

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden' && wasm.on_visibility_hidden) {
      wasm.on_visibility_hidden();
    }
  });

  wasm.init();

  console.log('[Bridge] initialized');
}
```

Returns nothing. The bridge is self-contained after init. `applyDiffs` is private. `wasm` is module-private (imports reference it through closure).

### 2.4 Required WASM Exports (Protocol Contract)

The bridge requires these exports from any WASM module:

| Export                        | Signature         | Called when                     |
|-------------------------------|-------------------|---------------------------------|
| `init`                        | `() → void`       | Bridge initialization           |
| `process_event`               | `() → void`       | Any DOM event fires             |
| `on_fetch_complete`           | `(status, len)`   | HTTP fetch resolves             |
| `on_timer_complete`           | `(callbackId)`    | setTimeout fires                |
| `on_file_open_complete`       | `(handle, size)`  | File read completes             |
| `on_decompress_complete`      | `(handle, size)`  | Decompression completes         |
| `on_kv_complete`              | `(success)`       | IndexedDB put/delete completes  |
| `on_kv_get_complete`          | `(len)`           | IndexedDB get completes (small) |
| `on_kv_get_blob_complete`     | `(handle, size)`  | IndexedDB get completes (large) |
| `on_clipboard_copy_complete`  | `(success)`       | Clipboard write completes       |
| `get_event_buffer_ptr`        | `() → ptr`        | Initialization                  |
| `get_diff_buffer_ptr`         | `() → ptr`        | Initialization                  |
| `get_fetch_buffer_ptr`        | `() → ptr`        | Initialization                  |
| `get_string_buffer_ptr`       | `() → ptr`        | Initialization                  |
| `memory`                      | (Memory export)   | Always                          |

Optional exports (called if present):

| Export                  | Signature   | Called when                        |
|-------------------------|-------------|------------------------------------|
| `on_visibility_hidden`  | `() → void` | Page hidden (tab switch, minimize) |

---

## 3. ATS2 → WASM Pipeline

### 3.1 Toolchain

**ATS2 (ATS/Postiats):** Compiles `.dats`/`.sats` to C.

```bash
git clone https://github.com/githwxi/ATS-Postiats.git
cd ATS-Postiats
./configure
make
export PATSHOME=$(pwd)
export PATH=$PATSHOME/bin:$PATH
```

**wasi-sdk** (for clang targeting wasm32): Provides clang with a minimal libc.

```bash
# Download from https://github.com/WebAssembly/wasi-sdk/releases
export WASI_SDK=/opt/wasi-sdk
```

Alternatively, for a fully freestanding build (no WASI imports), use standard clang:

```bash
# Uses system clang with --target=wasm32
# Requires providing our own malloc/memcpy/etc in runtime.c
```

The freestanding approach produces a leaner module with zero import dependencies beyond the bridge.

### 3.2 Build Process

```
src/*.sats ─┐
             ├─ patsopt ─→ build/*.c ─┐
src/*.dats ─┘                         ├─ clang ─→ build/quire.wasm
                         runtime.c ───┘
```

**Makefile:**

```makefile
PATSOPT  = patsopt
CC       = clang
CFLAGS   = --target=wasm32 -nostdlib -O2 -I$(PATSHOME)/ccomp/runtime
LDFLAGS  = -Wl,--no-entry -Wl,--allow-undefined

EXPORTS  = -Wl,--export=init \
           -Wl,--export=process_event \
           -Wl,--export=on_fetch_complete \
           -Wl,--export=on_timer_complete \
           -Wl,--export=on_file_open_complete \
           -Wl,--export=on_decompress_complete \
           -Wl,--export=on_kv_complete \
           -Wl,--export=on_kv_get_complete \
           -Wl,--export=on_kv_get_blob_complete \
           -Wl,--export=on_clipboard_copy_complete \
           -Wl,--export=get_event_buffer_ptr \
           -Wl,--export=get_diff_buffer_ptr \
           -Wl,--export=get_fetch_buffer_ptr \
           -Wl,--export=get_string_buffer_ptr \
           -Wl,--export=memory

ATS_SRC  = src/quire.dats src/dom.dats src/epub.dats src/reader.dats
C_GEN    = $(patsubst src/%.dats,build/%_dats.c,$(ATS_SRC))

build/quire.wasm: $(C_GEN) src/runtime.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(EXPORTS) -o $@ $^

build/%_dats.c: src/%.dats src/%.sats
	$(PATSOPT) --output $@ --dynamic $<

clean:
	rm -f build/*

.PHONY: clean
```

`--allow-undefined` permits the `js_*` bridge imports to resolve at instantiation time.

### 3.3 WASM Runtime Support (runtime.c)

Freestanding WASM needs a minimal C runtime. ATS2's generated C uses `malloc`, `memcpy`, `memset`, and a few other libc functions.

```c
/* runtime.c — minimal C runtime for freestanding WASM */

#define HEAP_SIZE (1 << 20)  /* 1 MB initial heap */

static unsigned char __heap[HEAP_SIZE];
static unsigned long __heap_offset = 0;

void* malloc(unsigned long size) {
    size = (size + 7) & ~7;  /* 8-byte align */
    if (__heap_offset + size > HEAP_SIZE) return 0;
    void* ptr = &__heap[__heap_offset];
    __heap_offset += size;
    return ptr;
}

void free(void* ptr) {
    /* bump allocator: free is a no-op */
    /* safe because ATS2 linear types prevent use-after-free */
    (void)ptr;
}

void* calloc(unsigned long n, unsigned long size) {
    void* ptr = malloc(n * size);
    if (ptr) __builtin_memset(ptr, 0, n * size);
    return ptr;
}

void* memcpy(void* dst, const void* src, unsigned long n) {
    return __builtin_memcpy(dst, src, n);
}

void* memset(void* dst, int c, unsigned long n) {
    return __builtin_memset(dst, c, n);
}

void* memmove(void* dst, const void* src, unsigned long n) {
    return __builtin_memmove(dst, src, n);
}

int memcmp(const void* a, const void* b, unsigned long n) {
    return __builtin_memcmp(a, b, n);
}

/* Shared buffers — addresses exported to bridge */
static unsigned char event_buffer[256];
static unsigned char diff_buffer[4096];
static unsigned char fetch_buffer[16384];
static unsigned char string_buffer[4096];

unsigned char* get_event_buffer_ptr(void) { return event_buffer; }
unsigned char* get_diff_buffer_ptr(void)  { return diff_buffer; }
unsigned char* get_fetch_buffer_ptr(void) { return fetch_buffer; }
unsigned char* get_string_buffer_ptr(void) { return string_buffer; }
```

The bump allocator is appropriate because ATS2's linear type system prevents memory leaks at compile time. If a more sophisticated allocator is needed later, `free` can be made real without changing any other code.

### 3.4 Type-Level DOM Model

The core insight: the ATS2 code maintains a compile-time model of what the DOM looks like. Diff operations are typed as state transitions. If the program compiles, the diffs are valid.

**dom.sats** (types):

```ats2
(* A node that exists in the DOM with a given ID *)
abstype dom_node(id: int)

(* Proof that node [id] exists as a child of [parent] *)
absprop node_exists(id: int, parent: int)

(* Proof that node [id] has been removed *)
absprop node_removed(id: int)

(* Create element: given proof parent exists, produces proof child exists *)
fun create_element
  {parent: int} {child: int}
  (pf: node_exists(parent, _) | parent: int(parent), child: int(child),
   tag: string): (node_exists(child, parent) | void)

(* Remove child: consumes proof of existence, produces proof of removal *)
fun remove_child
  {id: int} {parent: int}
  (pf: node_exists(id, parent) | id: int(id)): (node_removed(id) | void)

(* Set text: requires proof node exists *)
fun set_text
  {id: int}
  (pf: !node_exists(id, _) | id: int(id), text: string): void

(* Set transform: requires proof node exists *)
fun set_transform
  {id: int}
  (pf: !node_exists(id, _) | id: int(id), x: int, y: int): void

(* Set innerHTML: requires proof node exists *)
fun set_inner_html
  {id: int}
  (pf: !node_exists(id, _) | id: int(id), html: string): void
```

The `!` prefix means the proof is *not consumed* — it can be reused. `create_element` produces a new proof. `remove_child` consumes the old proof and produces a `node_removed` proof that prevents further operations on that node. The type checker enforces:

- Cannot set text on a node that hasn't been created
- Cannot set text on a node that has been removed
- Cannot remove the same node twice
- Cannot create a child under a parent that doesn't exist

This is the "dataprops guarantee" — the dependent type system makes invalid diff sequences unrepresentable.

---

## 4. E-Reader Architecture

### 4.1 EPUB Processing Pipeline

EPUB is a ZIP file containing XHTML chapters, CSS, images, fonts, and metadata files. The processing pipeline:

```
User selects file
       │
       ▼
js_file_open(inputNodeId)
       │
       ▼
WASM reads ZIP headers via js_file_read_chunk
(ZIP end-of-central-directory → central directory → entry list)
       │
       ▼
For each entry:
  ├─ js_decompress(fileHandle, offset, size, DEFLATE_RAW)
  │    → blob handle
  ├─ Classify entry by path/extension:
  │    ├─ META-INF/container.xml → parse for .opf path
  │    ├─ *.opf → parse manifest + spine + metadata
  │    ├─ XHTML chapters → store in "chapters" IDB store
  │    ├─ CSS/images/fonts → store in "resources" IDB store
  │    └─ Other → skip
  └─ js_kv_put_blob(store, key, blobHandle)
       │
       ▼
Store book metadata in "books" IDB store
(title, author, spine order, cover image ref, etc.)
       │
       ▼
Navigate to first chapter
```

ZIP parsing happens in ATS2. The format is straightforward: read the end-of-central-directory record (last 22+ bytes), find the central directory offset, iterate entries. Each entry has a local file header with compressed data immediately following. WASM reads headers via `js_file_read_chunk` (synchronous, small reads) and hands compressed regions to `js_decompress` (async, returns blob handle).

XML parsing (container.xml, .opf) can be done in ATS2 with a minimal SAX-style parser. These files are small (< 10KB typically) and can be read entirely into the fetch buffer.

### 4.2 IndexedDB Schema

Three object stores, all within a single database:

**`books`** — keyed by generated book ID (hash of title+author or UUID)

```
{
  id: string,
  title: string,
  author: string,
  language: string,
  spine: [string],       // ordered chapter keys
  coverRef: string,      // key into resources store
  currentChapter: int,   // last read spine index
  currentPage: int,      // last read page within chapter
  addedAt: int           // timestamp
}
```

**`chapters`** — keyed by `"{bookId}/{spine-href}"`

```
ArrayBuffer of processed XHTML bytes
```

The XHTML is processed at import time:
- Resource references (`src`, `href`) are rewritten to blob URL placeholders
- Inline styles are sanitized
- Scripts are stripped

**`resources`** — keyed by `"{bookId}/{manifest-href}"`

```
ArrayBuffer of raw resource bytes (images, fonts, CSS)
```

At render time, the WASM module loads a chapter's XHTML from IndexedDB and rewrites placeholder URLs to actual blob URLs created from the resources store. This two-pass approach (rewrite at import, resolve at render) keeps imports fast and allows lazy resource loading.

### 4.3 Three-Chapter Sliding Window

The reader maintains three chapter containers in the DOM at all times:

```
┌──────────────────────────────────────────────────────┐
│ reader-viewport (overflow: hidden, 100vw × 100vh)    │
│                                                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │
│  │ prev-chapter│ │ curr-chapter│ │ next-chapter│    │
│  │ (rendered,  │ │ (rendered,  │ │ (rendered,  │    │
│  │  offscreen) │ │  visible)   │ │  offscreen) │    │
│  └─────────────┘ └─────────────┘ └─────────────┘   │
│                                                      │
└──────────────────────────────────────────────────────┘
```

Each container holds a fully rendered chapter using CSS column layout. The visible container is positioned at `translate(0, 0)`. The other two are offscreen (e.g., at `translate(-100vw * pageCount, 0)` and `translate(100vw * pageCount, 0)`).

Page turn within a chapter: single `SET_TRANSFORM` diff on the container.

Chapter boundary crossing:

```
State: [prev=Ch2, curr=Ch3, next=Ch4], page = lastPage(Ch3)

User turns to next page:

1. curr becomes prev   (Ch3 → prev slot)
2. next becomes curr   (Ch4 → curr slot, page 0)
3. Load Ch5 into old prev slot → becomes new next
4. Drop Ch2 from DOM

State: [prev=Ch3, curr=Ch4, next=Ch5], page = 0
```

In ATS2, this is modeled as a state machine. The type system ensures:
- There is always a current chapter
- Chapter loads complete before they become current
- The sliding window never has gaps

At the first chapter, `prev` is empty. At the last chapter, `next` is empty. The type models these as `option` types.

### 4.4 CSS Column Pagination

Each chapter container uses CSS multi-column layout:

```css
.chapter-container {
  column-width: var(--page-width);
  column-gap: var(--page-gap);
  height: var(--content-height);
  overflow: visible;        /* columns extend horizontally */
}

.reader-viewport {
  width: 100vw;
  height: 100vh;
  overflow: hidden;         /* clip to single page */
  position: relative;
}
```

The browser lays out chapter XHTML into vertical columns, each the width of the viewport. Columns extend horizontally beyond the viewport. The viewport clips everything to show a single "page."

**Measuring page count:** After setting `innerHTML` and allowing layout, measure the container:

```
pageStride = pageWidth + pageGap
pageCount  = ceil(scrollWidth / pageStride)
```

`js_measure_node` provides `scrollWidth`. WASM computes page count.

**Navigating to page N:**

```
SET_TRANSFORM(containerNodeId, -(N * pageStride), 0)
```

One diff. Instant.

**CSS variables** for reader settings:

```css
:root {
  --page-width: 100vw;
  --page-gap: 0px;
  --content-height: calc(100vh - 4rem);
  --font-size: 18px;
  --line-height: 1.6;
  --font-family: Georgia, serif;
  --bg-color: #fafaf8;
  --text-color: #2a2a2a;
}
```

Settings changes (font size, margins, theme) update CSS variables via `SET_ATTR` on `:root`, which triggers browser relayout. WASM then re-measures to get new page counts.

### 4.5 Page Turns and Input Handling

The WASM module receives click and keyboard events through the bridge.

**Touch/click zones:** Divide the viewport into three horizontal zones:

```
┌─────────┬─────────────────────┬─────────┐
│  prev   │                     │  next   │
│  page   │    (tap for menu)   │  page   │
│  (20%)  │       (60%)         │  (20%)  │
└─────────┴─────────────────────┴─────────┘
```

WASM receives click events with coordinates (via extending the event buffer to include x/y), determines which zone was hit, and emits the appropriate `SET_TRANSFORM` diff.

**Keyboard:**
- Left arrow, Page Up: previous page
- Right arrow, Page Down, Space: next page
- Home: first page of chapter
- End: last page of chapter

**Swipe gestures (future):** The bridge would need `touchstart`/`touchmove`/`touchend` events. These are generic DOM events and fit the existing protocol — just add `EVENT_TOUCHSTART`, `EVENT_TOUCHMOVE`, `EVENT_TOUCHEND` constants and forward them. WASM handles gesture recognition.

---

## 5. PWA Configuration

### 5.1 manifest.json

```json
{
  "name": "Quire",
  "short_name": "Quire",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#fafaf8",
  "theme_color": "#fafaf8",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

### 5.2 Service Worker

Minimal — caches the app shell (HTML, JS, WASM, CSS) for offline use. Book data is already in IndexedDB.

```javascript
const CACHE = 'quire-v1';
const SHELL = ['/', '/bridge.js', '/quire.wasm', '/reader.css', '/manifest.json'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));
});

self.addEventListener('fetch', e => {
  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));
});
```

Cache-first strategy. The WASM binary and bridge are immutable between versions; service worker update handles cache busting.

---

## 6. Project Structure

```
quire/
├── .github/
│   └── workflows/
│       ├── pr.yaml               # PR checks: bridge tests + WASM build
│       └── upload.yaml           # Main merge: package PWA artifact
├── CLAUDE.md
├── Makefile
├── package.json
├── index.html
├── manifest.json
├── service-worker.js
├── bridge.js
├── reader.css
├── src/
│   ├── runtime.c
│   ├── quire.sats
│   ├── quire.dats
│   ├── dom.sats
│   ├── dom.dats
│   ├── epub.sats
│   ├── epub.dats
│   ├── reader.sats
│   └── reader.dats
├── build/                        # Generated files (gitignored)
│   ├── *_dats.c
│   └── quire.wasm
└── test/
    ├── bridge.test.js            # Bridge protocol tests
    └── mock-wasm.js              # Mock WASM module for bridge tests
```

---

## 7. CLAUDE.md Specification

The `CLAUDE.md` file establishes project rules for AI coding agents. Contents:

```markdown
# Quire — Project Guidelines

## Architecture

Quire is a PWA e-reader. All application logic lives in ATS2, compiled to WASM.
A generic JavaScript bridge (bridge.js) connects WASM to the browser DOM.

## Hard Rules

1. **No application code in index.html.** The HTML file contains only a loading
   container and `import { initBridge } from './bridge.js'; await initBridge('quire.wasm');`.

2. **bridge.js is generic.** Only add code that is:
   - Required for WASM to access browser APIs not available in WASM
   - Not specific to any single application
   - bridge.js should be publishable as an npm package

3. **All UI logic lives in WASM.** The bridge never decides what to render, when to
   navigate, or how to respond to events. It forwards events to WASM and applies
   diffs from WASM.

4. **WASM owns the node ID space.** The bridge maintains a lookup table but never
   allocates node IDs. IDs are assigned by WASM via CREATE_ELEMENT diffs.

5. **Dependent types enforce correctness.** DOM operations in ATS2 carry proofs of
   node existence. If it compiles, the diffs are valid.

## Build

    make                    # Build quire.wasm
    make clean              # Remove build artifacts
    npx serve .             # Dev server

## Protocol

See design.md §2 for the bridge protocol specification, including:
- Diff buffer layout (16-byte aligned entries)
- Op codes and their encodings
- Required WASM exports
- JS import signatures

## File Conventions

- `.sats` files: type declarations and function signatures (the "interface")
- `.dats` files: implementations (the "code")
- Every `.dats` file has a corresponding `.sats` file
- runtime.c: minimal C runtime, only libc shims needed by ATS2 codegen

## Testing

Bridge protocol tests use a mock WASM module that emits known diff sequences.
Run: `npm test`

## CI

Two GitHub Actions workflows enforce quality:

- `pr.yaml` — runs on every PR. Runs bridge unit tests (`npm test`) and
  builds `quire.wasm` from ATS2 source. Both must pass to merge.
- `upload.yaml` — runs on merge to main. Builds the WASM, collects all PWA
  assets, and uploads a `quire-pwa` artifact. Download the artifact to get
  a deployable directory.

The ATS2 toolchain is built from source and cached. Cache key includes the
ATS-Postiats commit hash pinned in the workflow.
```

---

## 8. Milestones

Each milestone is a single PR. Milestones are ordered by dependency.

### Phase 0: Foundation

- [x] **M1: Project scaffold + CLAUDE.md**
  - Create directory structure per §6
  - Write CLAUDE.md per §7
  - `index.html` with loading div and two-line script
  - `manifest.json`
  - `.gitignore` (build/, node_modules/)
  - `package.json` with dev server script
  - `.github/workflows/pr.yaml` and `.github/workflows/upload.yaml` per §9
  - `test/mock-wasm.js`: mock WASM module with buffer exports
  - `test/bridge.test.js`: initial test scaffolding (node registry, event encoding)
  - `package.json` includes `vitest` and `jsdom` as dev dependencies, `"test": "vitest run"`

Bridge test coverage expands incrementally: M2–M4 each add tests for the bridge changes made in that milestone.

- [x] **M2: Bridge refactoring — remove app-specific code**
  - Remove contact templates and other swiftlink-specific UI code
  - Remove `initApp`, export `initBridge`
  - Result: bridge compiles and runs but has old op codes

- [x] **M3: Bridge refactoring — fix bugs + align protocol**
  - Fix diff entry stride overlap (§2.2, Bug 1): change to 16-byte stride
  - Fix OP_SET_ATTR placeholder (§2.2, Bug 2)
  - Update op codes: SET_TRANSFORM, CREATE_ELEMENT, SET_INNER_HTML, simplified SET_TEXT (§2.3.1–§2.3.5)
  - Result: all op codes match new protocol spec

- [x] **M4: Bridge refactoring — auto-flush + new imports**
  - Add `wrapExports` proxy (§2.3.11)
  - Move `applyDiffs` to private, remove all manual calls
  - `initBridge` calls `wasm.init()` (§2.3.12)
  - Add `js_measure_node` (§2.3.6)
  - Result: bridge is generic, self-contained, two-line bootstrap

### Phase 1: Build Pipeline

- [x] **M5: ATS2 → WASM build pipeline**
  - Install ATS2, document in README
  - `Makefile` per §3.2
  - `runtime.c` per §3.3
  - Minimal `quire.sats`/`quire.dats`: exports `init` that emits one `SET_TEXT` diff to replace "Loading…"
  - Verify: `make` produces `quire.wasm`, page shows text from WASM

- [x] **M6: DOM type model**
  - `dom.sats` with proofs per §3.4
  - `dom.dats` with diff emission functions
  - Extend hello world: create elements, set attributes, remove elements — all type-checked
  - Verify: compile-time rejection of invalid diff sequences

### Phase 2: File Handling

- [x] **M7: Bridge file + blob + decompression imports**
  - Add `js_file_open`, `js_file_read_chunk`, `js_file_close` (§2.3.7)
  - Add `js_decompress`, `js_blob_read_chunk`, `js_blob_size`, `js_blob_free` (§2.3.8)
  - Add `js_set_inner_html_from_blob` (§2.3.10)
  - Bridge-only PR — no app logic

- [x] **M8: Bridge IndexedDB imports**
  - Add `js_kv_open`, `js_kv_put`, `js_kv_put_blob`, `js_kv_get`, `js_kv_delete` (§2.3.9)
  - Bridge-only PR

- [x] **M9: EPUB import pipeline**
  - ZIP header parsing in ATS2 (read end-of-central-directory, iterate entries)
  - container.xml parsing → find .opf path
  - .opf parsing → extract metadata, spine, manifest
  - Decompress + store chapters and resources in IndexedDB
  - Basic UI: file input button, import progress, book title display
  - Verify: upload an EPUB, inspect IndexedDB to confirm correct storage

### Phase 3: Rendering

- [x] **M10: Single chapter rendering**
  - Load chapter XHTML from IndexedDB
  - Rewrite resource URLs to blob URLs
  - Inject via `SET_INNER_HTML` (or `js_set_inner_html_from_blob`)
  - CSS styles built and injected from WASM (CSS column layout)
  - Verify: chapter text appears, flows into columns

- [x] **M11: Pagination**
  - Use `js_measure_node` to get scrollWidth
  - Compute page count
  - `SET_TRANSFORM` for page navigation
  - Click zones (left/right 20% of viewport) for prev/next page
  - Keyboard navigation (arrows, space, page up/down)
  - Page number display
  - Verify: can read through an entire chapter page by page

- [x] **M12: Three-chapter sliding window**
  - `reader.sats`/`reader.dats` with sliding window state machine
  - Preload next/previous chapters
  - Chapter boundary transitions (§4.3)
  - Type-safe transitions enforced by dataprops
  - Verify: seamless reading across chapter boundaries

### Phase 4: Polish

- [x] **M13: Navigation UI**
  - Table of contents overlay (parsed from .opf/NCX)
  - Progress bar
  - Chapter title display
  - Jump to chapter

- [x] **M14: Reader settings**
  - Font size, font family
  - Theme (light, dark, sepia)
  - Line height, margins
  - Persist settings to IndexedDB
  - Re-measure page count on settings change

- [ ] **M15: Book library**
  - List imported books with title, author, cover
  - Last read position
  - Delete book (remove from IndexedDB)
  - Open book → resume at last position

- [ ] **M16: PWA finalization**
  - `service-worker.js` with cache-first strategy
  - App shell caching
  - Offline verification
  - Icon assets (192px, 512px)

### Phase 5: Touch + Future

- [ ] **M17: Touch gestures**
  - Add touch event forwarding to bridge (EVENT_TOUCHSTART, TOUCHMOVE, TOUCHEND)
  - Swipe gesture recognition in WASM
  - Animated page transitions via `SET_TRANSFORM`

- [ ] **M18: Bridge npm package extraction**
  - Extract bridge.js into standalone package
  - TypeScript declarations for the protocol
  - Documentation: required exports, import signatures, buffer layouts
  - Example: minimal WASM app using the bridge

---

## 9. CI/CD Workflows

### 9.1 PR Checks (`.github/workflows/pr.yaml`)

Triggered on every pull request. Two jobs run in parallel: bridge unit tests and WASM build. Both must pass.

**Bridge tests** run under Node with jsdom. The test suite (`test/bridge.test.js`) imports bridge internals and exercises them against a mock WASM module (`test/mock-wasm.js`) that provides the required exports — buffer pointers into a shared `ArrayBuffer`, a no-op `init`, and a `process_event` that writes known diff sequences into the diff buffer. This validates:

- Node registration and lookup (`registerNode`, `getNode`)
- Event encoding (`writeEvent` writes correct bytes at correct offsets)
- Diff application for every op code: `SET_TEXT`, `SET_ATTR`, `SET_TRANSFORM`, `CREATE_ELEMENT`, `REMOVE_CHILD`, `SET_INNER_HTML`
- The 16-byte stride alignment (no off-by-one on multi-entry diff buffers)
- The `wrapExports` proxy (every call flushes diffs, pointer getters are not wrapped)
- String buffer read helpers (`getStringFromBuffer`, `getStringFromFetchBuffer`)
- File and blob handle lifecycle (open/read/close with mock data)
- Error paths (missing nodes, unknown ops, zero-length strings)

The mock WASM module is a plain JS object that mimics the WASM export surface. It allocates a single `ArrayBuffer` and returns offsets into it for the four buffer pointers. Tests write crafted byte sequences into the diff buffer, then call `applyDiffs` (or trigger it through the proxy) and assert DOM state via jsdom.

**WASM build** installs ATS2 from source (cached) and system clang with `lld` for `wasm-ld`. Runs `make` and verifies `build/quire.wasm` exists. The ATS-Postiats commit is pinned in the workflow to ensure reproducible builds; updating it is a deliberate choice, not something that drifts.

```yaml
name: PR Checks

on:
  pull_request:
    branches: [main]

concurrency:
  group: pr-${{ github.head_ref }}
  cancel-in-progress: true

env:
  ATS_COMMIT: "d12abf1da4476cbe33a448c28726cc350af3ce6d"  # Pin ATS-Postiats version; update deliberately

jobs:
  bridge-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci
      - run: npm test

  build-wasm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache ATS2 toolchain
        id: cache-ats
        uses: actions/cache@v4
        with:
          path: ~/ats2
          key: ats2-${{ env.ATS_COMMIT }}-${{ runner.os }}

      - name: Build ATS2
        if: steps.cache-ats.outputs.cache-hit != 'true'
        run: |
          sudo apt-get update && sudo apt-get install -y libgmp-dev
          git clone https://github.com/githwxi/ATS-Postiats.git ~/ats2
          cd ~/ats2
          git checkout ${{ env.ATS_COMMIT }}
          ./configure
          make -j$(nproc)

      - name: Install WASM toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y clang lld

      - name: Build quire.wasm
        env:
          PATSHOME: ~/ats2
          PATH: ~/ats2/bin:$PATH
        run: |
          make
          test -f build/quire.wasm
```

### 9.2 PWA Packaging (`.github/workflows/upload.yaml`)

Triggered on push to `main` (i.e., merged PRs). Builds the WASM binary, assembles all files needed to serve the PWA into a staging directory, and uploads it as a GitHub Actions artifact named `quire-pwa`. Downloading and extracting this artifact gives a directory that can be served from any static host.

The artifact contains:

```
quire-pwa/
├── index.html
├── bridge.js
├── quire.wasm
├── reader.css
├── manifest.json
├── service-worker.js
├── icon-192.png
└── icon-512.png
```

No build step touches `bridge.js`, `index.html`, or `reader.css` — they are static assets copied as-is. Only `quire.wasm` is built.

```yaml
name: Package PWA

on:
  push:
    branches: [main]

env:
  ATS_COMMIT: "d12abf1da4476cbe33a448c28726cc350af3ce6d"

jobs:
  package:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache ATS2 toolchain
        id: cache-ats
        uses: actions/cache@v4
        with:
          path: ~/ats2
          key: ats2-${{ env.ATS_COMMIT }}-${{ runner.os }}

      - name: Build ATS2
        if: steps.cache-ats.outputs.cache-hit != 'true'
        run: |
          sudo apt-get update && sudo apt-get install -y libgmp-dev
          git clone https://github.com/githwxi/ATS-Postiats.git ~/ats2
          cd ~/ats2
          git checkout ${{ env.ATS_COMMIT }}
          ./configure
          make -j$(nproc)

      - name: Install WASM toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y clang lld

      - name: Build quire.wasm
        env:
          PATSHOME: ~/ats2
          PATH: ~/ats2/bin:$PATH
        run: make

      - name: Assemble PWA
        run: |
          mkdir -p dist
          cp index.html dist/
          cp bridge.js dist/
          cp reader.css dist/
          cp manifest.json dist/
          cp service-worker.js dist/
          cp build/quire.wasm dist/
          # Icons may not exist yet (M16); copy if present
          cp icon-192.png dist/ 2>/dev/null || true
          cp icon-512.png dist/ 2>/dev/null || true

      - name: Upload PWA artifact
        uses: actions/upload-artifact@v4
        with:
          name: quire-pwa
          path: dist/
          retention-days: 90
```

### 9.3 Design Notes

**Why not wasi-sdk?** The build is freestanding (`-nostdlib`, `--target=wasm32`, `--allow-undefined`). System clang plus `lld` (which provides `wasm-ld`) is sufficient and avoids downloading a 200MB+ SDK tarball on every uncached run. If the build ever needs WASI imports, switch to wasi-sdk and cache it the same way as ATS2.

**Why pin the ATS-Postiats commit?** ATS2 development is active and occasionally introduces breaking changes in codegen. Pinning to a known-good commit prevents mysterious CI failures unrelated to Quire changes. Bumping the pin is a one-line change in both workflow files (via the shared `ATS_COMMIT` env var).

**GitHub Pages deployment:** The `upload.yaml` workflow both uploads an artifact and deploys to GitHub Pages. The artifact remains available as a universal intermediate for alternative deployment targets (Cloudflare, Netlify, custom servers).

**Artifact retention** is set to 90 days. Older builds can always be regenerated from the corresponding commit.
