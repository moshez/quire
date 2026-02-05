/**
 * Mock WASM module for bridge tests.
 *
 * Provides the required exports that the bridge expects from a WASM module:
 * - Buffer pointers (event, diff, fetch, string)
 * - init function
 * - process_event function
 * - Callback handlers
 *
 * Tests can manipulate the shared ArrayBuffer to simulate WASM behavior.
 */

const EVENT_BUFFER_SIZE = 256;
const DIFF_BUFFER_SIZE = 4096;
const FETCH_BUFFER_SIZE = 16384;
const STRING_BUFFER_SIZE = 4096;

const TOTAL_SIZE = EVENT_BUFFER_SIZE + DIFF_BUFFER_SIZE + FETCH_BUFFER_SIZE + STRING_BUFFER_SIZE;

// Offsets into the shared buffer
const EVENT_OFFSET = 0;
const DIFF_OFFSET = EVENT_BUFFER_SIZE;
const FETCH_OFFSET = DIFF_OFFSET + DIFF_BUFFER_SIZE;
const STRING_OFFSET = FETCH_OFFSET + FETCH_BUFFER_SIZE;

/**
 * Creates a mock WASM instance with shared memory.
 * @returns {Object} Mock WASM instance with exports and helper methods
 */
export function createMockWasm() {
  // Shared memory buffer
  const memory = new WebAssembly.Memory({ initial: 1 });

  // Track callback invocations
  const callbacks = {
    init: [],
    process_event: [],
    on_fetch_complete: [],
    on_timer_complete: [],
    on_file_open_complete: [],
    on_decompress_complete: [],
    on_kv_open_complete: [],
    on_kv_complete: [],
    on_kv_get_complete: [],
    on_kv_get_blob_complete: [],
    on_clipboard_copy_complete: [],
    on_visibility_hidden: [],
    on_push_subscribe_complete: [],
    on_push_subscription_result: [],
    on_push_subscription_change: [],
    on_pending_pushes_result: [],
    on_pending_pushes_cleared: []
  };

  // Diff writer helper for tests
  let diffCount = 0;

  const exports = {
    memory,

    get_event_buffer_ptr() {
      return EVENT_OFFSET;
    },

    get_diff_buffer_ptr() {
      return DIFF_OFFSET;
    },

    get_fetch_buffer_ptr() {
      return FETCH_OFFSET;
    },

    get_string_buffer_ptr() {
      return STRING_OFFSET;
    },

    init() {
      callbacks.init.push({ timestamp: Date.now() });
    },

    process_event() {
      callbacks.process_event.push({ timestamp: Date.now() });
    },

    on_fetch_complete(status, len) {
      callbacks.on_fetch_complete.push({ status, len });
    },

    on_timer_complete(callbackId) {
      callbacks.on_timer_complete.push({ callbackId });
    },

    on_file_open_complete(handle, size) {
      callbacks.on_file_open_complete.push({ handle, size });
    },

    on_decompress_complete(handle, size) {
      callbacks.on_decompress_complete.push({ handle, size });
    },

    on_kv_open_complete(success) {
      callbacks.on_kv_open_complete.push({ success });
    },

    on_kv_complete(success) {
      callbacks.on_kv_complete.push({ success });
    },

    on_kv_get_complete(len) {
      callbacks.on_kv_get_complete.push({ len });
    },

    on_kv_get_blob_complete(handle, size) {
      callbacks.on_kv_get_blob_complete.push({ handle, size });
    },

    on_clipboard_copy_complete(success) {
      callbacks.on_clipboard_copy_complete.push({ success });
    },

    on_visibility_hidden() {
      callbacks.on_visibility_hidden.push({ timestamp: Date.now() });
    },

    on_push_subscribe_complete(len) {
      callbacks.on_push_subscribe_complete.push({ len });
    },

    on_push_subscription_result(len) {
      callbacks.on_push_subscription_result.push({ len });
    },

    on_push_subscription_change() {
      callbacks.on_push_subscription_change.push({ timestamp: Date.now() });
    },

    on_pending_pushes_result(len) {
      callbacks.on_pending_pushes_result.push({ len });
    },

    on_pending_pushes_cleared(success) {
      callbacks.on_pending_pushes_cleared.push({ success });
    }
  };

  // Helper methods for tests
  const helpers = {
    /**
     * Get the callbacks tracking object
     */
    getCallbacks() {
      return callbacks;
    },

    /**
     * Clear all callback records
     */
    clearCallbacks() {
      for (const key in callbacks) {
        callbacks[key] = [];
      }
    },

    /**
     * Reset diff buffer (set count to 0)
     */
    resetDiffs() {
      diffCount = 0;
      const view = new DataView(memory.buffer);
      view.setUint8(DIFF_OFFSET, 0);
    },

    /**
     * Write a diff entry to the diff buffer.
     * Uses 16-byte aligned entries per protocol spec.
     *
     * @param {number} op - Operation code
     * @param {number} nodeId - Target node ID
     * @param {number} value1 - First value parameter
     * @param {number} value2 - Second value parameter
     */
    writeDiff(op, nodeId, value1 = 0, value2 = 0) {
      const view = new DataView(memory.buffer);
      // Header at offset 0 contains count
      // Entries start at offset 4 for alignment
      const entryOffset = DIFF_OFFSET + 4 + (diffCount * 16);

      view.setUint32(entryOffset, op, true);
      view.setUint32(entryOffset + 4, nodeId, true);
      view.setUint32(entryOffset + 8, value1, true);
      view.setUint32(entryOffset + 12, value2, true);

      diffCount++;
      view.setUint8(DIFF_OFFSET, diffCount);
    },

    /**
     * Write a string to the fetch buffer
     * @param {string} str - String to write
     * @param {number} offset - Offset within fetch buffer (default 0)
     * @returns {number} Number of bytes written
     */
    writeToFetchBuffer(str, offset = 0) {
      const encoder = new TextEncoder();
      const bytes = encoder.encode(str);
      const arr = new Uint8Array(memory.buffer, FETCH_OFFSET + offset, bytes.length);
      arr.set(bytes);
      return bytes.length;
    },

    /**
     * Write a string to the string buffer
     * @param {string} str - String to write
     * @param {number} offset - Offset within string buffer (default 0)
     * @returns {number} Number of bytes written
     */
    writeToStringBuffer(str, offset = 0) {
      const encoder = new TextEncoder();
      const bytes = encoder.encode(str);
      const arr = new Uint8Array(memory.buffer, STRING_OFFSET + offset, bytes.length);
      arr.set(bytes);
      return bytes.length;
    },

    /**
     * Read the event buffer contents
     * @returns {Object} Parsed event data
     */
    readEventBuffer() {
      const view = new DataView(memory.buffer);
      return {
        type: view.getUint8(EVENT_OFFSET),
        nodeId: view.getUint32(EVENT_OFFSET + 1, true),
        data1: view.getUint32(EVENT_OFFSET + 5, true),
        data2: view.getUint32(EVENT_OFFSET + 9, true)
      };
    },

    /**
     * Get direct access to memory buffer for advanced tests
     */
    getMemoryBuffer() {
      return memory.buffer;
    },

    /**
     * Get buffer offsets for direct manipulation
     */
    getOffsets() {
      return {
        event: EVENT_OFFSET,
        diff: DIFF_OFFSET,
        fetch: FETCH_OFFSET,
        string: STRING_OFFSET
      };
    }
  };

  return {
    instance: { exports },
    exports,
    helpers
  };
}

