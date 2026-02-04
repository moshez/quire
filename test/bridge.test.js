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
