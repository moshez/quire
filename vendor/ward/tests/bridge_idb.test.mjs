// bridge_idb.test.mjs — IndexedDB round-trip tests

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('IndexedDB round-trip', () => {
  it('done resolves after full put/get/delete chain', async () => {
    const { done } = await createWardInstance();
    // done resolves when ward_exit is called after the full chain
    await done;
  });

  it('IDB kv store is empty after chain completes', async () => {
    const { done } = await createWardInstance();
    await done;

    // After the chain: put → get → delete, the key should be gone
    const db = await new Promise((resolve, reject) => {
      const req = indexedDB.open('ward', 1);
      req.onupgradeneeded = () => req.result.createObjectStore('kv');
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });

    const result = await new Promise((resolve, reject) => {
      const tx = db.transaction('kv', 'readonly');
      const req = tx.objectStore('kv').get('test-key');
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });

    assert.equal(result, undefined, 'test-key should have been deleted');
    db.close();
  });
});
