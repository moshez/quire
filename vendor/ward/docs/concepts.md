# Concepts

## Linear types as ownership

Ward types are `absvtype` -- linear types that must be consumed exactly once. The ATS2 compiler statically enforces that every array is freed, every promise is handled, every resolver is used. At runtime, linear types erase to `ptr` -- zero overhead.

```ats
val arr = ward_arr_alloc<int>(10)   (* ownership acquired *)
val () = ward_arr_free<int>(arr)    (* ownership released *)
(* arr cannot be used again -- use-after-free is a compile error *)
```

If you forget to free an array, the compiler rejects the code. If you try to free it twice, the compiler rejects the code. This is not garbage collection -- it is static ownership tracking with zero runtime cost.

## Dependent types as bounds

Array indices carry static constraints. `{i:nat | i < n}` means the index is proven in-bounds at compile time. There is no runtime bounds check -- the compiler proves safety statically.

```ats
fun{a:t@ype}
ward_arr_get
  {l:agz}{n,i:nat | i < n}
  (arr: !ward_arr(a, l, n), i: int i)
  : a
```

The constraint `i < n` means any call to `ward_arr_get` with an out-of-bounds index is a compile-time error, not a runtime panic.

## Borrow protocol (freeze/thaw/dup/drop)

Mutable arrays can be frozen to allow shared read-only access. The borrow count is tracked statically -- you cannot thaw (regain mutability) until all borrows are returned.

```
ward_arr(a, l, n)                        (* mutable, owned *)
    │
    ▼ freeze
@(ward_arr_frozen(a, l, n, 1),           (* frozen, 1 borrow *)
  ward_arr_borrow(a, l, n))              (* read-only handle *)
    │
    ├── dup → borrow count becomes k+1
    ├── drop → borrow count becomes k-1
    │
    ▼ thaw (requires k=0)
ward_arr(a, l, n)                        (* mutable again *)
```

This is analogous to Rust's `&T` / `&mut T` distinction, but enforced entirely at compile time through the ATS2 type system.

## Safe text and SAFE_CHAR

DOM tag and attribute names must be `ward_safe_text` -- text where every character is verified at compile time. The `SAFE_CHAR` predicate allows only `[a-zA-Z0-9-]`:

```ats
stadef SAFE_CHAR(c:int) =
  (c >= 97 && c <= 122)       (* a-z *)
  || (c >= 65 && c <= 90)     (* A-Z *)
  || (c >= 48 && c <= 57)     (* 0-9 *)
  || c == 45                  (* - *)
```

Characters are verified by passing `char2int1('c')` which preserves the static index for the ATS2 constraint solver. An unsafe character (e.g. `<`, `"`, `&`) is a compile-time error. This prevents XSS and injection by construction, not by sanitization.

## Promise chains

Promises are linear and indexed by state: `datasort PromiseState = Pending | Resolved`. The resolver is a separate linear value consumed by `resolve` -- you cannot resolve twice or forget to resolve.

```ats
val @(p, r) = ward_promise_create<int>()
(* p: ward_promise_pending(int), r: ward_promise_resolver(int) *)
val () = ward_promise_resolve<int>(r, 42)  (* consumes r *)
```

Chaining uses monadic bind (`ward_promise_then`). The callback receives the resolved value and must return a new pending promise. Use `ward_promise_return` to lift an immediate value:

```ats
val p2 = ward_promise_then<int><int>(p, lam (x) => ward_promise_return<int>(x + 1))
```

No error type parameter. Use `Result(a, e)` as your `a` if you need errors.

## DOM state threading

DOM operations consume and return a linear `ward_dom_state`. This ensures operations are sequenced and the state is not duplicated or leaked:

```ats
val dom = ward_dom_init()
val dom = ward_dom_create_element(dom, 1, 0, tag, 3)
val dom = ward_dom_set_safe_text(dom, 1, text, 10)
val () = ward_dom_fini(dom)
```

For async boundaries (e.g., timer callbacks), `ward_dom_store` and `ward_dom_load` persist and retrieve the state through a global slot.

## The trusted surface

Safety by construction means the `.sats` files are the specification. User code cannot introduce `praxi` or `$UNSAFE` operations. The trusted surface is limited to:

- **`memory.dats`** -- implementations behind the safe interface. Each `$UNSAFE` use is individually justified.
- **`dom.dats`**, **`promise.dats`**, etc. -- similarly restricted implementation files.
- **`runtime.h`** / **`runtime.c`** -- the C runtime (bump allocator, memset/memcpy).
- **`ward_bridge.mjs`** -- the JS bridge that implements WASM imports.

The anti-exerciser (`exerciser/anti/`) contains 12 files that must fail to compile, verifying that the type system rejects:

| File | What it tests |
|------|--------------|
| `buffer_overflow.dats` | Out-of-bounds array access |
| `double_free.dats` | Freeing an array twice |
| `leak.dats` | Forgetting to free an array |
| `out_of_bounds.dats` | Index beyond array size |
| `thaw_with_borrows.dats` | Thawing while borrows exist |
| `use_after_free.dats` | Using an array after freeing |
| `write_while_frozen.dats` | Writing to a frozen array |
| `unsafe_char.dats` | Non-SAFE_CHAR in text builder |
| `double_resolve.dats` | Resolving a promise twice |
| `extract_pending.dats` | Extracting from a pending promise |
| `forget_resolver.dats` | Forgetting to use a resolver |
| `use_after_then.dats` | Using a promise after chaining |
