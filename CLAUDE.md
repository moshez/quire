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
