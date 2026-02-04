/**
 * Generic WASM-to-DOM bridge
 *
 * This bridge connects any WASM module to the browser DOM. It provides:
 * - Event forwarding from DOM to WASM
 * - Diff-based DOM updates from WASM
 * - Async I/O primitives (fetch, storage, timers)
 * - Push notification support
 *
 * The bridge is generic and contains no application-specific logic.
 * All UI decisions are made by the WASM module.
 */

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
const OP_SET_TRANSFORM = 3;
const OP_CREATE_ELEMENT = 4;
const OP_REMOVE_CHILD = 5;
const OP_SET_INNER_HTML = 6;

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

const PUSH_DB_NAME = 'bridge-push';
const PUSH_STORE_NAME = 'pending';
const PUSH_DB_VERSION = 1;

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
      const tag = tagLen > 0 ? readString(tagPtr, tagLen) : 'bridge';
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
    // 16-byte stride with 4-byte aligned fields
    // Header at byte 0, entries start at byte 4
    const offset = 4 + i * 16;
    const op = view.getUint32(offset, true);
    const nodeId = view.getUint32(offset + 4, true);
    const value1 = view.getUint32(offset + 8, true);
    const value2 = view.getUint32(offset + 12, true);

    const node = getNode(nodeId);

    switch (op) {
      case OP_SET_TEXT:
        // value1 = offset in fetch buffer, value2 = length
        if (node) {
          node.textContent = value2 > 0 ? getStringFromFetchBuffer(value1, value2) : '';
        }
        break;
      case OP_SET_ATTR: {
        // value1 = name length, value2 = value length
        // Name at stringBuffer[0..value1], value at stringBuffer[value1..value1+value2]
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
      case OP_SET_TRANSFORM:
        // value1 = x (int32), value2 = y (int32)
        if (node) {
          const x = value1 | 0;  // reinterpret uint32 as int32
          const y = value2 | 0;
          node.style.transform = `translate(${x}px, ${y}px)`;
        }
        break;
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
      case OP_REMOVE_CHILD:
        if (node && node.parentNode) node.parentNode.removeChild(node);
        break;
      case OP_SET_INNER_HTML:
        // value1 = offset in fetch buffer, value2 = length
        if (node) {
          node.innerHTML = getStringFromFetchBuffer(value1, value2);
        }
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

export async function initBridge(wasmUrl) {
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

  console.log('[Bridge] initialized');
}

// Test helper: initialize bridge with a provided mock module (bypasses fetch)
export function _initForTest(mockModule) {
  wasm = mockModule;
  memory = mockModule.exports.memory;

  eventBuffer = new Uint8Array(memory.buffer, mockModule.exports.get_event_buffer_ptr(), EVENT_BUFFER_SIZE);
  diffBuffer = new Uint8Array(memory.buffer, mockModule.exports.get_diff_buffer_ptr(), DIFF_BUFFER_SIZE);
  fetchBuffer = new Uint8Array(memory.buffer, mockModule.exports.get_fetch_buffer_ptr(), FETCH_BUFFER_SIZE);
  stringBuffer = new Uint8Array(memory.buffer, mockModule.exports.get_string_buffer_ptr(), 4096);
}

// Test helper: apply diffs (for testing without full initialization)
export function _applyDiffs() {
  applyDiffs();
}

// Test helper: clear node registry (for test isolation)
export function _clearNodeRegistry() {
  nodeRegistry.clear();
  nextNodeId = 1;
}

export { registerNode, getNode };
