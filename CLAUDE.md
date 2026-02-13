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
6. **Never work around ward bugs** — if ward (vendor/ward/) has a bug, STOP and give the user a bug report instead of working around it. Do not patch vendor/ files or add workarounds in quire code. The user will report the issue upstream and have it fixed.
7. **Minimize C code** — Quire has zero application-level C files. All app code is in ATS2. Ward's `runtime.h` provides codegen macros and `atspre_*` arithmetic. If an algorithm can be expressed with ward_arr_set/get, div/mod, and existing extern funs, it belongs in ATS2. Any new C code requires justification: (a) external research showing this operation is conventionally done in C, (b) what ATS2-only solutions were tried and why they don't work, (c) trade-offs, and (d) why the C implementation is safe.
8. **Be fanatic about safety** — Auditing or checking are not reliable. Only ATS2-provable safety matters. It is unacceptable to work around safety, even if it's "small". If something is truly absolutely impossible to express safely in ATS2, file a bug against ward. Note that ward might well reject any bug that is not well justified.

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

## Converting C Blocks to ATS2

C `%{` blocks bypass all ATS2 type checking. Convert them to pure ATS whenever
possible. The general pattern:

### Step 1: Declare C primitives as extern

Move irreducible C operations (byte access, bitwise ops, pointer arithmetic)
to `runtime.h` as macros, then declare them in `.sats`:

```ats
(* .sats — declare the primitive *)
fun buf_get_u8(p: ptr, off: int): int = "mac#"
fun buf_set_u8(p: ptr, off: int, v: int): void = "mac#"
```

```c
/* runtime.h — implement the primitive */
#define buf_get_u8(p, off) (((unsigned char*)(p))[(off)])
#define buf_set_u8(p, off, v) (((unsigned char*)(p))[(off)] = (unsigned char)(v))
```

### Step 2: Move global state to runtime.c

Don't keep `static` variables in `%{` blocks. Put them in `runtime.c` with
getter/setter functions declared as `= "mac#"` in `.sats`.

### Step 3: Write ATS implementations using the primitives

Use `fn` for non-recursive module-local helpers, `implement` for `.sats` functions.
Both support `{...}` template parameters.

### Freestanding arithmetic

ATS2's built-in `+`, `*`, `>=`, `>` generate prelude template dispatch calls
(`g0int_add`, `g0int_mul`, etc.) that don't exist in freestanding mode. Replace
them with explicit extern functions and overloads:

```ats
extern fun add_int_int(a: int, b: int): int = "mac#quire_add"
extern fun mul_int_int(a: int, b: int): int = "mac#quire_mul"
overload + with add_int_int of 10   (* priority 10 beats built-in *)
overload * with mul_int_int of 10
```

For comparisons, explicit function calls are more reliable than overloads
(overloads for `>=` can remain ambiguous):

```ats
extern fun gte_int_int(a: int, b: int): bool = "mac#quire_gte"
(* Use: if gte_int_int(x, 255) then ... *)
```

### g0int vs g1int

Plain `int` is `g0int` (untracked). `int c` from `[c:nat] int c` is `g1int`
(dependent, statically indexed). These are **different types** — g0int overloads
don't match g1int arguments, causing ATS2 to fall back to prelude templates
(`g1int_mul`, `g1int_add`). Solutions:
- Use plain `int` returns when you don't need the static index
- Add separate g1int overloads if you need dependent arithmetic
- Use `castfn` to explicitly cast between the two

### ATS2 keywords to avoid

`op` is a reserved keyword in ATS2. Don't use it as any identifier — not in
dynamic variables, static variables, or dataprop indices. Use `opc`, `opcode`, etc.

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

## Writing Dataprops

Dataprops are compile-time proofs that are completely erased at runtime. Use
them to make invalid states unrepresentable.

### Whitelist pattern: enumerate valid values

When only specific values are legal, create a dataprop with one constructor
per valid value. The constructors ARE the whitelist — no other values can
produce a proof:

