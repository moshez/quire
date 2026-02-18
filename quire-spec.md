# Quire — ePub Reader Specification

## Overview

Quire is a serverless, offline-first ePub reader built as a PWA. It supports ePub format only (ePub 2 full support, ePub 3 structural features, no embedded media or scripting). No accounts, no sync, no DRM. All state lives on-device in IndexedDB. Mobile apps are the PWA wrapped in minimal Capacitor shell.

---

## Architecture

### Rendering Pipeline

The browser's HTML parser is used to parse ePub XHTML into a DOM tree via an invisible node. The parsed XML tree is stored internally per chapter. Content is rendered into real DOM elements on demand, with pagination computed by measuring content against the viewport.

A sliding window of pages is materialized: the current page plus surrounding pages. Pages outside the window are replaced by spacers with cached dimensions. This bounds DOM size regardless of chapter length while enabling smooth page transitions.

Page boundaries are computed during an initial layout pass at chapter load. These breakpoints are cached for the lifetime of the chapter view.

### Viewport Management

Content is laid out in a container wider than the viewport. Pages are viewport-width slices. Page turns are CSS transform offsets within this container. Adjacent pages are already laid out, giving instant transitions.

**Two-column mode:** Activated above 768px viewport width. Each "page turn" advances two columns (one spread). Progress tracking counts spreads. Reading position is stored as the left column's position for consistent behavior when switching between single and two-column layouts.

### Storage

All persistence uses IndexedDB:

- **Book content:** ePubs are exploded into individual resources (XHTML, images, CSS, fonts) for efficient per-resource access during rendering without full-archive decompression.
- **Annotations:** Separate object store from book content, enabling independent export and survival across book re-imports.
- **Reading positions:** Lightweight key-value entries per book.
- **Preferences:** Global settings (theme, font, sizes) and per-book overrides.
- **Search index:** Plain text per chapter with character offset mapping back to XML tree positions, built at import time.

Resource URLs are served via blob URLs generated in the main thread. The service worker handles PWA shell caching only.

**Storage quota:** Browsers allocate a fraction of available disk space. Typical ePubs are 1–5 MB; illustrated nonfiction can reach 50–100 MB. The app surfaces storage usage in settings. The archive feature (see Library) allows reclaiming space while preserving metadata and annotations.

### Book Identity

Books are identified by content hash (hash of the ePub file). This is used to reconnect annotations when a book is deleted and re-imported. Duplicate detection at import time uses this hash.

### ePub Compatibility

**ePub 2:** Full support. NCX table of contents, OPF spine and manifest, XHTML content documents, embedded CSS and fonts.

**ePub 3:** Structural support — nav document (used as TOC), spine, manifest. No support for embedded audio/video, JavaScript in content documents, or media overlays. ePub 3 nav document is preferred over NCX when both are present.

**CSS handling — three modes:**

1. **Publisher default:** The book's embedded CSS is applied as-is. Embedded fonts are loaded via blob URLs. User can still adjust font size.
2. **Reader default:** Quire's typography choices (Literata/Inter, configured spacing and margins) override the book's CSS. Publisher structural CSS (centering, poetry blocks, text-align on specific elements) is preserved.
3. **User custom:** The user's explicit font, size, spacing, and margin choices override everything.

The mode is selectable per-book and persisted.

### Bundled Fonts

Two fonts are bundled with the PWA (pulled from Google Fonts at build time, not loaded at runtime):

- **Literata** — serif, designed for long-form reading (used by Google Play Books)
- **Inter** — sans-serif, excellent screen legibility

Total addition: ~300–400 KB to PWA size.

### Accessibility

ePub semantic structure (headings, landmarks, reading order) is preserved in rendered output. App chrome (library, settings, overlays) follows ARIA standards. Screen reader page-turn announcements use ARIA live regions. Focus management ensures screen readers navigate smoothly between app UI and book content without focus traps.

---

## Library

### Shelves

Books exist in one of three states:

- **Active** — on the main shelf, fully available. Default state after import.
- **Hidden** — on the hidden shelf. Full content retained, just removed from the default view. For books you don't want cluttering the main shelf but aren't ready to archive.
- **Archived** — on the archived shelf. Content is deleted from IndexedDB; metadata, annotations, reading position, and cover thumbnail are retained. Re-importing the same book (matched by content hash) restores it to active with annotations reconnected.

### Library View

List layout (grid deferred to later version). Each row shows: cover thumbnail, title, author, progress bar with percentage. Unstarted books show "New." Finished books show "Done."

**Top bar:** App name, import button (⊕), settings gear (⚙), sort dropdown (▼).

**Sort options:** Last opened (default), title, author, date added.

**Shelf switching:** Popover filter accessed from the top bar. Active shelf is default. Hidden and archived shelves show the same list layout with contextually appropriate actions.

