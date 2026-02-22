# Quire MVP Implementation Plan

Gap analysis: current PoC vs quire-spec.md. Each step is a self-contained
unit of work that can be built, tested, and committed independently.

Deferred features (explicitly NOT v1 per spec): grid view, image tap-to-zoom,
multi-color highlights, cross-library search, RTL/vertical text, reading
speed/time remaining, reading goals/statistics, pinch-to-zoom font, "Open
with" OS registration, data backup export/import.

---

## Phase 1 — Storage & Identity Foundation

These changes restructure how books are identified and stored, which almost
everything else depends on.

- [x] **1.1 Content-hash book identity.** Replace `dc:identifier` with a hash
  of the EPUB file bytes as the canonical book ID. Update `epub.sats/dats` to
  compute the hash during import (streaming hash during ZIP parse). Update
  `library.dats` `find_dup` to match on content hash. Update serialization
  format (bump version). Add dataprop `BOOK_IDENTITY(hash)` proving identity
  is derived from content. Remove `ADD_BOOK_RESULT`/`DUP_BAD_EPUB` (no longer
  applicable — same hash = same book by definition).

- [x] **1.2 Exploded resource storage.** Currently chapter content is stored
  as compressed blobs keyed by `book_id/path`. Ensure ALL resources (XHTML,
  images, CSS, fonts) are individually exploded into IndexedDB during import
  so they can be served via blob URLs without full-archive decompression.
  Verify the existing `ward_idb` API supports this or extend it.

- [x] **1.3 Per-book metadata fields.** Add to library record: `date_added`
  (timestamp), `last_opened` (timestamp), `file_size` (bytes), `cover_key`
  (IndexedDB key for cover thumbnail). Update `REC_INTS`/`REC_BYTES` in
  `library.dats`, serialization, and deserialize. Add dataprop proving
  timestamp fields are non-negative.

- [x] **1.4 Sort by last-opened and date-added.** Extend `SORT_MODE_VALID`
  with two new constructors: `SORT_BY_LAST_OPENED(2)` and
  `SORT_BY_DATE_ADDED(3)`. Default sort = last-opened (per spec). Update sort
  comparison in `library.dats` to handle integer timestamp comparison (reverse
  chronological — most recent first). Add text constants for "Last opened" and
  "Date added". Update sort UI in `quire.dats` to cycle through all four
  modes. Add sort dropdown (▼) per spec wireframe.

- [x] **1.5 Hidden shelf.** Add a `hidden` flag (0 or 1) to the library
  record alongside `archived`. Three shelf states: active (hidden=0,
  archived=0), hidden (hidden=1, archived=0), archived (hidden=0, archived=1).
  Add `SHELF_STATE_VALID` dataprop proving mutual exclusion. Add
  `VIEW_MODE_VALID` constructor for hidden shelf (2). Replace current shelf
  toggle button with a shelf filter popover (radio buttons: Active / Hidden /
  Archived, per spec wireframe). Add text constants "Hidden", "No hidden
  books", "Hide", "Unhide".

- [x] **1.6 E2e: three-shelf and sort modes.** Import book, hide it, verify
  it appears on hidden shelf via shelf filter popover, unhide, archive, verify
  archived shelf, unarchive. Test all four sort modes (last opened, title,
  author, date added) produce correct ordering.

---

## Phase 2 — Import Pipeline Hardening

- [x] **2.1 Cover image extraction.** During OPF parse, identify the cover
  image (manifest item with `properties="cover-image"` for EPUB3, or
  `<meta name="cover" content="..."/>` for EPUB2). Extract, generate a
  thumbnail (scale to max 200px wide via canvas in bridge), store thumbnail
  blob in IndexedDB keyed by book content hash. Display in library cards.

- [x] **2.2 Search index building at import time.** Extract plain text per
  chapter during import. Store in IndexedDB with character offset mapping back
  to XML tree positions. Fold diacritics during indexing. Schema: one record
  per chapter with `{bookHash, chapterIndex, plainText, offsets[]}`.

- [x] **2.3 Duplicate detection with Skip/Replace prompt.** When content hash
  matches an existing book (any shelf state), show a WASM-rendered modal:
  `"[Title]" is already in your library.` with two buttons: "Skip" (cancel
  import) and "Replace" (swap content, preserve annotations and reading
  position). Per spec wireframe, the existing book card is visible below the
  dialog. Add dataprop proving the user chose one of the two options.