```ats
dataprop VALID_OPCODE(opc: int) =
  | OPCODE_SET_TEXT(1)
  | OPCODE_SET_ATTR(2)
  | OPCODE_CREATE_ELEMENT(4)

(* Only way to call: dom_emit_diff(OPCODE_SET_TEXT(), 1, ...) *)
fn dom_emit_diff {opc:int}
  (pf: VALID_OPCODE(opc), opcode: int opc, ...): void
```

This is stronger than `#define` constants — even if you use the right numeric
value, you must also produce the matching proof. "Use magic, don't use magic,
can't break it."

### Sized buffer pattern: capacity as a type property

Don't hardcode buffer sizes in consumer modules. Instead, define a
general-purpose pointer type that carries remaining capacity as a phantom
type index. The concrete size appears ONLY at the buffer's definition
site (buf.sats); downstream modules reference the capacity through the
type, never through a literal.

**buf.sats** — the single source of truth for buffer sizes:

```ats
(* Buffer pointer that knows its remaining capacity — erased to ptr *)
abstype sized_buf(cap: int) = ptr

(* Concrete size appears ONLY here, at the definition site *)
stadef SBUF_CAP = 4096

(* Accessor returns a sized_buf — callers get capacity from the type *)
fun get_string_buf(): sized_buf(SBUF_CAP) = "mac#get_string_buffer_ptr"

(* Writing checks len <= remaining capacity *)
fun sbuf_write {cap,l:nat | l <= cap}
  (dst: sized_buf(cap), src: ptr, len: int l): void = "mac#sbuf_write"

(* Advancing reduces remaining capacity *)
fun sbuf_advance {cap,n:nat | n <= cap}
  (buf: sized_buf(cap), n: int n): sized_buf(cap - n) = "mac#ptr_add_int"
```

**Consumer module** — imports buf.sats, uses SBUF_CAP without knowing
its concrete value matters:

```ats
staload "buf.sats"

fun dom_create_element
  {tl:nat | tl <= SBUF_CAP}
  (..., tag_len: int tl): ... = "mac#"
```

**Usage** — sequential writes track remaining space automatically:

```ats
val sbuf = get_string_buf()            (* sized_buf(SBUF_CAP) *)
val () = sbuf_write(sbuf, name, nl)    (* ATS checks: nl <= SBUF_CAP *)
val sbuf = sbuf_advance(sbuf, nl)      (* sized_buf(SBUF_CAP - nl) *)
val () = sbuf_write(sbuf, value, vl)   (* ATS checks: vl <= SBUF_CAP - nl *)
```

The key insight: if the buffer size changes from 4096 to 8192, only
buf.sats needs updating. All consumer module constraints and proofs
automatically adjust because they reference `SBUF_CAP`, not `4096`.

**Note**: ATS2 `#define` is dynamic-level only. For type-level constraints
(`{tl:nat | tl <= ...}`), use `stadef` instead:

```ats
#define STRING_BUFFER_SIZE 4096   (* for runtime C code *)
stadef SBUF_CAP = 4096            (* for type-level constraints *)
```

### praxi for connecting proofs to specific values

Use `praxi` (proof axioms) when a proof should only be obtainable through
specific known values:

```ats
praxi lemma_attr_class(): VALID_ATTR_NAME(5)   (* "class" *)
praxi lemma_attr_id(): VALID_ATTR_NAME(2)      (* "id" *)
```

These are the ONLY way to obtain `VALID_ATTR_NAME` proofs. Since each praxi
maps to a specific known-safe string, arbitrary dynamic data can never produce
a proof.

### dataprop vs dataview

- `dataprop` = non-linear (can be unused, duplicated). Use for most proofs.
- `dataview` = linear (must be consumed exactly once). Use when tracking
  resource ownership (e.g., a buffer lock that must be released).

### Constraint solver limitations

The ATS2 constraint solver handles linear integer arithmetic but NOT case
analysis on dataprop constructors. If the solver needs to know that
`VALID_ATTR_NAME(n)` implies `n <= 8`, add an explicit constraint alongside
the proof parameter:

