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

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { JSDOM } from 'jsdom';
import { indexedDB, IDBKeyRange } from 'fake-indexeddb';
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
  EVENT_KEYDOWN,
  EVENT_PUSH,
  EVENT_NOTIFICATION_CLICK
} from './mock-wasm.js';

// Set up jsdom environment
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
  url: 'http://localhost'
});
global.document = dom.window.document;
global.window = dom.window;
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;
// Set up fake IndexedDB
global.indexedDB = indexedDB;
global.IDBKeyRange = IDBKeyRange;

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

describe('Bridge Module Exports', () => {
  it('should export initBridge function', async () => {
    const bridge = await import('../bridge.js');
    expect(typeof bridge.initBridge).toBe('function');
  });

  it('should export registerNode function', async () => {
    const bridge = await import('../bridge.js');
    expect(typeof bridge.registerNode).toBe('function');
  });

  it('should export getNode function', async () => {
    const bridge = await import('../bridge.js');
    expect(typeof bridge.getNode).toBe('function');
  });

  it('should NOT export initApp (renamed to initBridge)', async () => {
    const bridge = await import('../bridge.js');
    expect(bridge.initApp).toBeUndefined();
  });
});

describe('wrapExports Proxy', () => {
  let mockWasm;
  let bridge;

  beforeEach(async () => {
    document.body.innerHTML = '<div id="root" data-wasm data-node-id="1"></div>';
    bridge = await import('../bridge.js');
    mockWasm = createMockWasm();
    bridge._clearNodeRegistry();
    const root = document.getElementById('root');
    bridge.registerNode(root);
  });

  it('should auto-flush diffs when WASM export is called through wrapped module', () => {
    const { helpers } = mockWasm;
    const root = document.getElementById('root');

    // Initialize with wrap=true to use auto-flush proxy
    bridge._initForTest(mockWasm, true);

    // Write a diff and text to buffers
    const text = 'Auto-flushed text';
    helpers.writeToFetchBuffer(text, 0);
    helpers.writeDiff(OP_SET_TEXT, 1, 0, text.length);

    // Call process_event through the wrapped wasm - should auto-flush
    const wrappedWasm = bridge._getWasm();
    wrappedWasm.process_event();

    // Diff should have been applied
    expect(root.textContent).toBe('Auto-flushed text');
  });

  it('should NOT auto-flush diffs when using unwrapped module', () => {
    const { helpers } = mockWasm;
    const root = document.getElementById('root');

    // Initialize without wrap (useWrap=false)
    bridge._initForTest(mockWasm, false);

    // Write a diff
    const text = 'Should not appear yet';
    helpers.writeToFetchBuffer(text, 0);
    helpers.writeDiff(OP_SET_TEXT, 1, 0, text.length);

    // Call process_event - should NOT auto-flush
    mockWasm.exports.process_event();

    // Diff should NOT have been applied (text should still be empty)
    expect(root.textContent).toBe('');

    // Manual applyDiffs should apply it
    bridge._applyDiffs();
    expect(root.textContent).toBe('Should not appear yet');
  });

  it('should not wrap buffer pointer getters', () => {
    bridge._initForTest(mockWasm, true);
    const wrappedWasm = bridge._getWasm();

    // Buffer pointer getters should return numbers directly
    expect(typeof wrappedWasm.get_event_buffer_ptr()).toBe('number');
    expect(typeof wrappedWasm.get_diff_buffer_ptr()).toBe('number');
    expect(typeof wrappedWasm.get_fetch_buffer_ptr()).toBe('number');
    expect(typeof wrappedWasm.get_string_buffer_ptr()).toBe('number');
  });

  it('should not wrap memory export', () => {
    bridge._initForTest(mockWasm, true);
    const wrappedWasm = bridge._getWasm();

    // Memory should be accessible
    expect(wrappedWasm.memory).toBeDefined();
    expect(wrappedWasm.memory.buffer).toBeInstanceOf(ArrayBuffer);
  });

  it('should clear diff count after applying diffs', () => {
    const { helpers, exports } = mockWasm;
    const diffPtr = exports.get_diff_buffer_ptr();

    bridge._initForTest(mockWasm, true);
    const wrappedWasm = bridge._getWasm();

    // Write a diff
    helpers.writeDiff(OP_SET_TEXT, 1, 0, 5);

    // Verify diff count is 1
    const view = new DataView(exports.memory.buffer);
    expect(view.getUint8(diffPtr)).toBe(1);

    // Call any function through wrapped wasm
    wrappedWasm.init();

    // Diff count should be cleared to 0
    expect(view.getUint8(diffPtr)).toBe(0);
  });
});

