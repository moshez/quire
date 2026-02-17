// crash-repro.spec.js — Test ward#18 standalone crash reproduction
// Loads crash_repro.wasm via ward_bridge.mjs in Chromium.
// If the renderer crashes, this test detects it.

import { test, expect } from '@playwright/test';

test('crash_repro completes without renderer crash', async ({ page }) => {
  // Only run once (desktop viewport) — crash is viewport-independent
  const info = test.info();
  test.skip(info.project.name !== 'desktop', 'skip non-desktop viewports');

  let crashed = false;
  page.on('crash', () => { crashed = true; });

  await page.goto('/vendor/ward/exerciser/crash_repro.html', {
    waitUntil: 'domcontentloaded',
    timeout: 15000,
  });

  // Wait for the exerciser to finish (logs "SUCCESS" or "FATAL:")
  try {
    await page.waitForFunction(
      () => {
        const log = document.getElementById('log');
        return log && (log.textContent.includes('SUCCESS') || log.textContent.includes('FATAL:'));
      },
      { timeout: 30000 }
    );
  } catch (e) {
    // waitForFunction can fail if renderer crashed
    await new Promise(r => setTimeout(r, 500));
  }

  if (crashed) {
    test.fail(true, 'Chromium renderer crashed — ward#18 reproduced!');
    return;
  }

  // If no crash, check the log for results
  const logText = await page.evaluate(() => document.getElementById('log')?.textContent || '');
  console.log('crash_repro log:', logText);

  // Take a screenshot
  await page.screenshot({ path: 'e2e/screenshots/crash-repro.png' });

  expect(logText).toContain('SUCCESS');
});
