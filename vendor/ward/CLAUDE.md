# Ward

Linear memory safety library for ATS2. Provides Rust-like guarantees (no buffer overflow, no use-after-free, no double-free, no mutable aliasing) through dependent and linear types, compiled to freestanding WASM.

## Design Principles

**Safety by construction, not by inspection.** The `.sats` files are the specification -- user code cannot introduce `praxi` or `$UNSAFE` operations. Even inside `local` blocks in `.dats` implementations, each `$UNSAFE` use is individually justified with what alternative was considered and why it doesn't work. The goal is to minimize the trusted surface. For example, `ward_safe_text` verifies each character via the constraint solver at compile time -- safe values are constructed safely, not checked after the fact.

## Build

**Prerequisites:** ATS2 toolchain must be installed first (see ATS2 Toolchain section below).

**IMPORTANT:** You MUST run `make check` locally and verify the build succeeds before committing any changes to `.sats` or `.dats` files.

```bash
make              # Build WASM + native exerciser
make check        # Build everything + run anti-exerciser
make test         # Run bridge tests (requires Node.js + npm install)
make check-all    # make check + make test
make wasm         # WASM only (build/ward.wasm)
make exerciser    # Native exerciser (builds and runs)
make anti-exerciser  # Verify unsafe code is rejected
make clean        # Remove build/
make node-exerciser  # Node.js DOM exerciser (requires Node.js + npm)
```

## Architecture

Unified typed array system -- no untyped layer. Byte buffers use `ward_arr<byte>`.

```
ward_safe_text       -- compile-time verified read-only text (non-linear)
ward_arr_borrow      -- typed read-only shared access
ward_arr_frozen      -- frozen typed array with borrow counting
ward_arr             -- typed, bounds-checked, linear arrays
ward_promise         -- linear promise with datasort state index
malloc/free          -- the unsafe world (never exposed)
```

All functions prefixed `ward_` for easy auditing. No raw pointer extraction -- safety guarantees are inescapable. All proofs are erased at runtime -- zero overhead.

## API

### Types

| Type | Description |
|------|-------------|
| `ward_arr(a, l, n)` | Typed array of `n` elements of type `a` at address `l` |
| `ward_arr_frozen(a, l, n, k)` | Frozen typed array, `k` outstanding borrows |
| `ward_arr_borrow(a, l, n)` | Read-only borrow of typed array |
| `ward_safe_text(n)` | Non-linear read-only text, `n` bytes, compile-time character verified |
| `ward_text_builder(n, filled)` | Linear builder for safe text construction |
| `ward_promise(a, s)` | Linear promise indexed by `PromiseState` (Pending or Resolved) |
| `ward_promise_resolver(a)` | Linear write-end, consumed by `resolve` |
| `ward_dom_state(l)` | Linear DOM diff buffer at address `l` |

### Memory Functions

| Function | Signature |
|----------|-----------|
| `ward_arr_alloc<a>(n)` | `{n:pos} -> [l:agz] ward_arr(a, l, n)` |
| `ward_arr_free<a>(arr)` | `ward_arr(a, l, n) -> void` |
| `ward_arr_get<a>(arr, i)` | Read element `i`, `{i < n}` |
| `ward_arr_set<a>(arr, i, v)` | Write element `i`, `{i < n}` |
| `ward_arr_split<a>(arr, m)` | Split into `@(ward_arr(l, m), ward_arr(l+m, n-m))` |
| `ward_arr_join<a>(left, right)` | Rejoin adjacent arrays |
| `ward_arr_freeze<a>(arr)` | `-> @(ward_arr_frozen(l, n, 1), ward_arr_borrow(l, n))` |
| `ward_arr_thaw<a>(frozen)` | `ward_arr_frozen(l, n, 0) -> ward_arr(l, n)` |
| `ward_arr_dup<a>(frozen, borrow)` | Increment borrow count, return new borrow |
| `ward_arr_drop<a>(frozen, borrow)` | Decrement borrow count, consume borrow |
| `ward_arr_read<a>(borrow, i)` | Read element `i` through borrow |
| `ward_arr_borrow_split<a>(frozen, borrow, m)` | Split borrow into two sub-borrows (count +1) |
| `ward_arr_borrow_join<a>(frozen, left, right)` | Rejoin sub-borrows (count -1) |
| `ward_text_build(n)` | `{n:pos} -> ward_text_builder(n, 0)` |
| `ward_text_putc(b, i, c)` | `{SAFE_CHAR(c)} -> ward_text_builder(n, i+1)` |
| `ward_text_done(b)` | `ward_text_builder(n, n) -> ward_safe_text(n)` |
| `ward_safe_text_get(t, i)` | Read byte `i` from safe text |

### Promise Functions

| Function | Signature |
|----------|-----------|
| `ward_promise_create<a>()` | `-> @(ward_promise_pending(a), ward_promise_resolver(a))` |
| `ward_promise_resolved<a>(v)` | `(a) -> ward_promise_resolved(a)` |
| `ward_promise_resolve<a>(r, v)` | `(resolver, a) -> void` (consumes resolver) |
| `ward_promise_extract<a>(p)` | `ward_promise_resolved(a) -> a` |
| `ward_promise_discard<a>{s}(p)` | `ward_promise(a, s) -> void` |
| `ward_promise_then<a><b>(p, f)` | `(pending(a), a -<cloref1> b) -> pending(b)` |

### DOM Functions

