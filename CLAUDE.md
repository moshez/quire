# Quire

PWA e-reader. All application logic in ATS2 → WASM. Generic JS bridge for DOM access.

## Build

**Prerequisites:** ATS2 toolchain must be installed first (see ATS2 Toolchain section below).

**IMPORTANT:** You MUST run `make` locally and verify the build succeeds before committing any changes to `.sats` or `.dats` files. NEVER COUNT ON CI TO VERIFY ATS2 BUILD. If the ATS2 toolchain is not available, install it first before making any code changes.

```bash
# Set environment (required before make)
export PATSHOME=~/ATS2-Postiats-int-0.4.2
export PATH=$PATSHOME/bin:$PATH

make                    # Build quire.wasm - REQUIRED before commit
npm test                # Bridge tests
npx serve .             # Dev server
```

## Milestone Workflow

When completing a milestone from quire-design.md §8:
1. Implement all items listed under the milestone
2. Add/update tests as specified
3. Mark the milestone checkbox as done: `- [ ]` → `- [x]`
4. Commit and push

## Rules

1. **No app code in index.html** — only loading div + `initBridge('quire.wasm')`
2. **bridge.js is generic** — no app-specific logic, publishable as npm package (see Bridge Policy below)
3. **All UI logic in WASM** — bridge forwards events and applies diffs
4. **WASM owns node IDs** — assigned via CREATE_ELEMENT diffs
5. **Dependent types enforce correctness** — if it compiles, diffs are valid

## Type Safety Requirements

**All new functionality must be proven correct using ATS2's type system.** Avoid writing plain C in `%{` blocks when dataprops can enforce invariants at compile time.

The goal is **functional correctness**, not just safety. Prove that code *does the right thing*, not merely that it *doesn't crash*.

### Functional Correctness Examples

Use dataprops to encode relationships that guarantee correct behavior:

```ats
(* TOC lookup: prove the returned entry corresponds to the queried node *)
dataprop TOC_MAPS(node_id: int, toc_idx: int) =
  | {n,i:nat} TOC_ENTRY_FOR(n, i)  (* node n maps to TOC index i *)

fun toc_lookup {n:int}
  (node_id: int(n)): [i:int] (TOC_MAPS(n, i) | int(i))

(* Navigation: prove we land on the requested chapter *)
dataprop AT_CHAPTER(int) =
  | {c:nat} VIEWING(c)

fun go_to_chapter {target:nat}
  (ch: int(target)): (AT_CHAPTER(target) | void)

(* Progress calculation: prove percentage reflects actual position *)
dataprop PROGRESS(chapter: int, page: int, total_chapters: int, pct: int) =
  | {c,p,t,x:nat | x == (c * 100) / t} CORRECT_PCT(c, p, t, x)
```

### Safety as a Byproduct

Functional correctness proofs often imply safety, but safety alone is insufficient:
- Bounded array access proves you read *the correct element*, not just *some valid element*
- State machine proofs ensure operations happen *in the right order*, not just *without crashing*
- Linear resource tracking proves DOM nodes are *correctly parented*, not just *not leaked*

If C code is unavoidable, document why dataprops couldn't be used and what runtime checks substitute for compile-time proofs.

### UI and Application Logic Proofs

UI code (state machines, event routing, async callback dispatch) must also be proven correct:

- **App state machines**: Define `dataprop` or `absprop` for valid app states and transitions.  Prove that state changes only follow valid paths (e.g., `INIT → LOADING_DB → LOADING_LIB → LIBRARY`).
- **Node ID mappings**: When DOM node IDs map to app-level indices (e.g., book card buttons → book indices), prove the mapping is correct using `dataprop`.
- **Async callback dispatch**: Prove that callback routing delivers to the correct handler based on pending operation state.
- **Serialization roundtrips**: When data is serialized for storage and later deserialized, prove the roundtrip preserves the data using `absprop`.

```ats
(* App state machine: prove only valid transitions *)
dataprop APP_STATE_VALID(state: int) =
  | APP_INIT(0) | APP_LOADING_DB(1) | APP_LOADING_LIB(2)
  | APP_LIBRARY(3) | APP_IMPORTING(4) | APP_LOADING_BOOK(5)
  | APP_READING(6)

(* Book card mapping: prove button node_id maps to correct book index *)
dataprop BOOK_CARD_MAPS(node_id: int, book_index: int, count: int) =
  | {n:int} {i,c:nat | i < c} CARD_FOR_BOOK(n, i, c)

(* Serialization roundtrip: prove restore undoes serialize *)
absprop SERIALIZE_ROUNDTRIP(serialize_len: int, restore_ok: int)
```

## Known Bug Classes and Proof Obligations

This section documents bugs discovered during development and the correctness proofs
that prevent them. **Every fix to ATS2 or bridge code must also add or strengthen
a proof obligation** to prevent the same class of bug from recurring.

### 1. Missing State Transitions (app_state bug)

**Bug**: `open_db()` called `js_kv_open()` without first setting
`app_state = APP_STATE_LOADING_DB`. When the async callback
`on_kv_open_complete` fired, it checked `app_state == APP_STATE_LOADING_DB`,
found it was still `INIT`, and skipped the library load entirely.

