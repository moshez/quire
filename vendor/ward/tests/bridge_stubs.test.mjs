// bridge_stubs.test.mjs — tests for unstubbed bridge functions

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('unstubbed bridge functions', () => {
  describe('fetch', () => {
    it('exports ward_on_fetch_complete', async () => {
      const { ward } = await createWardInstance();
      assert.equal(typeof ward.ward_on_fetch_complete, 'function');
    });
  });

  describe('file', () => {
    it('exports ward_on_file_open', async () => {
      const { ward } = await createWardInstance();
      assert.equal(typeof ward.ward_on_file_open, 'function');
    });
  });

  describe('decompress', () => {
    it('exports ward_on_decompress_complete', async () => {
      const { ward } = await createWardInstance();
      assert.equal(typeof ward.ward_on_decompress_complete, 'function');
    });
  });

  describe('notification', () => {
    it('exports ward_on_permission_result', async () => {
      const { ward } = await createWardInstance();
      assert.equal(typeof ward.ward_on_permission_result, 'function');
    });
  });

  describe('push', () => {
    it('exports ward_on_push_subscribe', async () => {
      const { ward } = await createWardInstance();
      assert.equal(typeof ward.ward_on_push_subscribe, 'function');
    });
  });
});