describe('Push Event Constants', () => {
  it('should have push event types defined', () => {
    expect(EVENT_PUSH).toBe(8);
    expect(EVENT_NOTIFICATION_CLICK).toBe(9);
  });
});

describe('Diff Application', () => {
  let mockWasm;
  let bridge;

  beforeEach(async () => {
    // Reset DOM
    document.body.innerHTML = '<div id="root" data-wasm data-node-id="1"></div>';

    bridge = await import('../bridge.js');
    mockWasm = createMockWasm();

    // Initialize bridge with mock WASM
    bridge._initForTest(mockWasm);
    bridge._clearNodeRegistry();

    // Register root node
    const root = document.getElementById('root');
    bridge.registerNode(root);
  });

  describe('OP_SET_TEXT', () => {
    it('should set text content from fetch buffer', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      // Write text to fetch buffer and create diff
      const text = 'Hello, World!';
      helpers.writeToFetchBuffer(text, 0);
      helpers.writeDiff(OP_SET_TEXT, 1, 0, text.length);

      bridge._applyDiffs();

      expect(root.textContent).toBe('Hello, World!');
    });

    it('should clear text when length is 0', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');
      root.textContent = 'existing text';

      helpers.writeDiff(OP_SET_TEXT, 1, 0, 0);

      bridge._applyDiffs();

      expect(root.textContent).toBe('');
    });

    it('should read from offset in fetch buffer', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      // Write text at offset 10
      const text = 'Offset text';
      helpers.writeToFetchBuffer(text, 10);
      helpers.writeDiff(OP_SET_TEXT, 1, 10, text.length);

      bridge._applyDiffs();

      expect(root.textContent).toBe('Offset text');
    });
  });

  describe('OP_SET_ATTR', () => {
    it('should set attribute on node', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      // Write attr name and value to string buffer
      const name = 'class';
      const value = 'my-class';
      helpers.writeToStringBuffer(name, 0);
      helpers.writeToStringBuffer(value, name.length);
      helpers.writeDiff(OP_SET_ATTR, 1, name.length, value.length);

      bridge._applyDiffs();

      expect(root.getAttribute('class')).toBe('my-class');
    });

    it('should remove attribute when value length is 0', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');
      root.setAttribute('data-test', 'value');

      // Write attr name only
      const name = 'data-test';
      helpers.writeToStringBuffer(name, 0);
      helpers.writeDiff(OP_SET_ATTR, 1, name.length, 0);

      bridge._applyDiffs();

      expect(root.hasAttribute('data-test')).toBe(false);
    });

    it('should handle multi-byte attribute values', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      const name = 'title';
      const value = '日本語テスト';  // Japanese text
      helpers.writeToStringBuffer(name, 0);
      helpers.writeToStringBuffer(value, name.length);
      helpers.writeDiff(OP_SET_ATTR, 1, name.length, new TextEncoder().encode(value).length);

      bridge._applyDiffs();

      expect(root.getAttribute('title')).toBe('日本語テスト');
    });
  });

  describe('OP_SET_TRANSFORM', () => {
    it('should set CSS transform with positive values', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      helpers.writeDiff(OP_SET_TRANSFORM, 1, 100, 200);

      bridge._applyDiffs();

      expect(root.style.transform).toBe('translate(100px, 200px)');
    });

    it('should handle negative values (int32 reinterpretation)', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      // -100 as uint32 is 0xFFFFFF9C (4294967196)
      const negX = (-100 >>> 0);
      const negY = (-50 >>> 0);
      helpers.writeDiff(OP_SET_TRANSFORM, 1, negX, negY);

      bridge._applyDiffs();

      expect(root.style.transform).toBe('translate(-100px, -50px)');
    });

    it('should set transform to origin (0, 0)', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');
      root.style.transform = 'translate(100px, 100px)';

      helpers.writeDiff(OP_SET_TRANSFORM, 1, 0, 0);

      bridge._applyDiffs();

      expect(root.style.transform).toBe('translate(0px, 0px)');
    });
  });

  describe('OP_CREATE_ELEMENT', () => {
    it('should create element with specified tag name', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      const tagName = 'span';
      helpers.writeToStringBuffer(tagName, 0);
      // nodeId=10, parent=1, tagNameLen=4
      helpers.writeDiff(OP_CREATE_ELEMENT, 10, 1, tagName.length);

      bridge._applyDiffs();

      expect(root.children.length).toBe(1);
      expect(root.children[0].tagName.toLowerCase()).toBe('span');
      expect(root.children[0].dataset.nodeId).toBe('10');
      expect(root.children[0].dataset.wasm).toBe('');
    });

    it('should register created element in node registry', () => {
      const { helpers } = mockWasm;

      const tagName = 'div';
      helpers.writeToStringBuffer(tagName, 0);
      helpers.writeDiff(OP_CREATE_ELEMENT, 20, 1, tagName.length);

      bridge._applyDiffs();

      const createdNode = bridge.getNode(20);
      expect(createdNode).toBeDefined();
      expect(createdNode.tagName.toLowerCase()).toBe('div');
    });

    it('should create nested elements', () => {
      const { helpers } = mockWasm;

      // Create first child
      helpers.writeToStringBuffer('section', 0);
      helpers.writeDiff(OP_CREATE_ELEMENT, 10, 1, 7);
      bridge._applyDiffs();
      helpers.resetDiffs();

      // Create grandchild inside first child
      helpers.writeToStringBuffer('article', 0);
      helpers.writeDiff(OP_CREATE_ELEMENT, 11, 10, 7);
      bridge._applyDiffs();

      const section = bridge.getNode(10);
      const article = bridge.getNode(11);
      expect(section.contains(article)).toBe(true);
    });

    it('should not create element if parent does not exist', () => {
      const { helpers } = mockWasm;

      const tagName = 'div';
      helpers.writeToStringBuffer(tagName, 0);
      // Parent ID 999 doesn't exist
      helpers.writeDiff(OP_CREATE_ELEMENT, 10, 999, tagName.length);

      bridge._applyDiffs();

      expect(bridge.getNode(10)).toBeUndefined();
    });
  });

  describe('OP_REMOVE_CHILD', () => {
    it('should remove child from parent', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      // First create a child
      helpers.writeToStringBuffer('div', 0);
      helpers.writeDiff(OP_CREATE_ELEMENT, 10, 1, 3);
      bridge._applyDiffs();
      helpers.resetDiffs();

      expect(root.children.length).toBe(1);

      // Now remove it
      helpers.writeDiff(OP_REMOVE_CHILD, 10, 0, 0);
      bridge._applyDiffs();

      expect(root.children.length).toBe(0);
    });

    it('should handle removing non-existent node gracefully', () => {
      const { helpers } = mockWasm;

      // Try to remove a node that doesn't exist
      helpers.writeDiff(OP_REMOVE_CHILD, 999, 0, 0);

      // Should not throw
      expect(() => bridge._applyDiffs()).not.toThrow();
    });
  });

  describe('OP_SET_INNER_HTML', () => {
    it('should set innerHTML from fetch buffer', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      const html = '<p>Hello <strong>World</strong></p>';
      helpers.writeToFetchBuffer(html, 0);
      helpers.writeDiff(OP_SET_INNER_HTML, 1, 0, html.length);

      bridge._applyDiffs();

      expect(root.innerHTML).toBe('<p>Hello <strong>World</strong></p>');
    });

    it('should read from offset in fetch buffer', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      const html = '<em>Emphasized</em>';
      helpers.writeToFetchBuffer(html, 50);
      helpers.writeDiff(OP_SET_INNER_HTML, 1, 50, html.length);

      bridge._applyDiffs();

      expect(root.innerHTML).toBe('<em>Emphasized</em>');
    });

    it('should clear innerHTML when length is 0', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');
      root.innerHTML = '<div>existing content</div>';

      helpers.writeDiff(OP_SET_INNER_HTML, 1, 0, 0);

      bridge._applyDiffs();

      expect(root.innerHTML).toBe('');
    });
  });

  describe('Multiple Diffs', () => {
    it('should apply multiple diffs in sequence', () => {
      const { helpers } = mockWasm;
      const root = document.getElementById('root');

      // Create two children
      helpers.writeToStringBuffer('span', 0);
      helpers.writeDiff(OP_CREATE_ELEMENT, 10, 1, 4);

      helpers.writeToStringBuffer('div', 0);
      helpers.writeDiff(OP_CREATE_ELEMENT, 11, 1, 3);

      bridge._applyDiffs();

      expect(root.children.length).toBe(2);
    });

    it('should handle 16-byte stride correctly with many diffs', () => {
      const { helpers } = mockWasm;

      // Create 5 elements - tests that stride doesn't cause overlap
      for (let i = 0; i < 5; i++) {
        helpers.writeToStringBuffer('p', 0);
        helpers.writeDiff(OP_CREATE_ELEMENT, 100 + i, 1, 1);
      }

      bridge._applyDiffs();

      // All 5 should be created
      for (let i = 0; i < 5; i++) {
        const node = bridge.getNode(100 + i);
        expect(node).toBeDefined();
        expect(node.tagName.toLowerCase()).toBe('p');
      }
    });
  });
});