**Context menu** (long-press on mobile, right-click on desktop): Book info, Hide, Archive, Delete. Actions vary by current shelf (e.g., Unhide on hidden shelf, Unarchive on archived shelf).

**Empty state:** Central import prompt with "Import an ePub" button and "or drag and drop here" hint on desktop. Disappears after first book is imported.

### Book Info View

Accessed from context menu. Shows: large cover image, title, author, progress (percentage and chapter), date added, last read date, file size. Action buttons for Hide, Archive, Delete.

---

## Import

### Entry Points

- **⊕ button** in library top bar → opens native file picker filtered to `.epub`
- **Drag and drop** on desktop → entire library area is a drop target (dashed border appears on dragover)
- **"Open with"** registration via Capacitor (nice-to-have)

### Process

1. Validate: confirm file is a valid zip with OPF. **Reject malformed files** with a clear error message. No partial import — the book either imports fully or not at all.
2. Parse OPF: extract metadata (title, author, identifier), spine, manifest.
3. Extract and store: explode all resources into IndexedDB.
4. Build search index: extract plain text per chapter, store with character offset mapping.
5. Extract cover image and generate thumbnail.

The importing book appears at the top of the library list immediately with a progress indicator. The rest of the library remains interactive during import.

### Error Handling

Malformed files are rejected with a dismissible error banner showing the filename and a brief explanation. The message mentions DRM since that's the most common reason a valid `.epub` won't open: "Quire supports .epub files without DRM."

### Duplicate Detection

If the content hash matches an existing book (any shelf state), the user is prompted: "Skip" (cancel import) or "Replace" (swap content, preserve annotations and reading position). Annotations are re-anchored by CFI plus surrounding text context.

---

## Reading View

### Default State

Text only. No chrome, no UI elements, no distractions. The user sees a page of a book and nothing else.

### Tap Zones (invisible)

- **Left third** of screen → page back
- **Right third** of screen → page forward
- **Center third** of screen → toggle chrome

### Chrome (toggled by center tap)

**Top bar:** Close button (✕, returns to library), chapter title, bookmark toggle (🔖, filled/unfilled).

**Bottom bar:** Action buttons (☰ TOC, Aa typography, 🔍 search, ⋯ overflow menu). Below: scrubber track with chapter boundary tick marks, draggable position indicator, percentage display, synthetic page number.

Chrome auto-hides after a timeout or on the next page turn.

### Page Turning

- **Touch:** Tap left/right zones. Swipe left (forward) / swipe right (back) with minimum horizontal distance threshold to avoid conflict with text selection.
- **Mouse:** Click left/right zones. Scroll wheel down → forward, scroll wheel up → back.
- **Keyboard:** Right arrow, space, Page Down → forward. Left arrow, Shift+space, Page Up → back.

### Text Selection and Highlighting

Long press (touch) or click-drag (mouse) initiates browser-native text selection. Once text is selected, a floating toolbar appears near the selection with actions: highlight, add note, copy, search for selection.

Text selection cannot span a page boundary (known limitation of the virtualized rendering).

Highlights are rendered as styled overlays applied when pages enter the materialization window. Annotation data is indexed by page range for efficient lookup on page turns.

### Footnotes

Links with `epub:type="noteref"` are intercepted. Instead of navigating to the footnote location, a popup appears near the reference showing the footnote content. Long footnotes scroll internally within the popup. Dismissed by tapping ✕ or tapping outside.

### External Links

Opened in a new browser tab.

### Images

Scaled to fit viewport width for v1. Tap-to-zoom deferred to a later version.

### Tables

Wide tables that exceed viewport width get horizontal scroll. No scaling or reformatting.

### RTL and Vertical Text

Not supported in v1. Deferred — requires page turn direction reversal and significant layout work. No architectural decisions should preclude adding this later.

---

## Navigation

### Table of Contents

Opened via ☰ button in the reading chrome.

**Mobile:** Full-screen overlay, slides in from the left.

**Desktop:** Sidebar that overlays or pushes the reading content.

Shows the book's TOC hierarchy with nested entries indented. Current chapter is visually marked. Chapter entries show a synthetic page number on the right for scale. Part/section headings are non-tappable labels.

The panel opens scrolled to show the current chapter in view, not at the top.

Tapping a chapter navigates there and closes the panel (mobile) or navigates in-place (desktop sidebar).

**Bookmarks sub-view:** Toggled via a bookmark count indicator in the TOC header. Shows all bookmarks with chapter, page, and a text snippet. Tap navigates to that location.

### Position Stack

Every navigation action (TOC jump, search result, annotation link, footnote) pushes the current reading position onto a stack. A persistent "back" affordance pops the stack, returning to the exact prior position. This ensures no feature can strand the user away from where they were reading.