**Root cause**: The state transition was in a C `%{` block that bypasses ATS2
type checking. The `APP_STATE_TRANSITION` dataprop existed but was documentary
— nothing enforced that `open_db()` actually performed the transition.

**Fix (ENFORCED)**: `open_db()` has been converted from a C `%{` block to pure
ATS code. The function constructs an `INIT_TO_LOADING_DB()` proof witness at
compile time, guaranteeing the transition is valid. The `set_app_state(1)` call
happens textually before `js_kv_open()`, making the bug impossible by construction.

**Proof obligation**: Every C block that modifies `app_state` MUST include:
```c
app_state = APP_STATE_X;  // TRANSITION: VALID_TRANSITION_NAME(from, to)
```
Where the transition name matches a constructor of `APP_STATE_TRANSITION`.
Code review MUST verify the `from` state matches the function's precondition.
All C state transitions now have `// TRANSITION:` comments.

**Similar risks**: Any function that sets up async operations (js_kv_open,
js_file_open, js_decompress) must set state BEFORE the async call, not after.
The `ASYNC_PRECONDITION` dataprop in epub.sats documents this pattern.

### 2. Shared Buffer Corruption (string buffer race)

**Bug**: `dom_set_attr("class", "book-title")` wrote "class" to the string
buffer and emitted a SET_ATTR diff. Before the bridge flushed the diff,
`library_get_title()` overwrote the string buffer with the book title.
The bridge then read "A Tal" (first 5 bytes of "A Tale of Testing") as
the attribute name, crashing with "'A Tal' is not a valid attribute name."

**Root cause**: The diff buffer protocol assumed diffs would be flushed
before the string buffer was reused. But `dom_set_attr` only flushed
PREVIOUS diffs (via `js_apply_diffs()` at the start), not its OWN diff.
Any code between `dom_set_attr` and the next DOM operation could corrupt
the pending diff's string data.

**Fix**: `dom_set_attr` and `dom_create_element` now call `js_apply_diffs()`
at the END as well, ensuring their diffs are consumed while string data
is still valid. See `BUFFER_FLUSHED` absprop in dom.sats.

**Proof obligation**: DOM operations that write to the string buffer
(SET_ATTR, CREATE_ELEMENT) must flush immediately. The `BUFFER_FLUSHED`
absprop documents this invariant. New DOM operations that use shared
buffers must follow the same pattern: flush before AND after writing.

**Similar risks**: Any code that reads from the fetch buffer between
DOM operations faces the same issue — `dom_set_text_offset` reads
fetch buffer data that could be overwritten by intervening code.

### 3. Invalid Attribute Names (SET_ATTR type safety)

**Bug**: Closely related to #2. Arbitrary data was passed as an HTML
attribute name, causing a DOM exception. The attribute name should always
be a known constant string like "class", "id", "type", etc.

**Fix (ENFORCED)**: `dom_set_attr_checked()` in dom.sats requires a
`VALID_ATTR_NAME(n)` proof as its first argument. All ATS code in `init()`
now uses `dom_set_attr_checked` with proof witnesses from `lemma_attr_class()`,
`lemma_attr_id()`, etc. These `praxi` functions are the ONLY way to obtain
VALID_ATTR_NAME proofs, making it impossible to pass dynamic data as attribute
names from ATS code.

**Proof obligation for C code**: C blocks that call `dom_set_attr` directly
should use only compile-time string constants and document which constructor applies:
```c
// VALID_ATTR_NAME: ATTR_CLASS(5)
dom_set_attr(pf, id, (void*)str_class, 5, (void*)str_value, val_len);
```

### Guidelines for New Code

1. **Prefer ATS over C blocks**: ATS type checking catches proof violations
   at compile time. C blocks bypass all checking. Write new logic in ATS
   whenever possible.

2. **Every state transition needs a proof witness**: When changing app_state
   in C code, cite the `APP_STATE_TRANSITION` constructor in a comment.
   When in ATS code, construct and consume the proof.

3. **Never modify shared buffers between DOM operations**: If you must read
   or write the string/fetch buffer between DOM calls, call `js_apply_diffs()`
   first to flush pending diffs.

4. **Use dom_set_attr_checked in ATS code**: Always prefer `dom_set_attr_checked`
   over `dom_set_attr`. The checked version requires a `VALID_ATTR_NAME` proof
   (obtained via `lemma_attr_class()`, `lemma_attr_id()`, etc.), making it
   impossible to pass dynamic data as attribute names.

5. **Async operations require state setup BEFORE the call**: If a function
   triggers an async bridge operation (js_kv_open, js_file_open, etc.),
   all state (app_state, pending flags) must be set BEFORE the call, not
   in a continuation or callback. Document with `ASYNC_PRECONDITION`.

6. **Buffer writes need bounds proofs**: Use `STRING_BUFFER_SAFE` and
   `FETCH_BUFFER_SAFE` dataprops when writing to shared buffers. These
   prove writes stay within buffer bounds (4096 and 16384 respectively).