describe('js_measure_node', () => {
  let mockWasm;
  let bridge;

  beforeEach(async () => {
    document.body.innerHTML = '<div id="root" data-wasm data-node-id="1" style="width: 100px; height: 50px;"></div>';
    bridge = await import('../bridge.js');
    mockWasm = createMockWasm();
    bridge._initForTest(mockWasm, false);
    bridge._clearNodeRegistry();
    const root = document.getElementById('root');
    bridge.registerNode(root);
  });

  it('should return 0 for non-existent node', () => {
    const result = bridge._measureNode(999);
    expect(result).toBe(0);
  });

  it('should return 1 for existing node', () => {
    const result = bridge._measureNode(1);
    expect(result).toBe(1);
  });

  it('should write measurements to fetch buffer', () => {
    const result = bridge._measureNode(1);
    expect(result).toBe(1);

    const measurements = bridge._getMeasurements();
    expect(measurements).not.toBeNull();
    // jsdom provides basic bounding rect support
    expect(typeof measurements.left).toBe('number');
    expect(typeof measurements.top).toBe('number');
    expect(typeof measurements.width).toBe('number');
    expect(typeof measurements.height).toBe('number');
    expect(typeof measurements.scrollWidth).toBe('number');
    expect(typeof measurements.scrollHeight).toBe('number');
  });

  it('should measure created elements', () => {
    const { helpers } = mockWasm;

    // Create a new element
    helpers.writeToStringBuffer('div', 0);
    helpers.writeDiff(OP_CREATE_ELEMENT, 10, 1, 3);
    bridge._applyDiffs();

    const result = bridge._measureNode(10);
    expect(result).toBe(1);
  });
});