### Scrubber

The progress bar in the bottom chrome is interactive. Dragging the position indicator scrubs through the book. On Kobo-style interaction: dragging shows a preview of the target location. Releasing navigates there. Chapter boundaries are shown as tick marks on the track.

---

## Progress Tracking

### Internal Representation

Progress is tracked by character offset within the book's text content — a stable metric independent of font size, screen dimensions, or layout settings. This is used for position persistence, bookmark anchoring, and annotation addressing.

### User-Facing Display

- **Percentage** of the book completed (primary display in scrubber)
- **Chapter-relative progress** (shown in chrome: "Ch 4" or chapter title)
- **Synthetic page number** (based on current layout, shown in scrubber)

No Kindle-style location numbers. Synthetic page numbers are understood to change with display settings — they're a convenience, not a stable reference.

### Reading Position Persistence

Position is saved to IndexedDB:

- On `visibilitychange` (tab hidden, app backgrounded)
- On chapter transitions
- Debounced every 5 page turns

This covers normal reading, app switching, and crash recovery.

---

## Annotations

### Highlight Storage

Annotations are stored in a separate IndexedDB object store per book, keyed by book content hash.

Each annotation contains:

- **EPUB CFI** — primary anchor into the document structure
- **Highlighted text** — the selected text content
- **Surrounding context** — a few words before and after, for fuzzy re-anchoring if CFI fails
- **Note text** — optional user-written note
- **Chapter reference** — chapter title and index
- **Timestamp** — creation date

### Annotation Anchoring

EPUB CFI (Canonical Fragment Identifier) is the primary addressing scheme. CFIs are XPath-like references that identify specific character positions within the ePub's XML structure: `epubcfi(/6/4[chap01ref]!/4[body01]/10[para05]/3:10)`.

The highlighted text and surrounding context serve as fallback anchors. If a CFI fails to resolve (e.g., after a book re-import with slightly different structure), fuzzy text matching using the stored context recovers the annotation position.

### Annotations List

Accessed from the ⋯ overflow menu in reading chrome.

**Mobile:** Full-screen overlay.

**Desktop:** Sidebar alongside reading content.

Highlights are grouped by chapter. Each highlight shows the quoted text with a colored left border accent. Highlights with notes show a 📝 icon and the note text below. Tap navigates to the highlight location.

Long-press on a highlight opens a context menu: edit note, remove note (keep highlight), delete highlight.

Export button in the header generates a Markdown file.

### Annotation Export

Produces a Markdown file structured as:

```
# Book Title
## Author Name

### Chapter Name

> Highlighted text

**Note:** User's note

---
*Exported from Quire · [date]*
```

Clean, readable, works in any Markdown viewer or as plain text.

---

## Search

### Indexing

Full-text search index is built at import time. Plain text is extracted per chapter and stored in IndexedDB with character offset mappings back to positions in the parsed XML tree. Diacritics are folded (searching "resume" matches "résumé"). Search is case-insensitive.

### Activation

