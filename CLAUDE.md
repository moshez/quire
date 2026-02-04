# Quire

PWA e-reader. All application logic in ATS2 → WASM. Generic JS bridge for DOM access.

## Build

    make                    # Build quire.wasm
    npm test                # Bridge tests
    npx serve .             # Dev server

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

## Protocol

See quire-design.md §2 for bridge protocol (diff buffer layout, op codes, exports).