describe('File Handle Operations', () => {
  let mockWasm;
  let bridge;

  beforeEach(async () => {
    document.body.innerHTML = '<div id="root" data-wasm data-node-id="1"></div>';
    bridge = await import('../bridge.js');
    mockWasm = createMockWasm();
    bridge._initForTest(mockWasm, false);
    bridge._clearNodeRegistry();
    bridge._clearHandles();
    const root = document.getElementById('root');
    bridge.registerNode(root);
  });

  describe('js_file_read_chunk', () => {
    it('should read chunk from file handle', () => {
      // Create test data
      const testData = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      const buffer = testData.buffer;

      // Add file handle directly
      bridge._addFileHandle(1, buffer);

      // Read chunk
      const bytesRead = bridge._fileReadChunk(1, 0, 5);

      expect(bytesRead).toBe(5);

      // Verify data was copied to fetch buffer
      const result = bridge._readFetchBuffer(0, 5);
      expect(Array.from(result)).toEqual([1, 2, 3, 4, 5]);
    });

    it('should read chunk with offset', () => {
      const testData = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      const buffer = testData.buffer;
      bridge._addFileHandle(1, buffer);

      const bytesRead = bridge._fileReadChunk(1, 5, 5);

      expect(bytesRead).toBe(5);
      const result = bridge._readFetchBuffer(0, 5);
      expect(Array.from(result)).toEqual([6, 7, 8, 9, 10]);
    });

    it('should return 0 for non-existent handle', () => {
      const bytesRead = bridge._fileReadChunk(999, 0, 10);
      expect(bytesRead).toBe(0);
    });

    it('should clamp to remaining buffer size', () => {
      const testData = new Uint8Array([1, 2, 3, 4, 5]);
      const buffer = testData.buffer;
      bridge._addFileHandle(1, buffer);

      // Request more than available from offset 3
      const bytesRead = bridge._fileReadChunk(1, 3, 100);

      expect(bytesRead).toBe(2); // Only 2 bytes remaining
      const result = bridge._readFetchBuffer(0, 2);
      expect(Array.from(result)).toEqual([4, 5]);
    });

    it('should return 0 when offset is past buffer end', () => {
      const testData = new Uint8Array([1, 2, 3, 4, 5]);
      const buffer = testData.buffer;
      bridge._addFileHandle(1, buffer);

      const bytesRead = bridge._fileReadChunk(1, 100, 10);
      expect(bytesRead).toBe(0);
    });
  });

  describe('js_file_close', () => {
    it('should remove file handle', () => {
      const testData = new Uint8Array([1, 2, 3]);
      bridge._addFileHandle(1, testData.buffer);

      expect(bridge._hasFileHandle(1)).toBe(true);

      bridge._fileClose(1);

      expect(bridge._hasFileHandle(1)).toBe(false);
    });

    it('should not throw for non-existent handle', () => {
      expect(() => bridge._fileClose(999)).not.toThrow();
    });
  });
});

