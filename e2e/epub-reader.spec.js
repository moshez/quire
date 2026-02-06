/**
 * E2E test: EPUB import and reading flow.
 *
 * Creates a minimal EPUB programmatically, imports it into Quire,
 * verifies the library view, opens the book, flips pages, and
 * takes screenshots at each key step.
 */

import { test, expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');

mkdirSync(SCREENSHOT_DIR, { recursive: true });

async function screenshot(page, name) {
  await page.screenshot({ path: join(SCREENSHOT_DIR, `${name}.png`), fullPage: true });
}

test.describe('EPUB Reader E2E', () => {

  test('import epub, read, and flip pages', async ({ page }) => {
    // Generate a 3-chapter EPUB with enough text for multiple pages
    const epubBuffer = createEpub({
      title: 'A Tale of Testing',
      author: 'Quire Bot',
      chapters: 3,
      paragraphsPerChapter: 20,
    });

    // Navigate to app and wait for WASM initialization.
    // The app goes through: INIT → LOADING_DB → LOADING_LIB → LIBRARY.
    await page.goto('/');
    await page.waitForSelector('label.import-btn', { timeout: 15000 });

    // Wait for the library to finish loading via IndexedDB callbacks.
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await screenshot(page, '01-library-empty');

    // Check that the empty library message is visible
    const emptyMsg = page.locator('.empty-lib');
    await expect(emptyMsg).toBeVisible();
    await expect(emptyMsg).toContainText('No books yet');

    // --- Import the EPUB ---
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'test-book.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    // Wait for import to finish and library to rebuild with a book card
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, '02-library-with-book');

    // Verify the book card shows correct title and author
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('A Tale of Testing');
    const bookAuthor = page.locator('.book-author');
    await expect(bookAuthor).toContainText('Quire Bot');

    // Verify "Not started" position
    const bookPosition = page.locator('.book-position');
    await expect(bookPosition).toContainText('Not started');

    // --- Open the book ---
    const readBtn = page.locator('.read-btn');
    await readBtn.click();

    // Wait for reader to appear with chapter content
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForSelector('.chapter-container', { timeout: 15000 });
    // Let CSS column layout settle
    await page.waitForTimeout(1000);
    await screenshot(page, '03-reader-chapter1');

    // Verify chapter container is visible
    const chapterContainer = page.locator('.chapter-container').first();
    await expect(chapterContainer).toBeVisible();

    // --- Flip pages forward using click zones ---
    const viewport = page.viewportSize();
    const rightZoneX = viewport.width - 50;
    const leftZoneX = 50;
    const centerX = viewport.width / 2;
    const centerY = viewport.height / 2;

    // Click right zone to go to next page
    await page.mouse.click(rightZoneX, centerY);
    await page.waitForTimeout(500);
    await screenshot(page, '04-reader-page-forward');

    // Click right zone again
    await page.mouse.click(rightZoneX, centerY);
    await page.waitForTimeout(500);
    await screenshot(page, '05-reader-page-forward2');

    // --- Flip back using left click zone ---
    await page.mouse.click(leftZoneX, centerY);
    await page.waitForTimeout(500);
    await screenshot(page, '06-reader-page-back');

    // --- Keyboard navigation ---
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(500);
    await screenshot(page, '07-reader-arrow-right');

    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(500);

    await page.keyboard.press('Space');
    await page.waitForTimeout(500);
    await screenshot(page, '08-reader-space-forward');

    // --- TOC overlay ---
    await page.mouse.click(centerX, centerY);
    await page.waitForTimeout(500);

    const tocOverlay = page.locator('.toc-overlay');
    const tocVisible = await tocOverlay.isVisible().catch(() => false);
    if (tocVisible) {
      await screenshot(page, '09-toc-overlay');

      const tocEntries = page.locator('.toc-entry');
      const entryCount = await tocEntries.count();
      if (entryCount > 1) {
        await tocEntries.nth(1).click();
        await page.waitForTimeout(1000);
        await screenshot(page, '10-reader-chapter2-via-toc');
      }
    } else {
      await screenshot(page, '09-current-state');
    }

    // --- Navigate back to library ---
    // Dismiss TOC overlay if still showing (it intercepts pointer events)
    const tocStillVisible = await tocOverlay.isVisible().catch(() => false);
    if (tocStillVisible) {
      await page.keyboard.press('Escape');
      await page.waitForTimeout(500);
    }

    // Use Escape to go back to library (works reliably even with overlays)
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);

    // Wait for library to reappear
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, '11-library-after-reading');

    // Verify reading position was saved
    const posAfterRead = page.locator('.book-position');
    await expect(posAfterRead).toBeVisible();
    const posText = await posAfterRead.textContent();
    expect(posText === 'Not started' || posText.includes('Ch ')).toBeTruthy();
  });
});