```ats
fun dom_set_attr
  {nl:nat | nl <= SBUF_CAP} {vl:nat | nl + vl <= SBUF_CAP}
  (pf_attr: VALID_ATTR_NAME(nl), ..., name_len: int nl, ...): ...
```

The `nl <= SBUF_CAP` is redundant with `VALID_ATTR_NAME` (max name is 8 chars)
but necessary for the constraint solver.

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

### 4. set_text Destroying Sibling/Child Nodes (TEXT_RENDER_SAFE)

**Bug**: `ward_dom_stream_set_text` sets `textContent`, which REPLACES all
existing children with a single text node. In parsed HTML SAX output,
whitespace text nodes appear between sibling elements (from XHTML
indentation), and the parser may split large text into multiple TEXT nodes.
Calling `set_text` on a parent that already has children destroys them.

**Root cause**: `render_tree`'s TEXT handler called `set_text(parent, ...)`
unconditionally. Whitespace text between `<h1>` and `<p>` wiped the `<h1>`.
Non-whitespace text after element children wiped all siblings.

**Fix (ENFORCED)**: `render_tree` tracks `has_child` (0 or 1) per scope:
- `has_child=0`: parent has no DOM children. `set_text(parent)` is safe.
- `has_child=1`: parent has existing children. TEXT is wrapped in a `<span>`
  and `set_text` is called on the span, not the parent.
- Whitespace-only TEXT nodes are always skipped (optimization).
- `has_child` transitions 0→1 after any TEXT or ELEMENT_OPEN creates a
  DOM node. Entering a child scope resets to 0.

See `TEXT_RENDER_SAFE` dataprop in dom.sats and `SIBLING_CONTINUATION`
invariant (prevents the first-element-only bug in loop recursion shape).

**Proof obligation**: Any code that calls `set_text` on a node must ensure
no existing children will be destroyed. In `render_tree`, the `has_child`
parameter structurally enforces this. New code adding `set_text` calls must
document which invariant guarantees safety.

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

4. **dom_set_attr requires VALID_ATTR_NAME**: `dom_set_attr` itself requires
   a `VALID_ATTR_NAME` proof (obtained via `lemma_attr_class()`, `lemma_attr_id()`,
   etc.). `dom_set_attr_checked` is a backward-compatible alias — both enforce
   the proof. C callers are unaffected (proof is erased).

5. **Async operations require state setup BEFORE the call**: If a function
   triggers an async bridge operation (js_kv_open, js_file_open, etc.),
   all state (app_state, pending flags) must be set BEFORE the call, not
   in a continuation or callback. Document with `ASYNC_PRECONDITION`.

6. **Buffer writes use sized_buf**: Use `sized_buf` from buf.sats for all
   buffer writes. The `sbuf_write` and `sbuf_advance` functions enforce bounds
   at the type level. Never hardcode buffer sizes — reference `SBUF_CAP` and
   `FBUF_CAP` from buf.sats, which is the single source of truth.

7. **Single pending flag invariant**: At most one async pending flag
   (`settings_is_save_pending`, `library_is_metadata_pending`, etc.) may
   be active at any time. See `SINGLE_PENDING` dataprop in library.sats.

8. **Every bug fix must add a preventing proof or invariant**: When fixing a bug,
   don't just fix the code — add a dataprop, absprop, or documented structural
   invariant that makes the same class of bug impossible to reintroduce. If the
   invariant can be encoded as a dataprop (data values, state transitions, bounds),
   use a dataprop. If it's structural (recursion shape, continuation pattern),
   document it as a formal invariant in the `.sats` file with the specific bug
   class it prevents. This is standard operating procedure for all bug fixes.

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
- `buf.sats`: general-purpose sized buffer type — single source of truth for buffer sizes
- `arith.sats`: freestanding arithmetic — single source for all `mac#atspre_*` bindings
- No quire-specific C files — ward's `runtime.h` provides all codegen macros

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
