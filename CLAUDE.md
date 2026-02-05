# Quire

PWA e-reader. All application logic in ATS2 → WASM. Generic JS bridge for DOM access.

## Build

**Prerequisites:** ATS2 toolchain must be installed first (see ATS2 Toolchain section below).

```bash
# Set environment (required before make)
export PATSHOME=~/ATS2-Postiats-int-0.4.2
export PATH=$PATSHOME/bin:$PATH

make                    # Build quire.wasm
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