- [x] **2.4 Error banner with filename and DRM message.** On malformed file
  rejection, show a dismissible banner (not inline status text). Per spec
  wireframe: `✕` close button, "Import failed", filename in quotes (e.g.,
  `"vacation-photos.zip"`), "is not a valid ePub file.", "Quire supports
  .epub files without DRM." Banner persists until user dismisses it. Requires
  bridge support for filename pass-through to WASM.

- [x] **2.5 Import progress on card.** Per spec wireframe, the importing book
  appears at the top of the library list with its own card showing
  "Importing...", title, a progress bar, and status text (e.g., "Extracting
  chapters..."). The rest of the library remains interactive below.

- [x] **2.6 E2e: import errors and duplicates.** Import an invalid file,
  verify dismissible error banner appears with filename and DRM message.
  Import same EPUB twice, verify Skip/Replace dialog appears with book title;
  verify Skip cancels, Replace preserves annotations.

---

## Phase 3 — Library View Enhancements

- [x] **3.1 Cover thumbnails on book cards.** Load cover thumbnail blob from
  IndexedDB, create blob URL, display as `<img>` in each book card (left
  side, per spec wireframe). Fallback to a placeholder icon when no cover
  exists. Ensure blob URLs are revoked when cards are removed from DOM.

- [x] **3.2 Progress bar on book cards.** Add a visual progress bar to each
  card showing reading percentage (per spec wireframe: `━━━━━━━━━○── 68%`).
  Unstarted books show "New" (no progress bar). Finished books (100%) show
  "Done" (full bar). Calculate percentage from chapter/spine_count and
  page/page_count (approximate until character-offset tracking lands).

- [x] **3.3 Context menu (long-press / right-click).** Implement a context
  menu on book cards. Long-press on mobile, right-click on desktop (per spec:
  browser right-click menu is NOT intercepted in reading view, only in
  library). Menu items per spec wireframe: Book info, Hide, Archive, Delete.
  Items vary by current shelf (e.g., "Unhide" on hidden shelf, "Unarchive"
  on archived shelf). Requires bridge event for contextmenu/long-press,
  WASM-driven menu rendering, and dismiss on outside tap.

- [x] **3.4 Book info view.** Full-screen overlay (mobile) or modal (desktop)
  per spec wireframe: ← Back header, large cover image centered, title,
  author, then metadata rows: Progress (% + chapter of total), Added (date),
  Last read (date), Size (MB). Three action buttons at bottom: Hide, Archive,
  Delete (contextual per shelf). Accessed from context menu "Book info" item.

- [x] **3.5 Delete book.** Implement full book deletion: remove from library
  index, delete all resources from IndexedDB, delete search index entries,
  delete annotations (with confirmation prompt). Currently only
  archive/restore exists.

- [x] **3.6 E2e: library view enhancements.** Verify cover thumbnails on
  book cards. Long-press / right-click book card, verify context menu appears
  with correct items for current shelf state. Open book info from context
  menu, verify cover, metadata (title, author, progress, dates, size), and
  action buttons.

---

## Phase 4 — Reading Chrome & Navigation

- [x] **4.1 Chrome auto-hide.** After toggling chrome visible, start a timer
  (e.g., 5 seconds). Auto-hide chrome when timer fires or on next page turn.
  Cancel timer on user interaction with chrome elements (tapping any chrome
  button, interacting with scrubber). Use `ward_timer` API.

- [x] **4.2 Chapter title in top chrome.** Display the current chapter's
  title in the top bar between the close button and bookmark toggle (per spec
  wireframe: `✕  Chapter 4: The Garden    🔖`). Look up title from TOC data
  using current spine index. Update on chapter transitions.

- [x] **4.3 Bookmark toggle and `B` shortcut.** Add bookmark button
  (filled/unfilled 🔖) to top chrome. Also wire `B` keyboard shortcut and
  double-tap (when chrome visible) to toggle bookmark. Bookmarks are per-page
  markers stored in IndexedDB per book. Toggling adds/removes a bookmark at
  the current reading position. Store bookmarks as `{chapter, page,
  textSnippet, timestamp}`.

- [x] **4.4 Scrubber with chapter boundary ticks.** Make the bottom progress
  bar interactive — dragging scrubs through the book. Per spec wireframe:
  `●━━━━━━━━━━━━━━○──────────────` with chapter tick marks, percentage
  display, and synthetic page number (`Ch 4  42%  p.127`). Dragging shows a
  preview tooltip (hover on desktop); releasing navigates. Requires bridge
  touch/mouse drag events on the scrubber element.

- [x] **4.5 Bookmarks sub-view in TOC panel.** Per spec wireframe: TOC header
  shows bookmark count (`🔖 4`). Tapping it switches from Contents to
  Bookmarks view. Header changes to `✕  Bookmarks  Contents` (Contents link
  to switch back). Each bookmark shows chapter name, page number, and text
  snippet. Tap navigates to bookmark location.

- [ ] **4.6 Position stack.** Every navigation action (TOC jump, search
  result, annotation link, footnote) pushes current position onto a stack. A
  persistent "back" affordance pops the stack, returning to the exact prior
  position. Stack stored in reader state (not persisted across sessions).

- [ ] **4.7 Escape key hierarchy.** Escape key follows the UI stack: close
  footnote popup → close TOC/settings/search panel → hide chrome → return to
  library. Each press pops one layer. This is also the Android hardware back
  button behavior in the Capacitor shell.

- [ ] **4.8 E2e: reading chrome and navigation.** Verify chrome auto-hides
  after timeout and on page turn. Bookmark a page (tap or `B`), verify toggle
  state, check bookmark appears in TOC bookmarks sub-view, tap to navigate
  back. Interact with scrubber, verify chapter tick marks and drag-to-navigate.
  Test escape hierarchy: open search → Escape closes, toggle chrome → Escape
  hides, open TOC → Escape closes. Navigate via TOC jump, verify position
  stack back affordance returns to prior position.

---

## Phase 5 — Reading Position Persistence

- [ ] **5.1 Save position on visibilitychange.** Register a bridge-level
  `visibilitychange` listener. When the page becomes hidden (tab switch, app
  background), save current reading position to IndexedDB immediately. This
  covers app switching and crash recovery.

- [ ] **5.2 Save position on chapter transition.** Whenever the reader
  transitions to a new chapter, save the position. This is partially
  implemented (reader tracks chapter/page) but verify it persists to IDB.

- [ ] **5.3 Debounced save every 5 page turns.** Count page turns and save
  to IndexedDB every 5th turn. Use a counter in reader state, not a timer.

- [ ] **5.4 Character-offset position tracking.** Replace page-index-based
  position with character offset within the book's text content. This is
  stable across font size / viewport changes. Requires mapping page boundaries
  to character offsets during layout. Store character offset in IDB alongside
  chapter+page for backward compatibility. Used for position persistence,
  bookmark anchoring, and annotation addressing per spec.

- [ ] **5.5 E2e: position persistence.** Read to a position, reload page,
  verify reader resumes at saved position. Also test visibilitychange save.

---

## Phase 6 — CSS & Typography

- [ ] **6.1 Bundle Literata and Inter fonts.** Add Literata (serif) and Inter
  (sans-serif) as static assets in the PWA. Pull from Google Fonts and save in assets.
  Reference via `@font-face` in
  reader CSS. ~300–400 KB total per spec.

- [ ] **6.2 Typography settings panel.** Per spec wireframe: Aa button opens
  a bottom sheet (mobile) or popover (desktop, anchored near Aa button).
  Controls: Font selector (Literata / Inter / Publisher — tap to select),
  Size slider (smaller ↔ larger), Line spacing slider (tight ↔ loose),
  Margins slider (narrow ↔ wide), Theme selector (Auto / Light / Sepia /
  Dark — tap to select), "Reset to defaults" link at bottom. All changes
  apply immediately with live preview. Settings debounce-persisted to IDB.
  Dismiss via ✕, tap outside, or swipe down.

- [ ] **6.3 Provably correct theme data structures.** Each theme is a
  compile-time data structure with specific color values for every surface
  (background, text, accent, highlight, chrome, etc.). Color correctness is
  proven via dataprops encoding color theory invariants. No theme can be
  constructed without satisfying all proofs. Implementation:

  **Luminance model.** Relative luminance per WCAG/sRGB: linearize each
  channel (`C_lin = C_srgb / 12.92` for low values, gamma 2.4 curve
  otherwise), then `L = 2126 * R_lin + 7152 * G_lin + 722 * B_lin` (scaled
  to 0–10000 integers, coefficients sum to 10000). Precompute luminance for
  every color constant at definition site as a `stadef`.

  **Contrast ratio proof.** `CONTRAST_AA(L_hi, L_lo)` dataprop proving
  `(L_hi + 50) * 10 >= 45 * (L_lo + 50)` (WCAG AA ≥ 4.5:1 for body text).
  Every foreground/background pair in a theme must carry this proof. Dark
  themes additionally carry `CONTRAST_COMFORT(L_hi, L_lo)` proving
  `(L_hi + 50) * 10 <= 150 * (L_lo + 50)` (≤ 15:1 to prevent halation).

  **Polarity proof.** `LIGHT_POLARITY(bg, fg)` proves `bg >= 500; fg <= 180`
  (background perceptually light, text perceptually dark).
  `DARK_POLARITY(bg, fg)` proves `bg <= 50; fg >= 400`. Polarity must be
  consistent across ALL surface pairs within a theme — no inverted regions.

  **Sepia warmth proof.** `SEPIA_WARMTH(r, b)` proves the sRGB red channel
  exceeds blue by 15–50 units (`r - b >= 15; r - b <= 50`), encoding the
  warm tint without oversaturation.

  **Highlight sandwich proof.** `HIGHLIGHT_VALID(bg, fg, hl)` proves the
  highlight luminance sits between bg and fg with ≥ 3:1 contrast to each:
  `(L_bg + 50) * 10 >= 30 * (L_hl + 50)` AND
  `(L_hl + 50) * 10 >= 30 * (L_fg + 50)`. Guarantees highlighted text
  remains readable while the highlight is visible against the page.

  **Accent readable proof.** `ACCENT_READABLE(L_accent, L_bg)` proves
  accent/link colors meet AA contrast against their background surface.

  **Theme record.** Each theme is a flat record of `stadef` color constants
  with all proofs constructed at the definition site. If any color is changed,
  the proofs fail at compile time. Structure:
  ```
  bg, fg, accent, highlight, chrome_bg, chrome_fg, chrome_accent,
  link, selection, divider
  ```
  Each pair (e.g., `chrome_fg` on `chrome_bg`) carries its own
  `CONTRAST_AA` proof.

- [ ] **6.4 Auto theme.** Add "Auto" theme option that follows system
  `prefers-color-scheme`. Auto is the default on first launch. If user
  explicitly selects Light/Sepia/Dark, that overrides Auto. Requires bridge
  `matchMedia` listener for system theme changes. Auto resolves to one of
  the proven-correct theme records (Light or Dark) at runtime — the proof
  obligations are satisfied by the underlying concrete theme, not by Auto
  itself.

- [ ] **6.5 Three CSS modes.** Implement per-book CSS mode:
  (a) Publisher default — book's CSS applied as-is, embedded fonts loaded via
  blob URLs, user can still adjust font size.
  (b) Reader default — Quire's typography (Literata/Inter, configured spacing)
  overrides book CSS; publisher structural CSS (centering, poetry,
  text-align) preserved.
  (c) User custom — user's explicit font/size/spacing/margin override all.
  The Font selector in the typography panel drives this: selecting Literata or
  Inter → Reader default mode; selecting Publisher → Publisher mode. Store
  mode per book in library record.

- [ ] **6.6 Embedded font loading via blob URLs.** When rendering a chapter in
  Publisher CSS mode, extract font resources from IndexedDB, create blob URLs,
  inject `@font-face` rules pointing to blob URLs. Revoke URLs when chapter
  is unloaded.

- [ ] **6.7 Dark mode color inversion.** Publisher-specified colors (e.g.,
  colored text for dialogue attribution) are inverted in dark mode to maintain
  readability. Text and background colors are overridden; images are left
  untouched.

- [ ] **6.8 E2e: typography settings.** Open typography panel (Aa), verify
  font/size/spacing/margin controls, change font, verify live update, change
  theme to Auto/Light/Sepia/Dark, verify colors update.

---

## Phase 7 — Text Selection & Annotations

- [ ] **7.1 Text selection detection.** Detect browser-native text selection
  completion (long press on touch, click-drag on mouse). When selection exists,
  show a floating toolbar near the selection per spec wireframe:
  `│ 🖍 📝  📋  🔍  │` (Highlight, Note, Copy, Search for selection).
  Requires bridge event for selection change + range coordinates. Text
  selection cannot span a page boundary (spec-acknowledged limitation).

- [ ] **7.2 Highlight storage.** IndexedDB object store for annotations,
  separate from book content (per spec: "enabling independent export and
  survival across book re-imports"). Keyed by book content hash. Each
  annotation: EPUB CFI (primary anchor), highlighted text, surrounding context
  (few words before/after for fuzzy re-anchoring), optional note text, chapter
  title + index, creation timestamp.

- [ ] **7.3 Highlight rendering.** When pages enter the materialization
  window, look up annotations for the visible range. Render highlights as
  styled overlays (colored background spans). Index annotations by page range
  for efficient lookup on page turns.

- [ ] **7.4 Add/edit/delete notes on highlights.** Tap a highlight to open
  edit UI. Long-press context menu on highlight per spec wireframe: "Edit
  note", "Remove note" (keep highlight), "Delete highlight". Persist changes
  to IDB.

- [ ] **7.5 Annotations list panel.** Per spec wireframe: accessed from ⋯
  overflow menu in reading chrome. Mobile: full-screen overlay with header
  `✕  Annotations  Export`. Desktop: sidebar alongside reading content.
  Highlights grouped by chapter with chapter name as section header. Each
  highlight shows quoted text with colored left border accent (`▌`). Notes
  show 📝 icon + note text below. Tap navigates to highlight location.
  Empty state: "No annotations yet / Highlight text while reading to add
  your first annotation."

- [ ] **7.6 Annotation export to Markdown.** Export button in annotations
  panel header. Generate Markdown per spec format: `# Book Title`,
  `## Author Name`, `### Chapter Name`, `> Highlighted text`,
  `**Note:** User's note`, footer `*Exported from Quire · [date]*`.
  Download as `.md` file via bridge.

- [ ] **7.7 Annotation re-anchoring on re-import.** When a book is re-imported
  (same content hash), annotations survive automatically. If CFI fails to
  resolve (slightly different structure), fuzzy text matching using stored
  surrounding context recovers the annotation position.

- [ ] **7.8 E2e: annotations.** Select text in reader, highlight it, add
  note, verify highlight persists across page turns and reload, verify
  annotation list shows the highlight with note. Export to Markdown, verify
  file structure matches spec format.

---

## Phase 8 — Search

- [ ] **8.1 Search activation.** Three triggers per spec: 🔍 button in
  chrome, `Ctrl+F`/`Cmd+F` interception (prevent browser default — native
  find won't work with virtualized rendering), `/` keyboard shortcut. All
  open the search UI. Entering search pushes current position onto position
  stack.

- [ ] **8.2 Search UI.** Per spec wireframe: search bar slides down from top,
  replacing chrome header (mobile) or appearing as sidebar with dropdown
  results (desktop). Keyboard opens automatically. Book text visible but
  dimmed. Results appear as scrollable list as user types: chapter name + text
  snippet with match highlighted (`▊tortoise▊`). Result count shown
  ("7 results"). No-results state: "No matches found in this book."
  Keyboard shortcuts in search: Enter/↓ next result, Shift+Enter/↑ previous,
  Escape closes search.

- [ ] **8.3 Search execution.** Query the per-chapter plain text index in
  IndexedDB. Case-insensitive, diacritics-folded matching. Return results
  with chapter index, character offset, and surrounding sentence context
  snippet.

- [ ] **8.4 Search result navigation.** Tapping a result closes the list,
  navigates to the location, highlights the match in the rendered page.
  Enters result navigation mode per spec wireframe: bottom bar shows
  `◂  2 of 7  ▸` with arrows to cycle through results + ☰ button to
  reopen results list. Page turns work normally in this mode; ◂/▸ always
  jump to next/prev result regardless of current page. ✕ closes search and
  returns to reading position before search was opened (position stack).

- [ ] **8.5 E2e: search.** Open reader, activate search (🔍 or `/` or
  Ctrl+F), type query, verify results list with chapter names and highlighted
  snippets, tap result, verify navigation + result navigation bar with ◂/▸
  and count.

---

## Phase 9 — Footnotes & Links

- [ ] **9.1 Footnote popup.** Intercept links with `epub:type="noteref"`.
  Instead of navigating, show a popup near the reference per spec wireframe:
  bordered box with footnote content, ✕ dismiss button. Long footnotes scroll
  internally within the popup. Dismiss via ✕ or tap outside. Push position
  onto position stack. On touch: footnote link tap shows popup. On desktop:
  hover on footnote link changes cursor to indicate popup behavior.

- [ ] **9.2 External link handling.** Links pointing outside the EPUB
  (http/https) open in a new browser tab. Internal cross-chapter links
  navigate within the reader and push onto position stack.

- [ ] **9.3 E2e: footnotes.** Open EPUB with footnotes, tap noteref link,
  verify popup appears with footnote content, verify ✕ dismisses.

---

## Phase 10 — Accessibility

- [ ] **10.1 ARIA on app chrome.** Add ARIA roles and labels to library UI
  (list, listitem, button labels for ⊕/⚙/▼), settings modal, import
  controls, shelf filter, context menu. Ensure keyboard-navigable.

- [ ] **10.2 ARIA on reading chrome.** Label reading chrome buttons (close,
  bookmark, TOC, typography, search, overflow). Add roles to TOC panel,
  scrubber (slider role), annotations panel, search panel.

- [ ] **10.3 Screen reader page-turn announcements.** Use ARIA live region
  to announce page changes (e.g., "Page 5 of 12, Chapter 3"). Announce
  chapter transitions.

- [ ] **10.4 Focus management.** Ensure screen readers navigate smoothly
  between app UI and book content. No focus traps. When TOC/settings/search
  panels open, focus moves into them; on close, focus returns to prior
  element. Pinch-to-zoom is not intercepted (browser accessibility feature).

---

## Phase 11 — Wide tables & images

- [ ] **11.1 Wide table horizontal scroll.** Tables exceeding viewport width
  get `overflow-x: auto` wrapper. No scaling or reformatting. CSS-only fix
  applied during chapter rendering.

- [ ] **11.2 Images scaled to viewport width.** Ensure images in chapter
  content are constrained to `max-width: 100%`. Per spec: "Scaled to fit
  viewport width for v1."

---

## Phase 12 — Mobile: Capacitor Android Build

- [ ] **12.1 Add Capacitor.** `npm install @capacitor/core @capacitor/android`,
  `npx cap init` with app name "Quire" and bundle ID. Add `capacitor.config.ts`
  pointing `webDir` at the PWA root (`.`). Run `npx cap add android` to
  scaffold the `android/` directory.

- [ ] **12.2 Android project configuration.** Set `minSdkVersion 24` (Android
  7.0+, WebView with WASM support). Configure `AndroidManifest.xml`:
  `INTERNET` permission, `android:usesCleartextTraffic="false"`, portrait +
  landscape orientation. Set app icon and splash screen assets.

- [ ] **12.3 Capacitor plugins.** Add `@capacitor/status-bar` (immersive
  reading mode), `@capacitor/keyboard` (search input focus management),
  `@capacitor/app` (hardware back button → Escape key hierarchy from 4.7).
  Wire hardware back button to the same escape dispatch already implemented
  in WASM.

- [ ] **12.4 CI: build Android APK.** Add `.github/workflows/android.yml`:
  checkout, setup-node 20, setup-java temurin 17, cache Gradle, `npm ci`,
  build WASM + assets, `npx cap sync android`, `./gradlew assembleDebug`.
  Upload debug APK as artifact. Optionally build signed release APK when
  keystore secrets are configured (base64-decode keystore, pass signing
  properties to `assembleRelease`, upload release APK).

- [ ] **12.5 E2e: verify Android build artifact.** CI step after APK build:
  assert the debug APK exists and is > 0 bytes. (Full device testing is
  manual for v1.)

---

## Ordering Notes

Phases are roughly dependency-ordered:
- **Phase 1** must come first (identity + storage changes touch everything)
- **Phase 2** depends on Phase 1 (import uses new identity/storage)
- **Phases 3–4** depend on 1–2 (library UI needs new metadata; chrome needs
  TOC data)
- **Phase 5** is independent, can be parallelized with 3–4
- **Phase 6** is independent, can be parallelized with 3–5
- **Phase 7** depends on Phase 1 (annotations keyed by content hash) and
  Phase 5.4 (character-offset addressing)
- **Phase 8** depends on Phase 2.2 (search index)
- **Phase 9** is mostly independent (only needs position stack from 4.6)
- **Phase 10** should be done after the UI it annotates exists
- **Phase 11** is independent CSS work, can be done anytime
- **Phase 12** depends on Phase 4.7 (escape/back button hierarchy) but the
  build scaffolding can start anytime