describe('Blob Handle Operations', () => {
  let mockWasm;
  let bridge;

  beforeEach(async () => {
    document.body.innerHTML = '<div id="root" data-wasm data-node-id="1"></div>';
    bridge = await import('../bridge.js');
    mockWasm = createMockWasm();
    bridge._initForTest(mockWasm, false);
    bridge._clearNodeRegistry();
    bridge._clearHandles();
    const root = document.getElementById('root');
    bridge.registerNode(root);
  });

  describe('js_blob_size', () => {
    it('should return blob size', () => {
      const testData = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      bridge._addBlobHandle(1, testData.buffer);

      const size = bridge._blobSize(1);
      expect(size).toBe(10);
    });

    it('should return 0 for non-existent handle', () => {
      const size = bridge._blobSize(999);
      expect(size).toBe(0);
    });
  });

  describe('js_blob_read_chunk', () => {
    it('should read chunk from blob handle', () => {
      const testData = new Uint8Array([10, 20, 30, 40, 50]);
      bridge._addBlobHandle(1, testData.buffer);

      const bytesRead = bridge._blobReadChunk(1, 0, 3);

      expect(bytesRead).toBe(3);
      const result = bridge._readFetchBuffer(0, 3);
      expect(Array.from(result)).toEqual([10, 20, 30]);
    });

    it('should read chunk with offset', () => {
      const testData = new Uint8Array([10, 20, 30, 40, 50]);
      bridge._addBlobHandle(1, testData.buffer);

      const bytesRead = bridge._blobReadChunk(1, 2, 3);

      expect(bytesRead).toBe(3);
      const result = bridge._readFetchBuffer(0, 3);
      expect(Array.from(result)).toEqual([30, 40, 50]);
    });

    it('should return 0 for non-existent handle', () => {
      const bytesRead = bridge._blobReadChunk(999, 0, 10);
      expect(bytesRead).toBe(0);
    });

    it('should clamp to remaining buffer size', () => {
      const testData = new Uint8Array([1, 2, 3]);
      bridge._addBlobHandle(1, testData.buffer);

      const bytesRead = bridge._blobReadChunk(1, 1, 100);

      expect(bytesRead).toBe(2);
      const result = bridge._readFetchBuffer(0, 2);
      expect(Array.from(result)).toEqual([2, 3]);
    });
  });

  describe('js_blob_free', () => {
    it('should remove blob handle', () => {
      const testData = new Uint8Array([1, 2, 3]);
      bridge._addBlobHandle(1, testData.buffer);

      expect(bridge._hasBlobHandle(1)).toBe(true);

      bridge._blobFree(1);

      expect(bridge._hasBlobHandle(1)).toBe(false);
    });

    it('should not throw for non-existent handle', () => {
      expect(() => bridge._blobFree(999)).not.toThrow();
    });
  });
});

