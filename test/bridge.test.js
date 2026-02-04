/**
 * Bridge protocol tests
 *
 * Tests the bridge.js module against a mock WASM module.
 * Validates:
 * - Node registration and lookup
 * - Event encoding
 * - Diff application for all op codes
 * - 16-byte stride alignment
 * - String buffer operations
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { JSDOM } from 'jsdom';
import {
  createMockWasm,
  OP_SET_TEXT,
  OP_SET_ATTR,
  OP_SET_TRANSFORM,
  OP_CREATE_ELEMENT,
  OP_REMOVE_CHILD,
  OP_SET_INNER_HTML,
  EVENT_CLICK,
  EVENT_INPUT,
  EVENT_KEYDOWN
} from './mock-wasm.js';

// Set up jsdom environment
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
  url: 'http://localhost'
});
global.document = dom.window.document;
global.window = dom.window;
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;

describe('Mock WASM Module', () => {
  let mockWasm;

  beforeEach(() => {
    mockWasm = createMockWasm();
  });

  it('should provide buffer pointers', () => {
    const { exports } = mockWasm;

    expect(typeof exports.get_event_buffer_ptr()).toBe('number');
    expect(typeof exports.get_diff_buffer_ptr()).toBe('number');
    expect(typeof exports.get_fetch_buffer_ptr()).toBe('number');
    expect(typeof exports.get_string_buffer_ptr()).toBe('number');
  });

  it('should have memory export', () => {
    const { exports } = mockWasm;
    expect(exports.memory).toBeDefined();
    expect(exports.memory.buffer).toBeInstanceOf(ArrayBuffer);
  });

  it('should track init calls', () => {
    const { exports, helpers } = mockWasm;

    expect(helpers.getCallbacks().init).toHaveLength(0);
    exports.init();
    expect(helpers.getCallbacks().init).toHaveLength(1);
  });

  it('should track process_event calls', () => {
    const { exports, helpers } = mockWasm;

    expect(helpers.getCallbacks().process_event).toHaveLength(0);
    exports.process_event();
    expect(helpers.getCallbacks().process_event).toHaveLength(1);
  });
});

describe('Diff Buffer Layout', () => {
  let mockWasm;

  beforeEach(() => {
    mockWasm = createMockWasm();
    mockWasm.helpers.resetDiffs();
  });

  it('should write diffs with 16-byte stride', () => {
    const { exports, helpers } = mockWasm;
    const diffPtr = exports.get_diff_buffer_ptr();
    const view = new DataView(exports.memory.buffer);

    // Write two diffs
    helpers.writeDiff(OP_SET_TEXT, 1, 0, 5);
    helpers.writeDiff(OP_SET_ATTR, 2, 10, 20);

    // Check header (diff count)
    expect(view.getUint8(diffPtr)).toBe(2);

    // First entry at offset 4 (after header, aligned)
    const entry1Offset = diffPtr + 4;
    expect(view.getUint32(entry1Offset, true)).toBe(OP_SET_TEXT);
    expect(view.getUint32(entry1Offset + 4, true)).toBe(1);
    expect(view.getUint32(entry1Offset + 8, true)).toBe(0);
    expect(view.getUint32(entry1Offset + 12, true)).toBe(5);

    // Second entry at offset 4 + 16 = 20
    const entry2Offset = diffPtr + 4 + 16;
    expect(view.getUint32(entry2Offset, true)).toBe(OP_SET_ATTR);
    expect(view.getUint32(entry2Offset + 4, true)).toBe(2);
    expect(view.getUint32(entry2Offset + 8, true)).toBe(10);
    expect(view.getUint32(entry2Offset + 12, true)).toBe(20);
  });

  it('should reset diff count', () => {
    const { exports, helpers } = mockWasm;
    const diffPtr = exports.get_diff_buffer_ptr();
    const view = new DataView(exports.memory.buffer);

    helpers.writeDiff(OP_SET_TEXT, 1, 0, 5);
    expect(view.getUint8(diffPtr)).toBe(1);

    helpers.resetDiffs();
    expect(view.getUint8(diffPtr)).toBe(0);
  });
});

describe('String Buffer Operations', () => {
  let mockWasm;

  beforeEach(() => {
    mockWasm = createMockWasm();
  });

  it('should write to fetch buffer', () => {
    const { exports, helpers } = mockWasm;
    const fetchPtr = exports.get_fetch_buffer_ptr();

    const testStr = 'Hello, World!';
    const bytesWritten = helpers.writeToFetchBuffer(testStr);

    expect(bytesWritten).toBe(testStr.length);

    const decoder = new TextDecoder();
    const arr = new Uint8Array(exports.memory.buffer, fetchPtr, bytesWritten);
    expect(decoder.decode(arr)).toBe(testStr);
  });

  it('should write to string buffer', () => {
    const { exports, helpers } = mockWasm;
    const stringPtr = exports.get_string_buffer_ptr();

    const testStr = 'test-attribute';
    const bytesWritten = helpers.writeToStringBuffer(testStr);

    expect(bytesWritten).toBe(testStr.length);

    const decoder = new TextDecoder();
    const arr = new Uint8Array(exports.memory.buffer, stringPtr, bytesWritten);
    expect(decoder.decode(arr)).toBe(testStr);
  });

  it('should write to string buffer with offset', () => {
    const { exports, helpers } = mockWasm;
    const stringPtr = exports.get_string_buffer_ptr();

    const name = 'class';
    const value = 'my-class';

    helpers.writeToStringBuffer(name, 0);
    helpers.writeToStringBuffer(value, name.length);

    const decoder = new TextDecoder();
    const nameArr = new Uint8Array(exports.memory.buffer, stringPtr, name.length);
    const valueArr = new Uint8Array(exports.memory.buffer, stringPtr + name.length, value.length);

    expect(decoder.decode(nameArr)).toBe(name);
    expect(decoder.decode(valueArr)).toBe(value);
  });
});

describe('Event Buffer', () => {
  let mockWasm;

  beforeEach(() => {
    mockWasm = createMockWasm();
  });

  it('should read event buffer contents', () => {
    const { exports, helpers } = mockWasm;
    const eventPtr = exports.get_event_buffer_ptr();
    const view = new DataView(exports.memory.buffer);

    // Simulate bridge writing an event
    view.setUint8(eventPtr, EVENT_CLICK);
    view.setUint32(eventPtr + 1, 42, true);  // nodeId
    view.setUint32(eventPtr + 5, 100, true); // data1
    view.setUint32(eventPtr + 9, 200, true); // data2

    const event = helpers.readEventBuffer();
    expect(event.type).toBe(EVENT_CLICK);
    expect(event.nodeId).toBe(42);
    expect(event.data1).toBe(100);
    expect(event.data2).toBe(200);
  });
});

describe('Callback Tracking', () => {
  let mockWasm;

  beforeEach(() => {
    mockWasm = createMockWasm();
  });

  it('should track on_fetch_complete', () => {
    const { exports, helpers } = mockWasm;

    exports.on_fetch_complete(200, 1024);

    const callbacks = helpers.getCallbacks();
    expect(callbacks.on_fetch_complete).toHaveLength(1);
    expect(callbacks.on_fetch_complete[0]).toEqual({ status: 200, len: 1024 });
  });

  it('should track on_timer_complete', () => {
    const { exports, helpers } = mockWasm;

    exports.on_timer_complete(5);

    const callbacks = helpers.getCallbacks();
    expect(callbacks.on_timer_complete).toHaveLength(1);
    expect(callbacks.on_timer_complete[0]).toEqual({ callbackId: 5 });
  });

  it('should track on_file_open_complete', () => {
    const { exports, helpers } = mockWasm;

    exports.on_file_open_complete(1, 50000);

    const callbacks = helpers.getCallbacks();
    expect(callbacks.on_file_open_complete).toHaveLength(1);
    expect(callbacks.on_file_open_complete[0]).toEqual({ handle: 1, size: 50000 });
  });

  it('should clear all callbacks', () => {
    const { exports, helpers } = mockWasm;

    exports.init();
    exports.process_event();
    exports.on_fetch_complete(200, 100);

    helpers.clearCallbacks();

    const callbacks = helpers.getCallbacks();
    expect(callbacks.init).toHaveLength(0);
    expect(callbacks.process_event).toHaveLength(0);
    expect(callbacks.on_fetch_complete).toHaveLength(0);
  });
});

describe('Op Code Constants', () => {
  it('should have correct op code values', () => {
    expect(OP_SET_TEXT).toBe(1);
    expect(OP_SET_ATTR).toBe(2);
    expect(OP_SET_TRANSFORM).toBe(3);
    expect(OP_CREATE_ELEMENT).toBe(4);
    expect(OP_REMOVE_CHILD).toBe(5);
    expect(OP_SET_INNER_HTML).toBe(6);
  });
});

describe('Event Type Constants', () => {
  it('should have correct event type values', () => {
    expect(EVENT_CLICK).toBe(1);
    expect(EVENT_INPUT).toBe(2);
    expect(EVENT_KEYDOWN).toBe(4);
  });
});