- 🔍 button in reading chrome
- `Ctrl+F` / `Cmd+F` intercepted (browser-native find won't work with virtualized rendering)
- `/` keyboard shortcut

### Scope

v1: Search within the current book across all chapters. Cross-library search deferred but the IndexedDB schema supports adding it later.

### UI Flow

1. **Entry:** Search bar slides down from top, replacing chrome header. Keyboard opens automatically. Book text visible but dimmed.
2. **Results:** Appear as a scrollable list as the user types. Each result shows chapter name and a text snippet with match highlighted, with surrounding sentence context.
3. **Navigation:** Tapping a result closes the list, navigates to the location, and enters result navigation mode: a bottom bar shows "N of M results" with ◂/▸ arrows to cycle through results. The match is highlighted in the rendered page.
4. **Reading around results:** Page turns work normally in navigation mode. ◂/▸ always jump to the next/previous result regardless of current page.
5. **Exit:** ✕ closes search and returns to reading position before search was opened (position stack behavior).

### Keyboard Shortcuts in Search

- `Enter` or `↓` → next result
- `Shift+Enter` or `↑` → previous result
- `Escape` → close search, return to reading position

---

## Typography and Theme Settings

### Access

Aa button in reading chrome opens a bottom sheet (mobile) or popover (desktop).

### Controls

- **Font:** Literata (serif), Inter (sans-serif), Publisher (book's embedded fonts/CSS). Tap to select.
- **Size:** Continuous slider, smaller to larger.
- **Line spacing:** Continuous slider, tight to loose.
- **Margins:** Continuous slider, narrow to wide.
- **Theme:** Auto (follows system `prefers-color-scheme`), Light, Sepia, Dark.
- **Reset to defaults:** Text link at the bottom of the panel.

### Behavior

All changes apply immediately — no apply/cancel. The reading view updates live as the user adjusts settings. Settings are persisted to IndexedDB on change (debounced). Dismissing the panel (✕, tap outside, swipe down) leaves settings as-is.

### Theme Implementation

Auto theme follows system `prefers-color-scheme` on first launch. If the user explicitly selects a theme, the choice overrides auto. Theme changes selectively override text and background colors while leaving images untouched. Publisher-specified colors (e.g., colored text for dialogue attribution) are inverted in dark mode to maintain readability.

---

## Gesture and Input Vocabulary

### Touch

| Gesture | Action |
|---|---|
| Tap left third | Page back |
| Tap right third | Page forward |
| Tap center third | Toggle chrome |
| Swipe left | Page forward |
| Swipe right | Page back |
| Long press + drag | Text selection (browser native) |
| Tap footnote link | Footnote popup |
| Tap external link | Open in new tab |
| Double-tap (when chrome visible) | Bookmark current page |

### Mouse

| Input | Action |
|---|---|
| Click left/right/center zones | Same as tap zones |
| Scroll wheel down | Page forward |
| Scroll wheel up | Page back |
| Click-drag | Text selection |
| Right-click | Browser context menu (not intercepted) |
| Hover on footnote link | Cursor change indicating popup behavior |
| Hover on scrubber | Preview tooltip |

### Keyboard

| Key | Action |
|---|---|
| →, Space, Page Down | Page forward |
| ←, Shift+Space, Page Up | Page back |
| Escape | Toggle chrome / close panel / return to library |
| / or Ctrl+F | Open search |
| B | Toggle bookmark |

### Hybrid Devices

Touch and mouse input sets are both active simultaneously. Custom gesture detection uses pointer events to handle both correctly.

### Gestures Not Mapped

Pinch-to-zoom is not intercepted. Browser-native pinch zoom works as an accessibility feature. Font size changes live in the typography settings panel.

---

## Android Back Button

In the Capacitor shell, the hardware back button walks backwards through the UI stack:

1. Footnote popup open → close popup
2. TOC/settings/search panel open → close panel
3. Chrome visible → hide chrome
4. Reading view, nothing open → return to library
5. Library → minimize app (Capacitor default)

Each press pops one layer.

---

## Data Backup

### Export

Produces a single JSON file containing: library metadata (titles, authors, content hashes), all annotations, reading positions, shelf assignments, and user preferences. Does **not** include actual ePub file content (which the user has separately).

### Import

Reads the JSON file and restores all state. If a book referenced in the backup is not currently in the library, annotations and metadata are kept as orphaned records. They reconnect automatically if the book is later re-imported (matched by content hash).

---

## DRM

Not supported. Explicitly and deliberately. Quire opens unencrypted ePub files only. This is a feature: it means the reader works with any DRM-free ePub from any source without vendor lock-in.

---

## Deferred Features (Not v1)

- Grid view in library
- Image tap-to-zoom
- Multi-color highlights
- Cross-library search
- RTL and vertical text
- Reading speed estimation / time remaining
- Reading goals and statistics
- Pinch-to-zoom font size adjustment
- "Open with" OS registration
- Data backup (export/import) — designed for, built later

---

## Appendix: Wireframes

### Reading View — Default (Text Only)

```
┌─────────────────────────────────┐
│                                 │
│                                 │
│   Lorem ipsum dolor sit amet,   │
│   consectetur adipiscing elit.  │
│   Sed do eiusmod tempor         │
│   incididunt ut labore et       │
│   dolore magna aliqua. Ut enim  │
│   ad minim veniam, quis         │
│   nostrud exercitation ullamco   │
│   laboris nisi ut aliquip ex    │
│   ea commodo consequat.         │
│                                 │
│   Duis aute irure dolor in      │
│   reprehenderit in voluptate    │
│   velit esse cillum dolore eu   │
│   fugiat nulla pariatur.        │
│                                 │
│                                 │
│                                 │
│ ◂ tap          tap          tap ▸│
│  zone          zone         zone│
│  back         center        fwd │
└─────────────────────────────────┘
```

### Reading View — Chrome Visible (Center Tap)

```
┌─────────────────────────────────┐
│ ✕  Chapter 4: The Garden    🔖 │
│─────────────────────────────────│
│                                 │
│   Lorem ipsum dolor sit amet,   │
│   consectetur adipiscing elit.  │
│   Sed do eiusmod tempor         │
│   incididunt ut labore et       │
│   dolore magna aliqua. Ut enim  │
│   ad minim veniam, quis         │
│   nostrud exercitation ullamco   │
│   laboris nisi ut aliquip ex    │
│   ea commodo consequat.         │
│                                 │
│   Duis aute irure dolor in      │
│   reprehenderit in voluptate    │
│   velit esse cillum dolore eu   │
│   fugiat nulla pariatur.        │
│                                 │
│─────────────────────────────────│
│  ☰  TOC    Aa    🔍    ⋯      │
│  ●━━━━━━━━━━━━━━○──────────────│
│  Ch 4            42%    p.127   │
└─────────────────────────────────┘
```

### Reading View — Text Selection

```
┌─────────────────────────────────┐
│                                 │
│   Lorem ipsum dolor sit amet,   │
│   consectetur adipiscing elit.  │
│   ██████████████████████████    │
│   ██████████████████ labore et  │
│   dolore magna aliqua. Ut enim  │
│                                 │
│        ┌──────────────────┐     │
│        │ 🖍 📝  📋  🔍  │     │
│        └──────────────────┘     │
│                                 │
└─────────────────────────────────┘
```

### Reading View — Footnote Popup

```
┌─────────────────────────────────┐
│                                 │
│   established by Gauss in       │
│   his 1801 work.¹               │
│                                 │
│   ┌───────────────────────────┐ │
│   │ ¹ Disquisitiones          │ │
│   │ Arithmeticae, published   │ │
│   │ in Leipzig. See also      │ │
│   │ the discussion in ch. 7.  │ │
│   │                       ✕   │ │
│   └───────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### Reading View — Desktop Two-Column with TOC Sidebar

```
┌──────────────┬──────────────────────────────────────────┐
│ ✕ Contents   │                                          │
│──────────────│  Lorem ipsum dolor   Duis aute irure     │
│              │  sit amet, consect   dolor in reprehen   │
│ Preface    3 │  adipiscing elit.    derit in voluptat   │
│ Part I       │  Sed do eiusmod      velit esse cillum   │
│  1. Intro 12 │  tempor incididunt   dolore eu fugiat    │
│  2. Mean  28 │  ut labore et        nulla pariatur.     │
│  3. Figu  51 │  dolore magna        Excepteur sint      │
│ Part II      │  aliqua. Ut enim     occaecat cupidat    │
│► 4. Cons ●85│  ad minim veniam,    non proident, su    │
│  5. Recu 104│  quis nostrud        nt in culpa qui     │
│  6. Loca 131│  exercitation        officia deserunt    │
│  7. Prop 158│  ullamco laboris     mollit anim id      │
│  8. Typo 187│  nisi ut aliquip     est laborum.        │
│  9. Mumo 220│  ex ea commodo                           │
│              │  consequat.                              │
│              │                                          │
│              │──────────────────────────────────────────│
│              │  ●━━━━━━━━━━━━━━○──── 42%    p.91       │
└──────────────┴──────────────────────────────────────────┘
```

### Library — Active Shelf

```
┌─────────────────────────────────┐
│ Quire                 ⊕  ⚙  ▼ │
│─────────────────────────────────│
│                                 │
│ ┌───┐ The Left Hand of Dark..  │
│ │   │ Ursula K. Le Guin         │
│ │ ▓ │ ━━━━━━━━━○── 68%         │
│ └───┘                           │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│ ┌───┐ Gödel, Escher, Bach      │
│ │   │ Douglas Hofstadter        │
│ │ ▓ │ ━━○──────── 22%          │
│ └───┘                           │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│ ┌───┐ Erta Ale                  │
│ │   │ Moshe Zadka               │
│ │   │ New                       │
│ └───┘                           │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│ ┌───┐ Annihilation              │
│ │   │ Jeff VanderMeer           │
│ │ ▓ │ ━━━━━━━━━━━━━━━━━━━ Done │
│ └───┘                           │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Library — Context Menu (Long-Press / Right-Click)

```
│ ┌───┐ Gödel, Escher, Bach      │
│ │   │ Douglas Hofstadter        │
│ │ ▓ │ ━━○──────── 22%          │
│ └───┘                           │
│ ┌─────────────────────────────┐ │
│ │  Book info                  │ │
│ │  Hide                       │ │
│ │  Archive                    │ │
│ │  Delete                     │ │
│ └─────────────────────────────┘ │
```

### Library — Shelf Filter

```
│ Quire            ⊕  ⚙  ▼ │
│  ┌──────────────────┐      │
│  │ ● Active          │      │
│  │ ○ Hidden          │      │
│  │ ○ Archived        │      │
│  └──────────────────┘      │
```

### Library — Empty State (First Launch)

```
┌─────────────────────────────────┐
│ Quire                 ⊕  ⚙  ▼ │
│─────────────────────────────────│
│                                 │
│                                 │
│                                 │
│                                 │
│          ┌─────────┐            │
│          │  ⊕      │            │
│          │         │            │
│          │ Import  │            │
│          │ an ePub │            │
│          └─────────┘            │
│                                 │
│      or drag and drop here      │
│         (on desktop)            │
│                                 │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Book Info View

```
┌─────────────────────────────────┐
│ ← Back                          │
│─────────────────────────────────│
│                                 │
│        ┌───────────┐            │
│        │           │            │
│        │           │            │
│        │   cover   │            │
│        │           │            │
│        │           │            │
│        └───────────┘            │
│                                 │
│  Gödel, Escher, Bach            │
│  Douglas Hofstadter              │
│                                 │
│  Progress    22% · Ch 5 of 20   │
│  Added       Jan 14, 2026       │
│  Last read   Feb 16, 2026       │
│  Size        4.2 MB             │
│                                 │
│  ┌──────┐ ┌──────┐ ┌────────┐  │
│  │ Hide │ │Archiv│ │ Delete │  │
│  └──────┘ └──────┘ └────────┘  │
└─────────────────────────────────┘
```

### TOC Panel — Mobile

```
┌─────────────────────────────────┐
│ ✕  Contents              🔖 4  │
│─────────────────────────────────│
│                                 │
│  Preface                     3  │
│  Part I: Overview               │
│    1. Introduction          12  │
│    2. Meaning and Form      28  │
│    3. Figure and Ground     51  │
│  Part II: EGB                   │
│  ► 4. Consistency          ●85  │
│    5. Recursive Structures 104  │
│    6. The Location of       131  │
│       Meaning                   │
│    7. The Propositional     158  │
│       Calculus                  │
│    8. Typographical Number  187  │
│       Theory                    │
│    9. Mumon and Gödel       220  │
│  Part III: ...                  │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### TOC Panel — Bookmarks Sub-View

```
┌─────────────────────────────────┐
│ ✕  Bookmarks         Contents  │
│─────────────────────────────────│
│                                 │
│  Ch 4: Consistency              │
│  p. 91  "The tortoise smiled.." │
│                                 │
│  Ch 8: Typographical Number..   │
│  p. 194                         │
│                                 │
│  Ch 12: Minds and Thoughts      │
│  p. 340                         │
│                                 │
│  Ch 17: Church, Turing, Tar..   │
│  p. 512                         │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Annotations List — Mobile

```
┌─────────────────────────────────┐
│ ✕  Annotations           Export │
│─────────────────────────────────│
│                                 │
│ Ch 2: Meaning and Form          │
│                                 │
│  ▌"The formal system           │
│  ▌ known as TNT is rich        │
│  ▌ enough to represent all"    │
│                                 │
│  ▌"Isomorphism is at the       │
│  ▌ heart of meaning"           │
│  ▌ 📝 This connects to the    │
│  ▌    Saussure stuff           │
│                                 │
│ Ch 4: Consistency               │
│                                 │
│  ▌"What the tortoise said      │
│  ▌ to Achilles amounts to a    │
│  ▌ demand for justification"   │
│                                 │
│ Ch 8: Typographical Number..    │
│                                 │
│  ▌"You can't get at the        │
│  ▌ meaning of a formal         │
│  ▌ system from inside it"      │
│  ▌ 📝 Reminds me of the       │
│  ▌    halting problem          │
│                                 │
└─────────────────────────────────┘
```

### Annotations — Context Menu (Long-Press)

```
│  ▌"Isomorphism is at the       │
│  ▌ heart of meaning"           │
│  ▌ 📝 This connects to the    │
│  ▌    Saussure stuff           │
│  ┌─────────────────────────┐   │
│  │  Edit note               │   │
│  │  Remove note             │   │
│  │  Delete highlight        │   │
│  └─────────────────────────┘   │
```

### Annotations — Empty State

```
┌─────────────────────────────────┐
│ ✕  Annotations           Export │
│─────────────────────────────────│
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│        No annotations yet       │
│                                 │
│     Highlight text while        │
│     reading to add your         │
│     first annotation            │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Annotations — Desktop Sidebar

```
┌────────────────────────────────────────────┬──────────────┐
│                                            │✕ Annotations │
│  Lorem ipsum dolor   Duis aute irure       │       Export │
│  sit amet, consect   dolor in reprehen     │──────────────│
│  adipiscing elit.    derit in voluptat     │              │
│  Sed do eiusmod      velit esse cillum     │Ch 2: Meaning │
│  tempor incididunt   dolore eu fugiat      │              │
│  ut labore et        nulla pariatur.       │ ▌"The formal │
│  dolore magna        Excepteur sint        │ ▌ system.."  │
│  aliqua. Ut enim     occaecat cupidat     │              │
│  ad minim veniam,    non proident, su      │ ▌"Isomorph.. │
│  quis nostrud        nt in culpa qui       │ ▌ 📝 Saussu..│
│  exercitation        officia deserunt      │              │
│  ullamco laboris     mollit anim id        │Ch 4: Consis  │
│  nisi ut aliquip     est laborum.          │              │
│  ex ea commodo                             │ ▌"What the.. │
│  consequat.                                │              │
│                                            │              │
│────────────────────────────────────────────│              │
│  ●━━━━━━━━━━━━━━○──── 42%    p.91         │              │
└────────────────────────────────────────────┴──────────────┘
```

### Typography / Theme Settings — Mobile (Bottom Sheet)

```
┌─────────────────────────────────┐
│                                 │
│   Lorem ipsum dolor sit amet,   │
│   consectetur adipiscing elit.  │
│   Sed do eiusmod tempor         │
│   incididunt ut labore et       │
│                                 │
│─────────────────────────────────│
│                          ✕      │
│                                 │
│  Font                           │
│  ┌────────┐┌────────┐┌───────┐ │
│  │Literata││  Inter  ││Publis.│ │
│  │ ●      ││        ││       │ │
│  └────────┘└────────┘└───────┘ │
│                                 │
│  Size                           │
│   A─────────━━━━━━━●━━───────A  │
│  smaller                 larger │
│                                 │
│  Spacing                        │
│   ≡─────────━━━━●━━━━───────≡   │
│  tight                   loose  │
│                                 │
│  Margins                        │
│   ┤──────────━━●━━━━━────────├  │
│  narrow                   wide  │
│                                 │
│  Theme                          │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐  │
│  │ ○  │ │ ○  │ │ ○  │ │ ○  │  │
│  │Auto│ │Lite│ │Sepi│ │Dark│  │
│  └────┘ └────┘ └────┘ └────┘  │
│                                 │
│          Reset to defaults      │
│                                 │
└─────────────────────────────────┘
```

### Typography / Theme Settings — Desktop Popover

```
│                                            │
│  Lorem ipsum dolor   Duis aute irure       │
│  sit amet, consect   dolor in reprehen     │
│  adipiscing elit.    derit in voluptat     │
│  Sed do eiusmod      velit esse cillum     │
│                                            │
│                      ┌──────────────────┐  │
│                      │             ✕    │  │
│                      │ Font             │  │
│                      │ Literata Inter Pub│  │
│                      │ ●               │  │
│                      │                  │  │
│                      │ Size             │  │
│                      │ A━━━━━━●━━━━━━A  │  │
│                      │                  │  │
│                      │ Spacing          │  │
│                      │ ≡━━━━●━━━━━━━≡   │  │
│                      │                  │  │
│                      │ Margins          │  │
│                      │ ┤━━━●━━━━━━━━├   │  │
│                      │                  │  │
│                      │ Theme            │  │
│                      │ Auto Lt Sep Dk   │  │
│                      └──────────────────┘  │
│────────────────────────────────────────────│
│  ☰  TOC    Aa    🔍    ⋯                  │
│  ●━━━━━━━━━━━━━━○──────────────            │
```

### Search — Entry State

```
┌─────────────────────────────────┐
│ ┌─────────────────────────┐ ✕  │
│ │ Search...            🔍 │    │
│ └─────────────────────────┘    │
│─────────────────────────────────│
│                                 │
│   Lorem ipsum dolor sit amet,   │
│   consectetur adipiscing elit.  │
│   Sed do eiusmod tempor         │
│   incididunt ut labore et       │
│   dolore magna aliqua. Ut enim  │
│   ad minim veniam, quis         │
│   nostrud exercitation ullamco   │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Search — Results List

```
┌─────────────────────────────────┐
│ ┌─────────────────────────┐ ✕  │
│ │ tortoise             🔍 │    │
│ └─────────────────────────┘    │
│  7 results                      │
│─────────────────────────────────│
│                                 │
│  Ch 1: Introduction             │
│  ...what the ▊tortoise▊ said   │
│  to Achilles was not unlike...  │
│                                 │
│  Ch 4: Consistency              │
│  ...the ▊tortoise▊ smiled      │
│  and produced another rule...   │
│                                 │
│  Ch 4: Consistency              │
│  ...but the ▊tortoise▊ was     │
│  not finished. "And what if     │
│  I refuse this rule too?"...    │
│                                 │
│  Ch 7: The Propositional...     │
│  ...Carroll's ▊tortoise▊       │
│  dialogue foreshadowed the...   │
│                                 │
│  ┈ 3 more results ┈            │
│                                 │
└─────────────────────────────────┘
```

### Search — Result Navigation Mode

```
┌─────────────────────────────────┐
│ ┌─────────────────────────┐ ✕  │
│ │ tortoise             🔍 │    │
│ └─────────────────────────┘    │
│                                 │
│   system of reasoning. But      │
│   the ▊tortoise▊ smiled and    │
│   produced another rule from    │
│   under its shell. "You have    │
│   granted me these premises,"   │
│   it said. "And what if I       │
│   refuse this rule too?"        │
│                                 │
│   Achilles was beginning to     │
│   feel uneasy. The weight of    │
│   infinitely many rules         │
│   pressed upon him.             │
│                                 │
│                                 │
│─────────────────────────────────│
│       ◂  2 of 7  ▸      ☰     │
└─────────────────────────────────┘
```

### Search — No Results

```
┌─────────────────────────────────┐
│ ┌─────────────────────────┐ ✕  │
│ │ xyzzy                🔍 │    │
│ └─────────────────────────┘    │
│  No results                     │
│─────────────────────────────────│
│                                 │
│                                 │
│                                 │
│       No matches found          │
│       in this book              │
│                                 │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Search — Desktop Variant

```
┌─────────────────────────────────────────────────────────┐
│  ┌────────────────────┐                                 │
│  │ tortoise        🔍 │ ✕                               │
│  └────────────────────┘                                 │
│  ┌────────────────────┐                                 │
│  │Ch 1: ...the ▊tort..│                                 │
│  │Ch 4: ...the ▊tort..│  system of reasoning.           │
│  │Ch 4: ...but the ▊t.│  But the ▊tortoise▊            │
│  │Ch 7: ...Carroll's..│  smiled and produced            │
│  │Ch 9: ...as the ▊t..│  another rule from              │
│  │Ch 12: ...▊tortoise.│  under its shell.               │
│  │Ch 15: ...like the..│                                 │
│  └────────────────────┘  "You have granted me           │
│                          these premises," it             │
│                          said. "And what if I            │
│                          refuse this rule too?"          │
│                                                         │
│                                                         │
│─────────────────────────────────────────────────────────│
│       ◂  2 of 7  ▸                   42%    p.91       │
└─────────────────────────────────────────────────────────┘
```

### Import — Drag and Drop (Desktop)

```
┌─────────────────────────────────┐
│ Quire                 ⊕  ⚙  ▼ │
│─────────────────────────────────│
│                                 │
│ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐  │
│                                 │
│ │                           │  │
│                                 │
│ │       Drop ePub here      │  │
│                                 │
│ │                           │  │
│                                 │
│ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  │
│                                 │
│ ┌───┐ The Left Hand of Dark..  │
│ │ ▓ │ Ursula K. Le Guin        │
│ └───┘ ━━━━━━━━━○── 68%         │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│ ┌───┐ Gödel, Escher, Bach      │
│ │ ▓ │ Douglas Hofstadter        │
│ └───┘ ━━○──────── 22%          │
│                                 │
└─────────────────────────────────┘
```

### Import — Processing

```
┌─────────────────────────────────┐
│ Quire                 ⊕  ⚙  ▼ │
│─────────────────────────────────│
│                                 │
│ ┌───┐ Importing...              │
│ │   │ Annihilation              │
│ │   │ ━━━━━━━━━━━━━○────────── │
│ └───┘ Extracting chapters...    │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│ ┌───┐ The Left Hand of Dark..  │
│ │ ▓ │ Ursula K. Le Guin        │
│ └───┘ ━━━━━━━━━○── 68%         │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│ ┌───┐ Gödel, Escher, Bach      │
│ │ ▓ │ Douglas Hofstadter        │
│ └───┘ ━━○──────── 22%          │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Import — Error

```
┌─────────────────────────────────┐
│ Quire                 ⊕  ⚙  ▼ │
│─────────────────────────────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ✕                           │ │
│ │ Import failed               │ │
│ │                             │ │
│ │ "vacation-photos.zip"       │ │
│ │ is not a valid ePub file.   │ │
│ │                             │ │
│ │ Quire supports .epub files  │ │
│ │ without DRM.                │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌───┐ The Left Hand of Dark..  │
│ │ ▓ │ Ursula K. Le Guin        │
│ └───┘ ━━━━━━━━━○── 68%         │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│ ┌───┐ Gödel, Escher, Bach      │
│ │ ▓ │ Douglas Hofstadter        │
│ └───┘ ━━○──────── 22%          │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### Import — Duplicate Detection

```
┌─────────────────────────────────┐
│ Quire                 ⊕  ⚙  ▼ │
│─────────────────────────────────│
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │ "Annihilation" is already   │ │
│ │ in your library.            │ │
│ │                             │ │
│ │  ┌──────────┐ ┌──────────┐ │ │
│ │  │   Skip   │ │ Replace  │ │ │
│ │  └──────────┘ └──────────┘ │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌───┐ Annihilation              │
│ │   │ Jeff VanderMeer           │
│ │ ▓ │ ━━━━━━━━━━━━━━━━━━━ Done │
│ └───┘                           │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│                                 │
│                                 │
└─────────────────────────────────┘
```
