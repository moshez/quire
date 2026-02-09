// ward_bridge.mjs — Bridge between ward WASM and a DOM document
// Parses the ward binary diff protocol and applies it to a standard DOM.
// Works in any ES module environment (browser or Node.js).

// Parse a little-endian i32 from a Uint8Array at offset
function readI32(buf, off) {
  return buf[off] | (buf[off+1] << 8) | (buf[off+2] << 16) | (buf[off+3] << 24);
}

// Write a little-endian i32 into a Uint8Array at offset
function writeI32(buf, off, v) {
  buf[off]   = v & 0xff;
  buf[off+1] = (v >>> 8) & 0xff;
  buf[off+2] = (v >>> 16) & 0xff;
  buf[off+3] = (v >>> 24) & 0xff;
}

/**
 * Load a ward WASM module and connect it to a DOM document.
 *
 * @param {BufferSource} wasmBytes — compiled WASM bytes
 * @param {Element} root — root element for ward to render into (node_id 0)
 * @param {object} [opts] — optional configuration
 * @param {object} [opts.extraImports] — additional WASM imports merged into env
 * @returns {{ exports, nodes, done }} — WASM exports, node registry,
 *   and a promise that resolves when WASM calls ward_exit
 */
export async function loadWard(wasmBytes, root, opts) {
  const document = root.ownerDocument;
  const window = document.defaultView;
  let instance = null;
  let resolveDone;
  const done = new Promise(r => { resolveDone = r; });

  // Node registry: node_id -> DOM element
  const nodes = new Map();
  nodes.set(0, root);

  // Active event listener state
  const listeners = new Map();  // listenerId -> { node, type, handler }
  let currentEvent = null;

  // File handle cache: handle -> { buffer: ArrayBuffer, size: int }
  const fileCache = new Map();
  let nextFileHandle = 1;

  // Blob cache: handle -> ArrayBuffer (decompressed)
  const blobCache = new Map();
  let nextBlobHandle = 1;

  function readBytes(ptr, len) {
    return new Uint8Array(instance.exports.memory.buffer, ptr, len).slice();
  }

  function readString(ptr, len) {
    return new TextDecoder().decode(readBytes(ptr, len));
  }

  function writeBytes(ptr, data) {
    new Uint8Array(instance.exports.memory.buffer).set(data, ptr);
  }

  // --- DOM flush ---

  function wardDomFlush(bufPtr, len) {
    const mem = new Uint8Array(instance.exports.memory.buffer);
    const buf = mem.slice(bufPtr, bufPtr + len);

    const op = buf[0];
    const nodeId = readI32(buf, 1);

    switch (op) {
      case 4: { // CREATE_ELEMENT
        const parentId = readI32(buf, 5);
        const tagLen = buf[9];
        const tag = new TextDecoder().decode(buf.slice(10, 10 + tagLen));
        const el = document.createElement(tag);
        nodes.set(nodeId, el);
        const parent = nodes.get(parentId);
        if (parent) parent.appendChild(el);
        break;
      }
      case 1: { // SET_TEXT
        const textLen = buf[5] | (buf[6] << 8);
        const text = new TextDecoder().decode(buf.slice(7, 7 + textLen));
        const el = nodes.get(nodeId);
        if (el) el.textContent = text;
        break;
      }
      case 2: { // SET_ATTR
        const nameLen = buf[5];
        const name = new TextDecoder().decode(buf.slice(6, 6 + nameLen));
        const valOff = 6 + nameLen;
        const valLen = buf[valOff] | (buf[valOff+1] << 8);
        const value = new TextDecoder().decode(buf.slice(valOff + 2, valOff + 2 + valLen));
        const el = nodes.get(nodeId);
        if (el) el.setAttribute(name, value);
        break;
      }
      case 3: { // REMOVE_CHILDREN
        const el = nodes.get(nodeId);
        if (el) {
          while (el.firstChild) el.removeChild(el.firstChild);
        }
        break;
      }
      case 5: { // REMOVE_CHILD — remove a specific node
        const el = nodes.get(nodeId);
        if (el && el.parentNode) {
          el.parentNode.removeChild(el);
          nodes.delete(nodeId);
        }
        break;
      }
      default:
        throw new Error(`Unknown ward DOM op: ${op}`);
    }
  }

  // --- Timer ---

  function wardSetTimer(delayMs, resolverPtr) {
    setTimeout(() => {
      instance.exports.ward_timer_fire(resolverPtr);
    }, delayMs);
  }

  // --- IndexedDB ---

  let dbPromise = null;
  function openDB() {
    if (!dbPromise) {
      dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open('ward', 1);
        req.onupgradeneeded = () => {
          req.result.createObjectStore('kv');
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    }
    return dbPromise;
  }

  function wardIdbPut(keyPtr, keyLen, valPtr, valLen, resolverPtr) {
    const key = readString(keyPtr, keyLen);
    const val = readBytes(valPtr, valLen);
    openDB().then(db => {
      const tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').put(val, key);
      tx.oncomplete = () => {
        instance.exports.ward_idb_fire(resolverPtr, 0);
      };
      tx.onerror = () => {
        instance.exports.ward_idb_fire(resolverPtr, -1);
      };
    });
  }

  function wardIdbGet(keyPtr, keyLen, resolverPtr) {
    const key = readString(keyPtr, keyLen);
    openDB().then(db => {
      const tx = db.transaction('kv', 'readonly');
      const req = tx.objectStore('kv').get(key);
      req.onsuccess = () => {
        const result = req.result;
        if (result === undefined) {
          instance.exports.ward_idb_fire_get(resolverPtr, 0, 0);
        } else {
          const data = new Uint8Array(result);
          const len = data.length;
          const ptr = instance.exports.malloc(len);
          new Uint8Array(instance.exports.memory.buffer).set(data, ptr);
          instance.exports.ward_idb_fire_get(resolverPtr, ptr, len);
        }
      };
      req.onerror = () => {
        instance.exports.ward_idb_fire_get(resolverPtr, 0, 0);
      };
    });
  }

  function wardIdbDelete(keyPtr, keyLen, resolverPtr) {
    const key = readString(keyPtr, keyLen);
    openDB().then(db => {
      const tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').delete(key);
      tx.oncomplete = () => {
        instance.exports.ward_idb_fire(resolverPtr, 0);
      };
      tx.onerror = () => {
        instance.exports.ward_idb_fire(resolverPtr, -1);
      };
    });
  }

  // --- Window ---

  function wardJsFocusWindow() {
    if (window) window.focus();
  }

  function wardJsGetVisibilityState() {
    if (typeof document.visibilityState === 'string') {
      return document.visibilityState === 'hidden' ? 1 : 0;
    }
    return 0; // visible
  }

  function wardJsLog(level, msgPtr, msgLen) {
    const msg = readString(msgPtr, msgLen);
    const labels = ['debug', 'info', 'warn', 'error'];
    const label = labels[level] || 'log';
    console.log(`[ward:${label}] ${msg}`);
  }

  // --- Navigation ---

  function wardJsGetUrl(outPtr, maxLen) {
    if (!window) return 0;
    const bytes = new TextEncoder().encode(window.location.href);
    const n = Math.min(bytes.length, maxLen);
    writeBytes(outPtr, bytes.subarray(0, n));
    return n;
  }

  function wardJsGetUrlHash(outPtr, maxLen) {
    if (!window) return 0;
    const hash = window.location.hash;
    const bytes = new TextEncoder().encode(hash);
    const n = Math.min(bytes.length, maxLen);
    writeBytes(outPtr, bytes.subarray(0, n));
    return n;
  }

  function wardJsSetUrlHash(hashPtr, hashLen) {
    if (!window) return;
    window.location.hash = readString(hashPtr, hashLen);
  }

  function wardJsReplaceState(urlPtr, urlLen) {
    if (!window) return;
    const url = readString(urlPtr, urlLen);
    window.history.replaceState(null, '', url);
  }

  function wardJsPushState(urlPtr, urlLen) {
    if (!window) return;
    const url = readString(urlPtr, urlLen);
    window.history.pushState(null, '', url);
  }

  // --- DOM read ---

  function wardJsMeasureNode(nodeId) {
    const el = nodes.get(nodeId);
    if (!el) {
      for (let i = 0; i < 6; i++) instance.exports.ward_measure_set(i, 0);
      return 0;
    }
    const rect = el.getBoundingClientRect();
    instance.exports.ward_measure_set(0, Math.round(rect.x));
    instance.exports.ward_measure_set(1, Math.round(rect.y));
    instance.exports.ward_measure_set(2, Math.round(rect.width));
    instance.exports.ward_measure_set(3, Math.round(rect.height));
    instance.exports.ward_measure_set(4, el.scrollWidth | 0);
    instance.exports.ward_measure_set(5, el.scrollHeight | 0);
    return 1;
  }

  function wardJsQuerySelector(selectorPtr, selectorLen) {
    const selector = readString(selectorPtr, selectorLen);
    const el = document.querySelector(selector);
    if (!el) return -1;
    // Find node_id for element in registry
    for (const [id, node] of nodes) {
      if (node === el) return id;
    }
    return -1;
  }

  // --- Event listener ---

  function encodeEventPayload(event, type) {
    // Encode event data as bytes for WASM consumption
    // Format: type-dependent fields as little-endian i32s
    const parts = [];

    if (type === 'click' || type === 'mousedown' || type === 'mouseup' ||
        type === 'pointerdown' || type === 'pointerup') {
      // [clientX:i32, clientY:i32]
      const buf = new Uint8Array(8);
      writeI32(buf, 0, Math.round(event.clientX || 0));
      writeI32(buf, 4, Math.round(event.clientY || 0));
      return buf;
    }

    if (type === 'keydown' || type === 'keyup') {
      // [keyCode:i32, modifiers:i32]
      // modifiers: bit0=shift, bit1=ctrl, bit2=alt, bit3=meta
      const buf = new Uint8Array(8);
      writeI32(buf, 0, event.keyCode || 0);
      const mods = (event.shiftKey ? 1 : 0) | (event.ctrlKey ? 2 : 0) |
                   (event.altKey ? 4 : 0) | (event.metaKey ? 8 : 0);
      writeI32(buf, 4, mods);
      return buf;
    }

    if (type === 'input' || type === 'change') {
      // [value as UTF-8 bytes]
      const val = event.target ? (event.target.value || '') : '';
      return new TextEncoder().encode(val);
    }

    if (type === 'submit') {
      // No payload
      return new Uint8Array(0);
    }

    if (type === 'focus' || type === 'blur') {
      // No payload
      return new Uint8Array(0);
    }

    if (type === 'scroll') {
      // [scrollLeft:i32, scrollTop:i32]
      const buf = new Uint8Array(8);
      const t = event.target || document.documentElement;
      writeI32(buf, 0, Math.round(t.scrollLeft || 0));
      writeI32(buf, 4, Math.round(t.scrollTop || 0));
      return buf;
    }

    if (type === 'resize') {
      // [innerWidth:i32, innerHeight:i32]
      const buf = new Uint8Array(8);
      writeI32(buf, 0, window ? window.innerWidth : 0);
      writeI32(buf, 4, window ? window.innerHeight : 0);
      return buf;
    }

    if (type === 'touchstart' || type === 'touchend' || type === 'touchmove') {
      // [clientX:i32, clientY:i32] of first touch
      const buf = new Uint8Array(8);
      const touch = event.touches?.[0] || event.changedTouches?.[0];
      if (touch) {
        writeI32(buf, 0, Math.round(touch.clientX));
        writeI32(buf, 4, Math.round(touch.clientY));
      }
      return buf;
    }

    // Default: empty payload
    return new Uint8Array(0);
  }

  function wardJsAddEventListener(nodeId, eventTypePtr, typeLen, listenerId) {
    const node = nodes.get(nodeId);
    if (!node) return;
    const type = readString(eventTypePtr, typeLen);

    const handler = (event) => {
      currentEvent = event;
      const payload = encodeEventPayload(event, type);
      const payloadLen = payload.length;
      if (payloadLen > 0) {
        const ptr = instance.exports.malloc(payloadLen);
        writeBytes(ptr, payload);
        instance.exports.ward_bridge_stash_set_ptr(ptr);
      }
      instance.exports.ward_on_event(listenerId, payloadLen);
      currentEvent = null;
    };

    node.addEventListener(type, handler);
    listeners.set(listenerId, { node, type, handler });
  }

  function wardJsRemoveEventListener(listenerId) {
    const entry = listeners.get(listenerId);
    if (!entry) return;
    entry.node.removeEventListener(entry.type, entry.handler);
    listeners.delete(listenerId);
  }

  function wardJsPreventDefault() {
    if (currentEvent) currentEvent.preventDefault();
  }

  // --- Fetch ---

  function wardJsFetch(urlPtr, urlLen, resolverPtr) {
    const url = readString(urlPtr, urlLen);
    fetch(url).then(async resp => {
      const body = new Uint8Array(await resp.arrayBuffer());
      const bodyLen = body.length;
      let bodyPtr = 0;
      if (bodyLen > 0) {
        bodyPtr = instance.exports.malloc(bodyLen);
        writeBytes(bodyPtr, body);
      }
      instance.exports.ward_on_fetch_complete(resolverPtr, resp.status, bodyPtr, bodyLen);
    }).catch(() => {
      instance.exports.ward_on_fetch_complete(resolverPtr, 0, 0, 0);
    });
  }

  // --- Clipboard ---

  function wardJsClipboardWriteText(textPtr, textLen, resolverPtr) {
    const text = readString(textPtr, textLen);
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => {
        instance.exports.ward_on_clipboard_complete(resolverPtr, 1);
      }).catch(() => {
        instance.exports.ward_on_clipboard_complete(resolverPtr, 0);
      });
    } else {
      instance.exports.ward_on_clipboard_complete(resolverPtr, 0);
    }
  }

  // --- File ---

  function wardJsFileOpen(inputNodeId, resolverPtr) {
    const inputEl = nodes.get(inputNodeId);
    if (!inputEl || !inputEl.files || !inputEl.files[0]) {
      instance.exports.ward_on_file_open(resolverPtr, 0, 0);
      return;
    }
    const file = inputEl.files[0];
    file.arrayBuffer().then(buf => {
      const handle = nextFileHandle++;
      fileCache.set(handle, { buffer: buf, size: buf.byteLength });
      instance.exports.ward_on_file_open(resolverPtr, handle, buf.byteLength);
    }).catch(() => {
      instance.exports.ward_on_file_open(resolverPtr, 0, 0);
    });
  }

  function wardJsFileRead(handle, fileOffset, len, outPtr) {
    const entry = fileCache.get(handle);
    if (!entry) return 0;
    const available = Math.min(len, entry.buffer.byteLength - fileOffset);
    if (available <= 0) return 0;
    const src = new Uint8Array(entry.buffer, fileOffset, available);
    writeBytes(outPtr, src);
    return available;
  }

  function wardJsFileClose(handle) {
    fileCache.delete(handle);
  }

  // --- Decompress ---

  function wardJsDecompress(dataPtr, dataLen, method, resolverPtr) {
    const data = readBytes(dataPtr, dataLen);
    // method: 0=gzip, 1=deflate, 2=deflate-raw
    const formats = ['gzip', 'deflate', 'deflate-raw'];
    const format = formats[method];
    if (!format || typeof DecompressionStream === 'undefined') {
      instance.exports.ward_on_decompress_complete(resolverPtr, 0, 0);
      return;
    }
    const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream(format));
    new Response(stream).arrayBuffer().then(buf => {
      const handle = nextBlobHandle++;
      blobCache.set(handle, buf);
      instance.exports.ward_on_decompress_complete(resolverPtr, handle, buf.byteLength);
    }).catch(() => {
      instance.exports.ward_on_decompress_complete(resolverPtr, 0, 0);
    });
  }

  function wardJsBlobRead(handle, blobOffset, len, outPtr) {
    const buf = blobCache.get(handle);
    if (!buf) return 0;
    const available = Math.min(len, buf.byteLength - blobOffset);
    if (available <= 0) return 0;
    const src = new Uint8Array(buf, blobOffset, available);
    writeBytes(outPtr, src);
    return available;
  }

  function wardJsBlobFree(handle) {
    blobCache.delete(handle);
  }

  // --- Notification/Push ---

  function wardJsNotificationRequestPermission(resolverPtr) {
    if (typeof Notification === 'undefined') {
      instance.exports.ward_on_permission_result(resolverPtr, 0);
      return;
    }
    Notification.requestPermission().then(perm => {
      instance.exports.ward_on_permission_result(resolverPtr, perm === 'granted' ? 1 : 0);
    }).catch(() => {
      instance.exports.ward_on_permission_result(resolverPtr, 0);
    });
  }

  function wardJsNotificationShow(titlePtr, titleLen) {
    if (typeof Notification === 'undefined' || Notification.permission !== 'granted') return;
    const title = readString(titlePtr, titleLen);
    new Notification(title);
  }

  function wardJsPushSubscribe(vapidPtr, vapidLen, resolverPtr) {
    if (!('serviceWorker' in navigator) || !('PushManager' in (window || {}))) {
      instance.exports.ward_on_push_subscribe(resolverPtr, 0, 0);
      return;
    }
    const vapidKey = readString(vapidPtr, vapidLen);
    // Convert base64 VAPID key to Uint8Array
    const rawKey = Uint8Array.from(atob(vapidKey.replace(/-/g, '+').replace(/_/g, '/')),
      c => c.charCodeAt(0));
    navigator.serviceWorker.ready.then(reg => {
      return reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: rawKey
      });
    }).then(sub => {
      const json = JSON.stringify(sub.toJSON());
      const bytes = new TextEncoder().encode(json);
      const ptr = instance.exports.malloc(bytes.length);
      writeBytes(ptr, bytes);
      instance.exports.ward_on_push_subscribe(resolverPtr, ptr, bytes.length);
    }).catch(() => {
      instance.exports.ward_on_push_subscribe(resolverPtr, 0, 0);
    });
  }

  function wardJsPushGetSubscription(resolverPtr) {
    if (!('serviceWorker' in navigator) || !('PushManager' in (window || {}))) {
      instance.exports.ward_on_push_subscribe(resolverPtr, 0, 0);
      return;
    }
    navigator.serviceWorker.ready.then(reg => {
      return reg.pushManager.getSubscription();
    }).then(sub => {
      if (!sub) {
        instance.exports.ward_on_push_subscribe(resolverPtr, 0, 0);
        return;
      }
      const json = JSON.stringify(sub.toJSON());
      const bytes = new TextEncoder().encode(json);
      const ptr = instance.exports.malloc(bytes.length);
      writeBytes(ptr, bytes);
      instance.exports.ward_on_push_subscribe(resolverPtr, ptr, bytes.length);
    }).catch(() => {
      instance.exports.ward_on_push_subscribe(resolverPtr, 0, 0);
    });
  }

  // --- Parse HTML (generic, safe) ---

  // Element blocklist — stripped during serialization
  const BLOCKED_ELEMENTS = new Set([
    'script', 'iframe', 'object', 'embed', 'form', 'input', 'link', 'meta'
  ]);

  // Attribute name filter: keep only [a-zA-Z0-9-], exclude style and on*
  function isSafeAttrName(name) {
    if (name === 'style' || name.startsWith('on')) return false;
    return /^[a-zA-Z0-9-]+$/.test(name);
  }

  function serializeTree(root) {
    const parts = [];

    function walkNode(node) {
      if (node.nodeType === 3) { // TEXT
        const text = node.textContent || '';
        if (text.length === 0) return;
        const bytes = new TextEncoder().encode(text);
        if (bytes.length > 65535) return; // skip oversized text
        parts.push(3); // TEXT opcode
        parts.push(bytes.length & 0xff, (bytes.length >> 8) & 0xff); // u16LE len
        for (let i = 0; i < bytes.length; i++) parts.push(bytes[i]);
        return;
      }
      if (node.nodeType !== 1) return; // skip non-element, non-text

      const tag = node.tagName.toLowerCase();
      if (BLOCKED_ELEMENTS.has(tag)) return;

      const tagBytes = new TextEncoder().encode(tag);
      if (tagBytes.length > 255) return; // skip impossibly long tags

      // Collect safe attributes
      const safeAttrs = [];
      for (const attr of node.attributes) {
        const name = attr.name.toLowerCase();
        if (!isSafeAttrName(name)) continue;
        const nameBytes = new TextEncoder().encode(name);
        const valBytes = new TextEncoder().encode(attr.value);
        if (nameBytes.length > 255 || valBytes.length > 65535) continue;
        safeAttrs.push({ nameBytes, valBytes });
      }

      // ELEMENT_OPEN
      parts.push(1); // ELEMENT_OPEN opcode
      parts.push(tagBytes.length); // tag_len:u8
      for (let i = 0; i < tagBytes.length; i++) parts.push(tagBytes[i]);
      parts.push(safeAttrs.length > 255 ? 255 : safeAttrs.length); // attr_count:u8

      for (const a of safeAttrs.slice(0, 255)) {
        parts.push(a.nameBytes.length); // attr_name_len:u8
        for (let i = 0; i < a.nameBytes.length; i++) parts.push(a.nameBytes[i]);
        parts.push(a.valBytes.length & 0xff, (a.valBytes.length >> 8) & 0xff); // attr_value_len:u16LE
        for (let i = 0; i < a.valBytes.length; i++) parts.push(a.valBytes[i]);
      }

      // Recurse children
      for (const child of node.childNodes) {
        walkNode(child);
      }

      // ELEMENT_CLOSE
      parts.push(2); // ELEMENT_CLOSE opcode
    }

    for (const child of root.childNodes) {
      walkNode(child);
    }

    return new Uint8Array(parts);
  }

  function wardJsParseHtml(htmlPtr, htmlLen) {
    const html = readString(htmlPtr, htmlLen);
    const template = document.createElement('template');
    template.innerHTML = html;
    const result = serializeTree(template.content);
    if (result.length === 0) return 0;
    const ptr = instance.exports.malloc(result.length);
    writeBytes(ptr, result);
    instance.exports.ward_parse_html_stash(ptr);
    return result.length;
  }

  // --- Build imports ---

  const imports = {
    env: {
      ward_dom_flush: wardDomFlush,
      ward_set_timer: wardSetTimer,
      ward_exit: () => { resolveDone(); },
      // IDB
      ward_idb_js_put: wardIdbPut,
      ward_idb_js_get: wardIdbGet,
      ward_idb_js_delete: wardIdbDelete,
      // Window
      ward_js_focus_window: wardJsFocusWindow,
      ward_js_get_visibility_state: wardJsGetVisibilityState,
      ward_js_log: wardJsLog,
      // Navigation
      ward_js_get_url: wardJsGetUrl,
      ward_js_get_url_hash: wardJsGetUrlHash,
      ward_js_set_url_hash: wardJsSetUrlHash,
      ward_js_replace_state: wardJsReplaceState,
      ward_js_push_state: wardJsPushState,
      // DOM read
      ward_js_measure_node: wardJsMeasureNode,
      ward_js_query_selector: wardJsQuerySelector,
      // Event listener
      ward_js_add_event_listener: wardJsAddEventListener,
      ward_js_remove_event_listener: wardJsRemoveEventListener,
      ward_js_prevent_default: wardJsPreventDefault,
      // Fetch
      ward_js_fetch: wardJsFetch,
      // Clipboard
      ward_js_clipboard_write_text: wardJsClipboardWriteText,
      // File
      ward_js_file_open: wardJsFileOpen,
      ward_js_file_read: wardJsFileRead,
      ward_js_file_close: wardJsFileClose,
      // Decompress
      ward_js_decompress: wardJsDecompress,
      ward_js_blob_read: wardJsBlobRead,
      ward_js_blob_free: wardJsBlobFree,
      // Notification/Push
      ward_js_notification_request_permission: wardJsNotificationRequestPermission,
      ward_js_notification_show: wardJsNotificationShow,
      ward_js_push_subscribe: wardJsPushSubscribe,
      ward_js_push_get_subscription: wardJsPushGetSubscription,
      // Parse HTML
      ward_js_parse_html: wardJsParseHtml,
    },
  };

  // Merge extraImports if provided
  if (opts && opts.extraImports) {
    Object.assign(imports.env, opts.extraImports);
  }

  const result = await WebAssembly.instantiate(wasmBytes, imports);
  instance = result.instance;
  instance.exports.ward_node_init(0);

  return { exports: instance.exports, nodes, done };
}