// Op codes (matching bridge protocol)
export const OP_SET_TEXT = 1;
export const OP_SET_ATTR = 2;
export const OP_SET_TRANSFORM = 3;
export const OP_CREATE_ELEMENT = 4;
export const OP_REMOVE_CHILD = 5;
export const OP_SET_INNER_HTML = 6;

// Event types (matching bridge protocol)
export const EVENT_CLICK = 1;
export const EVENT_INPUT = 2;
export const EVENT_SUBMIT = 3;
export const EVENT_KEYDOWN = 4;
export const EVENT_KEYUP = 5;
export const EVENT_FOCUS = 6;
export const EVENT_BLUR = 7;
export const EVENT_PUSH = 8;
export const EVENT_NOTIFICATION_CLICK = 9;

/**
 * Helper to write events directly to the event buffer.
 * Mirrors bridge.js writeEvent function for testing.
 * @param {DataView} view - DataView of WASM memory at event buffer
 * @param {number} type - Event type
 * @param {number} nodeId - Node ID
 * @param {number} data1 - First data parameter
 * @param {number} data2 - Second data parameter
 */
export function writeEventToBuffer(view, offset, type, nodeId, data1 = 0, data2 = 0) {
  view.setUint8(offset, type);
  view.setUint32(offset + 1, nodeId, true);
  view.setUint32(offset + 5, data1, true);
  view.setUint32(offset + 9, data2, true);
}
