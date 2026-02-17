# Architecture

## Build pipeline

```
ATS2 source (.sats/.dats)
    |
    v patsopt
C source (_dats.c)
    |
    v clang --target=wasm32
WASM objects (.o)
    |
    v wasm-ld
WASM binary (.wasm)
    |
    v ward_bridge.mjs
DOM in browser / jsdom in Node.js
```

**patsopt** compiles ATS2 to C. The C code contains only assignments, function calls, and struct operations -- no dynamic allocation, no exceptions. **clang** cross-compiles to wasm32 freestanding. **wasm-ld** links all objects into a single WASM binary with explicit exports. The JS bridge instantiates the WASM and provides host imports.

## Module dependency graph

```
memory.sats <-- dom.sats
    ^            ^
    |            |
promise.sats <--+
    ^            |
    |            |
event.sats      idb.sats
                window.sats
                nav.sats
                dom_read.sats
                listener.sats
                fetch.sats
                clipboard.sats
                file.sats
                decompress.sats
                notify.sats
```

All modules depend on `memory.sats` for array types and safe text. Async modules also depend on `promise.sats`. The DOM module depends on `memory.sats` for borrow types.

## Safety guarantees

Ward provides four guarantees through the ATS2 type system:

1. **No buffer overflow** -- array indices carry `{i:nat | i < n}` constraints, proven at compile time
2. **No use-after-free** -- linear types must be consumed exactly once; using a consumed value is a type error
3. **No double-free** -- consuming a linear value twice is a type error
4. **No mutable aliasing** -- freeze/thaw protocol ensures either one mutable owner or many read-only borrows, never both

All proofs are erased at runtime. There are no runtime bounds checks, no reference counting, no garbage collection. The compiled WASM is the same code you would write by hand in C, but with compile-time proof that it is safe.

## Anti-exerciser

The `exerciser/anti/` directory contains 17 files that **must fail to compile**. `make anti-exerciser` runs `patsopt` on each and verifies it is rejected. This is a regression test for the type system -- if any file compiles, it means the safety specification has a hole.

| File | Rejected pattern |
|------|-----------------|
| `buffer_overflow.dats` | Accessing index >= array size |
| `double_free.dats` | Freeing a linear array twice |
| `leak.dats` | Failing to free a linear array |
| `out_of_bounds.dats` | Index beyond array bounds |
| `thaw_with_borrows.dats` | Thawing while borrows outstanding |
| `use_after_free.dats` | Reading from freed array |
| `write_while_frozen.dats` | Mutating a frozen array |
| `unsafe_char.dats` | Non-SAFE_CHAR character in text builder |
| `double_resolve.dats` | Resolving a promise resolver twice |
| `extract_pending.dats` | Extracting value from pending promise |
| `forget_resolver.dats` | Dropping a resolver without resolving |
| `use_after_then.dats` | Using a promise after passing it to `then` |
| `use_stream_after_end.dats` | Using a DOM stream after `stream_end` |
| `arr_too_large.dats` | Array exceeding 1MB size limit |
| `arena_destroy_with_borrows.dats` | Destroying arena with outstanding tokens |

## Runtime architecture

### `runtime.h` -- Freestanding WASM runtime

Replaces the ATS2 standard runtime headers that require libc. Provides:

- **ATS2 macro infrastructure** -- `ATSboxof`, `ATSINSmove`, `ATSPMVint`, etc.
- **Ward type definitions** -- all ward types erase to `void*`
- **Closure support** -- `ATSclosurerize_beg/end`, `ATSFCreturn`, `ATSPMVcfunlab`
- **DOM helpers** -- `ward_set_byte`, `ward_set_i32`, `ward_copy_at`
- **Promise support** -- `_ward_cloptr1_wrap` self-freeing closure wrapper, `_ward_resolve_chain` declaration
- **Stash and table declarations** -- `ward_bridge_stash_set/get_int`, `ward_measure_set/get`, `ward_listener_set/get`, `ward_resolver_stash/unstash/fire`, `ward_js_stash_read`

### `runtime.c` -- Free-list allocator and support

- **Free-list allocator** -- segregated-list `malloc` with 9 size classes (32, 128, 512, 4096, 8192, 16384, 65536, 262144, 1048576 bytes) and oversized free list (first-fit). `free` returns blocks to the appropriate list.
- **Arena allocator** -- `ward_arena_create/alloc/destroy` for bulk allocation with explicit lifetime management. Arena block layout: `[max:4][used:4][data]` with 8-byte aligned bump allocation.
- **memset/memcpy** -- freestanding implementations
- **Bridge int stash** -- 4-slot integer array for stash IDs and metadata
- **Resolver table** -- 64-slot linear clear-on-take table for async resolvers
- **Listener table** -- 128-slot table for event listener closures

### `ward_prelude.h` -- Native build macros

Provides the same ward type macros for gcc (used by the native exerciser). Must mirror `runtime.h` additions.

## DOM streaming

DOM operations use a streaming model with a 256KB diff buffer. The `ward_dom_stream` type accumulates ops into the buffer. When the next op wouldn't fit, the stream auto-flushes to the JS bridge and resets the cursor. At `stream_end`, any remaining ops are flushed.

This batching reduces WASM/JS boundary crossings -- a single `ward_dom_flush` call can carry many ops instead of one op per call.

## Freestanding WASM

The WASM build uses three `-D` flags to suppress ATS2 runtime headers that require libc:

| Flag | Suppresses |
|------|-----------|
| `-D_ATS_CCOMP_HEADER_NONE_` | `pats_ccomp_*.h` (which need `setjmp.h`) |
| `-D_ATS_CCOMP_EXCEPTION_NONE_` | Exception handling |
| `-D_ATS_CCOMP_PRELUDE_NONE_` | Prelude CATS files |

`-include lib/runtime.h` provides all needed macros instead. Stub CATS files in `exerciser/wasm_stubs/` shadow the libats includes that ATS2 generates `#include` directives for.

The resulting WASM binary has:
- No libc dependency
- No dynamic linking
- No WASI requirement
- 16 MB initial memory, 256 MB max, with 64 KB stack
- Explicit exports for host callbacks