describe('js_set_inner_html_from_blob', () => {
  let mockWasm;
  let bridge;

  beforeEach(async () => {
    document.body.innerHTML = '<div id="root" data-wasm data-node-id="1"></div>';
    bridge = await import('../bridge.js');
    mockWasm = createMockWasm();
    bridge._initForTest(mockWasm, false);
    bridge._clearNodeRegistry();
    bridge._clearHandles();
    const root = document.getElementById('root');
    bridge.registerNode(root);
  });

  it('should set innerHTML from blob', () => {
    const root = document.getElementById('root');
    const html = '<p>Hello from blob!</p>';
    const encoder = new TextEncoder();
    const htmlData = encoder.encode(html);
    bridge._addBlobHandle(1, htmlData.buffer);

    const result = bridge._setInnerHtmlFromBlob(1, 1);

    expect(result).toBe(1);
    expect(root.innerHTML).toBe('<p>Hello from blob!</p>');
  });

  it('should return 0 for non-existent node', () => {
    const html = '<p>Test</p>';
    const encoder = new TextEncoder();
    const htmlData = encoder.encode(html);
    bridge._addBlobHandle(1, htmlData.buffer);

    const result = bridge._setInnerHtmlFromBlob(999, 1);

    expect(result).toBe(0);
  });

  it('should return 0 for non-existent blob', () => {
    const result = bridge._setInnerHtmlFromBlob(1, 999);

    expect(result).toBe(0);
  });

  it('should handle complex HTML', () => {
    const root = document.getElementById('root');
    const html = '<div class="chapter"><h1>Chapter 1</h1><p>Lorem ipsum <em>dolor</em> sit amet.</p></div>';
    const encoder = new TextEncoder();
    const htmlData = encoder.encode(html);
    bridge._addBlobHandle(1, htmlData.buffer);

    const result = bridge._setInnerHtmlFromBlob(1, 1);

    expect(result).toBe(1);
    expect(root.querySelector('h1').textContent).toBe('Chapter 1');
    expect(root.querySelector('em').textContent).toBe('dolor');
  });

  it('should handle UTF-8 content', () => {
    const root = document.getElementById('root');
    const html = '<p>日本語テスト</p>';
    const encoder = new TextEncoder();
    const htmlData = encoder.encode(html);
    bridge._addBlobHandle(1, htmlData.buffer);

    const result = bridge._setInnerHtmlFromBlob(1, 1);

    expect(result).toBe(1);
    expect(root.querySelector('p').textContent).toBe('日本語テスト');
  });
});

describe('Handle Isolation', () => {
  let bridge;

  beforeEach(async () => {
    bridge = await import('../bridge.js');
    bridge._clearHandles();
  });

  it('should clear all handles', () => {
    const testData = new Uint8Array([1, 2, 3]);
    bridge._addFileHandle(1, testData.buffer);
    bridge._addFileHandle(2, testData.buffer);
    bridge._addBlobHandle(1, testData.buffer);
    bridge._addBlobHandle(2, testData.buffer);

    expect(bridge._hasFileHandle(1)).toBe(true);
    expect(bridge._hasFileHandle(2)).toBe(true);
    expect(bridge._hasBlobHandle(1)).toBe(true);
    expect(bridge._hasBlobHandle(2)).toBe(true);

    bridge._clearHandles();

    expect(bridge._hasFileHandle(1)).toBe(false);
    expect(bridge._hasFileHandle(2)).toBe(false);
    expect(bridge._hasBlobHandle(1)).toBe(false);
    expect(bridge._hasBlobHandle(2)).toBe(false);
  });

  it('should have separate namespaces for file and blob handles', () => {
    const fileData = new Uint8Array([1, 2, 3]);
    const blobData = new Uint8Array([4, 5, 6]);

    bridge._addFileHandle(1, fileData.buffer);
    bridge._addBlobHandle(1, blobData.buffer);

    // Both should exist independently
    expect(bridge._hasFileHandle(1)).toBe(true);
    expect(bridge._hasBlobHandle(1)).toBe(true);

    // Freeing one shouldn't affect the other
    bridge._blobFree(1);
    expect(bridge._hasFileHandle(1)).toBe(true);
    expect(bridge._hasBlobHandle(1)).toBe(false);
  });
});

