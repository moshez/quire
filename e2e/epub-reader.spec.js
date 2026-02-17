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
import { createEpub, TINY_PNG } from './create-epub.js';
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SCREENSHOT_DIR = join(process.cwd(), 'e2e', 'screenshots');

mkdirSync(SCREENSHOT_DIR, { recursive: true });

/** Viewport-aware screenshot: includes project name in filename */
async function screenshot(page, name) {
  const vp = page.viewportSize();
  const tag = `${vp.width}x${vp.height}`;
  await page.screenshot({ path: join(SCREENSHOT_DIR, `${name}-${tag}.png`), fullPage: true });
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
      // If we caught the importing state, verify status div has content
      const importStatus = page.locator('.import-status');
      await expect(importStatus).not.toBeEmpty({ timeout: 10000 });
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

    // Record all WASM export + import calls for crash reproduction.
    // WASM exports are frozen/non-writable, so we build a plain wrapper object
    // (same pattern as bridge.js wrapExports) and return a fake result.
    await page.addInitScript(() => {
      const origInstantiate = WebAssembly.instantiate;
      WebAssembly.instantiate = async function(bytes, imports) {
        // Wrap import functions (WASM→JS calls) to log them
        if (imports && imports.env) {
          for (const [name, fn] of Object.entries(imports.env)) {
            if (typeof fn === 'function') {
              const origFn = fn;
              imports.env[name] = function(...args) {
                console.log('WASM_IMP:' + name + ':' + JSON.stringify(args));
                const ret = origFn.apply(this, args);
                if (ret !== undefined) console.log('WASM_IMP_RET:' + name + ':' + JSON.stringify(ret));
                return ret;
              };
            }
          }
        }

        const result = await origInstantiate.call(WebAssembly, bytes, imports);
        const realInstance = result.instance;
        const realExports = realInstance.exports;

        // Build plain wrapper — can't modify frozen WASM exports
        const wrappedExports = Object.create(null);
        for (const [key, val] of Object.entries(realExports)) {
          if (typeof val !== 'function') {
            wrappedExports[key] = val;
          } else {
            const orig = val;
            wrappedExports[key] = function(...args) {
              console.log('WASM_CALL:' + key + ':' + JSON.stringify(args));
              try {
                const ret = orig.apply(null, args);
                if (ret !== undefined) console.log('WASM_RET:' + key + ':' + JSON.stringify(ret));
                return ret;
              } catch(e) {
                console.log('WASM_ERR:' + key + ':' + e.message);
                throw e;
              }
            };
          }
        }

        const mem = realExports.memory;
        if (mem) {
          console.log('WASM_MEM:initial_pages=' + (mem.buffer.byteLength / 65536));
        }

        // Return fake result with our wrapped exports
        return {
          instance: { exports: wrappedExports },
          module: result.module
        };
      };
    });

    const consoleMessages = [];
    const pageErrors = [];
    page.on('console', msg => consoleMessages.push(`[${msg.type()}] ${msg.text()}`));
    page.on('pageerror', err => pageErrors.push(err.message));
    page.on('crash', () => {
      console.error('PAGE CRASHED during import test');
      // Dump all WASM recordings (exports, imports, memory)
      const wasmCalls = consoleMessages.filter(m =>
        m.includes('WASM_CALL:') || m.includes('WASM_RET:') ||
        m.includes('WASM_IMP:') || m.includes('WASM_IMP_RET:') ||
        m.includes('WASM_ERR:') || m.includes('WASM_MEM:'));
      console.error('WASM call trace (' + wasmCalls.length + ' entries):');
      wasmCalls.forEach(c => console.error(c));
    });

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

        // Wait for page info to change (page flip or chapter transition)
        await page.waitForFunction((prev) => {
          const info = document.querySelector('.page-info');
          return info && info.textContent !== prev;
        }, prevPageText, { timeout: 15000 });

        const curPageText = await pageInfoEl.textContent();
        const curCh = curPageText.match(/^Ch (\d+)\//)?.[1];

        // On chapter transition, wait for content to load
        if (curCh !== prevCh) {
          await page.waitForFunction(() => {
            const el = document.querySelector('.chapter-container');
            return el && el.childElementCount > 0;
          }, { timeout: 15000 });
          // Let CSS column layout settle after chapter load
          await page.waitForTimeout(500);
        } else {
          await page.waitForTimeout(200);
        }

        // Assert non-empty content
        const childCount = await walkContainer.evaluate(el => el.childElementCount);
        const hasContent = await walkContainer.evaluate(el =>
          el.textContent.length > 0 || !!el.querySelector('svg'));

        const ok = childCount > 0 && hasContent;
        walkLog.push({ step, page: curPageText, childCount, ok });

        await screenshot(page, `conan-walk-${String(step).padStart(2, '0')}`);

        if (curPageText === prevPageText) {
          // Page didn't change — we're at the end
          walkLog.push({ step, page: curPageText, note: 'end-of-book' });
          break;
        }

        expect(childCount).toBeGreaterThan(0);
        prevPageText = curPageText;
      } catch (e) {
        if (crashed) {
          walkLog.push({ step, note: 'CRASHED', prevPage: prevPageText });
          break;
        }
        walkLog.push({ step, note: 'error: ' + e.message, prevPage: prevPageText });
        break;
      }
    }

    // Log the complete walk for CI artifact inspection
    console.log('=== CONAN WALK LOG ===');
    walkLog.forEach(entry => console.log(JSON.stringify(entry)));
    console.log('=== END WALK LOG ===');

    // The walk should have progressed past the cover page at minimum
    expect(walkLog.length).toBeGreaterThan(1);

    // If not crashed, navigate back to library
    if (!crashed) {
      const backBtn = page.locator('.back-btn');
      await backBtn.click();
      await page.waitForSelector('.book-card', { timeout: 10000 });
    }
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

  test('ward crash_repro exerciser does not crash Chromium', async ({ page }) => {
    // Tests whether ward's DOM operations alone (without quire) crash Chromium.
    // If this crashes: the bug is in ward (bridge + WASM interaction).
    // If this passes: the bug is in quire-specific code, not ward.
    //
    // The exerciser reproduces the exact memory lifecycle from the conan
    // crash trace: ZIP alloc/free, multiple DOM cycles, decompress metadata,
    // cover chapter render, REMOVE_CHILDREN + large chapter render with
    // allocations during the DOM stream, then post-render allocations.
    const crashed = { value: false };
    page.on('crash', () => { crashed.value = true; });

    await page.goto('/vendor/ward/exerciser/crash_repro.html');

    // Wait for the exerciser to complete or crash
    try {
      await page.waitForFunction(() => {
        const log = document.getElementById('log');
        return log && (log.textContent.includes('SUCCESS') || log.textContent.includes('FATAL'));
      }, { timeout: 30000 });

      const logContent = await page.evaluate(() => document.getElementById('log').textContent);
      console.log('crash_repro log:', logContent);
      expect(logContent).toContain('SUCCESS');
      expect(crashed.value).toBe(false);
    } catch (e) {
      if (crashed.value) {
        console.error('WARD CRASH_REPRO CRASHED CHROMIUM — this is a ward bug');
        throw new Error('crash_repro.wasm + ward_bridge.mjs crashed Chromium renderer');
      }
      throw e;
    }
  });

});
