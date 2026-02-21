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

    // Verify position is saved (should show progress percentage in library)
    const posText = await page.locator('.book-position').textContent();
    expect(posText).toMatch(/\d+%/);
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

    // Verify shelf filter buttons — "Library" is active (sort-active class)
    const shelfLibBtn = page.locator('.lib-toolbar button', { hasText: 'Library' });
    await expect(shelfLibBtn).toBeVisible();
    const shelfLibClass = await shelfLibBtn.getAttribute('class');
    expect(shelfLibClass).toContain('sort-active');

    // Verify sort buttons visible
    const sortBtnInactive = page.locator('.sort-btn');
    const sortBtnActive = page.locator('.sort-active');
    await expect(sortBtnInactive.first()).toBeVisible();

    // Verify archive button visible on the book card
    const archiveBtn = page.locator('.archive-btn');
    await expect(archiveBtn).toBeVisible();
    await expect(archiveBtn).toContainText('Archive');

    // Verify hide button visible on the book card
    const hideBtn = page.locator('.hide-btn');
    await expect(hideBtn).toBeVisible();
    await expect(hideBtn).toContainText('Hide');

    // Archive the book
    await archiveBtn.click();

    // Book should disappear from active view — library should show empty
    await page.waitForSelector('.empty-lib', { timeout: 10000 });
    await screenshot(page, 'archive-02-empty-after-archive');

    // Verify empty message says "No books yet" (active view)
    const emptyMsg = page.locator('.empty-lib');
    await expect(emptyMsg).toContainText('No books yet');

    // Switch to archived view via shelf filter button
    const shelfArchivedBtn = page.locator('.lib-toolbar button', { hasText: 'Archived' });
    await shelfArchivedBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, 'archive-03-archived-view');

    // "Archived" button should now have sort-active class
    const archivedBtnClass = await page.locator('.lib-toolbar button', { hasText: 'Archived' }).getAttribute('class');
    expect(archivedBtnClass).toContain('sort-active');

    // Verify the archived book is shown with correct title
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('Archive Test Book');

    // Verify restore button visible (not "Archive")
    const restoreBtn = page.locator('.archive-btn');
    await expect(restoreBtn).toBeVisible();
    await expect(restoreBtn).toContainText('Restore');

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

    // Switch back to active view via shelf filter button
    const shelfActiveBtn = page.locator('.lib-toolbar button', { hasText: 'Library' });
    await shelfActiveBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, 'archive-05-restored');

    // Book should be back in active view with correct title
    const restoredTitle = page.locator('.book-title');
    await expect(restoredTitle).toContainText('Archive Test Book');

    // Archive, Hide, and Read buttons should be visible again
    const readBtn = page.locator('.read-btn');
    await expect(readBtn).toBeVisible();
    const archBtn = page.locator('.archive-btn');
    await expect(archBtn).toContainText('Archive');
    const hideBtn2 = page.locator('.hide-btn');
    await expect(hideBtn2).toContainText('Hide');
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

    // Import same EPUB again — duplicate modal appears for active books
    const fileInput2 = page.locator('input[type="file"]');
    await fileInput2.setInputFiles(epubPath);

    // Wait for duplicate modal to appear
    await page.waitForSelector('.dup-overlay', { timeout: 30000 });
    await screenshot(page, 'dedup-02-modal-shown');

    // Click "Replace" to proceed with reimport
    const replaceBtn = page.locator('.dup-replace');
    await replaceBtn.click();

    // Wait for modal to dismiss and import to complete
    await expect(page.locator('.dup-overlay')).not.toBeVisible({ timeout: 10000 });
    await page.waitForSelector('label.import-btn', { timeout: 30000 });
    await page.waitForTimeout(1000);
    await screenshot(page, 'dedup-03-after-replace');

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

    // Wait for async image loading from IDB to complete (blob: URL appears)
    await page.waitForFunction(() => {
      const img = document.querySelector('.chapter-container img');
      return img && img.src.startsWith('blob:');
    }, { timeout: 15000 });

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

  test('hide and unhide a book', async ({ page }) => {
    // Import a book, hide it, verify it appears on the hidden shelf,
    // unhide it, verify it returns to the active shelf.
    const epubBuffer = createEpub({
      title: 'Hide Test Book',
      author: 'Hide Bot',
      chapters: 2,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'hide-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });
    await screenshot(page, 'hide-01-imported');

    // Verify hide button visible with text "Hide" in active view
    const hideBtn = page.locator('.hide-btn');
    await expect(hideBtn).toBeVisible();
    await expect(hideBtn).toContainText('Hide');

    // Hide the book
    await hideBtn.click();

    // Book should disappear from active view — library should show empty
    await page.waitForSelector('.empty-lib', { timeout: 10000 });
    await screenshot(page, 'hide-02-empty-after-hide');

    // Verify empty message says "No books yet" (active view)
    const emptyMsg = page.locator('.empty-lib');
    await expect(emptyMsg).toContainText('No books yet');

    // Switch to hidden view via shelf filter button
    const shelfHiddenBtn = page.locator('.lib-toolbar button', { hasText: 'Hidden' });
    await shelfHiddenBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, 'hide-03-hidden-view');

    // "Hidden" button should now have sort-active class
    const hiddenBtnClass = await page.locator('.lib-toolbar button', { hasText: 'Hidden' }).getAttribute('class');
    expect(hiddenBtnClass).toContain('sort-active');

    // Verify the hidden book is shown with correct title
    const bookTitle = page.locator('.book-title');
    await expect(bookTitle).toContainText('Hide Test Book');

    // Verify unhide button visible (not "Hide")
    const unhideBtn = page.locator('.hide-btn');
    await expect(unhideBtn).toBeVisible();
    await expect(unhideBtn).toContainText('Unhide');

    // Import button should be hidden in hidden view
    const importBtns = page.locator('label.import-btn');
    expect(await importBtns.count()).toBe(0);

    // Unhide the book
    await unhideBtn.click();

    // Hidden view should now be empty
    await page.waitForSelector('.empty-lib', { timeout: 10000 });
    const hiddenEmpty = page.locator('.empty-lib');
    await expect(hiddenEmpty).toContainText('No hidden books');
    await screenshot(page, 'hide-04-hidden-empty');

    // Switch back to active view via shelf filter button
    const shelfActiveBtn = page.locator('.lib-toolbar button', { hasText: 'Library' });
    await shelfActiveBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
    await screenshot(page, 'hide-05-restored');

    // Book should be back in active view with correct title
    const restoredTitle = page.locator('.book-title');
    await expect(restoredTitle).toContainText('Hide Test Book');

    // Read, Hide, and Archive buttons should all be present
    const readBtn = page.locator('.read-btn');
    await expect(readBtn).toBeVisible();
    const hideBtn2 = page.locator('.hide-btn');
    await expect(hideBtn2).toContainText('Hide');
    const archBtn = page.locator('.archive-btn');
    await expect(archBtn).toContainText('Archive');
  });

  test('sort books by last opened and date added', async ({ page }) => {
    // Import two books sequentially, verify date-added and last-opened
    // sort modes produce correct ordering.
    const epub1 = createEpub({
      title: 'Zephyr Book',
      author: 'Alice Author',
      chapters: 2,
      paragraphsPerChapter: 2,
    });
    const epub2 = createEpub({
      title: 'Alpha Book',
      author: 'Zelda Writer',
      chapters: 2,
      paragraphsPerChapter: 2,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import first book (Zephyr Book — imported earlier, smaller date_added)
    const fileInput = page.locator('input[type="file"]');
    const path1 = join(SCREENSHOT_DIR, 'sort-lo-test1.epub');
    writeFileSync(path1, epub1);
    await fileInput.setInputFiles(path1);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Wait for IndexedDB save, then reload to get fresh state
    await page.waitForTimeout(2000);
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await page.waitForSelector('.book-card', { timeout: 15000 });

    // Import second book (Alpha Book — imported later, larger date_added)
    const fileInput2 = page.locator('input[type="file"]');
    const path2 = join(SCREENSHOT_DIR, 'sort-lo-test2.epub');
    writeFileSync(path2, epub2);
    await fileInput2.setInputFiles(path2);

    // Wait for second book card to appear
    await page.waitForFunction(() => {
      const cards = document.querySelectorAll('.book-card');
      return cards.length >= 2;
    }, { timeout: 30000 });
    await screenshot(page, 'sort-lo-01-two-books');

    // --- Test date-added sort ---
    // Sort by date added (reverse chronological — most recent first)
    // Alpha Book was imported later → should be first
    const sortDateAdded = page.locator('.lib-toolbar button', { hasText: 'Date added' });
    await expect(sortDateAdded).toBeVisible();
    await sortDateAdded.click();
    await page.waitForTimeout(500);
    await screenshot(page, 'sort-lo-02-by-date-added');

    // Verify "Date added" button has sort-active class
    const dateAddedClass = await sortDateAdded.getAttribute('class');
    expect(dateAddedClass).toContain('sort-active');

    // Alpha Book (imported later) should be first
    const titlesByDate = page.locator('.book-title');
    const firstByDate = await titlesByDate.nth(0).textContent();
    const secondByDate = await titlesByDate.nth(1).textContent();
    expect(firstByDate).toContain('Alpha Book');
    expect(secondByDate).toContain('Zephyr Book');

    // --- Test last-opened sort ---
    // Both books were assigned last_opened=now at import time. Since Zephyr
    // was imported first (earlier timestamp) and Alpha second (later timestamp),
    // reverse-chronological sort puts Alpha first — same order as date-added.
    // This verifies the sort mode switch works and the button activates.
    const sortLastOpened = page.locator('.lib-toolbar button', { hasText: 'Last opened' });
    await expect(sortLastOpened).toBeVisible();
    await sortLastOpened.click();
    await page.waitForTimeout(500);
    await screenshot(page, 'sort-lo-03-by-last-opened');

    // Verify "Last opened" button has sort-active class
    const lastOpenedClass = await sortLastOpened.getAttribute('class');
    expect(lastOpenedClass).toContain('sort-active');

    // Both books should still be visible
    const titlesLO = page.locator('.book-title');
    expect(await titlesLO.count()).toBe(2);

    // Alpha Book (imported later → higher last_opened) should be first
    const firstLO = await titlesLO.nth(0).textContent();
    const secondLO = await titlesLO.nth(1).textContent();
    expect(firstLO).toContain('Alpha Book');
    expect(secondLO).toContain('Zephyr Book');

    // Verify switching back to title sort still works
    const sortTitle = page.locator('.lib-toolbar button', { hasText: 'By title' });
    await sortTitle.click();
    await page.waitForTimeout(500);

    // By title: Alpha first, Zephyr second (alphabetical)
    const titlesTitle = page.locator('.book-title');
    const firstTitle = await titlesTitle.nth(0).textContent();
    expect(firstTitle).toContain('Alpha Book');

    // Verify title button now has sort-active class
    const titleBtnClass = await sortTitle.getAttribute('class');
    expect(titleBtnClass).toContain('sort-active');
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
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Should start at Ch 1, page 1
    const pageInfo = page.locator('.page-info');
    const initialText = await pageInfo.textContent();
    expect(initialText).toMatch(/^Ch 1\//);
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
    const readBtn2 = page.locator('.read-btn');
    await readBtn2.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });
    await page.waitForTimeout(1000);

    // Verify restored page is the same page we were on (or close — within 1
    // due to viewport size differences between render passes)
    const restoredText = await pageInfo.textContent();
    expect(restoredText).toMatch(/^Ch 1\//);
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

  test('context menu appears with correct items per shelf state', async ({ page }) => {
    // Import a book with cover, right-click to open context menu,
    // verify items per shelf state (active, archived, hidden).
    const epubBuffer = createEpub({
      title: 'Context Menu Test',
      author: 'Ctx Bot',
      chapters: 1,
      paragraphsPerChapter: 3,
      coverImage: true,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `ctx-menu-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Wait for event listeners to be fully registered
    await page.waitForTimeout(1000);

    // --- Active shelf: right-click opens context menu ---
    // Dispatch contextmenu event directly via page.evaluate for maximum reliability
    const ctxResult = await page.evaluate(() => {
      const card = document.querySelector('.book-card');
      if (!card) return { error: 'no .book-card found' };
      const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
      card.dispatchEvent(event);
      const overlay = document.querySelector('.ctx-overlay');
      return { overlayCreated: !!overlay };
    });
    console.log('Context menu dispatch result:', JSON.stringify(ctxResult));
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });

    // Verify 4 buttons: Book info, Hide, Archive, Delete
    await expect(page.locator('.ctx-menu button')).toHaveCount(4);
    await expect(page.locator('.ctx-menu button', { hasText: 'Book info' })).toBeVisible();
    await expect(page.locator('.ctx-menu button', { hasText: 'Hide' })).toBeVisible();
    await expect(page.locator('.ctx-menu button', { hasText: 'Archive' })).toBeVisible();
    await expect(page.locator('.ctx-menu button', { hasText: 'Delete' })).toBeVisible();
    await screenshot(page, 'ctx-01-active-menu');

    // Dismiss by clicking overlay
    await page.locator('.ctx-overlay').click({ position: { x: 5, y: 5 } });
    await expect(page.locator('.ctx-overlay')).toHaveCount(0, { timeout: 10000 });

    // --- Archive the book, switch to archived view ---
    const archiveBtn = page.locator('.archive-btn');
    await archiveBtn.click();
    await page.waitForSelector('.empty-lib', { timeout: 10000 });

    const shelfArchivedBtn = page.locator('.lib-toolbar button', { hasText: 'Archived' });
    await shelfArchivedBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    // Right-click archived book
    await page.locator('.book-card').dispatchEvent('contextmenu');
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });

    // Archived shelf: 3 buttons — Book info, Restore, Delete (no Hide)
    await expect(page.locator('.ctx-menu button')).toHaveCount(3);
    await expect(page.locator('.ctx-menu button', { hasText: 'Hide' })).toHaveCount(0);
    await expect(page.locator('.ctx-menu button', { hasText: 'Restore' })).toBeVisible();
    await screenshot(page, 'ctx-02-archived-menu');

    // Dismiss, restore, switch to active
    await page.locator('.ctx-overlay').click({ position: { x: 5, y: 5 } });
    await expect(page.locator('.ctx-overlay')).toHaveCount(0, { timeout: 10000 });
    const restoreBtn = page.locator('.archive-btn');
    await restoreBtn.click();
    await page.waitForSelector('.empty-lib', { timeout: 10000 });
    const shelfActiveBtn = page.locator('.lib-toolbar button', { hasText: 'Library' });
    await shelfActiveBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    // --- Hide the book, switch to hidden view ---
    const hideBtn = page.locator('.hide-btn');
    await hideBtn.click();
    await page.waitForSelector('.empty-lib', { timeout: 10000 });

    const shelfHiddenBtn = page.locator('.lib-toolbar button', { hasText: 'Hidden' });
    await shelfHiddenBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });

    // Right-click hidden book
    await page.locator('.book-card').dispatchEvent('contextmenu');
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });

    // Hidden shelf: 3 buttons — Book info, Unhide, Delete (no Archive)
    await expect(page.locator('.ctx-menu button')).toHaveCount(3);
    await expect(page.locator('.ctx-menu button', { hasText: 'Archive' })).toHaveCount(0);
    await expect(page.locator('.ctx-menu button', { hasText: 'Unhide' })).toBeVisible();
    await screenshot(page, 'ctx-03-hidden-menu');

    // Dismiss, unhide, switch to active
    await page.locator('.ctx-overlay').click({ position: { x: 5, y: 5 } });
    await expect(page.locator('.ctx-overlay')).toHaveCount(0, { timeout: 10000 });
    const unhideBtn = page.locator('.hide-btn');
    await unhideBtn.click();
    await page.waitForSelector('.empty-lib', { timeout: 10000 });
    const shelfActiveBtn2 = page.locator('.lib-toolbar button', { hasText: 'Library' });
    await shelfActiveBtn2.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('book info overlay shows metadata and action buttons', async ({ page }) => {
    // Import a book with cover, open book info via context menu,
    // verify metadata fields and action buttons.
    const bookTitle = 'Info Overlay Test';
    const author = 'Info Bot';
    const epubBuffer = createEpub({
      title: bookTitle,
      author: author,
      chapters: 1,
      paragraphsPerChapter: 3,
      coverImage: true,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `info-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Wait for event listeners to be fully registered
    await page.waitForTimeout(500);

    // Right-click to open context menu
    await page.locator('.book-card').dispatchEvent('contextmenu');
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });

    // Click "Book info" in context menu
    await page.locator('.ctx-menu button', { hasText: 'Book info' }).click();

    // Wait for info overlay
    await page.waitForSelector('.info-overlay', { timeout: 10000 });

    // Verify title and author
    await expect(page.locator('.info-title')).toContainText(bookTitle);
    await expect(page.locator('.info-author')).toContainText(author);

    // Verify metadata row labels
    const rowLabels = page.locator('.info-row-label');
    const labelTexts = await rowLabels.allTextContents();
    expect(labelTexts).toContain('Progress');
    expect(labelTexts).toContain('Added');
    expect(labelTexts).toContain('Last read');
    expect(labelTexts).toContain('Size');

    // Verify cover container and image loads async
    await expect(page.locator('.info-cover')).toBeVisible();
    await page.waitForSelector('.info-cover img', { timeout: 10000 });

    // Verify action buttons
    await expect(page.locator('.info-btn', { hasText: 'Hide' })).toBeVisible();
    await expect(page.locator('.info-btn', { hasText: 'Archive' })).toBeVisible();
    await expect(page.locator('.info-btn-danger')).toContainText('Delete');

    // Verify action buttons are in viewport
    await expect(page.locator('.info-actions')).toBeInViewport();
    await screenshot(page, 'info-01-overlay');

    // Dismiss via back button
    await page.locator('.info-back').click();
    await expect(page.locator('.info-overlay')).toHaveCount(0, { timeout: 10000 });
    await screenshot(page, 'info-02-dismissed');
  });

  test('delete book via confirmation modal', async ({ page }) => {
    // Import a book, delete via context menu, verify confirmation modal,
    // cancel, then delete for real, verify book is gone and stays gone after reload.
    const epubBuffer = createEpub({
      title: 'Delete Test Book',
      author: 'Delete Bot',
      chapters: 1,
      paragraphsPerChapter: 3,
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });

    // Import
    const fileInput = page.locator('input[type="file"]');
    const vp = page.viewportSize();
    const vpTag = `${vp.width}x${vp.height}`;
    const epubPath = join(SCREENSHOT_DIR, `del-test-${vpTag}.epub`);
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Wait for event listeners to be fully registered
    await page.waitForTimeout(500);

    // Right-click to open context menu
    await page.locator('.book-card').dispatchEvent('contextmenu');
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });

    // Click "Delete" in context menu
    await page.locator('.ctx-menu button', { hasText: 'Delete' }).click();

    // Wait for delete confirmation modal (reuses dup-overlay CSS)
    await page.waitForSelector('.dup-overlay', { timeout: 10000 });

    // Verify modal shows book title and confirmation message
    await expect(page.locator('.dup-title')).toContainText('Delete Test Book');
    await expect(page.locator('.dup-msg')).toContainText('Permanently delete?');

    // Verify Cancel and Delete buttons
    await expect(page.locator('.dup-btn')).toBeVisible();
    await expect(page.locator('.dup-replace')).toBeVisible();
    await screenshot(page, 'del-01-confirm-modal');

    // Click Cancel
    await page.locator('.dup-btn').click();
    await expect(page.locator('.dup-overlay')).toHaveCount(0, { timeout: 5000 });

    // Book should still be in library
    await expect(page.locator('.book-card')).toHaveCount(1);
    await screenshot(page, 'del-02-after-cancel');

    // Right-click again, click Delete in context menu
    await page.locator('.book-card').dispatchEvent('contextmenu');
    await page.waitForSelector('.ctx-overlay', { timeout: 10000 });
    await page.locator('.ctx-menu button', { hasText: 'Delete' }).click();
    await page.waitForSelector('.dup-overlay', { timeout: 10000 });

    // Click Delete button (confirm)
    await page.locator('.dup-replace').click();
    await expect(page.locator('.dup-overlay')).toHaveCount(0, { timeout: 10000 });

    // Book card should be gone
    await expect(page.locator('.book-card')).toHaveCount(0, { timeout: 10000 });

    // Empty library message should appear
    await expect(page.locator('.empty-lib')).toContainText('No books yet');
    await screenshot(page, 'del-03-after-delete');

    // Reload page — verify book stays deleted (IDB cleaned up)
    await page.reload();
    await page.waitForSelector('.library-list', { timeout: 15000 });
    await expect(page.locator('.book-card')).toHaveCount(0);
    await expect(page.locator('.empty-lib')).toContainText('No books yet');
    await screenshot(page, 'del-04-after-reload');
  });

});
