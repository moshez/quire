# Quire

PWA e-reader. All application logic in ATS2 → WASM. Generic JS bridge for DOM access.

## Build

    make                    # Build quire.wasm
    npm test                # Bridge tests
    npx serve .             # Dev server

## Milestone Workflow

When completing a milestone from quire-design.md §8:
1. Implement all items listed under the milestone
2. Add/update tests as specified
3. Mark the milestone checkbox as done: `- [ ]` → `- [x]`
4. Commit and push

## Rules

1. **No app code in index.html** — only loading div + `initBridge('quire.wasm')`
2. **bridge.js is generic** — no app-specific logic, publishable as npm package
3. **All UI logic in WASM** — bridge forwards events and applies diffs
4. **WASM owns node IDs** — assigned via CREATE_ELEMENT diffs
5. **Dependent types enforce correctness** — if it compiles, diffs are valid

## Files

- `.sats`: type declarations (interface)
- `.dats`: implementations
- `runtime.c`: minimal C runtime for WASM

## ATS2 Toolchain (M5+)

When adding the WASM build in M5:
- ATS2 must be installed locally by the developer
- CI builds from local source, no remote cloning or caching
- Keep CI simple: if it's slow, that's fine

## Protocol

See quire-design.md §2 for bridge protocol (diff buffer layout, op codes, exports).
