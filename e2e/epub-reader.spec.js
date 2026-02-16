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
import { createEpub, TINY_PNG, repackageEpub } from './create-epub.js';
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
    // Instrument DecompressionStream before any page JS runs to trace crash location
    await page.addInitScript(() => {
      const OrigDS = globalThis.DecompressionStream;
      let dsCount = 0;
      globalThis.DecompressionStream = function(format) {
        const id = ++dsCount;
        console.log('DIAG:DS#' + id + ' created format=' + format);
        const ds = new OrigDS(format);

        // The bridge does: ds.writable.getWriter() then writer.write/close
        // and ds.readable.getReader() then reader.read() in a pump loop.
        // We patch getWriter and getReader on the stream objects.
        const origGetWriter = ds.writable.getWriter;
        ds.writable.getWriter = function() {
          const w = origGetWriter.call(ds.writable);
          const wWrite = w.write.bind(w);
          const wClose = w.close.bind(w);
          w.write = function(chunk) {
            console.log('DIAG:DS#' + id + '.write len=' + (chunk ? chunk.byteLength || chunk.length : 0));
            return wWrite(chunk);
          };
          w.close = function() {
            console.log('DIAG:DS#' + id + '.close');
            return wClose();
          };
          return w;
        };

        const origGetReader = ds.readable.getReader;
        ds.readable.getReader = function() {
          const r = origGetReader.call(ds.readable);
          const rRead = r.read.bind(r);
          let readCount = 0;
          r.read = function() {
            return rRead().then(function(result) {
              readCount++;
              console.log('DIAG:DS#' + id + '.read#' + readCount +
                ' done=' + result.done + ' len=' + (result.value ? result.value.length : 0));
              return result;
            });
          };
          return r;
        };

        return ds;
      };
      // Preserve prototype chain for typeof checks
      globalThis.DecompressionStream.prototype = OrigDS.prototype;
    });

    // This test uses a real-world EPUB whose metadata entries (container.xml,
    // content.opf) are deflate-compressed (ZIP method 8). The async decompression
    // path in epub_read_container_async / epub_read_opf_async handles this.
    // Additionally, the OPF has <dc:creator id="author_0"> (attribute on tag),
    // which tests the _find_gt metadata parsing fix.
    const consoleMessages = [];
    const pageErrors = [];
    page.on('console', msg => consoleMessages.push(`[${msg.type()}] ${msg.text()}`));
    page.on('pageerror', err => pageErrors.push(err.message));
    page.on('crash', () => {
      console.error('PAGE CRASHED during import test');
      console.error('Console:', consoleMessages);
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

    // === DIAGNOSTIC: Sync vs async crash determination ===
    // Click Next via page.evaluate to catch sync errors and trace timing.
    // The WASM navigate_next path: remove_children (sync DOM) → load_chapter
    //   (sync file read + start async decompress) → return.
    // Then async: decompress callback → parse HTML → render_tree → DOM updates.
    // We need to know if the crash is during the sync click handler or the
    // async decompress/render callback.

    // Instrument wardJsDecompress and DOM flush to trace where the crash occurs.
    // We can't easily patch DecompressionStream after construction, so instead
    // we wrap the WASM exports that are called after decompression completes.
    await page.evaluate(() => {
      // Track decompress completion callback
      window._diagDecompressCount = 0;
      window._diagDomFlushCount = 0;
      window._diagSetImageCount = 0;
      // We'll monkey-patch after WASM loads. The bridge stores instance.exports.
      // wardJsDecompress logs before calling DecompressionStream.
      // But we need to intercept the callback. Let's poll for the WASM instance.
      const checkInterval = setInterval(() => {
        // The bridge exposes the ward_on_decompress_complete export.
        // We can find it through the instance stored in the bridge closure.
        // Actually, we can't access the bridge's closure. Instead, let's just
        // log from here by watching DOM mutations.
        clearInterval(checkInterval);
      }, 100);

      // Simpler approach: observe DOM mutations on the chapter container
      const observer = new MutationObserver((mutations) => {
        for (const m of mutations) {
          if (m.type === 'childList') {
            const target = m.target;
            if (target.classList && target.classList.contains('chapter-container')) {
              console.log('DIAG:DOM mutation on .chapter-container: ' +
                'added=' + m.addedNodes.length + ' removed=' + m.removedNodes.length +
                ' children=' + target.childElementCount);
            }
          }
        }
      });
      // Start observing once the container exists
      const waitForContainer = setInterval(() => {
        const c = document.querySelector('.chapter-container');
        if (c) {
          clearInterval(waitForContainer);
          observer.observe(c, { childList: true, subtree: false });
          console.log('DIAG:MutationObserver attached to .chapter-container');
        }
      }, 100);
    });

    let clickCompleted = false;
    try {
      await page.evaluate(() => {
        window._diagMessages = [];
        window.addEventListener('error', (e) => {
          window._diagMessages.push('ERROR:' + e.message);
        });
        window.addEventListener('unhandledrejection', (e) => {
          window._diagMessages.push('REJECTION:' + String(e.reason));
        });
        const btn = document.querySelector('.next-btn');
        console.log('DIAG:pre-click');
        btn.click(); // Synchronous: triggers ward_on_event → navigate_next
        console.log('DIAG:post-click');
        // If we get here, the click handler completed synchronously.
        // The async decompress callback hasn't fired yet.
      });
      clickCompleted = true;
      console.log('DIAG: page.evaluate completed — click handler was synchronous and OK');
    } catch (clickErr) {
      console.error('DIAG: page.evaluate failed:', clickErr.message);
      // Check which console messages we got before the crash
      console.error('DIAG: console messages captured:', JSON.stringify(consoleMessages));
    }

    if (clickCompleted) {
      // Click handler completed OK. Now wait for the async decompress/render.
      console.log('DIAG: waiting for async decompress/render...');
      try {
        // Wait up to 15s for new chapter content to appear
        await page.waitForFunction(() => {
          const info = document.querySelector('.page-info');
          return info && /^Ch 2\//.test(info.textContent);
        }, { timeout: 15000 });
        console.log('DIAG: chapter 2 loaded successfully!');
        await screenshot(page, 'conan-chapter2-loaded');

        // Check for any errors that occurred during async rendering
        const diagMsgs = await page.evaluate(() => window._diagMessages || []);
        if (diagMsgs.length > 0) {
          console.log('DIAG: errors during async render:', diagMsgs);
        }

        // Navigate back to library
        const backBtn = page.locator('.back-btn');
        await backBtn.click();
        await page.waitForSelector('.book-card', { timeout: 10000 });
        await screenshot(page, 'conan-library-after-reading');
      } catch (asyncErr) {
        console.error('DIAG: async phase failed:', asyncErr.message);
        console.error('DIAG: console messages:', JSON.stringify(consoleMessages));
        // Try to capture any diagnostic info
        try {
          const diagMsgs = await page.evaluate(() => window._diagMessages || []);
          console.error('DIAG: page errors:', diagMsgs);
        } catch (_) { /* page might be crashed */ }
        throw asyncErr;
      }
    } else {
      // The click itself crashed the page.
      // Check console messages to determine sync vs async:
      // - If we see "DIAG:post-click", the crash was async (during microtask)
      // - If we only see "DIAG:pre-click", the crash was during btn.click()
      const preClick = consoleMessages.some(m => m.includes('DIAG:pre-click'));
      const postClick = consoleMessages.some(m => m.includes('DIAG:post-click'));
      console.error(`DIAG: pre-click=${preClick} post-click=${postClick}`);
      if (postClick) {
        console.error('CRASH IS ASYNC — happens after click handler returns (decompress/render)');
      } else if (preClick) {
        console.error('CRASH IS SYNC — happens during btn.click() (navigate_next WASM code)');
      } else {
        console.error('CRASH IS VERY EARLY — even pre-click log not captured');
      }
      throw new Error(`Conan chapter transition crashed (pre=${preClick} post=${postClick})`);
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

  test('conan chapter HTML via innerHTML does not crash Chrome', async ({ page }) => {
    // Diagnostic: inject the EXACT conan chapter HTML into the reader
    // container via innerHTML, WITHOUT going through the WASM render path.
    // If THIS crashes, the issue is in Chrome's rendering of the content.
    // If this works, the issue is in the WASM render path.

    // First, import conan and navigate to the reader
    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(msg.text()));
    page.on('crash', () => {
      console.error('PAGE CRASHED during innerHTML injection test');
      console.error('Console:', consoleMessages);
    });

    // Import conan EPUB
    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles('test/fixtures/conan-stories.epub');
    await page.waitForSelector('.book-card', { timeout: 30000 });

    // Open book (renders cover page)
    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Read the conan chapter body HTML
    const chapterBodyHtml = readFileSync(
      join(process.cwd(), 'e2e', 'conan-chapter-body.html'), 'utf-8'
    );

    // Clear the container and inject conan chapter HTML directly
    let injectCrashed = false;
    try {
      await page.evaluate((html) => {
        const c = document.querySelector('.chapter-container');
        console.log('INJECT: clearing container');
        c.innerHTML = '';
        console.log('INJECT: setting chapter HTML (' + html.length + ' chars)');
        c.innerHTML = html;
        console.log('INJECT: innerHTML set OK, childCount=' + c.childElementCount);
      }, chapterBodyHtml);
      console.log('Test node: innerHTML injection completed OK');
    } catch (injectErr) {
      console.error('Test node: innerHTML injection failed:', injectErr.message);
      injectCrashed = true;
    }

    if (injectCrashed) {
      console.error('CHROME CRASHES ON CONAN HTML via innerHTML — rendering bug!');
      console.error('Console:', consoleMessages);
      throw new Error('Chrome crashes rendering conan chapter HTML');
    }

    // Wait a moment for browser to lay out the content
    await page.waitForTimeout(2000);

    // Take screenshot of the injected content
    await screenshot(page, 'conan-injected-chapter');

    // Verify content rendered
    const container = page.locator('.chapter-container').first();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);

    // Navigate back
    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('WASM render of conan HTML (no image) via synthetic EPUB', async ({ page }) => {
    // Key diagnostic: Use conan's ACTUAL chapter body HTML (without img tag)
    // in a synthetic EPUB, going through the WASM render path.
    // This isolates: complex HTML structure vs image loading.
    // If CRASH: the complex HTML structure causes the crash
    // If OK: the crash is specifically in image loading (try_set_image)
    const fullBody = readFileSync(
      join(process.cwd(), 'e2e', 'conan-chapter-body.html'), 'utf-8'
    );
    // Remove img tag to isolate HTML structure from image loading
    const bodyNoImg = fullBody.replace(/<img[^>]*>/g, '');

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(msg.text()));
    page.on('crash', () => {
      console.error('PAGE CRASHED during conan-html-noimg test');
      console.error('Console:', consoleMessages);
    });

    const epubBuffer = createEpub({
      title: 'Conan HTML NoImg',
      author: 'Test Bot',
      svgCover: true,
      coverImage: true,
      rawChapters: [{ body: bodyNoImg }],
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'conan-html-noimg-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Click Next — SVG cover → conan chapter (without image)
    const nextBtn = page.locator('.next-btn');
    await nextBtn.click();

    // Wait for chapter content
    await page.waitForFunction(() => {
      const info = document.querySelector('.page-info');
      return info && /^Ch 2\//.test(info.textContent);
    }, { timeout: 15000 });

    const container = page.locator('.chapter-container').first();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);
    await screenshot(page, 'conan-html-noimg-rendered');

    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('WASM render of conan HTML with REAL illus.jpg via synthetic EPUB', async ({ page }) => {
    // KEY DIAGNOSTIC: Use conan's ACTUAL HTML + ACTUAL 18KB JPEG illustration
    // in a synthetic EPUB. This isolates whether the JPEG image data + blob URL
    // creation during async render causes the crash.
    const fullBody = readFileSync(
      join(process.cwd(), 'e2e', 'conan-chapter-body.html'), 'utf-8'
    );

    // Extract the real illus.jpg from the conan fixture
    // From ZIP analysis: data_off=114862, size=18538 (stored, method 0)
    const epubData = readFileSync(
      join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub')
    );
    const illusJpg = epubData.subarray(114862, 114862 + 18538);

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(msg.text()));
    page.on('crash', () => {
      console.error('PAGE CRASHED during conan-html-with-real-jpeg test');
      console.error('Console:', consoleMessages);
    });

    const epubBuffer = createEpub({
      title: 'Conan HTML RealJPEG',
      author: 'Test Bot',
      svgCover: true,
      coverImage: true,
      rawChapters: [{ body: fullBody }],
      extraImages: [
        { name: '70880881323834106_illus.jpg', data: illusJpg },
      ],
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'conan-html-withimg-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Click Next — SVG cover → conan chapter (with image)
    const nextBtn = page.locator('.next-btn');
    await nextBtn.click();

    // Wait for chapter content
    await page.waitForFunction(() => {
      const info = document.querySelector('.page-info');
      return info && /^Ch 2\//.test(info.textContent);
    }, { timeout: 15000 });

    const container = page.locator('.chapter-container').first();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);
    await screenshot(page, 'conan-html-withimg-rendered');

    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('minimal HTML + real 18KB JPEG isolates crash trigger', async ({ page }) => {
    // MINIMAL ISOLATION: simplest possible HTML body + real JPEG from conan.
    // Pure JS blob URL test PASSES with same data, so this must be our WASM path.
    // Intercept wardJsSetImageSrc to log data before the crash.
    const epubData = readFileSync(
      join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub')
    );
    const illusJpg = epubData.subarray(114862, 114862 + 18538);

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(msg.text()));
    page.on('crash', () => {
      console.error('PAGE CRASHED during minimal-jpeg isolation test');
      console.error('Console:', consoleMessages);
    });

    // Patch HTMLImageElement.prototype.src to intercept ALL blob URL assignments.
    // Previous WebAssembly.instantiate patch didn't work.
    // This is more reliable — patches the DOM API directly.
    await page.addInitScript(() => {
      const srcDesc = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
      const origSetter = srcDesc.set;
      let imgSetCount = 0;
      srcDesc.set = function(val) {
        imgSetCount++;
        const isBlobUrl = typeof val === 'string' && val.startsWith('blob:');
        console.log('DIAG:IMG_SRC #' + imgSetCount + ' blob=' + isBlobUrl +
          ' val=' + String(val).substring(0, 50));
        if (isBlobUrl) {
          // DEFER blob URL assignment to next microtask
          const el = this;
          const url = val;
          console.log('DIAG:DEFERRING blob src #' + imgSetCount);
          setTimeout(() => {
            console.log('DIAG:APPLYING deferred blob src #' + imgSetCount);
            origSetter.call(el, url);
          }, 0);
          return;
        }
        return origSetter.call(this, val);
      };
      Object.defineProperty(HTMLImageElement.prototype, 'src', srcDesc);
      console.log('DIAG:IMG_SRC_INTERCEPTOR installed');
    });

    const epubBuffer = createEpub({
      title: 'Minimal JPEG Test',
      author: 'Test Bot',
      svgCover: true,
      coverImage: true,
      rawChapters: [{ body: '<p>Hello world</p><img src="test.jpg" alt="test"/>' }],
      extraImages: [
        { name: 'test.jpg', data: illusJpg },
      ],
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'minimal-jpeg-test.epub');
    writeFileSync(epubPath, epubBuffer);
    await fileInput.setInputFiles(epubPath);
    await page.waitForSelector('.book-card', { timeout: 30000 });

    const readBtn = page.locator('.read-btn');
    await readBtn.click();
    await page.waitForSelector('.reader-viewport', { timeout: 15000 });
    await page.waitForFunction(() => {
      const el = document.querySelector('.chapter-container');
      return el && el.childElementCount > 0;
    }, { timeout: 15000 });

    // Click Next — SVG cover → minimal chapter with JPEG
    const nextBtn = page.locator('.next-btn');
    await nextBtn.click();

    // Wait for chapter content
    await page.waitForFunction(() => {
      const info = document.querySelector('.page-info');
      return info && /^Ch 2\//.test(info.textContent);
    }, { timeout: 15000 });

    const container = page.locator('.chapter-container').first();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);
    await screenshot(page, 'minimal-jpeg-rendered');

    const backBtn = page.locator('.back-btn');
    await backBtn.click();
    await page.waitForSelector('.book-card', { timeout: 10000 });
  });

  test('pure JS blob URL with conan JPEG in CSS columns isolates Chrome bug', async ({ page }) => {
    // STANDALONE ISOLATION: no WASM, no EPUB, no bridge.
    // Creates a blob URL from the real JPEG and inserts it into CSS columns.
    // If this crashes: it's a Chrome rendering bug with JPEG blob URLs in CSS columns.
    // If this passes: the crash is in our WASM/bridge code path.
    const epubData = readFileSync(
      join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub')
    );
    const illusJpg = epubData.subarray(114862, 114862 + 18538);
    const jpegBase64 = illusJpg.toString('base64');

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(msg.text()));
    page.on('crash', () => {
      console.error('PAGE CRASHED during pure-JS blob URL test');
      console.error('Console:', consoleMessages);
    });

    // Navigate to a blank page and inject CSS columns + blob URL image
    await page.goto('about:blank');
    await page.evaluate((b64) => {
      // Decode base64 to Uint8Array
      const binary = atob(b64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

      // Create blob URL (same as wardJsSetImageSrc)
      const blob = new Blob([bytes], { type: 'image/jpeg' });
      const url = URL.createObjectURL(blob);

      // Set up CSS columns (same as .chapter-container)
      document.body.innerHTML = `
        <style>
          .chapter-container {
            column-width: 300px;
            column-gap: 0;
            column-fill: auto;
            height: 100vh;
            overflow: hidden;
          }
        </style>
        <div class="chapter-container">
          <p>Hello world before image</p>
          <img src="${url}" alt="test"/>
          <p>Hello world after image</p>
        </div>
      `;
      console.log('DIAG: blob URL set, waiting for render');
    }, jpegBase64);

    // Wait for image to load
    await page.waitForTimeout(3000);

    // If we get here without crash, the pure JS path is fine
    await screenshot(page, 'pure-js-blob-jpeg');
    const childCount = await page.evaluate(() =>
      document.querySelector('.chapter-container').childElementCount
    );
    expect(childCount).toBeGreaterThan(0);
  });

  test('pure JS incremental DOM + blob URL JPEG mimics WASM path', async ({ page }) => {
    // This test mimics the WASM path exactly:
    // 1. Create container with CSS columns (100vw like real app)
    // 2. Create elements ONE BY ONE via createElement/appendChild (like diff buffer)
    // 3. Set image src via blob URL mid-stream (like wardJsSetImageSrc)
    // 4. Continue creating more elements after the image
    // If this crashes: it's incremental DOM + blob URL in CSS columns that crashes
    // If this passes: something else in the WASM/bridge path triggers it
    const epubData = readFileSync(
      join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub')
    );
    const illusJpg = epubData.subarray(114862, 114862 + 18538);
    const jpegBase64 = illusJpg.toString('base64');

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(msg.text()));
    page.on('crash', () => {
      console.error('PAGE CRASHED during incremental DOM test');
      console.error('Console:', consoleMessages);
    });

    await page.goto('about:blank');
    await page.evaluate((b64) => {
      // Set up CSS columns matching real app
      const style = document.createElement('style');
      style.textContent = `
        .chapter-container {
          column-width: 100vw;
          column-gap: 0;
          padding: 2rem 0;
          overflow: hidden;
          height: 100%;
        }
        .chapter-container>* {
          padding-left: 1.5rem;
          padding-right: 1.5rem;
          box-sizing: border-box;
        }
        .chapter-container img {
          max-width: 100%;
          height: auto;
        }
      `;
      document.head.appendChild(style);

      // Create container
      const container = document.createElement('div');
      container.className = 'chapter-container';
      document.body.appendChild(container);

      // Create elements ONE BY ONE (mimicking diff buffer flushes)
      // This is what the WASM render path does

      // Heading
      const h2 = document.createElement('h2');
      h2.textContent = 'Test Chapter';
      container.appendChild(h2);

      // A few paragraphs before the image
      for (let i = 0; i < 5; i++) {
        const p = document.createElement('p');
        p.textContent = 'Lorem ipsum dolor sit amet, paragraph ' + i;
        container.appendChild(p);
      }

      // Create img and set blob URL (like wardJsSetImageSrc)
      const binary = atob(b64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      const blob = new Blob([bytes], { type: 'image/jpeg' });
      const url = URL.createObjectURL(blob);

      const img = document.createElement('img');
      container.appendChild(img);
      // Set src AFTER appendChild (like the WASM path: create element → flush → set src)
      img.src = url;
      console.log('DIAG: img.src set to blob URL, continuing element creation...');

      // More paragraphs AFTER the image (the render continues)
      for (let i = 0; i < 10; i++) {
        const p = document.createElement('p');
        p.textContent = 'More text after image, paragraph ' + i;
        container.appendChild(p);
      }

      console.log('DIAG: all elements created, total children=' + container.childElementCount);
    }, jpegBase64);

    // Wait for rendering
    await page.waitForTimeout(3000);
    await screenshot(page, 'incremental-dom-blob-jpeg');
    const childCount = await page.evaluate(() =>
      document.querySelector('.chapter-container').childElementCount
    );
    expect(childCount).toBeGreaterThan(0);
  });

  test('re-packaged conan EPUB does not crash on chapter transition', async ({ page }) => {
    // KEY DIAGNOSTIC: Extract ALL files from the real conan EPUB and re-package
    // them using our createZip. Same content, different ZIP binary structure.
    // If this passes → crash is about the original ZIP binary structure
    // If this crashes → crash is about the content itself
    const epubData = readFileSync(
      join(process.cwd(), 'test', 'fixtures', 'conan-stories.epub')
    );
    const repackaged = repackageEpub(epubData);

    const consoleMessages = [];
    page.on('console', msg => consoleMessages.push(msg.text()));
    page.on('crash', () => {
      console.error('PAGE CRASHED during re-packaged conan test');
      console.error('Console:', consoleMessages);
    });

    await page.goto('/');
    await page.waitForSelector('.library-list', { timeout: 15000 });
    const fileInput = page.locator('input[type="file"]');
    const epubPath = join(SCREENSHOT_DIR, 'conan-repackaged.epub');
    writeFileSync(epubPath, repackaged);
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

    await screenshot(page, 'conan-repackaged-cover');

    // Click Next — SVG cover → chapter 1 (h-0)
    const nextBtn = page.locator('.next-btn');
    await nextBtn.click();

    // Wait for chapter content
    await page.waitForFunction(() => {
      const info = document.querySelector('.page-info');
      return info && /^Ch 2\//.test(info.textContent);
    }, { timeout: 15000 });

    const container = page.locator('.chapter-container').first();
    const childCount = await container.evaluate(el => el.childElementCount);
    expect(childCount).toBeGreaterThan(0);
    await screenshot(page, 'conan-repackaged-chapter1');

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
});