| Function | Signature |
|----------|-----------|
| `ward_dom_init()` | `-> [l:agz] ward_dom_state(l)` |
| `ward_dom_fini(state)` | `ward_dom_state(l) -> void` |
| `ward_dom_create_element(state, node_id, parent_id, tag, tag_len)` | Create element with safe text tag |
| `ward_dom_set_text(state, node_id, text, text_len)` | Set text from borrow |
| `ward_dom_set_attr(state, node_id, attr_name, name_len, value, value_len)` | Set attribute (safe text name) |
| `ward_dom_set_style(state, node_id, value, value_len)` | Dedicated style setter |
| `ward_dom_remove_children(state, node_id)` | Remove all children |

### SAFE_CHAR predicate

```ats
stadef SAFE_CHAR(c:int) =
  (c >= 97 && c <= 122)       (* a-z *)
  || (c >= 65 && c <= 90)     (* A-Z *)
  || (c >= 48 && c <= 57)     (* 0-9 *)
  || c == 45                  (* - *)
```

Characters are verified by passing `char2int1('c')` which preserves the static index for the constraint solver.

## Files

### Library (`lib/`)
- `memory.sats` -- type declarations (the specification): 5 types, 18 functions
- `memory.dats` -- implementations (the "unsafe core" behind the safe interface)
- `dom.sats` -- DOM diff protocol specification (5 core + 4 convenience operations)
- `dom.dats` -- DOM implementation (ward_set_byte/i32/copy_at via $extfcall)
- `promise.sats` -- linear promise specification: datasort, 2 types, 7 functions
- `promise.dats` -- promise implementation (ward_slot_get/set via $extfcall)
- `event.sats` -- promise-based timer and exit specification
- `event.dats` -- timer implementation (erases resolver to ptr for JS host)
- `ward_bridge.mjs` -- JS bridge: parses binary diff protocol, applies to DOM
- `runtime.h` -- freestanding WASM runtime: ATS2 macro infrastructure + ward type definitions
- `runtime.c` -- bump allocator + memset/memcpy + DOM global state for WASM
- `ward_prelude.h` -- native build: ward type macros for gcc

### Exerciser (`exerciser/`)
- `exerciser.dats` -- native exerciser that tests all operations
- `wasm_exerciser.dats` -- WASM exerciser exporting test functions
- `dom_exerciser.dats` -- WASM DOM exerciser (pure safe ATS2, no $UNSAFE)
- `node_exerciser.mjs` -- Node.js wrapper: loads jsdom, runs ward via bridge
- `wasm_stubs/` -- empty stubs for libats CATS files (not needed in freestanding mode)
- `anti/` -- anti-exerciser: code that MUST fail to compile (12 files):
  buffer_overflow, double_free, leak, out_of_bounds, thaw_with_borrows,
  use_after_free, write_while_frozen, unsafe_char,
  double_resolve, extract_pending, forget_resolver, use_after_then

### Tests (`tests/`)
- `helpers.mjs` -- shared test utilities (creates ward instance with jsdom)
- `bridge_*.test.mjs` -- bridge tests using node:test

## Key ATS2 Patterns

### No raw pointer extraction

There is no way to recover a `ptr l` from any ward type. All memory operations take the proof directly -- the pointer is hidden inside.

### Linear types as ownership

Ward array types are `absvtype` -- linear types that must be consumed exactly once. At runtime they are all erased to `ptr`.

### Dependent types as bounds

Array indices carry static constraints: `{i:nat | i < n}` means the index is proven in-bounds at compile time.

### Template functions

All ward operations are ATS2 templates. Any file using them must include:

```ats
staload _ = "./../lib/memory.dats"  (* template resolution *)
```

### Avoiding ATS2 constraint solver limits

The solver can't reduce `sizeof(a)` at compile time. Inside the `local` block, use:

```ats
val tail = $UNSAFE.cast{ptr(l+m)}(ptr_add<a>(arr, m))
```

### $UNSAFE.cast vs $UNSAFE.castvwtp1

`$UNSAFE.cast` CONSUMES linear values. For `!T` (borrowed) parameters, use `$UNSAFE.castvwtp1` which borrows without consuming.

### stadef vs #define

`stadef` is static-level only -- use `#define` for dynamic-level constants.

### Reserved words

`prefix`, `op` are reserved keywords in ATS2. Do not use them as identifiers.

## Freestanding WASM Build

The WASM build uses three `-D` flags to suppress ATS2 runtime headers that require libc:

- `-D_ATS_CCOMP_HEADER_NONE_` -- suppresses `pats_ccomp_*.h` (which need `setjmp.h`)
- `-D_ATS_CCOMP_EXCEPTION_NONE_` -- suppresses exception handling
- `-D_ATS_CCOMP_PRELUDE_NONE_` -- suppresses prelude CATS files

`lib/runtime.h` provides all needed macros. Stub CATS files in `exerciser/wasm_stubs/` shadow the libats includes.

## ATS2 Toolchain

### Installation (no root required)

```bash
curl -sL "https://raw.githubusercontent.com/ats-lang/ats-lang.github.io/master/FROZEN000/ATS-Postiats/ATS2-Postiats-int-0.4.2.tgz" -o /tmp/ats2.tgz
mkdir -p ~/.ats2
tar -xzf /tmp/ats2.tgz -C ~/.ats2
cd ~/.ats2/ATS2-Postiats-int-0.4.2
make -j$(nproc) -C src/CBOOT patsopt
mkdir -p bin
cp src/CBOOT/patsopt bin/patsopt
```

The Makefile defaults to `PATSHOME=$(HOME)/.ats2/ATS2-Postiats-int-0.4.2`.

### WASM Toolchain

Requires clang with wasm32 target and wasm-ld:

```bash
sudo apt-get install -y clang lld
```