describe('IndexedDB Key-Value Store', () => {
  let mockWasm;
  let bridge;
  let dbCounter = 0;

  // Helper to create unique DB names for test isolation
  function uniqueDbName() {
    return `test-db-${Date.now()}-${dbCounter++}`;
  }

  // Helper to write strings to memory and get pointers
  function writeStrings(mockWasm, ...strings) {
    const results = [];
    let offset = 0;
    const stringPtr = mockWasm.exports.get_string_buffer_ptr();
    const encoder = new TextEncoder();

    for (const str of strings) {
      const bytes = encoder.encode(str);
      const arr = new Uint8Array(mockWasm.exports.memory.buffer, stringPtr + offset, bytes.length);
      arr.set(bytes);
      results.push({ ptr: stringPtr + offset, len: bytes.length });
      offset += bytes.length;
    }
    return results;
  }

  beforeEach(async () => {
    document.body.innerHTML = '<div id="root" data-wasm data-node-id="1"></div>';
    bridge = await import('../bridge.js');
    mockWasm = createMockWasm();
    bridge._initForTest(mockWasm, false);
    bridge._clearNodeRegistry();
    bridge._clearHandles();
    bridge._clearKvDb();
    mockWasm.helpers.clearCallbacks();
  });

  afterEach(() => {
    bridge._clearKvDb();
  });

  describe('js_kv_open', () => {
    it('should call on_kv_open_complete with success=1 on successful open', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'teststore');

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);

      // Wait for async operation
      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_open_complete).toHaveLength(1);
      expect(callbacks.on_kv_open_complete[0].success).toBe(1);
      expect(bridge._isKvDbOpen()).toBe(true);
    });

    it('should create specified object stores during upgrade', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'books,chapters,resources');

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);

      await new Promise(resolve => setTimeout(resolve, 50));

      expect(bridge._isKvDbOpen()).toBe(true);
    });

    it('should open without stores when storesLen is 0', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo] = writeStrings(mockWasm, dbName);

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, 0, 0);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_open_complete).toHaveLength(1);
      expect(callbacks.on_kv_open_complete[0].success).toBe(1);
    });
  });

  describe('js_kv_put', () => {
    it('should call on_kv_complete with success=0 when DB is not open', async () => {
      const [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'testkey');

      bridge._kvPut(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len, 0, 5);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_complete).toHaveLength(1);
      expect(callbacks.on_kv_complete[0].success).toBe(0);
    });

    it('should store data from fetch buffer', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'teststore');

      // Open DB first
      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));
      mockWasm.helpers.clearCallbacks();

      // Write data to fetch buffer
      const testData = 'Hello, IndexedDB!';
      bridge._writeToFetchBuffer(testData, 0);

      // Put data
      const [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'mykey');
      bridge._kvPut(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len, 0, testData.length);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_complete).toHaveLength(1);
      expect(callbacks.on_kv_complete[0].success).toBe(1);
    });
  });

  describe('js_kv_put_blob', () => {
    it('should call on_kv_complete with success=0 when DB is not open', async () => {
      const testData = new Uint8Array([1, 2, 3, 4, 5]);
      bridge._addBlobHandle(1, testData.buffer);

      const [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'testkey');
      bridge._kvPutBlob(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len, 1);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_complete).toHaveLength(1);
      expect(callbacks.on_kv_complete[0].success).toBe(0);
    });

    it('should call on_kv_complete with success=0 for invalid blob handle', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'teststore');

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));
      mockWasm.helpers.clearCallbacks();

      const [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'testkey');
      bridge._kvPutBlob(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len, 999);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_complete).toHaveLength(1);
      expect(callbacks.on_kv_complete[0].success).toBe(0);
    });

    it('should store data from blob handle', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'teststore');

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));
      mockWasm.helpers.clearCallbacks();

      // Add blob
      const testData = new Uint8Array([10, 20, 30, 40, 50]);
      bridge._addBlobHandle(1, testData.buffer);

      const [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'blobkey');
      bridge._kvPutBlob(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len, 1);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_complete).toHaveLength(1);
      expect(callbacks.on_kv_complete[0].success).toBe(1);
    });
  });

  describe('js_kv_get', () => {
    it('should call on_kv_get_complete with len=0 when DB is not open', async () => {
      const [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'testkey');

      bridge._kvGet(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_get_complete).toHaveLength(1);
      expect(callbacks.on_kv_get_complete[0].len).toBe(0);
    });

    it('should call on_kv_get_complete with len=0 for non-existent key', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'teststore');

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));
      mockWasm.helpers.clearCallbacks();

      const [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'nonexistent');
      bridge._kvGet(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_get_complete).toHaveLength(1);
      expect(callbacks.on_kv_get_complete[0].len).toBe(0);
    });

    it('should retrieve stored data and return length', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'teststore');

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));
      mockWasm.helpers.clearCallbacks();

      // Store data
      const testData = 'Test data for retrieval';
      bridge._writeToFetchBuffer(testData, 0);
      let [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'mykey');
      bridge._kvPut(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len, 0, testData.length);
      await new Promise(resolve => setTimeout(resolve, 50));
      mockWasm.helpers.clearCallbacks();

      // Retrieve data
      [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'mykey');
      bridge._kvGet(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_get_complete).toHaveLength(1);
      expect(callbacks.on_kv_get_complete[0].len).toBe(testData.length);

      // Verify data in fetch buffer
      const result = bridge._readFetchBuffer(0, testData.length);
      const decoder = new TextDecoder();
      expect(decoder.decode(result)).toBe(testData);
    });
  });

  describe('js_kv_delete', () => {
    it('should call on_kv_complete with success=0 when DB is not open', async () => {
      const [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'testkey');

      bridge._kvDelete(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len);

      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_complete).toHaveLength(1);
      expect(callbacks.on_kv_complete[0].success).toBe(0);
    });

    it('should delete stored data', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'teststore');

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));
      mockWasm.helpers.clearCallbacks();

      // Store data
      const testData = 'Data to delete';
      bridge._writeToFetchBuffer(testData, 0);
      let [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'deletekey');
      bridge._kvPut(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len, 0, testData.length);
      await new Promise(resolve => setTimeout(resolve, 50));
      mockWasm.helpers.clearCallbacks();

      // Delete data
      [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'deletekey');
      bridge._kvDelete(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_complete).toHaveLength(1);
      expect(callbacks.on_kv_complete[0].success).toBe(1);

      // Verify data is gone
      mockWasm.helpers.clearCallbacks();
      [storeInfo, keyInfo] = writeStrings(mockWasm, 'teststore', 'deletekey');
      bridge._kvGet(storeInfo.ptr, storeInfo.len, keyInfo.ptr, keyInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));

      const getCallbacks = mockWasm.helpers.getCallbacks();
      expect(getCallbacks.on_kv_get_complete).toHaveLength(1);
      expect(getCallbacks.on_kv_get_complete[0].len).toBe(0);
    });
  });

  describe('js_kv_close', () => {
    it('should close the database', async () => {
      const dbName = uniqueDbName();
      const [dbNameInfo, storesInfo] = writeStrings(mockWasm, dbName, 'teststore');

      bridge._kvOpen(dbNameInfo.ptr, dbNameInfo.len, 1, storesInfo.ptr, storesInfo.len);
      await new Promise(resolve => setTimeout(resolve, 50));

      expect(bridge._isKvDbOpen()).toBe(true);

      bridge._kvClose();

      expect(bridge._isKvDbOpen()).toBe(false);
    });

    it('should not throw when no database is open', () => {
      expect(() => bridge._kvClose()).not.toThrow();
    });
  });

  describe('Callback tracking in mock', () => {
    it('should track on_kv_open_complete callbacks', () => {
      mockWasm.exports.on_kv_open_complete(1);

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_open_complete).toHaveLength(1);
      expect(callbacks.on_kv_open_complete[0].success).toBe(1);
    });

    it('should track on_kv_complete callbacks', () => {
      mockWasm.exports.on_kv_complete(1);

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_complete).toHaveLength(1);
      expect(callbacks.on_kv_complete[0].success).toBe(1);
    });

    it('should track on_kv_get_complete callbacks', () => {
      mockWasm.exports.on_kv_get_complete(42);

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_get_complete).toHaveLength(1);
      expect(callbacks.on_kv_get_complete[0].len).toBe(42);
    });

    it('should track on_kv_get_blob_complete callbacks', () => {
      mockWasm.exports.on_kv_get_blob_complete(5, 1024);

      const callbacks = mockWasm.helpers.getCallbacks();
      expect(callbacks.on_kv_get_blob_complete).toHaveLength(1);
      expect(callbacks.on_kv_get_blob_complete[0]).toEqual({ handle: 5, size: 1024 });
    });
  });
});
