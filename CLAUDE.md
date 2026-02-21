# Quire

PWA e-reader. All application logic in ATS2 → WASM. Generic JS bridge for DOM access.

## Build

```bash
# Set environment (required before make)
export PATSHOME=~/ATS2-Postiats-int-0.4.2
export PATH=$PATSHOME/bin:$PATH

make                    # Build quire.wasm - REQUIRED before commit
npm test                # Bridge tests
npx serve .             # Dev server
```

**IMPORTANT:** `quire.wasm` is gitignored — NEVER commit it. CI builds WASM from source.

**IMPORTANT:** Work is NOT complete until CI (including e2e tests) passes green. Always push and watch CI before declaring a task done. E2E tests cannot run locally.

## Milestone Workflow

When completing a milestone from quire-design.md §8:
1. Implement all items listed under the milestone
2. Add/update tests as specified
3. Mark the milestone checkbox as done: `- [ ]` → `- [x]`
4. Commit and push

## "next" Command

If the user says just "next" and there is no task currently in progress, find
the first unchecked (`- [ ]`) item in `plan.md`, implement it fully (code,
build, tests, dataprop analysis per platform-usage rules), mark it done
(`- [x]`), and commit.

## Rules

1. **No app code in index.html** — only loading div + `initBridge('quire.wasm')`
2. **bridge.js is generic** — no app-specific logic, publishable as npm package (see Bridge Policy below)
3. **All UI logic in WASM** — bridge forwards events and applies diffs
4. **WASM owns node IDs** — assigned via CREATE_ELEMENT diffs

## ATS2 Notes

These are quire-specific notes supplementing the platform-usage rules.

### Runtime macros

Freestanding ATS2 code may need these macros in `runtime.h`:
- `ATSPMVi0nt(i)` — plain integer literals
- `ATSPMVintrep(i)` — statically-indexed integer representations
- `ATSPMVcastfn(castfn, ty, val)` — zero-cost type casts
- `ATSextfcall(f, args)` — external function calls via `$extfcall`

### dataprop parameters are erased

Adding a `dataprop` proof parameter to a `= "mac#"` function does NOT change
its C signature. C callers continue to work unchanged. This means you can
strengthen ATS interfaces with proof requirements without breaking C code.

### Sized buffer pattern

Don't hardcode buffer sizes in consumer modules. `buf.sats` defines
`sized_buf(cap)` — a pointer type carrying remaining capacity as a phantom
type index. The concrete size appears ONLY in `buf.sats` via `stadef SBUF_CAP`.
Downstream modules reference `SBUF_CAP`, never a literal.

**Note**: ATS2 `#define` is dynamic-level only. For type-level constraints
(`{tl:nat | tl <= ...}`), use `stadef` instead.

## Known Bug Classes and Proof Obligations

This section documents bugs discovered during development and the correctness proofs
that prevent them.

### 1. Missing State Transitions (app_state bug)

**Bug**: `open_db()` called `js_kv_open()` without first setting
`app_state = APP_STATE_LOADING_DB`. The async callback found stale state
and skipped the library load entirely.

**Fix (ENFORCED)**: `open_db()` constructs an `INIT_TO_LOADING_DB()` proof
witness at compile time. The `set_app_state(1)` call happens before
`js_kv_open()`, making the bug impossible by construction.

### 2. Shared Buffer Corruption (string buffer race)

**Bug**: `dom_set_attr("class", ...)` wrote to the string buffer but didn't
flush its own diff. Intervening code overwrote the buffer before the bridge
read it.

**Fix**: DOM operations that write to the string buffer now flush immediately
(before AND after). See `BUFFER_FLUSHED` absprop in dom.sats.

### 3. Invalid Attribute Names (SET_ATTR type safety)

**Fix (ENFORCED)**: `dom_set_attr` requires a `VALID_ATTR_NAME(n)` proof.

### 4. set_text Destroying Sibling/Child Nodes (TEXT_RENDER_SAFE)

**Fix (ENFORCED)**: `render_tree` tracks `has_child` per scope. When
`has_child=1`, TEXT is wrapped in `<span>` before `set_text`.
See `TEXT_RENDER_SAFE` dataprop in dom.sats.

## Quire-Specific Guidelines

1. **dom_set_attr requires VALID_ATTR_NAME**: Obtained via `lemma_attr_class()`,
   `lemma_attr_id()`, etc. `dom_set_attr_checked` is a backward-compatible alias.

2. **Buffer writes use sized_buf**: Use `sized_buf` from buf.sats. Never hardcode
   buffer sizes — reference `SBUF_CAP` and `FBUF_CAP`.

3. **Single pending flag invariant**: At most one async pending flag may be active
   at any time. See `SINGLE_PENDING` dataprop in library.sats.

## Visual Check Protocol

After any UI change, perform a visual check on CI screenshots across ALL
viewport sizes. This is mandatory before declaring work complete.

### How to do a visual check

1. **Wait for CI to pass** (or at least for e2e artifacts to be uploaded)
2. **Download artifacts**: `GIT_DIR=/opt/homedir/src/quire/.git gh run download <run_id> -D /tmp/e2e-artifacts`
3. **Find ALL screenshots**: `find /tmp/e2e-artifacts -name "*.png" | sort`
4. **Review EVERY viewport size** for EVERY screenshot — not just the feature
   you changed. The viewport sizes are: 375x667 (mobile portrait), 667x375
   (mobile landscape), 768x1024 (tablet), 1024x768 (desktop), 1440x900 (wide).
5. **Check the FULL PAGE on each viewport**, not just the element you modified.
   Look for:
   - Text truncation (e.g., "Archi..." instead of "Archive")
   - Elements clipped by the viewport edge
   - Buttons or interactive elements that are unreachable or too small to tap
   - Content overflowing its container
   - Broken flex/grid layouts (items not wrapping, overlapping)
   - Unreadable text (too small, too compressed, line-wrapping into gibberish)
6. **If anything looks wrong on ANY viewport, flag it** — do not say "looks
   fine" unless every viewport has been individually examined and every element
   on the page is properly laid out.

### Common mistakes to avoid

- **Tunnel vision**: Only checking the feature you just built, ignoring the
  rest of the page. If you added a modal, also check that the library cards,
  toolbar, and buttons behind it still look correct on every viewport.
- **Assuming functional = visual**: A test passing (element is visible, text
  matches) does NOT mean it looks right. A button can be "visible" but clipped
  to 3 characters.
- **Skipping viewports**: "Desktop looks fine" is not a visual check. Mobile
  portrait (375px wide) is where most layout breaks happen.

## Bridge Policy

**Be extremely careful about changes to bridge.js.** Most PRs should not touch it.

The bridge is intentionally minimal and generic — it could be published as a standalone
npm package for any WASM app needing DOM access. It must remain:
- **App-agnostic**: No knowledge of EPUB, readers, TOC, or any domain concepts
- **Protocol-only**: Just applies diffs and forwards events with raw data (node ID, coordinates)

If you think you need to modify bridge.js, first ask: can this be done in WASM instead?

## Files

- `.sats`: type declarations (interface)
- `.dats`: implementations
- `buf.sats`: general-purpose sized buffer type — single source of truth for buffer sizes
- `arith.sats`: freestanding arithmetic — single source for all `mac#atspre_*` bindings

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
