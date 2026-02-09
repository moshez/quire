// bridge_log.test.mjs — Logging bridge tests

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createWardInstance } from './helpers.mjs';

describe('Logging bridge', () => {
  it('ward_log does not throw and chain continues past it', async () => {
    // The exerciser calls ward_log(1, "ward-init", 9) at startup.
    // If the log import threw, ward_node_init would fail and done
    // would never resolve.
    const { done } = await createWardInstance();
    await done;
  });
});