7. **Single pending flag invariant**: At most one async pending flag
   (`settings_is_save_pending`, `library_is_metadata_pending`, etc.) may
   be active at any time. See `SINGLE_PENDING` dataprop in library.sats.

### Proof Architecture

Proofs are enforced at three levels:

| Level | Mechanism | Example |
|-------|-----------|---------|
| **Enforced** | ATS type system rejects incorrect code | `dom_set_attr_checked` requires `VALID_ATTR_NAME` proof |
| **Checked** | Dependent types + `praxi` functions | `open_db` constructs `INIT_TO_LOADING_DB()` witness |
| **Documented** | `// TRANSITION:` comments in C code | `app_state = APP_STATE_LIBRARY; // TRANSITION: ...` |

New code should prefer enforced > checked > documented. Move proofs up
the hierarchy whenever feasible.

## E2E Tests (Playwright)

End-to-end tests use Playwright to launch a real browser against the full app (WASM + bridge + DOM).

### Prerequisites

`quire.wasm` must be built and present at the project root before running e2e tests.

```bash
# Build WASM first (see Build section above)
make
cp build/quire.wasm quire.wasm   # or: make install
```

### Install Playwright

```bash
npm ci                                       # install @playwright/test
npx playwright install --with-deps chromium  # download browser + OS deps
```

On Ubuntu/Debian, `--with-deps` installs required system libraries (libgbm, libnss3, etc.). On other systems, omit `--with-deps` and install OS dependencies manually if the browser fails to launch.

### Run E2E Tests

```bash
npx playwright test              # headless (default)
npx playwright test --headed     # visible browser
npx playwright test --debug      # step-through debugger
```

Screenshots are saved to `e2e/screenshots/` after each run (gitignored).

### Configuration

- **Config file**: `playwright.config.js`
- **Test files**: `e2e/*.spec.js`
- **Dev server**: Playwright auto-starts `npx serve . -l 3737` (reuses an existing server outside CI)
- **Browser**: Chromium only — the app targets modern browsers, no cross-browser matrix needed
- **Timeouts**: 60s per test, 15s per assertion

### Writing E2E Tests

- Tests create their own test data (e.g., `createEpub()` from `e2e/create-epub.js`)
- No external fixtures or network requests — everything is self-contained
- Use `page.waitForSelector()` to wait for WASM-driven DOM updates (not arbitrary timeouts)
- The app state machine is async (IndexedDB callbacks), so wait for visible UI elements rather than internal state

### CI

The `e2e` job in `.github/workflows/pr.yaml` runs on every PR:
1. Downloads the WASM artifact from the `build-wasm` job
2. Installs Playwright browsers
3. Runs all e2e tests
4. Uploads screenshots (always) and Playwright report (on failure) as artifacts

## Bridge Policy

**Be extremely careful about changes to bridge.js.** Most PRs should not touch it.

The bridge is intentionally minimal and generic—it could be published as a standalone npm package for any WASM app needing DOM access. It must remain:
- **App-agnostic**: No knowledge of EPUB, readers, TOC, or any domain concepts
- **Protocol-only**: Just applies diffs and forwards events with raw data (node ID, coordinates)

If you think you need to modify bridge.js, first ask: can this be done in WASM instead?

Examples of what belongs in WASM, not bridge:
- Mapping node IDs to app-specific indices (e.g., TOC entries)
- Custom attribute handling or data extraction
- Any logic that references app concepts

If your change truly requires bridge modification (rare), document the justification in your commit message explaining why WASM couldn't handle it.

## Files

- `.sats`: type declarations (interface)
- `.dats`: implementations
- `runtime.h`: ATS2 macros and typedefs for freestanding builds
- `runtime.c`: minimal C runtime for WASM (allocator, memory ops, buffers)

## ATS2 Toolchain

### Installation

Download and build ATS2 (integer-only version, no GMP dependency):

```bash
# Download from GitHub Pages mirror
curl -sL "https://raw.githubusercontent.com/ats-lang/ats-lang.github.io/master/FROZEN000/ATS-Postiats/ATS2-Postiats-int-0.4.2.tgz" -o /tmp/ats2.tgz

# Extract
tar -xzf /tmp/ats2.tgz -C ~

# Build
cd ~/ATS2-Postiats-int-0.4.2
./configure
make

# Set environment (add to ~/.bashrc or ~/.zshrc)
export PATSHOME=~/ATS2-Postiats-int-0.4.2
export PATH=$PATSHOME/bin:$PATH
```

### WASM Toolchain

Requires clang with wasm32 target and wasm-ld:

```bash
# Ubuntu/Debian
sudo apt-get install -y clang lld
```

### Build Notes

- Uses freestanding WASM (no WASI, no libc)
- ATS2 prelude is disabled (-D_ATS_CCOMP_PRELUDE_NONE_)
- Runtime macros in src/runtime.h (included via -include flag)
- Function implementations in src/runtime.c (linked separately)
- CI builds ATS2 from source with caching

## Protocol

See quire-design.md §2 for bridge protocol (diff buffer layout, op codes, exports).
