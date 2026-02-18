/**
 * Smoke test: quick sanity check that WASM loads, import works,
 * and basic reader opens. Runs before full suite so obvious
 * failures (infinite loop, crash-on-load) fail fast.
 *
 * Runs only on desktop viewport for speed.
 */

import { test, expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');
mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.describe('Smoke', () => {
  test('WASM loads and EPUB import works', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => {
      errors.push(err.message);
      console.error('PAGE ERROR:', err.message);
    });
    page.on('crash', () => {
      console.error('PAGE CRASHED during smoke test. Errors:', errors);
    });

    // Generate a minimal EPUB
    const epubBuffer = createEpub({
      title: 'Smoke Test',
      author: 'Bot',
      chapters: 1,
      paragraphsPerChapter: 2,
    });

    // App loads and shows library
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import the EPUB
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'smoke-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    // Book card appears
    await page.waitForSelector('.book-card', { timeout: 30000 });
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('Smoke Test');

    // Open book — reader renders
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.chapter-container', { timeout: 15000 });

    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Page info visible
    const pageInfo = page.locator('.page-info');
    await expect(pageInfo).toBeVisible();

    // No crashes
    expect(errors.length).toBe(0);
  });
});
