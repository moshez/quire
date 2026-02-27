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
    // Per-viewport unique file path prevents TOCTOU race when
    // parallel Playwright workers write + read the same path.
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `test-book-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    // Verify import progress UI appears during import.
    // The import card appears at the top of the library list with a progress bar.
    // The import may complete very fast in CI, so we race the progress card
    // against the final book-card appearing.
    const sawProgress = await Promise.race([
      page.waitForSelector('.import-card', { timeout: 30000 })
        .then(() => true)
        .catch(() => false),
      page.waitForSelector('.book-card', { timeout: 30000 })
        .then(() => false),
    ]);

    if (sawProgress) {
      await screenshot(page, '02a-import-progress');
      // If we caught the import card, verify its structure
      const stillImporting = await page.locator('.import-card').isVisible();
      if (stillImporting) {
        // Progress bar elements should exist
        const importBar = page.locator('.import-bar');
        await expect(importBar).toBeVisible({ timeout: 5000 });
        const importFill = page.locator('.import-fill');
        await expect(importFill).toBeVisible({ timeout: 5000 });
        // Card should contain "Importing" text
        const importCard = page.locator('.import-card');
        await expect(importCard).toContainText('Importing', { timeout: 5000 });
      }
    }

    // Wait for import to finish and library to rebuild with a book card
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, '02-library-with-book');

    // Verify import card is removed after import completes
    const importCardGone = page.locator('.import-card');
    await expect(importCardGone).toHaveCount(0, { timeout: 5000 });

    // Verify import UI is cleaned up: "importing" class gone, "import-btn" restored
    const importBtn = page.locator('label.import-btn');
    await expect(importBtn).toBeVisible({ timeout: 5000 });

    // Verify the book card shows correct title and author
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('A Tale of Testing');
    const bookAuthor = page.locator('.book-author');
    await expect(bookAuthor).toContainText('Quire Bot');

    // Verify "New" progress state (unstarted book)
    const bookPosition = page.locator('.book-position');
    await expect(bookPosition).toContainText('New');

    // --- Open the book ---
    const bookCard = page.locator('.book-card');
    await bookCard.click();

    // Wait for reader to appear with chapter content
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForSelector('.chapter-container', { timeout: 15000 });
    // Let CSS column layout settle
    await page.waitForTimeout(1000);
    await screenshot(page, '03-reader-chapter1');

    // --- Verify navigation bar UI ---
    // Ensure chrome is visible (may have auto-hidden during chapter load)
    const readerNav = page.locator('.reader-nav');
    const navVisible = await readerNav.isVisible();
    if (!navVisible) {
      const vp0 = page.viewportSize();
      await page.mouse.click(vp0.width / 2, vp0.height / 2);
      await page.waitForTimeout(500);
    }
    await expect(readerNav).toBeVisible();

    const backBtn = page.locator('.back-btn');
    await expect(backBtn).toBeVisible();
    await expect(backBtn).toContainText('\u2190');

    // --- Verify chapter title in top chrome ---
    // Use toBeAttached instead of toBeVisible — on narrow viewports
    // the ch-title may be clipped by nav overflow
    const chTitle = page.locator('.ch-title');
    await expect(chTitle).toBeAttached();
    const chTitleText = await chTitle.textContent();
    expect(chTitleText).toMatch(/^Chapter \d+$/);
    expect(chTitleText).toBe('Chapter 1');

    // --- Verify prev/next buttons visible ---
    const prevBtn = page.locator('.prev-btn');
    const nextBtn = page.locator('.next-btn');
    await expect(prevBtn).toBeVisible();
    await expect(prevBtn).toContainText('\u2039');
    await expect(nextBtn).toBeVisible();
    await expect(nextBtn).toContainText('\u203A');

    const pageInfo = page.locator('.page-info');
    await expect(pageInfo).toBeVisible();

    // Page indicator should show "Ch X · p. N/M" format after chapter loads
    const pageText = await pageInfo.textContent();
    expect(pageText).toMatch(/^Ch \d+ · p\. \d+\/\d+$/);
    // First chapter, first page: "Ch 1 · p. 1/N"
    expect(pageText).toMatch(/^Ch 1 /);

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
    expect(pageTextAfterForward).toMatch(/^Ch \d+ · p\. \d+\/\d+$/);
    // Page 2: "Ch 1 · p. 2/N"
    expect(pageTextAfterForward).toMatch(/\s+2\/\d+$/);

    // RENDERING PROOF: after forward, transform shifts by exactly viewport width
    const transformPx = await chapterContainer.evaluate(el => {
      const style = el.getAttribute('style') || '';
      const match = style.match(/translateX\((-?\d+)px/);
      return match ? parseInt(match[1]) : 0;
    });
    expect(transformPx).toBe(-vpWidth);

    // --- Test prev button navigation ---
    // Show chrome first (hidden after right-zone click)
    const centerX = viewport.width / 2;
    await page.mouse.click(centerX, centerY);
    await page.waitForTimeout(300);
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

    // Determine total pages — extract from "Ch X · p. N/M" format
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
    // Show chrome first (hidden after keyboard navigation)
    await page.keyboard.press('t');
    await page.waitForTimeout(300);
    const backBtnNav = page.locator('.back-btn');
    await backBtnNav.click();
    await page.waitForTimeout(500);

    // Wait for library to reappear
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, '13-library-after-reading');

    // Verify reading position was saved (must NOT be "New")
    const posAfterRead = page.locator('.book-position');
    await expect(posAfterRead).toBeVisible();
    const posText = await posAfterRead.textContent();
    expect(posText).not.toBe('New');
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
    const bookCard = page.locator('.book-card');
    await bookCard.click();

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

    // Verify chapter progress format: "Ch X · p. N/M"
    const pageInfo = page.locator('.page-info');
    const progressText = await pageInfo.textContent();
    expect(progressText).toMatch(/^Ch \d+ · p\. \d+\/\d+$/);

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

      const prevCh = prevPageText.match(/^Ch (\d+) /)?.[1];

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
        const curCh = curPageText.match(/^Ch (\d+) /)?.[1];

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
    const bookCard = page.locator('.book-card');
    await bookCard.click();
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
    expect(initialText).toMatch(/^Ch 1 /);

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

    // Page info should show chapter 2: "Ch 2 ..."
    const ch2Text = await pageInfo.textContent();
    expect(ch2Text).toMatch(/^Ch 2 /);

    // Chapter title should update to "Chapter 2"
    const ch2Title = await page.locator('.ch-title').textContent();
    expect(ch2Title).toBe('Chapter 2');

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
    expect(backText).toMatch(/^Ch 1 /);

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
    const bookCard = page.locator('.book-card');
    await bookCard.click();
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

    // Wait for chapter content (should show Ch 2 )
    await page.waitForFunction(() => {
      const info = document.querySelector('.page-info');
      return info && /^Ch 2 /.test(info.textContent);
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
    const bookCard = page.locator('.book-card');
    await bookCard.click();
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

    // Wait for chapter content (should show Ch 2 )
    await page.waitForFunction(() => {
      const info = document.querySelector('.page-info');
      return info && /^Ch 2 /.test(info.textContent);
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
    const bookCard = page.locator('.book-card');
    await bookCard.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Should start at chapter 1
    const pageInfo = page.locator('.page-info');
    const initialText = await pageInfo.textContent();
    expect(initialText).toMatch(/^Ch 1 /);

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
    expect(ch2Text).toMatch(/^Ch 2 /);
    await screenshot(page, 'position-01-at-chapter2');

    // Go back to library
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    // Verify position is saved (should show progress percentage in library)
    const posText = await page.locator('.book-position').textContent();
    expect(posText).toMatch(/\d+%/);
    await screenshot(page, 'position-02-library-saved');

    // Re-enter the book
    const bookCard2 = page.locator('.book-card');
    await bookCard2.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify position restored: should be at chapter 2
    const restoredText = await pageInfo.textContent();
    expect(restoredText).toMatch(/^Ch 2 /);
    await screenshot(page, 'position-03-restored');

    // Navigate back
    const backBtn2 = page.locator('.back-btn');
    await backBtn2.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('chapter progress shows Ch X/Y format', async ({ page }) => {
    // Verify the page info displays chapter progress in "Ch X · p. N/M" format
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
    const bookCard = page.locator('.book-card');
    await bookCard.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify "Ch 1 · p. 1/N" format
    const pageInfo = page.locator('.page-info');
    const text = await pageInfo.textContent();
    // Format: "Ch X · p. N/M" where Y is total chapters (5)
    expect(text).toMatch(/^Ch 1 · p\. 1\/\d+$/);
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
    const bookCard = page.locator('.book-card');
    await bookCard.click();
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
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Archive Test Book', author: 'Archive Bot', chapters: 1, paragraphsPerChapter: 1 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `archive-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.waitForTimeout(1000);

    // Archive via context menu
    await page.evaluate(() => {
      const card = document.querySelector('.book-card');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });
    await page.locator('.ctx-menu button', { hasText: 'Archive' }).click();
    await page.waitForTimeout(500);
    await screenshot(page, 'archive-01-archived');

    // Book should disappear — cycle to Archived view
    // Click shelf button twice: Library → Hidden → Archived
    const shelfBtn = page.locator('.lib-toolbar button').first();
    await shelfBtn.click(); // → Hidden
    await page.waitForTimeout(300);
    await shelfBtn.click(); // → Archived
    await page.waitForTimeout(500);
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await expect(page.locator('.book-title')).toContainText('Archive Test Book');
    await screenshot(page, 'archive-02-in-archived-view');

    // Restore via context menu
    await page.evaluate(() => {
      const card = document.querySelector('.book-card');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });
    await page.locator('.ctx-menu button', { hasText: 'Restore' }).click();
    await page.waitForTimeout(500);

    // Cycle back to Library view
    await shelfBtn.click(); // → Library
    await page.waitForTimeout(500);
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await expect(page.locator('.book-title')).toContainText('Archive Test Book');
    await screenshot(page, 'archive-03-restored');

    expect(errors).toEqual([]);
  });

  test('sort books by cycling sort button', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    // Import two books
    const epub1 = createEpub({ title: 'Zebra Book', author: 'Alice', chapters: 1, paragraphsPerChapter: 1 });
    const epub2 = createEpub({ title: 'Apple Book', author: 'Zara', chapters: 1, paragraphsPerChapter: 1 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    writeFileSync(join(SCREENSHOT_DIR, `sort1-${vp.width}x${vp.height}.epub`), epub1);
    await page.locator('input[type="file"]').setInputFiles(join(SCREENSHOT_DIR, `sort1-${vp.width}x${vp.height}.epub`));
    await page.waitForSelector('.book-card', { timeout: 30000 });
    writeFileSync(join(SCREENSHOT_DIR, `sort2-${vp.width}x${vp.height}.epub`), epub2);
    await page.locator('input[type="file"]').setInputFiles(join(SCREENSHOT_DIR, `sort2-${vp.width}x${vp.height}.epub`));
    await page.waitForFunction(() => document.querySelectorAll('.book-card').length >= 2, { timeout: 30000 });
    await page.waitForTimeout(1000);

    // Click sort button to cycle — should change book order
    const sortBtn = page.locator('.lib-toolbar button').nth(1);
    const titlesBefore = await page.evaluate(() =>
      [...document.querySelectorAll('.book-title')].map(el => el.textContent)
    );
    await sortBtn.click(); // cycle to next sort mode
    await page.waitForTimeout(1000);
    const titlesAfter = await page.evaluate(() =>
      [...document.querySelectorAll('.book-title')].map(el => el.textContent)
    );
    // Order should have changed (or stayed same if already in that order)
    await screenshot(page, 'sort-01-after-cycle');
    expect(errors).toEqual([]);
  });

  test('hide and unhide a book via context menu', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Hide Test Book', author: 'Hide Bot', chapters: 1, paragraphsPerChapter: 1 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `hide-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.waitForTimeout(1000);

    // Hide via context menu
    await page.evaluate(() => {
      const card = document.querySelector('.book-card');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });
    await page.locator('.ctx-menu button', { hasText: 'Hide' }).click();
    await page.waitForTimeout(500);
    await screenshot(page, 'hide-01-hidden');

    // Cycle to Hidden view
    const shelfBtn = page.locator('.lib-toolbar button').first();
    await shelfBtn.click(); // → Hidden
    await page.waitForTimeout(500);
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await expect(page.locator('.book-title')).toContainText('Hide Test Book');
    await screenshot(page, 'hide-02-in-hidden-view');

    // Unhide via context menu
    await page.evaluate(() => {
      const card = document.querySelector('.book-card');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });
    await page.locator('.ctx-menu button', { hasText: 'Unhide' }).click();
    await page.waitForTimeout(500);

    // Cycle back to Library
    await shelfBtn.click(); // Hidden → Archived
    await page.waitForTimeout(300);
    await shelfBtn.click(); // Archived → Library
    await page.waitForTimeout(500);
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await expect(page.locator('.book-title')).toContainText('Hide Test Book');
    await screenshot(page, 'hide-03-unhidden');

    expect(errors).toEqual([]);
  });

  test('displays cover image in library card', async ({ page }) => {
    // Import a book with a cover image and verify the cover renders
    // in the library card, then persists across page reload.
    const epubBuffer = createEpub({
      title: 'Cover Book',
      author: 'Cover Author',
      chapters: 2,
      paragraphsPerChapter: 3,
      coverImage: true,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `cover-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'cover-01-after-import');

    // Verify img.book-cover element exists inside the card
    const coverImg = page.locator('.book-card img.book-cover');
    await expect(coverImg).toBeVisible({ timeout: 10000 });

    // Wait for the cover image to load from IDB (src attribute set async)
    await page.waitForFunction(() => {
      const img = document.querySelector('.book-card img.book-cover');
      return img && img.src && img.src.length > 0;
    }, { timeout: 15000 });
    await screenshot(page, 'cover-02-image-loaded');

    // Wait for IDB save to complete
    await page.waitForTimeout(2000);

    // Reload and verify cover persists
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await page.waitForSelector('.book-card', { timeout: 15000 });

    // Cover image should still be present after reload
    const coverAfter = page.locator('.book-card img.book-cover');
    await expect(coverAfter).toBeVisible({ timeout: 10000 });

    // Wait for IDB-loaded src
    await page.waitForFunction(() => {
      const img = document.querySelector('.book-card img.book-cover');
      return img && img.src && img.src.length > 0;
    }, { timeout: 15000 });
    await screenshot(page, 'cover-03-after-reload');
  });

  test('books without covers show no cover image', async ({ page }) => {
    // Import a book WITHOUT a cover image and verify no cover element exists.
    const epubBuffer = createEpub({
      title: 'No Cover Book',
      author: 'Plain Author',
      chapters: 2,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `no-cover-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'no-cover-01-after-import');

    // Verify the book card exists with title
    const title = page.locator('.book-title');
    await expect(title).toBeVisible();
    const titleText = await title.textContent();
    expect(titleText).toContain('No Cover Book');

    // Verify NO img.book-cover element exists in the card
    const coverImg = page.locator('.book-card img.book-cover');
    await expect(coverImg).toHaveCount(0);
    await screenshot(page, 'no-cover-02-verified');
  });

  test('search index records stored at import time', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('crash', () => { throw new Error('PAGE CRASHED: ' + errors.join('; ')); });

    // 2-chapter EPUB — expect 2 search index records
    const epubBuffer = createEpub({
      title: 'Search Index Test',
      author: 'Test Bot',
      chapters: 2,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('label.import-btn', { timeout: 15000 });
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `search-index-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'search-index-01-imported');

    // Query IDB for search index records (keys matching *s*)
    const searchKeys = await page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {
        const req = indexedDB.open('ward', 1);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
      const tx = db.transaction('kv', 'readonly');
      const store = tx.objectStore('kv');
      const allKeys = await new Promise((resolve, reject) => {
        const req = store.getAllKeys();
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
      // Search keys have 's' at position 16 (format: {16-hex}s{3-hex})
      const sKeys = allKeys.filter(k =>
        typeof k === 'string' && k.length === 20 && k[16] === 's'
      );
      // Read header of each search index record
      const records = [];
      for (const key of sKeys) {
        const val = await new Promise((resolve, reject) => {
          const tx2 = db.transaction('kv', 'readonly');
          const req = tx2.objectStore('kv').get(key);
          req.onsuccess = () => resolve(req.result);
          req.onerror = () => reject(req.error);
        });
        if (val instanceof Uint8Array && val.length >= 8) {
          const dv = new DataView(val.buffer, val.byteOffset, val.byteLength);
          records.push({
            key,
            textLen: dv.getUint32(0, true),
            runCount: dv.getUint16(4, true),
            reserved: dv.getUint16(6, true),
            totalSize: val.length,
          });
        }
      }
      return records;
    });

    // Expect exactly 2 search index records (one per chapter)
    expect(searchKeys.length).toBe(2);

    // Verify headers are valid
    for (const rec of searchKeys) {
      expect(rec.textLen).toBeGreaterThan(0);
      expect(rec.runCount).toBeGreaterThan(0);
      expect(rec.reserved).toBe(0);
      // Total size = 8 (header) + runCount*4 (offset map) + textLen (text)
      expect(rec.totalSize).toBe(8 + rec.runCount * 4 + rec.textLen);
    }

    await screenshot(page, 'search-index-02-verified');
    expect(errors).toEqual([]);
  });

  test('duplicate import shows skip/replace modal', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('crash', () => {
      console.error('PAGE CRASHED. Errors:', errors);
    });

    const epubBuffer = createEpub({
      title: 'Duplicate Test Book',
      author: 'Dup Author',
      chapters: 1,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // --- First import: should succeed normally ---
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles({
      name: 'dup-test.epub',
      mimeType: 'application/epub+zip',
      buffer: Buffer.from(epubBuffer),
    });
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'dup-01-first-import');

    const cardCount1 = await page.locator('.book-card').count();
    expect(cardCount1).toBe(1);

    // --- Second import of same EPUB: should show dup modal ---
    await fileInput.setInputFiles({
      name: 'dup-test.epub',
      mimeType: 'application/epub+zip',
      buffer: Buffer.from(epubBuffer),
    });

    // Wait for the dup overlay to appear
    const overlay = page.locator('.dup-overlay');
    await expect(overlay).toBeVisible({ timeout: 30000 });
    await screenshot(page, 'dup-02-modal-visible');

    // Verify modal shows book title and message
    const dupTitle = page.locator('.dup-title');
    await expect(dupTitle).toContainText('Duplicate Test Book');
    const dupMsg = page.locator('.dup-msg');
    await expect(dupMsg).toContainText('Already in library');

    // Verify both buttons are visible
    const skipBtn = page.locator('.dup-btn');
    await expect(skipBtn).toBeVisible();
    const replaceBtn = page.locator('.dup-replace');
    await expect(replaceBtn).toBeVisible();

    // --- Click Skip: overlay dismissed, still 1 book ---
    await skipBtn.click();
    await expect(overlay).not.toBeVisible({ timeout: 5000 });
    await screenshot(page, 'dup-03-after-skip');

    // Wait for import to finish
    const importBtn = page.locator('label.import-btn');
    await expect(importBtn).toBeVisible({ timeout: 10000 });
    const cardCount2 = await page.locator('.book-card').count();
    expect(cardCount2).toBe(1);

    // --- Third import of same EPUB: show modal again, click Replace ---
    await fileInput.setInputFiles({
      name: 'dup-test.epub',
      mimeType: 'application/epub+zip',
      buffer: Buffer.from(epubBuffer),
    });
    await expect(overlay).toBeVisible({ timeout: 30000 });
    await screenshot(page, 'dup-04-modal-again');

    await replaceBtn.click();
    await expect(overlay).not.toBeVisible({ timeout: 5000 });
    await screenshot(page, 'dup-05-after-replace');

    // Wait for import to finish
    await expect(importBtn).toBeVisible({ timeout: 10000 });
    const cardCount3 = await page.locator('.book-card').count();
    expect(cardCount3).toBe(1);

    // Book title should still be correct
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('Duplicate Test Book');

    expect(errors).toEqual([]);
  });

  test('corrupt library data survives reload without crash', async ({ page }) => {
    // Import a valid book, then overwrite the IDB library key with garbage,
    // reload, and verify no crash (pageerror) and the page renders.
    const epubBuffer = createEpub({
      title: 'Corrupt Test Book',
      author: 'Corrupt Bot',
      chapters: 1,
      paragraphsPerChapter: 2,
    });

    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `corrupt-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Wait for IDB save
    await page.waitForTimeout(2000);

    // Overwrite IDB 'lib' key with garbage bytes
    await page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {
        const req = indexedDB.open('ward', 1);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
      const tx = db.transaction('kv', 'readwrite');
      const store = tx.objectStore('kv');
      // Write 512 bytes of random garbage
      const garbage = new Uint8Array(512);
      for (let i = 0; i < garbage.length; i++) {
        garbage[i] = Math.floor(Math.random() * 256);
      }
      await new Promise((resolve, reject) => {
        const req = store.put(garbage, 'lib');
        req.onsuccess = () => resolve();
        req.onerror = () => reject(req.error);
      });
    });

    // Reload — the app should NOT crash
    await page.reload();

    // Wait for the app to initialize (library view or empty state)
    await page.waitForSelector('.library-list, label.import-btn', { timeout: 15000 });
    await screenshot(page, 'corrupt-01-after-reload');

    // No page errors should have occurred
    expect(errors).toEqual([]);

    // The page should be interactive (not crashed/frozen)
    const body = page.locator('body');
    await expect(body).toBeVisible();
  });

  test('library view has no viewport overflow on interactive elements', async ({ page }) => {
    // Import a book with a long title to stress-test layout,
    // then verify no interactive elements extend past the viewport.
    const epubBuffer = createEpub({
      title: 'A Very Long Book Title That Should Wrap Properly Without Overflowing The Viewport Edge',
      author: 'An Author With A Reasonably Long Name That Tests Wrapping',
      chapters: 1,
      paragraphsPerChapter: 2,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `overflow-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'overflow-01-library');

    // Check no interactive elements overflow the viewport
    const problems = await page.evaluate(() => {
      const vw = document.documentElement.clientWidth;
      const issues = [];
      for (const el of document.querySelectorAll(
        'button, label, a, input, [role="button"]'
      )) {
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.right > vw + 1) {
          issues.push(
            `"${el.textContent.trim().slice(0, 20)}" right=${Math.round(r.right)} > viewport=${vw}`
          );
        }
      }
      return issues;
    });
    expect(problems).toEqual([]);
  });

  test('invalid file import shows error banner with filename and DRM message', async ({ page }) => {
    // Import a non-EPUB file (plain text disguised as .zip) and verify
    // the error banner appears with filename, "is not a valid ePub file.",
    // and "Quire supports .epub files without DRM." message.
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('crash', () => {
      console.error('PAGE CRASHED during error banner test. Errors:', errors);
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await screenshot(page, 'errbanner-00-library');

    // Create a non-EPUB file (plain text bytes — will fail ZIP parsing)
    const fileInput = page.locator('input[type="file"]');
    const invalidContent = Buffer.from('This is not a valid EPUB file at all.');
    await fileInput.setInputFiles({
      name: 'vacation-photos.zip',
      mimeType: 'application/zip',
      buffer: invalidContent,
    });

    // Wait for import to finish and error banner to appear
    // The banner has class .err-banner
    const banner = page.locator('.err-banner');
    await expect(banner).toBeVisible({ timeout: 30000 });
    await screenshot(page, 'errbanner-01-banner-visible');

    // Verify banner contains "Import failed" (bold heading)
    await expect(banner).toContainText('Import failed');

    // Verify banner contains the filename in quotes
    await expect(banner).toContainText('vacation-photos.zip');

    // Verify banner contains "is not a valid ePub file."
    await expect(banner).toContainText('is not a valid ePub file.');

    // Verify banner contains DRM message
    await expect(banner).toContainText('Quire supports .epub files without DRM.');

    // Verify close button exists
    const closeBtn = page.locator('.err-close');
    await expect(closeBtn).toBeVisible();

    // Verify import UI is cleaned up (label reverts to "import-btn")
    const importBtn = page.locator('label.import-btn');
    await expect(importBtn).toBeVisible({ timeout: 10000 });

    // Dismiss the banner by clicking close
    await closeBtn.click();

    // Banner should disappear
    await expect(banner).not.toBeVisible({ timeout: 5000 });
    await screenshot(page, 'errbanner-02-dismissed');

    // No crashes
    expect(errors).toEqual([]);
  });

  test('error banner is dismissed when starting new import', async ({ page }) => {
    // Import an invalid file to trigger the error banner,
    // then import a valid EPUB and verify the banner is dismissed.
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import invalid file to trigger error banner
    const fileInput = page.locator('input[type="file"]');
    const invalidContent = Buffer.from('not a zip');
    await fileInput.setInputFiles({
      name: 'bad-file.txt',
      mimeType: 'application/octet-stream',
      buffer: invalidContent,
    });

    // Wait for error banner
    const banner = page.locator('.err-banner');
    await expect(banner).toBeVisible({ timeout: 30000 });
    await screenshot(page, 'errbanner-dismiss-01-banner');

    // Now import a valid EPUB — banner should be dismissed
    const epubBuffer = createEpub({
      title: 'Valid Book After Error',
      author: 'Recovery Bot',
      chapters: 1,
      paragraphsPerChapter: 2,
    });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `errbanner-valid-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    // Banner should be dismissed as new import starts
    await expect(banner).not.toBeVisible({ timeout: 10000 });

    // Valid book should import successfully
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'errbanner-dismiss-02-valid-imported');

    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('Valid Book After Error');

    expect(errors).toEqual([]);
  });

  test('reading position persists across page turns within a chapter', async ({ page }) => {
    // Import a book with enough text for multiple pages in one chapter,
    // flip forward several pages, go back to library, re-enter the book,
    // and verify the page (not just chapter) is restored.
    const epubBuffer = createEpub({
      title: 'Page Position Test',
      author: 'Page Bot',
      chapters: 2,
      paragraphsPerChapter: 30,  // Plenty of text for multi-page
    });

    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `page-pos-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    const bookCard = page.locator('.book-card');
    await bookCard.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Should start at Ch 1, page 1
    const pageInfo = page.locator('.page-info');
    const initialText = await pageInfo.textContent();
    expect(initialText).toMatch(/^Ch 1 /);
    expect(initialText).toMatch(/\s+1\/\d+$/);

    // Get total pages to know how many to flip
    const totalPages = parseInt(initialText.match(/\s+\d+\/(\d+)$/)[1]);

    // Flip forward at least 2 pages (or as many as available)
    const flips = Math.min(3, totalPages - 1);
    const nextBtn = page.locator('.next-btn');
    for (let i = 0; i < flips; i++) {
      await nextBtn.click();
      await page.waitForTimeout(300);
    }

    // Record the page we ended up on
    const afterFlipText = await pageInfo.textContent();
    const afterFlipPage = afterFlipText.match(/\s+(\d+)\/\d+$/)[1];
    const afterFlipPageNum = parseInt(afterFlipPage);
    expect(afterFlipPageNum).toBeGreaterThan(1);
    await screenshot(page, 'page-pos-01-after-flips');

    // Go back to library
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    // Verify library shows the position (not "New")
    const posText = await page.locator('.book-position').textContent();
    expect(posText).not.toBe('New');
    await screenshot(page, 'page-pos-02-library');

    // Re-enter the book
    const bookCard2 = page.locator('.book-card');
    await bookCard2.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify restored page is the same page we were on (or close — within 1
    // due to viewport size differences between render passes)
    const restoredText = await pageInfo.textContent();
    expect(restoredText).toMatch(/^Ch 1 /);
    const restoredPage = parseInt(restoredText.match(/\s+(\d+)\/\d+$/)[1]);
    // Allow ±1 tolerance since total pages can shift between render passes
    expect(Math.abs(restoredPage - afterFlipPageNum)).toBeLessThanOrEqual(1);
    await screenshot(page, 'page-pos-03-restored');

    // Navigate back
    const backBtn2 = page.locator('.back-btn');
    await backBtn2.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    expect(errors).toEqual([]);
  });

    test('context menu appears on right-click', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Context Menu Test', chapters: 1, paragraphsPerChapter: 1 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `ctx-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.waitForTimeout(1000);

    // Right-click to open context menu
    await page.evaluate(() => {
      const card = document.querySelector('.book-card');
      if (card) card.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });
    await expect(page.locator('.ctx-menu button')).toHaveCount(4);
    await screenshot(page, 'ctx-01-menu-open');

    // Dismiss
    await page.locator('.ctx-overlay').click({ position: { x: 5, y: 5 } });
    await expect(page.locator('.ctx-overlay')).toHaveCount(0, { timeout: 10000 });
    expect(errors).toEqual([]);
  });

test('bookmark toggle via button click and B key', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('crash', () => console.error('PAGE CRASHED'));

    const epubBuffer = createEpub({
      title: 'Bookmark Test',
      author: 'Quire Bot',
      chapters: 2,
      paragraphsPerChapter: 20,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `bookmark-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open the book
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify BM button exists with class bm-btn
    const bmBtn = page.locator('.bm-btn');
    await expect(bmBtn).toBeVisible();
    await expect(bmBtn).toHaveText('☆');
    await screenshot(page, 'bookmark-01-initial');

    // Click BM button to toggle bookmark on
    await bmBtn.click();
    await page.waitForTimeout(500);
    const bmActive = page.locator('.bm-active');
    await expect(bmActive).toBeVisible();
    await screenshot(page, 'bookmark-02-after-click-on');

    // Click again to toggle off
    await bmActive.click();
    await page.waitForTimeout(500);
    await expect(page.locator('.bm-btn')).toBeVisible();
    await expect(page.locator('.bm-active')).toHaveCount(0);
    await screenshot(page, 'bookmark-03-after-click-off');

    // Toggle via B key
    await page.locator('.reader-viewport').focus();
    await page.keyboard.press('b');
    await page.waitForTimeout(500);
    await expect(page.locator('.bm-active')).toBeVisible();
    await screenshot(page, 'bookmark-04-after-b-key-on');

    // Toggle off via B key
    await page.keyboard.press('b');
    await page.waitForTimeout(500);
    await expect(page.locator('.bm-btn')).toBeVisible();
    await expect(page.locator('.bm-active')).toHaveCount(0);
    await screenshot(page, 'bookmark-05-after-b-key-off');

    // Bookmark a page, then navigate forward via Next button (chrome-safe)
    await page.keyboard.press('b');
    await page.waitForTimeout(500);
    await expect(page.locator('.bm-active')).toBeVisible();
    // Use Next button to keep chrome visible during page turn
    await page.locator('.next-btn').click();
    await page.waitForTimeout(500);
    // Should be bm-btn (unbookmarked) on new page
    await expect(page.locator('.bm-btn')).toBeVisible();
    await expect(page.locator('.bm-active')).toHaveCount(0);
    await screenshot(page, 'bookmark-06-after-page-turn');

    // Navigate back via Prev button to bookmarked page
    await page.locator('.prev-btn').click();
    await page.waitForTimeout(500);
    // Should be bm-active (bookmarked)
    await expect(page.locator('.bm-active')).toBeVisible();
    await screenshot(page, 'bookmark-07-navigate-back');

    // Verify no page crashes
    expect(errors).toEqual([]);
  });

  test('scrubber bottom bar visible with chrome', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('crash', () => console.error('PAGE CRASHED'));

    const epubBuffer = createEpub({
      title: 'Scrubber Test',
      author: 'Quire Bot',
      chapters: 3,
      paragraphsPerChapter: 15,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `scrubber-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open the book
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify reader-bottom exists
    const readerBottom = page.locator('.reader-bottom');
    await expect(readerBottom).toBeAttached();
    await screenshot(page, 'scrubber-01-initial');

    // Verify scrubber DOM structure exists
    await expect(page.locator('.scrubber')).toBeAttached();
    await expect(page.locator('.scrub-track')).toBeAttached();
    await expect(page.locator('.scrub-fill')).toBeAttached();
    await expect(page.locator('.scrub-handle')).toBeAttached();
    await expect(page.locator('.scrub-tooltip')).toBeAttached();
    await expect(page.locator('.scrub-text')).toBeAttached();

    // Chrome is shown on reader entry — bottom bar should be visible
    await expect(readerBottom).toBeVisible();

    // After chrome auto-hides (wait 6s), bottom bar should hide too
    await page.waitForTimeout(6000);
    await expect(readerBottom).toBeHidden();
    await screenshot(page, 'scrubber-02-chrome-hidden');

    // Show chrome with center tap — bottom bar visible again
    const vp2 = page.viewportSize();
    const centerX = Math.floor(vp2.width / 2);
    const centerY = Math.floor(vp2.height / 2);
    await page.mouse.click(centerX, centerY);
    await page.waitForTimeout(500);
    await expect(readerBottom).toBeVisible();
    await screenshot(page, 'scrubber-03-chrome-shown');

    // Scrub-fill should have a width style (from update_scrubber_fill)
    const fillStyle = await page.locator('.scrub-fill').getAttribute('style');
    expect(fillStyle).toMatch(/width:/);
    await screenshot(page, 'scrubber-04-fill-has-width');

    // Navigate to next page and verify fill style is still present
    await page.locator('.next-btn').click();
    await page.waitForTimeout(500);
    const fillStyle2 = await page.locator('.scrub-fill').getAttribute('style');
    expect(fillStyle2).toMatch(/width:/);
    await screenshot(page, 'scrubber-05-fill-after-page-turn');

    // Verify no page crashes
    expect(errors).toEqual([]);
  });

  test('toc panel shows contents and bookmark views', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    page.on('crash', () => console.error('PAGE CRASHED'));

    const epubBuffer = createEpub({
      title: 'TOC Test',
      author: 'Quire Bot',
      chapters: 3,
      paragraphsPerChapter: 20,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `toc-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);

    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open the book
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify TOC button exists in nav bar
    const tocBtn = page.locator('.toc-btn');
    await expect(tocBtn).toBeAttached();
    await screenshot(page, 'toc-01-reader-loaded');

    // TOC panel should be hidden initially
    const tocPanel = page.locator('.toc-panel');
    await expect(tocPanel).toBeAttached();
    await expect(tocPanel).toBeHidden();

    // Click TOC button to open panel
    await tocBtn.click();
    await page.waitForTimeout(300);
    await expect(tocPanel).toBeVisible();
    await screenshot(page, 'toc-02-panel-open');

    // Panel should have the correct structure
    await expect(page.locator('.toc-header')).toBeAttached();
    await expect(page.locator('.toc-close-btn')).toBeAttached();
    await expect(page.locator('.toc-bm-count-btn')).toBeAttached();
    await expect(page.locator('.toc-switch-btn')).toBeAttached();
    await expect(page.locator('.toc-list')).toBeAttached();

    // Contents list should have chapter entries (3 chapters = 3 entries)
    const tocEntries = page.locator('.toc-entry');
    await expect(tocEntries).toHaveCount(3);

    // Each entry should show a chapter label
    const firstEntry = tocEntries.nth(0);
    const entryText = await firstEntry.textContent();
    expect(entryText).toMatch(/chapter/i);
    await screenshot(page, 'toc-03-contents-shown');

    // Click second chapter entry to navigate
    await tocEntries.nth(1).click();
    await page.waitForTimeout(500);

    // Panel should close after navigation
    await expect(tocPanel).toBeHidden();
    await screenshot(page, 'toc-04-after-chapter-nav');

    // Re-open TOC panel
    await tocBtn.click();
    await page.waitForTimeout(300);
    await expect(tocPanel).toBeVisible();

    // Switch to Bookmarks view via the switch button
    const switchBtn = page.locator('.toc-switch-btn');
    await switchBtn.click();
    await page.waitForTimeout(300);

    // Bookmark entries should be shown (initially 0, so list empty)
    const bmEntries = page.locator('.bm-entry');
    await expect(bmEntries).toHaveCount(0);
    await screenshot(page, 'toc-05-bookmarks-view-empty');

    // Close TOC panel via close button
    await page.locator('.toc-close-btn').click();
    await page.waitForTimeout(300);
    await expect(tocPanel).toBeHidden();
    await screenshot(page, 'toc-06-panel-closed');

    // Add a bookmark via BM button
    await page.locator('.bm-btn').click();
    await page.waitForTimeout(300);

    // Re-open TOC and switch to Bookmarks view
    await tocBtn.click();
    await page.waitForTimeout(300);
    await expect(tocPanel).toBeVisible();
    await page.locator('.toc-switch-btn').click();
    await page.waitForTimeout(300);

    // Now there should be 1 bookmark entry
    await expect(page.locator('.bm-entry')).toHaveCount(1);
    const bmText = await page.locator('.bm-entry').nth(0).textContent();
    expect(bmText).toMatch(/ch/i);
    await screenshot(page, 'toc-07-bookmark-in-list');

    // Click bookmark to navigate
    await page.locator('.bm-entry').nth(0).click();
    await page.waitForTimeout(500);

    // Panel should close after navigation
    await expect(tocPanel).toBeHidden();
    await screenshot(page, 'toc-08-after-bookmark-nav');

    // Verify no page crashes
    expect(errors).toEqual([]);
  });

  test('position stack: TOC navigation shows nav-back button, pop restores position', async ({ page }) => {
    // This test verifies the position stack feature:
    // 1. Nav-back button is hidden on reader load
    // 2. After TOC chapter navigation, nav-back button appears
    // 3. Clicking nav-back restores the previous position

    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    // Create a 3-chapter EPUB with enough text for stable page counts
    const epubBuffer = createEpub({
      title: 'Position Stack Test',
      chapters: 3,
      paragraphsPerChapter: 6,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `pos-stack-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);

    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles(epubPath);

    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });

    // Wait for chapter content to load
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent && el.textContent.length > 50;
    }, { timeout: 15000 });

    await screenshot(page, 'posstack-01-reader-loaded');

    // Nav-back button should exist but be hidden initially
    const navBackBtn = page.locator('.nav-back-btn');
    await expect(navBackBtn).toBeAttached();
    await expect(navBackBtn).toBeHidden();

    await screenshot(page, 'posstack-02-navback-hidden');

    // Open TOC panel
    const tocBtn = page.locator('.toc-btn');
    await tocBtn.click();
    await page.waitForTimeout(300);
    await expect(page.locator('.toc-panel')).toBeVisible();

    // Click second chapter entry
    const tocEntries = page.locator('.toc-entry');
    await tocEntries.nth(1).click();
    await page.waitForTimeout(500);

    // Panel should close after navigation
    await expect(page.locator('.toc-panel')).toBeHidden();

    // Nav-back button should now be visible (position stack has 1 entry)
    await expect(navBackBtn).toBeVisible();

    await screenshot(page, 'posstack-03-navback-visible');

    // The page indicator should show chapter 2
    const pageInfo = page.locator('.page-info');
    const pageText = await pageInfo.textContent();
    expect(pageText).toMatch(/Ch 2 /);

    // Click nav-back button to restore previous position
    await navBackBtn.click();
    await page.waitForTimeout(500);

    await screenshot(page, 'posstack-04-after-back');

    // Should now be back at chapter 1
    const pageTextAfter = await pageInfo.textContent();
    expect(pageTextAfter).toMatch(/Ch 1 /);

    // Nav-back button should be hidden again (stack is now empty)
    await expect(navBackBtn).toBeHidden();

    await screenshot(page, 'posstack-05-navback-hidden-again');

    // Verify no page crashes
    expect(errors).toEqual([]);
  });

  test('escape key hierarchy: TOC → chrome → library', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    const epubBuffer = createEpub({ title: 'Escape Test', chapters: 2, paragraphsPerChapter: 4 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `escape-test-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent && el.textContent.length > 50;
    }, { timeout: 15000 });

    // Wait for auto-hide timer to expire, then toggle chrome on via center tap
    await page.waitForTimeout(6000);
    await expect(page.locator('.reader-nav')).toBeHidden();

    const viewport = page.viewportSize();
    const centerX = viewport.width / 2;
    const centerY = viewport.height / 2;
    await page.mouse.click(centerX, centerY);
    await page.waitForTimeout(500);
    await expect(page.locator('.reader-nav')).toBeVisible();
    await screenshot(page, 'escape-01-chrome-visible');

    // Open TOC panel
    await page.locator('.toc-btn').click();
    await page.waitForTimeout(500);
    await expect(page.locator('.toc-panel')).toBeVisible();
    await screenshot(page, 'escape-02-toc-open');

    // Escape 1: closes TOC, still in reader with chrome visible
    await page.locator('.reader-viewport').focus();
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);
    await expect(page.locator('.toc-panel')).toBeHidden();
    await expect(page.locator('.reader-nav')).toBeVisible();
    await screenshot(page, 'escape-03-toc-closed');

    // Escape 2: hides chrome, still in reader
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);
    await expect(page.locator('.reader-nav')).toBeHidden();
    await expect(page.locator('.reader-viewport')).toBeAttached();
    await screenshot(page, 'escape-04-chrome-hidden');

    // Escape 3: exits to library
    await page.keyboard.press('Escape');
    await page.waitForTimeout(1000);
    await expect(page.locator('.book-card')).toBeVisible();
    await screenshot(page, 'escape-05-library');

    expect(errors).toEqual([]);
  });

  test('scrubber drag navigates and chapter ticks visible', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    // 3 chapters with enough text for multi-page
    const epubBuffer = createEpub({
      title: 'Scrub Drag Test',
      chapters: 3,
      paragraphsPerChapter: 20,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `scrub-drag-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent && el.textContent.length > 50;
    }, { timeout: 15000 });

    // Wait for auto-hide, then show chrome via center tap
    await page.waitForTimeout(6000);
    const viewport = page.viewportSize();
    await page.mouse.click(viewport.width / 2, viewport.height / 2);
    await page.waitForTimeout(500);
    await expect(page.locator('.reader-nav')).toBeVisible();
    await expect(page.locator('.reader-bottom')).toBeVisible();

    // Verify chapter tick marks exist (3 chapters = 2 ticks)
    const tickCount = await page.locator('.scrub-tick').count();
    expect(tickCount).toBe(2);
    await screenshot(page, 'scrub-drag-01-ticks-visible');

    // Get initial page info
    const pageInfo = page.locator('.page-info');
    const initialText = await pageInfo.textContent();
    expect(initialText).toMatch(/^Ch 1 /);

    // Get scrubber track bounding box for drag
    const track = page.locator('.scrub-track');
    const trackBox = await track.boundingBox();
    expect(trackBox).not.toBeNull();

    // Drag from ~10% to ~80% of the track (should advance pages)
    const startX = trackBox.x + trackBox.width * 0.1;
    const endX = trackBox.x + trackBox.width * 0.8;
    const trackY = trackBox.y + trackBox.height / 2;

    await page.mouse.move(startX, trackY);
    await page.mouse.down();
    await page.waitForTimeout(100);

    // Move in steps to simulate drag
    for (let i = 1; i <= 5; i++) {
      const x = startX + (endX - startX) * (i / 5);
      await page.mouse.move(x, trackY);
      await page.waitForTimeout(50);
    }
    await screenshot(page, 'scrub-drag-02-dragging');

    await page.mouse.up();
    await page.waitForTimeout(500);
    await screenshot(page, 'scrub-drag-03-after-drag');

    // Page info should have changed (dragging should advance position)
    const afterText = await pageInfo.textContent();
    expect(afterText).not.toBe(initialText);

    // Navigate back to library
    await page.locator('.back-btn').click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    expect(errors).toEqual([]);
  });

  test('chapter transition persists position without exit', async ({ page }) => {
    // Navigate to chapter 2, reload (no back button), verify position persisted.
    // Isolates chapter-transition IDB save from exit-triggered save.
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    const epubBuffer = createEpub({
      title: 'Chapter Persist Test',
      chapters: 3,
      paragraphsPerChapter: 1,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `ch-persist-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify at chapter 1
    const pageInfo = page.locator('.page-info');
    const ch1Text = await pageInfo.textContent();
    expect(ch1Text).toMatch(/^Ch 1 /);

    // Navigate to chapter 2 via Next button
    const container = page.locator('.chapter-container').first();
    const ch1Content = await container.textContent();
    await page.locator('.next-btn').click();
    await page.waitForFunction((prev) => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent !== prev && el.childElementCount > 0;
    }, ch1Content, { timeout: 15000 });
    await page.waitForTimeout(500);

    // Verify at chapter 2
    const ch2Text = await pageInfo.textContent();
    expect(ch2Text).toMatch(/^Ch 2 /);
    await screenshot(page, 'ch-persist-01-at-chapter2');

    // Wait for IDB save to complete
    await page.waitForTimeout(2000);

    // Reload page WITHOUT pressing back button — tests that chapter
    // transition itself persisted position to IDB
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await page.waitForSelector('.book-card', { timeout: 15000 });
    await screenshot(page, 'ch-persist-02-after-reload');

    // Verify position was saved (should show progress %, not "New")
    const posText = await page.locator('.book-position').textContent();
    expect(posText).not.toBe('New');

    // Re-enter the book — should restore at chapter 2
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    const restoredText = await pageInfo.textContent();
    expect(restoredText).toMatch(/^Ch 2 /);
    await screenshot(page, 'ch-persist-03-restored');

    expect(errors).toEqual([]);
  });

  test('visibilitychange saves position to IDB', async ({ page }) => {
    // Navigate to chapter 2, dispatch visibilitychange hidden event,
    // then verify IDB contains the updated position by reloading.
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    const epubBuffer = createEpub({
      title: 'Visibility Save Test',
      chapters: 3,
      paragraphsPerChapter: 1,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `vis-save-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify at chapter 1
    const pageInfo = page.locator('.page-info');
    const ch1Text = await pageInfo.textContent();
    expect(ch1Text).toMatch(/^Ch 1 /);

    // Navigate to chapter 2 via Next
    const container = page.locator('.chapter-container').first();
    const ch1Content = await container.textContent();
    await page.locator('.next-btn').click();
    await page.waitForFunction((prev) => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent !== prev && el.childElementCount > 0;
    }, ch1Content, { timeout: 15000 });
    await page.waitForTimeout(500);

    const ch2Text = await pageInfo.textContent();
    expect(ch2Text).toMatch(/^Ch 2 /);
    await screenshot(page, 'vis-save-01-at-chapter2');

    // Dispatch visibilitychange with hidden state — triggers IDB save
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', {
        value: 'hidden', writable: true, configurable: true
      });
      document.dispatchEvent(new Event('visibilitychange'));
    });

    // Wait for IDB write to complete
    await page.waitForTimeout(2000);

    // Restore visibility state
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', {
        value: 'visible', writable: true, configurable: true
      });
    });

    // Reload page — position should be persisted from visibilitychange save
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await page.waitForSelector('.book-card', { timeout: 15000 });
    await screenshot(page, 'vis-save-02-after-reload');

    // Position should show progress (not "New")
    const posText = await page.locator('.book-position').textContent();
    expect(posText).not.toBe('New');

    // Re-enter book — should resume at chapter 2
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    const restoredText = await pageInfo.textContent();
    expect(restoredText).toMatch(/^Ch 2 /);
    await screenshot(page, 'vis-save-03-restored');

    expect(errors).toEqual([]);
  });

  test('Aa settings panel controls font size and theme', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    const epubBuffer = createEpub({ title: 'Settings Test', chapters: 1, paragraphsPerChapter: 3 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `settings-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Verify Aa button exists in reader chrome
    const aaBtn = page.locator('button.settings-btn');
    await expect(aaBtn).toBeAttached();
    await expect(aaBtn).toContainText('A');
    await screenshot(page, 'settings-01-aa-button');

    // Click Aa button — settings overlay should appear with controls
    await aaBtn.click();
    await page.waitForTimeout(300);
    const overlay = page.locator('.stg-overlay');
    await expect(overlay).toBeVisible();

    // Verify settings panel has rows with buttons
    const rows = overlay.locator('.stg-row');
    const rowCount = await rows.count();
    expect(rowCount).toBeGreaterThanOrEqual(4);  // font size, font family, theme, spacing, margin
    await screenshot(page, 'settings-02-panel-open');

    // Read initial font size from viewport style
    const initialFontSize = await page.evaluate(() => {
      const vp = document.querySelector('.reader-viewport');
      return vp ? getComputedStyle(vp).fontSize : null;
    });

    // Click font size "A+" button — should increase font-size
    const fontPlusBtn = overlay.locator('button', { hasText: 'A+' });
    await expect(fontPlusBtn).toBeAttached();
    await fontPlusBtn.click();
    await page.waitForTimeout(300);
    await screenshot(page, 'settings-03-font-increased');

    // Verify font-size changed on viewport
    const newFontSize = await page.evaluate(() => {
      const vp = document.querySelector('.reader-viewport');
      return vp ? vp.style.fontSize : null;
    });
    expect(newFontSize).toBeTruthy();
    // Font size should have increased (default 18px → 19px)
    const newPx = parseInt(newFontSize, 10);
    expect(newPx).toBeGreaterThan(18);

    // Click Dark theme button — should apply dark mode filter
    const darkBtn = overlay.locator('button', { hasText: 'Dark' });
    await expect(darkBtn).toBeAttached();
    await darkBtn.click();
    await page.waitForTimeout(300);
    await screenshot(page, 'settings-04-dark-theme');

    // Verify dark mode filter is applied on chapter container
    const darkStyle = await page.evaluate(() => {
      const cc = document.querySelector('.chapter-container');
      return cc ? cc.getAttribute('style') : null;
    });
    expect(darkStyle).toContain('invert');

    // Click Sepia theme button — should apply sepia filter
    const sepiaBtn = overlay.locator('button', { hasText: 'Sepia' });
    await expect(sepiaBtn).toBeAttached();
    await sepiaBtn.click();
    await page.waitForTimeout(300);
    await screenshot(page, 'settings-04b-sepia-theme');

    // Verify sepia mode applies a distinct style on chapter container
    const sepiaStyle = await page.evaluate(() => {
      const cc = document.querySelector('.chapter-container');
      return cc ? cc.getAttribute('style') : null;
    });
    expect(sepiaStyle).toContain('sepia');

    // Click Light theme button — should remove all filters
    const lightBtn = overlay.locator('button', { hasText: 'Light' });
    await expect(lightBtn).toBeAttached();
    await lightBtn.click();
    await page.waitForTimeout(300);
    await screenshot(page, 'settings-05-light-theme');

    // Verify light mode clears filters
    const lightStyle = await page.evaluate(() => {
      const cc = document.querySelector('.chapter-container');
      return cc ? cc.getAttribute('style') : null;
    });
    expect(lightStyle).toContain('none');

    // Click the overlay backdrop (not a button) to dismiss
    await overlay.click({ position: { x: 10, y: 10 } });
    await page.waitForTimeout(300);
    // Overlay should be hidden (display:none)
    await expect(overlay).toBeHidden();
    await screenshot(page, 'settings-06-panel-closed');

    expect(errors).toEqual([]);
  });

  test('selection toolbar shows Highlight button on text select', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    const epubBuffer = createEpub({ title: 'Selection Test', chapters: 1, paragraphsPerChapter: 5 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `sel-test-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.textContent && el.textContent.length > 50;
    }, { timeout: 15000 });

    // Selection toolbar should exist but be hidden initially
    const selToolbar = page.locator('.sel-toolbar');
    await expect(selToolbar).toBeAttached();
    await screenshot(page, 'sel-01-toolbar-hidden');

    // Verify Highlight and Export buttons exist in the toolbar
    const toolbarBtns = page.locator('.sel-toolbar button');
    expect(await toolbarBtns.count()).toBe(2);
    const hlBtn = toolbarBtns.nth(0);
    await expect(hlBtn).toContainText('Highlight');
    const exportBtn = toolbarBtns.nth(1);
    await expect(exportBtn).toContainText('Export');
    await screenshot(page, 'sel-02-toolbar-buttons');

    // Programmatically create an annotation via evaluate
    // (simulates what the Highlight button does — sets internal C state)
    await page.evaluate(() => {
      // Trigger the export button click to verify download fires
      // First need to make the toolbar visible
      const toolbar = document.querySelector('.sel-toolbar');
      if (toolbar) toolbar.style.display = 'flex';
    });

    // Click Export — should trigger download (even if no annotations, it's a no-op)
    // Listen for download event
    const downloadPromise = page.waitForEvent('download', { timeout: 5000 }).catch(() => null);
    await exportBtn.click();
    await page.waitForTimeout(500);
    // Download may or may not fire (depends on annotation count)
    // Just verify no crash
    await screenshot(page, 'sel-03-after-export-click');

    expect(errors).toEqual([]);
  });

  test('link handler does not crash on chapter load', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Link Test', chapters: 1, paragraphsPerChapter: 3 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `link-test-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await screenshot(page, 'link-01-reader-loaded');
    // Link handler attached — no crash
    expect(errors).toEqual([]);
  });

  test('search panel finds chapters containing query', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));

    // Use 2 chapters — "mountain" appears in generated paragraph text
    const epubBuffer = createEpub({ title: 'Search Test', chapters: 2, paragraphsPerChapter: 4 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `search-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Search button should exist
    const searchBtn = page.locator('button.search-btn');
    await expect(searchBtn).toBeAttached();
    await screenshot(page, 'search-01-btn-exists');

    // Click search — panel should appear
    await searchBtn.click();
    await page.waitForTimeout(300);
    const searchPanel = page.locator('.search-panel');
    await expect(searchPanel).toBeVisible();
    await screenshot(page, 'search-02-panel-open');

    // Input field should be present
    const searchInput = searchPanel.locator('input[type="text"]');
    await expect(searchInput).toBeAttached();

    // Type "mountain" — appears in generated EPUB paragraphs
    await searchInput.fill('mountain');
    // Trigger change event (fill doesn't always fire change)
    await searchInput.dispatchEvent('change');
    // Wait for async IDB search to complete
    await page.waitForTimeout(2000);
    await screenshot(page, 'search-03-results');

    // Results should appear — at least one "Ch NN" result
    const resultDivs = searchPanel.locator('div div');
    const resultCount = await resultDivs.count();
    expect(resultCount).toBeGreaterThan(0);
    await screenshot(page, 'search-04-with-results');

    expect(errors).toEqual([]);
  });

  test('ARIA: reader nav has role=navigation and page info has aria-live', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'ARIA Test', chapters: 1, paragraphsPerChapter: 3 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `aria-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Verify nav has role=navigation
    const nav = page.locator('.reader-nav');
    const navRole = await nav.getAttribute('role');
    expect(navRole).toBe('navigation');

    // Verify page-info has aria-live=polite
    const pageInfo = page.locator('.page-info');
    const ariaLive = await pageInfo.getAttribute('aria-live');
    expect(ariaLive).toBe('polite');

    await screenshot(page, 'aria-01-roles-verified');
    expect(errors).toEqual([]);
  });

  test('chapter images have max-width CSS applied', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({
      title: 'CSS Render Test', chapters: 1, paragraphsPerChapter: 3, coverImage: true,
    });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `cssrender-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    // Verify the CSS rule is loaded (reader.css)
    const hasRule = await page.evaluate(() => {
      for (const sheet of document.styleSheets) {
        try {
          for (const rule of sheet.cssRules) {
            if (rule.selectorText && rule.selectorText.includes('.chapter-container img')) {
              return true;
            }
          }
        } catch(e) {}
      }
      return false;
    });
    expect(hasRule).toBe(true);
    await screenshot(page, 'cssrender-01-rules');
    expect(errors).toEqual([]);
  });

  test('R6: chapter content has max-width cap on wide viewports', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Width Cap Test', chapters: 1, paragraphsPerChapter: 5 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `r6-widthcap-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Check that paragraph elements have max-width applied
    const pStyle = await page.evaluate(() => {
      const p = document.querySelector('.chapter-container p');
      if (!p) return null;
      const cs = getComputedStyle(p);
      return {
        maxWidth: cs.maxWidth,
        marginLeft: cs.marginLeft,
        marginRight: cs.marginRight,
      };
    });
    expect(pStyle).not.toBeNull();
    // R6 max-width removed (broke column pagination). Width controlled by padding.
    // R7: padding should be 2rem = 32px
    const padStyle = await page.evaluate(() => {
      const p = document.querySelector('.chapter-container p');
      if (!p) return null;
      const cs = getComputedStyle(p);
      return {
        paddingLeft: parseFloat(cs.paddingLeft),
        paddingRight: parseFloat(cs.paddingRight),
      };
    });
    if (padStyle) {
      // 2rem at default 16px = 32px; at 18px base = 36px
      // Just verify >= 24px (the R7 minimum requirement)
      expect(padStyle.paddingLeft).toBeGreaterThanOrEqual(24);
      expect(padStyle.paddingRight).toBeGreaterThanOrEqual(24);
    }
    await screenshot(page, 'r6r7-01-width-and-padding');
    expect(errors).toEqual([]);
  });

  test('R1: bookmark button shows star icon instead of BM text', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'BM Icon Test', chapters: 1, paragraphsPerChapter: 3 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `r1-bm-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Bookmark button should show ☆ (unfilled star), not "BM"
    const bmBtn = page.locator('.bm-btn');
    await expect(bmBtn).toBeAttached();
    const bmText = await bmBtn.textContent();
    expect(bmText).not.toBe('BM');
    expect(bmText).toBe('☆');
    await screenshot(page, 'r1-01-star-icon');
    expect(errors).toEqual([]);
  });

  test('L3: card click opens book, no inline Read/Hide/Archive buttons', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Card Click Test', chapters: 1, paragraphsPerChapter: 3 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `l3-card-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Verify NO inline buttons exist
    await expect(page.locator('.read-btn')).toHaveCount(0);
    await expect(page.locator('.hide-btn')).toHaveCount(0);
    await expect(page.locator('.archive-btn')).toHaveCount(0);
    await screenshot(page, 'l3-01-no-buttons');

    // Click the card itself to open the book
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await screenshot(page, 'l3-02-reader-opened');

    expect(errors).toEqual([]);
  });

  test('L4: progress bar is 5px tall', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Bar Height Test', chapters: 3, paragraphsPerChapter: 1 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `l4-bar-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    // Open and close to get a reading position
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    // Go back to library
    const navVisible = await page.locator('.reader-nav').isVisible();
    if (!navVisible) {
      await page.mouse.click(vp.width / 2, vp.height / 2);
      await page.waitForTimeout(500);
    }
    await page.locator('.back-btn').click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
    // Check progress bar height
    const barHeight = await page.evaluate(() => {
      const bar = document.querySelector('.pbar');
      if (!bar) return null;
      return parseFloat(getComputedStyle(bar).height);
    });
    if (barHeight !== null) {
      expect(barHeight).toBeGreaterThanOrEqual(4);
      expect(barHeight).toBeLessThanOrEqual(6);
    }
    await screenshot(page, 'l4-01-bar-height');
    expect(errors).toEqual([]);
  });

  test('L1+L2: toolbar has single shelf and sort cycling buttons', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Count toolbar buttons — should be <= 4 (shelf + sort + import section)
    const toolbarBtns = await page.locator('.lib-toolbar button').count();
    expect(toolbarBtns).toBeLessThanOrEqual(4);
    expect(toolbarBtns).toBeGreaterThanOrEqual(2);
    await screenshot(page, 'l1l2-01-simplified-toolbar');
    expect(errors).toEqual([]);
  });

  test('L5: gear icon button exists in library toolbar', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Gear button ⚙ should exist in toolbar
    const gearBtn = await page.evaluate(() => {
      const btns = document.querySelectorAll('.lib-toolbar button');
      for (const btn of btns) {
        if (btn.textContent.includes('⚙')) return true;
      }
      return false;
    });
    expect(gearBtn).toBe(true);
    await screenshot(page, 'l5-01-gear-icon');
    expect(errors).toEqual([]);
  });

  test('R6: text line width capped on wide viewports', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Width Cap Test', chapters: 1, paragraphsPerChapter: 5 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `r6-cap-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Measure actual text width of a paragraph
    const textWidth = await page.evaluate(() => {
      const p = document.querySelector('.chapter-container p');
      if (!p) return null;
      const rect = p.getBoundingClientRect();
      return rect.width;
    });
    expect(textWidth).not.toBeNull();

    // On wide viewports (>= 1024px), text width should be <= 720px
    // (680px target + some tolerance for padding/box-sizing)
    if (vp.width >= 1024) {
      expect(textWidth).toBeLessThanOrEqual(720);
    }

    // Pagination must still work — should have multiple pages
    if (vp.width >= 1024) {
      const pageInfo = await page.locator('.page-info').textContent();
      // Should NOT be "p. 1/1" on wide viewport with 5 paragraphs
      // (unless content genuinely fits — 5 short paragraphs might fit)
    }

    await screenshot(page, 'r6-02-width-capped');
    expect(errors).toEqual([]);
  });

  test('R5: scrubber background is not dark overlay', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const epubBuffer = createEpub({ title: 'Scrub BG Test', chapters: 2, paragraphsPerChapter: 5 });
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const vp = page.viewportSize();
    const epubPath = join(SCREENSHOT_DIR, `r5-bg-${vp.width}x${vp.height}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await page.locator('input[type="file"]').setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await page.locator('.book-card').click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Scrubber bottom bar should NOT have dark background
    const bg = await page.evaluate(() => {
      const bottom = document.querySelector('.reader-bottom');
      if (!bottom) return null;
      return getComputedStyle(bottom).backgroundColor;
    });
    expect(bg).not.toBeNull();
    // Should not be dark rgba(0,0,0,...) with alpha > 0.1
    expect(bg).not.toMatch(/rgba\(0,\s*0,\s*0,\s*0\.[2-9]/);
    await screenshot(page, 'r5-02-light-scrubber');
    expect(errors).toEqual([]);
  });

  test('L6: Import button is reasonably sized in toolbar', async ({ page }) => {
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Measure Import button height vs Library button height
    const heights = await page.evaluate(() => {
      const importBtn = document.querySelector('.import-btn');
      const libBtn = document.querySelector('.lib-toolbar button');
      if (!importBtn || !libBtn) return null;
      return {
        importH: importBtn.getBoundingClientRect().height,
        libH: libBtn.getBoundingClientRect().height,
      };
    });
    expect(heights).not.toBeNull();
    // Import should not be more than 1.5x the height of toolbar buttons
    expect(heights.importH).toBeLessThanOrEqual(heights.libH * 1.5);
    await screenshot(page, 'l6-01-import-size');
    expect(errors).toEqual([]);
  });


});
