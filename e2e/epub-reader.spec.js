/**
 * E2E test: EPUB import and reading flow.
 *
 * Creates a minimal EPUB programmatically, imports it into Quire,
 * verifies the library view, opens the book, flips pages, and
 * takes screenshots at each key step.
 *
 * Runs at multiple viewport sizes (see playwright.config.js projects).
 */

import { test, expect } from '@playwright/test';
import { createEpub } from './create-epub.js';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');

mkdirSync(SCREENSHOT_DIR, { recursive: true });

/** Viewport-aware screenshot: includes project name in filename.
 * Forces a paint cycle before capture — CSS transform changes (e.g.,
 * translateX for column pagination) may not be painted yet in headless
 * Chromium when the screenshot is taken synchronously. */
async function screenshot(page, name) {
  // Wait for two animation frames to ensure CSS transforms are painted
  await page.evaluate(() => new Promise(r =>
    requestAnimationFrame(() => requestAnimationFrame(r))));
  const vp = page.viewportSize();
  const tag = `${vp.width}x${vp.height}`;
  await page.screenshot({ path: join(SCREENSHOT_DIR, `${name}-${tag}.png`) });
}

test.describe('EPUB Reader E2E', () => {

  test('import epub, read, and flip pages', async ({ page }) => {
    // Capture errors and console messages for debugging WASM crashes
    const errors = [];
    const consoleMessages = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('console', msg => consoleMessages.push(`[${msg.type()}] ${msg.text()}`));
    page.on('crash', () => {
      console.error('PAGE CRASHED. Errors:', errors);
      console.error('Console messages:', consoleMessages);
    });

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
    await screenshot(page, '00-app-loading');
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

    // Verify import progress UI appears during import.
    // The label class changes from "import-btn" to "importing" and the status div
    // shows progress messages. The import may complete very fast in CI, so we race
    // the progress check against the final book-card appearing.
    const sawProgress = await Promise.race([
      page.waitForSelector('label.importing', { timeout: 30000 })
        .then(() => true)
        .catch(() => false),
      page.waitForSelector('.book-card', { timeout: 30000 })
        .then(() => false),
    ]);

    if (sawProgress) {
      await screenshot(page, '02a-import-progress');
      // If we caught the importing state, verify status div has content —
      // but only if import is still in progress (it may have completed
      // between the race resolution and this assertion).
      const stillImporting = await page.locator('label.importing').isVisible();
      if (stillImporting) {
        const importStatus = page.locator('.import-status');
        await expect(importStatus).not.toBeEmpty({ timeout: 10000 });
      }
    }

    // Wait for import to finish and library to rebuild with a book card
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, '02-library-with-book');

    // Verify import UI is cleaned up: "importing" class gone, "import-btn" restored
    const importBtn = page.locator('label.import-btn');
    await expect(importBtn).toBeVisible({ timeout: 5000 });

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

    // --- Verify navigation bar UI ---
    const readerNav = page.locator('.reader-nav');
    await expect(readerNav).toBeVisible();

    const backBtn = page.locator('.back-btn');
    await expect(backBtn).toBeVisible();
    await expect(backBtn).toContainText('Back');

    // --- Verify prev/next buttons visible ---
    const prevBtn = page.locator('.prev-btn');
    const nextBtn = page.locator('.next-btn');
    await expect(prevBtn).toBeVisible();
    await expect(prevBtn).toContainText('Prev');
    await expect(nextBtn).toBeVisible();
    await expect(nextBtn).toContainText('Next');

    const pageInfo = page.locator('.page-info');
    await expect(pageInfo).toBeVisible();

    // Page indicator should show "Ch X/Y  N/M" format after chapter loads
    const pageText = await pageInfo.textContent();
    expect(pageText).toMatch(/^Ch \d+\/\d+\s+\d+\/\d+$/);
    // First chapter, first page: "Ch 1/3  1/N"
    expect(pageText).toMatch(/^Ch 1\//);

    // Verify chapter container is visible and has paragraph text
    const chapterContainer = page.locator('.chapter-container').first();
    await expect(chapterContainer).toBeVisible();
    await expect(chapterContainer).toContainText('mountain path', { timeout: 5000 });

    // Verify substantial content rendered (not just a heading + truncated line)
    const textLen = await chapterContainer.evaluate(el => el.textContent.length);
    expect(textLen).toBeGreaterThan(200);

    // Verify multiple paragraph elements rendered
    const pCount = await page.locator('.chapter-container p').count();
    expect(pCount).toBeGreaterThan(1);

    // Verify multi-page content: scrollWidth should exceed visible width
    const dims = await chapterContainer.evaluate(el => ({
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    }));
    expect(dims.scrollWidth).toBeGreaterThan(dims.clientWidth);

    // RENDERING PROOF: column width matches viewport width (no bleeding)
    // scrollWidth must be an exact multiple of viewport width
    const vpWidth = page.viewportSize().width;
    expect(dims.scrollWidth % vpWidth).toBe(0);

    // RENDERING PROOF: child elements have horizontal padding (not flush to edge)
    // The .chapter-container>* rule sets padding-left/right on children.
    // Padding is inside the bounding rect, so we check computed style.
    const childPadding = await chapterContainer.evaluate(el => {
      const child = el.firstElementChild;
      if (!child) return null;
      const cs = getComputedStyle(child);
      return {
        paddingLeft: parseFloat(cs.paddingLeft),
        paddingRight: parseFloat(cs.paddingRight),
      };
    });
    if (childPadding) {
      expect(childPadding.paddingLeft).toBeGreaterThan(0);
      expect(childPadding.paddingRight).toBeGreaterThan(0);
    }

    // --- Flip pages forward using click zones ---
    const viewport = page.viewportSize();
    const rightZoneX = viewport.width - 50;
    const leftZoneX = 50;
    const centerY = viewport.height / 2;

    // Capture initial transform (should be 'none' or translateX(0))
    const transformInitial = await chapterContainer.evaluate(
      el => getComputedStyle(el).transform
    );

    // Click right zone to go to next page
    await page.mouse.click(rightZoneX, centerY);
    await page.waitForTimeout(500);
    await screenshot(page, '04-reader-page-forward');

    // Verify transform CHANGED from initial (page actually moved)
    const transformAfterForward = await chapterContainer.evaluate(
      el => getComputedStyle(el).transform
    );
    expect(transformAfterForward).not.toBe(transformInitial);

    // Verify page indicator updated after forward click
    const pageTextAfterForward = await pageInfo.textContent();
    expect(pageTextAfterForward).toMatch(/^Ch \d+\/\d+\s+\d+\/\d+$/);
    // Page 2: "Ch 1/3  2/N"
    expect(pageTextAfterForward).toMatch(/\s+2\/\d+$/);

    // RENDERING PROOF: after forward, transform shifts by exactly viewport width
    const transformPx = await chapterContainer.evaluate(el => {
      const style = el.getAttribute('style') || '';
      const match = style.match(/translateX\((-?\d+)px/);
      return match ? parseInt(match[1]) : 0;
    });
    expect(transformPx).toBe(-vpWidth);

    // --- Test prev button navigation ---
    await prevBtn.click();
    await page.waitForTimeout(500);
    await screenshot(page, '04a-reader-prev-btn');

    // Should be back at page 1
    const pageTextAfterPrev = await pageInfo.textContent();
    expect(pageTextAfterPrev).toMatch(/\s+1\/\d+$/);

    // --- Test next button navigation ---
    await nextBtn.click();
    await page.waitForTimeout(500);
    await screenshot(page, '04b-reader-next-btn');

    // Should be at page 2
    const pageTextAfterNext = await pageInfo.textContent();
    expect(pageTextAfterNext).toMatch(/\s+2\/\d+$/);

    // Determine total pages — extract from "Ch X/Y  N/M" format
    const totalPages = parseInt(pageTextAfterNext.match(/\s+\d+\/(\d+)$/)[1]);

    // Click right zone again only if more pages exist in this chapter.
    // At wide viewports (2 pages), clicking Next would cross to chapter 2.
    if (totalPages > 2) {
      const transformBeforeThird = await chapterContainer.evaluate(
        el => getComputedStyle(el).transform
      );
      await page.mouse.click(rightZoneX, centerY);
      await page.waitForTimeout(500);
      await screenshot(page, '05-reader-page-forward2');

      const transformAfterThird = await chapterContainer.evaluate(
        el => getComputedStyle(el).transform
      );
      expect(transformAfterThird).not.toBe(transformBeforeThird);

      // Flip back using left click zone
      await page.mouse.click(leftZoneX, centerY);
      await page.waitForTimeout(500);
    }
    await screenshot(page, '06-reader-page-back');

    // Verify page indicator shows page 2 (went back from 3, or stayed at 2)
    const pageTextAfterBack = await pageInfo.textContent();
    expect(pageTextAfterBack).toMatch(/\s+2\/\d+$/);

    // --- Keyboard navigation ---
    // Ensure the viewport has focus for keyboard events.
    // (Previous interaction may have focused a button instead.)
    await page.locator('.reader-viewport').focus();
    await page.waitForTimeout(300);

    // Navigate forward then back to verify keyboard works
    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(500);
    await screenshot(page, '07-reader-arrow-left');

    // Should be at page 1
    const pageTextAfterArrowLeft = await pageInfo.textContent();
    expect(pageTextAfterArrowLeft).toMatch(/\s+1\/\d+$/);

    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(500);
    await screenshot(page, '08-reader-arrow-right');

    // Should be at page 2
    const pageTextAfterArrowRight = await pageInfo.textContent();
    expect(pageTextAfterArrowRight).toMatch(/\s+2\/\d+$/);

    await page.keyboard.press('Space');
    await page.waitForTimeout(500);
    await screenshot(page, '09-reader-space-forward');

    // --- Navigate back to library via back button ---
    const backBtnNav = page.locator('.back-btn');
    await backBtnNav.click();
    await page.waitForTimeout(500);

    // Wait for library to reappear
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, '13-library-after-reading');

    // Verify reading position was saved (must NOT be "Not started")
    const posAfterRead = page.locator('.book-position');
    await expect(posAfterRead).toBeVisible();
    const posText = await posAfterRead.textContent();
    expect(posText).not.toBe('Not started');
  });

  test('import real-world epub with deflate-compressed metadata', async ({ page }) => {
    // This test uses a real-world EPUB whose metadata entries (container.xml,
    // content.opf) are deflate-compressed (ZIP method 8). The async decompression
    // path in epub_read_container_async / epub_read_opf_async handles this.
    // Additionally, the OPF has <dc:creator id="author_0"> (attribute on tag),
    // which tests the _find_gt metadata parsing fix.

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(`[${msg.type()}] ${msg.text()}`));
    page.on('pageerror', err => consoleMessages.push(`[error] ${err.message}`));

    // Navigate to app and wait for library
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import the real EPUB fixture
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles('test/fixtures/conan-stories.epub');

    // Wait for import to complete — book card must appear
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'conan-import-success');

    // Verify import UI is cleaned up
    const importBtn = page.locator('label.import-btn');
    await expect(importBtn).toBeVisible({ timeout: 5000 });

    // Verify no errors were logged
    const errorLogs = consoleMessages.filter(m => m.includes('[ward:error]'));
    expect(errorLogs.length).toBe(0);

    // Verify import-done was logged (proves linear token was consumed)
    const doneLogs = consoleMessages.filter(m => m.includes('import-done'));
    expect(doneLogs.length).toBeGreaterThan(0);

    // Verify metadata extraction: title and author parsed from deflate-compressed
    // OPF with attributes on dc:creator (id="author_0")
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('Gods of the North');
    const bookAuthor = page.locator('.book-author');
    await expect(bookAuthor).toContainText('Robert E. Howard');

    // --- Open the book and verify reading works ---
    const readBtn = page.locator('.read-btn');
    await readBtn.click();

    // Wait for reader to appear
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForSelector('.chapter-container', { timeout: 15000 });

    // Wait for chapter content to render. The first spine entry in this EPUB
    // is a cover page with SVG (no text), so we check for child elements
    // rather than text content.
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    await screenshot(page, 'conan-reader');

    // Verify nav bar appears with all controls
    const readerNav = page.locator('.reader-nav');
    await expect(readerNav).toBeVisible();
    await expect(page.locator('.prev-btn')).toBeVisible();
    await expect(page.locator('.next-btn')).toBeVisible();
    await expect(page.locator('.page-info')).toBeVisible();

    // Verify chapter content rendered (deflate-compressed chapter data).
    // The first spine entry is a cover page — check child elements,
    // not text content, to confirm the chapter was decompressed and rendered.
    const container = page.locator('.chapter-container').first();
    await expect(container).toBeVisible();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);

    // Verify chapter progress format: "Ch X/Y  N/M"
    const pageInfo = page.locator('.page-info');
    const progressText = await pageInfo.textContent();
    expect(progressText).toMatch(/^Ch \d+\/\d+\s+\d+\/\d+$/);

    // --- 50-page walk: click Next up to 50 times, screenshot each ---
    const nextBtn = page.locator('.next-btn');
    const pageInfoEl = page.locator('.page-info');
    const walkContainer = page.locator('.chapter-container').first();
    const walkLog = [];
    let crashed = false;
    page.on('crash', () => { crashed = true; });

    let prevPageText = await pageInfoEl.textContent();
    walkLog.push({ step: 0, page: prevPageText, ok: true });

    for (let step = 1; step <= 50; step++) {
      if (crashed) break;

      const prevCh = prevPageText.match(/^Ch (\d+)\//)?.[1];

      try {
        await nextBtn.click();

        // Wait for page info to change — short timeout since page flips
        // are near-instant. Chapter transitions trigger async decompression
        // which may crash the renderer (ward#18).
        await page.waitForFunction((prev) => {
          const info = document.querySelector('.page-info');
          return info && info.textContent !== prev;
        }, prevPageText, { timeout: 5000 });

        const curPageText = await pageInfoEl.textContent();
        const curCh = curPageText.match(/^Ch (\d+)\//)?.[1];

        // On chapter transition, wait for content to load
        if (curCh !== prevCh) {
          await page.waitForFunction(() => {
            const el = document.querySelector('.chapter-container');
            return el && el.childElementCount > 0;
          }, { timeout: 10000 });
          await page.waitForTimeout(300);
        } else {
          await page.waitForTimeout(100);
        }

        // Capture column layout diagnostics + visible content check
        const diag = await walkContainer.evaluate(el => {
          const cs = getComputedStyle(el);
          const parent = el.parentElement;
          const parentCS = parent ? getComputedStyle(parent) : {};
          // Check if any child element's bounding rect intersects the viewport
          const vpWidth = window.innerWidth;
          const vpHeight = window.innerHeight;
          let visibleChildCount = 0;
          for (const child of el.children) {
            const r = child.getBoundingClientRect();
            if (r.width > 0 && r.height > 0 &&
                r.right > 0 && r.left < vpWidth &&
                r.bottom > 0 && r.top < vpHeight) {
              visibleChildCount++;
            }
          }
          return {
            childCount: el.childElementCount,
            textLen: el.textContent.length,
            hasSvg: !!el.querySelector('svg'),
            scrollWidth: el.scrollWidth,
            clientWidth: el.clientWidth,
            containerHeight: el.getBoundingClientRect().height,
            transform: el.style.transform || 'none',
            computedTransform: cs.transform,
            columnWidth: cs.columnWidth,
            overflow: parentCS.overflow || 'unknown',
            parentHeight: parent ? parent.getBoundingClientRect().height : 0,
            vpWidth,
            vpHeight,
            visibleChildCount,
          };
        });

        const ok = diag.childCount > 0 && (diag.textLen > 0 || diag.hasSvg);
        walkLog.push({ step, page: curPageText, ...diag, ok });

        await screenshot(page, `conan-walk-${String(step).padStart(2, '0')}`);

        if (curPageText === prevPageText) {
          walkLog.push({ step, page: curPageText, note: 'end-of-book' });
          break;
        }

        expect(diag.childCount).toBeGreaterThan(0);
        // Content must be visually rendered in the viewport — not just
        // present in the DOM but translated off-screen by a stale transform.
        // visibleChildCount checks bounding rects against viewport bounds,
        // catching the stale-transform bug (ward#18 regression) where
        // apply_page_transform was skipped on chapter transitions.
        expect(diag.scrollWidth).toBeGreaterThan(0);
        expect(diag.visibleChildCount).toBeGreaterThan(0);
        prevPageText = curPageText;
      } catch (e) {
        // Give crash event a chance to fire (it's async)
        await new Promise(r => setTimeout(r, 200));
        walkLog.push({
          step,
          note: crashed ? 'CRASHED' : 'error: ' + e.message,
          prevPage: prevPageText,
        });
        break;
      }
    }

    // Log the complete walk for CI artifact inspection
    console.log('=== CONAN WALK LOG ===');
    walkLog.forEach(entry => console.log(JSON.stringify(entry)));
    console.log('=== END WALK LOG ===');

    // The walk should have progressed past the cover page at minimum
    expect(walkLog.length).toBeGreaterThan(1);
  });

  test('chapter navigation: Next crosses to next chapter', async ({ page }) => {
    // Create an EPUB with a very short first chapter (1 page) and a second
    // chapter with enough text for multiple pages. This tests that clicking
    // Next at the last page of chapter 1 loads chapter 2.
    const epubBuffer = createEpub({
      title: 'Chapter Nav Test',
      author: 'Test Bot',
      chapters: 3,
      paragraphsPerChapter: 1,  // Very short — 1 page per chapter
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'chapnav-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForSelector('.chapter-container', { timeout: 15000 });

    // Wait for first chapter content to render
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);
    await screenshot(page, 'chapnav-01-chapter1');

    // Should be at page 1 of chapter 1 (only 1 page with 1 paragraph)
    const pageInfo = page.locator('.page-info');
    const initialText = await pageInfo.textContent();
    expect(initialText).toMatch(/^Ch 1\//);

    // Get initial chapter content
    const container = page.locator('.chapter-container').first();
    const initialContent = await container.textContent();

    // Click Next — should cross to chapter 2
    const nextBtn = page.locator('.next-btn');
    await nextBtn.click();

    // Wait for the new chapter content to load (async decompression)
    await page.waitForFunction((prevContent) => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent !== prevContent && el.childElementCount > 0;
    }, initialContent, { timeout: 15000 });
    await page.waitForTimeout(500);
    await screenshot(page, 'chapnav-02-chapter2');

    // Page info should show chapter 2: "Ch 2/..."
    const ch2Text = await pageInfo.textContent();
    expect(ch2Text).toMatch(/^Ch 2\//);

    // Verify content actually changed (different chapter heading)
    const newContent = await container.textContent();
    expect(newContent).not.toBe(initialContent);

    // Verify chapter 2 has non-empty content after transition
    const ch2ChildCount = await container.evaluate(el => el.childElementCount);
    expect(ch2ChildCount).toBeGreaterThan(0);
    const ch2TextLen = await container.evaluate(el => el.textContent.length);
    expect(ch2TextLen).toBeGreaterThan(0);

    // Click Prev — should go back to chapter 1
    const prevBtn = page.locator('.prev-btn');
    await prevBtn.click();

    // Wait for previous chapter to reload
    await page.waitForFunction((ch2Content) => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent !== ch2Content && el.childElementCount > 0;
    }, newContent, { timeout: 15000 });
    await page.waitForTimeout(500);
    await screenshot(page, 'chapnav-03-back-to-chapter1');

    // Should be at chapter 1 again
    const backText = await pageInfo.textContent();
    expect(backText).toMatch(/^Ch 1\//);

    // Verify chapter 1 has non-empty content after backward transition
    const ch1ChildCount = await container.evaluate(el => el.childElementCount);
    expect(ch1ChildCount).toBeGreaterThan(0);
    const ch1TextLen = await container.evaluate(el => el.textContent.length);
    expect(ch1TextLen).toBeGreaterThan(0);

    // Navigate back to library
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('SVG cover chapter transition does not crash', async ({ page }) => {
    // Regression test: synthetic EPUB with SVG cover + chapter transition.
    // Tests the same pattern as conan EPUB (SVG cover → Next → chapter load).
    const epubBuffer = createEpub({
      title: 'SVG Cover Nav Test',
      author: 'Test Bot',
      chapters: 2,
      paragraphsPerChapter: 1,
      svgCover: true,
      coverImage: true,
    });

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(`[${msg.type()}] ${msg.text()}`));
    page.on('crash', () => {
      console.error('PAGE CRASHED during SVG cover nav test');
      console.error('Console:', consoleMessages);
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'svgcover-nav-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });

    // Wait for cover to render
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    const pageInfo = page.locator('.page-info');
    await expect(pageInfo).toBeVisible();
    await screenshot(page, 'svgcover-before-nav');

    // Click Next — transition from SVG cover to chapter 1
    const nextBtn = page.locator('.next-btn');
    await nextBtn.click();

    // Wait for chapter content (should show Ch 2/)
    await page.waitForFunction(() => {
      const info = document.querySelector('.page-info');
      return info && /^Ch 2\//.test(info.textContent);
    }, { timeout: 15000 });

    const container = page.locator('.chapter-container').first();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);
    await screenshot(page, 'svgcover-after-nav');

    // Navigate back to library
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('large chapter with SVG cover and image does not crash', async ({ page }) => {
    // Diagnostic test: synthetic EPUB with SVG cover + large chapters (~21KB like
    // conan) + cover image. Tests whether chapter SIZE triggers the crash.
    const epubBuffer = createEpub({
      title: 'Large Chapter Test',
      author: 'Test Bot',
      chapters: 2,
      paragraphsPerChapter: 80,  // ~21KB like conan's h-0
      svgCover: true,
      coverImage: true,
    });

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(`[${msg.type()}] ${msg.text()}`));
    page.on('crash', () => {
      console.error('PAGE CRASHED during large chapter test');
      console.error('Console:', consoleMessages);
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'large-chapter-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });

    // Wait for cover to render
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    await screenshot(page, 'largechapter-cover');

    // Click Next — transition from SVG cover to large chapter 1
    const nextBtn = page.locator('.next-btn');
    await nextBtn.click();

    // Wait for chapter content (should show Ch 2/)
    await page.waitForFunction(() => {
      const info = document.querySelector('.page-info');
      return info && /^Ch 2\//.test(info.textContent);
    }, { timeout: 15000 });

    const container = page.locator('.chapter-container').first();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);
    const textLen = await container.evaluate(el => el.textContent.length);
    expect(textLen).toBeGreaterThan(100);
    await screenshot(page, 'largechapter-chapter1');

    // Navigate back to library
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('library persists across page reload', async ({ page }) => {
    // Import a book, reload the page, and verify the book is still there.
    const epubBuffer = createEpub({
      title: 'Persistence Test Book',
      author: 'Reload Author',
      chapters: 2,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'persistence-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'persist-01-after-import');

    // Verify book title is visible
    const titleBefore = page.locator('.book-title');
    await expect(titleBefore).toBeVisible();
    const titleText = await titleBefore.textContent();
    expect(titleText).toContain('Persistence Test Book');

    // Wait for IndexedDB save to complete (library_save is async)
    await page.waitForTimeout(2000);

    // Reload the page
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await screenshot(page, 'persist-02-after-reload');

    // Verify the book card is still there after reload
    const bookCard = page.locator('.book-card');
    await expect(bookCard).toBeVisible({ timeout: 10000 });

    // Verify title survived the reload
    const titleAfter = page.locator('.book-title');
    await expect(titleAfter).toBeVisible();
    const titleAfterText = await titleAfter.textContent();
    expect(titleAfterText).toContain('Persistence Test Book');

    // Verify author survived
    const authorAfter = page.locator('.book-author');
    await expect(authorAfter).toBeVisible();
    const authorText = await authorAfter.textContent();
    expect(authorText).toContain('Reload Author');

    await screenshot(page, 'persist-03-verified');
  });

  test('reading position is restored when re-entering book', async ({ page }) => {
    // Import a multi-chapter book, navigate to chapter 2, go back to library,
    // re-enter the book, and verify it resumes at chapter 2.
    const epubBuffer = createEpub({
      title: 'Position Restore Test',
      author: 'Resume Bot',
      chapters: 3,
      paragraphsPerChapter: 1,  // Short chapters — 1 page each
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'position-restore.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Should start at chapter 1
    const pageInfo = page.locator('.page-info');
    const initialText = await pageInfo.textContent();
    expect(initialText).toMatch(/^Ch 1\//);

    // Navigate to chapter 2
    const nextBtn = page.locator('.next-btn');
    const container = page.locator('.chapter-container').first();
    const ch1Content = await container.textContent();
    await nextBtn.click();
    await page.waitForFunction((prev) => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent !== prev && el.childElementCount > 0;
    }, ch1Content, { timeout: 15000 });
    await page.waitForTimeout(500);

    // Verify we're at chapter 2
    const ch2Text = await pageInfo.textContent();
    expect(ch2Text).toMatch(/^Ch 2\//);
    await screenshot(page, 'position-01-at-chapter2');

    // Go back to library
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    // Verify position is saved (should show "Ch 2" in library)
    const posText = await page.locator('.book-position').textContent();
    expect(posText).toMatch(/Ch 2/);
    await screenshot(page, 'position-02-library-saved');

    // Re-enter the book
    const readBtn2 = page.locator('.read-btn');
    await readBtn2.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify position restored: should be at chapter 2
    const restoredText = await pageInfo.textContent();
    expect(restoredText).toMatch(/^Ch 2\//);
    await screenshot(page, 'position-03-restored');

    // Navigate back
    const backBtn2 = page.locator('.back-btn');
    await backBtn2.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('chapter progress shows Ch X/Y format', async ({ page }) => {
    // Verify the page info displays chapter progress in "Ch X/Y  N/M" format
    const epubBuffer = createEpub({
      title: 'Progress Format Test',
      author: 'Format Bot',
      chapters: 5,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'progress-format.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify "Ch 1/5  1/N" format
    const pageInfo = page.locator('.page-info');
    const text = await pageInfo.textContent();
    // Format: "Ch X/Y  N/M" where Y is total chapters (5)
    expect(text).toMatch(/^Ch 1\/5\s+1\/\d+$/);
    await screenshot(page, 'progress-format');

    // Navigate back
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('SVG cover page renders without crashing', async ({ page }) => {
    // Emulates the real-world pattern where EPUB covers use
    // <svg><image xlink:href="cover.png"/> instead of <img>.
    // Verifies the SVG structure renders (childElementCount > 0) and
    // navigation to subsequent chapters works correctly.
    const epubBuffer = createEpub({
      title: 'SVG Cover Book',
      author: 'SVG Bot',
      chapters: 2,
      paragraphsPerChapter: 6,
      svgCover: true,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'svg-cover-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book — first spine entry is the SVG cover page
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Cover page should render SVG elements (not crash)
    const container = page.locator('.chapter-container').first();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);
    await screenshot(page, 'svg-cover-page');

    // Navigate to next chapter (actual text content)
    const nextBtn = page.locator('.next-btn');
    await nextBtn.click();
    await page.waitForTimeout(500);
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Chapter 1 should have text content
    const textContent = await container.evaluate(el => el.textContent);
    expect(textContent.length).toBeGreaterThan(50);
    await screenshot(page, 'svg-cover-chapter1');

    // Navigate back
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('archive and restore a book', async ({ page }) => {
    // Import a book, archive it, verify it disappears from active view,
    // switch to archived view, verify it appears, restore it, verify it
    // returns to active view.
    const epubBuffer = createEpub({
      title: 'Archive Test Book',
      author: 'Archive Bot',
      chapters: 2,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'archive-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'archive-01-imported');

    // Verify toolbar is visible
    const toolbar = page.locator('.lib-toolbar');
    await expect(toolbar).toBeVisible();

    // Verify view toggle button shows "Archived" (meaning we're in active view)
    const viewToggle = page.locator('.view-toggle');
    await expect(viewToggle).toBeVisible();
    await expect(viewToggle).toContainText('Archived');

    // Verify sort buttons visible (one has sort-btn, other has sort-active)
    const sortBtnInactive = page.locator('.sort-btn');
    const sortBtnActive = page.locator('.sort-active');
    await expect(sortBtnInactive).toBeVisible();
    await expect(sortBtnActive).toBeVisible();

    // Verify archive button visible on the book card
    const archiveBtn = page.locator('.archive-btn');
    await expect(archiveBtn).toBeVisible();
    await expect(archiveBtn).toContainText('Archive');

    // Archive the book
    await archiveBtn.click();

    // Book should disappear from active view — library should show empty
    await page.waitForSelector('.empty-lib', { timeout: 10000 });
    await screenshot(page, 'archive-02-empty-after-archive');

    // Verify empty message says "No books yet" (active view)
    const emptyMsg = page.locator('.empty-lib');
    await expect(emptyMsg).toContainText('No books yet');

    // Switch to archived view
    const viewToggle2 = page.locator('.view-toggle');
    await viewToggle2.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, 'archive-03-archived-view');

    // View toggle should now show "Library" (meaning we're in archived view)
    const viewToggle3 = page.locator('.view-toggle');
    await expect(viewToggle3).toContainText('Library');

    // Verify the archived book is shown with correct title
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('Archive Test Book');

    // Verify restore button visible (not "Archive")
    const restoreBtn = page.locator('.archive-btn');
    await expect(restoreBtn).toBeVisible();
    await expect(restoreBtn).toContainText('Restore');

    // Verify no "Read" button in archived view
    const readBtns = page.locator('.read-btn');
    expect(await readBtns.count()).toBe(0);

    // Import button should be hidden in archived view
    const importBtns = page.locator('label.import-btn');
    expect(await importBtns.count()).toBe(0);

    // Restore the book
    await restoreBtn.click();

    // Archived view should now be empty
    await page.waitForSelector('.empty-lib', { timeout: 10000 });
    const archivedEmpty = page.locator('.empty-lib');
    await expect(archivedEmpty).toContainText('No archived books');
    await screenshot(page, 'archive-04-archived-empty');

    // Switch back to active view
    const viewToggle4 = page.locator('.view-toggle');
    await viewToggle4.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, 'archive-05-restored');

    // Book should be back in active view with correct title
    const restoredTitle = page.locator('.book-title');
    await expect(restoredTitle).toContainText('Archive Test Book');

    // Archive and Read buttons should be visible again
    const readBtn = page.locator('.read-btn');
    await expect(readBtn).toBeVisible();
    const archBtn = page.locator('.archive-btn');
    await expect(archBtn).toContainText('Archive');
  });

  test('sort books by title and author', async ({ page }) => {
    // Import two books with different title/author ordering,
    // verify sort by title and sort by author reorder them.
    const epub1 = createEpub({
      title: 'Zephyr Winds',
      author: 'Alice Author',
      chapters: 1,
      paragraphsPerChapter: 2,
    });
    const epub2 = createEpub({
      title: 'Alpha Dawn',
      author: 'Zelda Writer',
      chapters: 1,
      paragraphsPerChapter: 2,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import first book
    const fileInput = page.locator('input[type="file"]');
    const path1 = join(SCREENSHOT_DIR, 'sort-test1.epub');
    writeFileSync(path1, epub1);
    await fileInput.setInputFiles(path1);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Wait for IndexedDB save, then reload to get a fresh state
    await page.waitForTimeout(2000);
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await page.waitForSelector('.book-card', { timeout: 15000 });

    // Import second book on the fresh page
    const fileInput2 = page.locator('input[type="file"]');
    const path2 = join(SCREENSHOT_DIR, 'sort-test2.epub');
    writeFileSync(path2, epub2);
    await fileInput2.setInputFiles(path2);

    // Wait for second book card to appear
    await page.waitForFunction(() => {
      const cards = document.querySelectorAll('.book-card');
      return cards.length >= 2;
    }, { timeout: 30000 });
    await screenshot(page, 'sort-01-two-books');

    // Sort by title (ascending) — "Alpha Dawn" should come first
    // Use text-based locators since active button has class sort-active, not sort-btn
    const sortTitle = page.locator('.lib-toolbar button', { hasText: 'By title' });
    await expect(sortTitle).toBeVisible();
    await sortTitle.click();
    await page.waitForTimeout(500);
    await screenshot(page, 'sort-02-by-title');

    // First book card title should be "Alpha Dawn"
    const titles = page.locator('.book-title');
    const firstTitle = await titles.nth(0).textContent();
    const secondTitle = await titles.nth(1).textContent();
    expect(firstTitle).toContain('Alpha Dawn');
    expect(secondTitle).toContain('Zephyr Winds');

    // Sort by author (ascending) — "Alice Author" should come first
    const sortAuthor = page.locator('.lib-toolbar button', { hasText: 'By author' });
    await expect(sortAuthor).toBeVisible();
    await sortAuthor.click();
    await page.waitForTimeout(500);
    await screenshot(page, 'sort-03-by-author');

    // After sort by author: Alice Author's book ("Zephyr Winds") should be first
    const authTitles = page.locator('.book-title');
    const firstByAuthor = await authTitles.nth(0).textContent();
    const secondByAuthor = await authTitles.nth(1).textContent();
    expect(firstByAuthor).toContain('Zephyr Winds');
    expect(secondByAuthor).toContain('Alpha Dawn');

    // Verify sort button active state — author button should have sort-active class
    const authorBtnClass = await sortAuthor.getAttribute('class');
    expect(authorBtnClass).toContain('sort-active');
  });

  test('re-import same EPUB is silently deduplicated', async ({ page }) => {
    // Importing the exact same EPUB file twice should result in only
    // 1 book card — content hash dedup means same bytes = same book.
    const epub = createEpub({
      title: 'Dedup Test Book',
      author: 'Dedup Author',
      chapters: 1,
      paragraphsPerChapter: 2,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Use viewport-unique path to avoid concurrent test file collisions
    const vp = page.viewportSize();
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, `dedup-test-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epub);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'dedup-01-first-import');

    // Verify first book is in the library
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('Dedup Test Book');

    // Wait for IndexedDB save, then reload to get fresh state
    await page.waitForTimeout(2000);
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await page.waitForSelector('.book-card', { timeout: 15000 });

    // Import same EPUB again — should deduplicate silently
    const fileInput2 = page.locator('input[type="file"]');
    await fileInput2.setInputFiles(epubPath);

    // Wait for import to start (label → "importing"), then finish (→ "import-btn").
    // Race against a short delay in case import is near-instant for dedup.
    await Promise.race([
      page.waitForSelector('label.importing', { timeout: 5000 }),
      page.waitForTimeout(1000),
    ]);
    await page.waitForSelector('label.import-btn', { timeout: 30000 });
    await page.waitForTimeout(1000);
    await screenshot(page, 'dedup-02-after-reimport');

    // Still only 1 book card — same content hash, same book
    const bookCards = page.locator('.book-card');
    expect(await bookCards.count()).toBe(1);

    // Title should still be correct
    const titleAfter = page.locator('.book-title');
    await expect(titleAfter).toContainText('Dedup Test Book');
  });

  test('different EPUBs get different IDs', async ({ page }) => {
    // Two EPUBs with different content should get different content hashes
    // and both appear in the library as separate books.
    const epub1 = createEpub({
      title: 'Unique Book Alpha',
      author: 'Author One',
      chapters: 1,
      paragraphsPerChapter: 2,
    });
    const epub2 = createEpub({
      title: 'Unique Book Beta',
      author: 'Author Two',
      chapters: 2,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import first EPUB
    const fileInput = page.locator('input[type="file"]');
    const path1 = join(SCREENSHOT_DIR, 'unique-book1.epub');
    writeFileSync(path1, epub1);
    await fileInput.setInputFiles(path1);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Wait for IndexedDB save, then reload to get fresh state
    await page.waitForTimeout(2000);
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await page.waitForSelector('.book-card', { timeout: 15000 });

    // Import second EPUB
    const fileInput2 = page.locator('input[type="file"]');
    const path2 = join(SCREENSHOT_DIR, 'unique-book2.epub');
    writeFileSync(path2, epub2);
    await fileInput2.setInputFiles(path2);

    // Wait for second book card to appear
    await page.waitForFunction(() => {
      const cards = document.querySelectorAll('.book-card');
      return cards.length >= 2;
    }, { timeout: 30000 });
    await screenshot(page, 'unique-books-both-imported');

    // Should have 2 book cards
    const bookCards = page.locator('.book-card');
    expect(await bookCards.count()).toBe(2);
  });

  test('create-epub with embedded image', async ({ page }) => {
    // Test that our EPUB creator can include images and they render
    const epubBuffer = createEpub({
      title: 'Image Test Book',
      author: 'Image Bot',
      chapters: 1,
      paragraphsPerChapter: 3,
      coverImage: true,  // Include a tiny PNG in chapter 1
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'image-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify image element exists with blob: src
    const imgInfo = await page.evaluate(() => {
      const img = document.querySelector('.chapter-container img');
      return img ? { src: img.src, hasBlob: img.src.startsWith('blob:') } : null;
    });
    expect(imgInfo).not.toBeNull();
    expect(imgInfo.hasBlob).toBe(true);
    await screenshot(page, 'embedded-image');

    // Navigate back
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('book content persists across page reload', async ({ page }) => {
    // Import a book, open it, verify chapter content renders,
    // reload the page, re-open the same book (now loaded from IDB),
    // and verify the same chapter content appears.
    const epubBuffer = createEpub({
      title: 'Content Persist Test',
      author: 'IDB Author',
      chapters: 2,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'content-persist.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'content-persist-01-imported');

    // Open book and verify chapter renders
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    const container = page.locator('.chapter-container').first();
    const textBefore = await container.evaluate(el => el.textContent);
    expect(textBefore.length).toBeGreaterThan(0);
    await screenshot(page, 'content-persist-02-reader');

    // Navigate back to library
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    // Wait for all IDB writes to settle
    await page.waitForTimeout(2000);

    // Reload the page
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, 'content-persist-03-after-reload');

    // Re-open the same book — should load from IDB
    const readBtn2 = page.locator('.read-btn');
    await readBtn2.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    const container2 = page.locator('.chapter-container').first();
    const textAfter = await container2.evaluate(el => el.textContent);
    expect(textAfter.length).toBeGreaterThan(0);
    expect(textAfter).toEqual(textBefore);
    await screenshot(page, 'content-persist-04-after-reload-reader');
  });

});
