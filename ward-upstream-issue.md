# ward bug: `ward_promise_discard` after `ward_promise_then` causes use-after-free

## Summary

`ward_promise_then` returns a linear `ward_promise_pending(b)` that shares underlying memory with the parent promise's `chain_field`. When the caller consumes this return value via `ward_promise_discard`, the chain node is freed, but the parent still references it. When the parent later resolves, `_ward_resolve_chain` accesses freed memory, causing a WASM `call_indirect` trap ("index out of bounds").

## Reproducer

```ats
val @(p, r) = ward_promise_create<int>()
val p2 = ward_promise_then<int><int>(p,
  llam (x: int): ward_promise_pending(int) =>
    ward_promise_return<int>(x + 1)
)
(* p2 is linear — caller MUST consume it *)
val () = ward_promise_discard<int>(p2) (* <-- frees chain node *)

(* Later, from async callback: *)
val () = ward_promise_resolve<int>(r, 42) (* <-- use-after-free! *)
```

## Root cause

In `promise.dats`, `ward_promise_then` (pending branch, line 149):

```ats
val chain = promise_mk(0, the_null_ptr, the_null_ptr, the_null_ptr)
val chain_ptr = $UNSAFE.castvwtp1{ptr}(chain)  (* borrow *)
val () = chain_field := chain_ptr              (* parent stores chain ptr *)
...
val _ = $UNSAFE.castvwtp0{ptr}(chain)          (* [U4] forget — owned by p *)
in chain_ptr end
```

The function returns `chain_ptr` cast back to `promise_vt` (line 161). This is the **same memory** that `p.chain_field` points to. Two references exist:

1. The parent promise `p.chain_field` → used by `_ward_resolve_chain` when `p` resolves
2. The returned `ward_promise_pending(b)` → given to the caller as a linear obligation

`ward_promise_discard` (line 111) does `val+ ~promise_mk(_, _, _, _) = p` — a destructive pattern match that **frees the memory**. The parent's `chain_field` becomes a dangling pointer.

When `_ward_resolve_chain` later follows `chain_val` (line 60-61), it calls `ward_cloref1_invoke` on garbage data, producing an invalid WASM function table index → `call_indirect` trap.

## Why the caller must discard

The caller of `ward_promise_then` receives a `ward_promise_pending(b)` — a linear type that **must** be consumed exactly once. The available consumption operations are:

- `ward_promise_extract` — only works on `Resolved`, not `Pending`
- `ward_promise_then` — creates yet another chain node with the same dual-ownership problem
- `ward_promise_discard` — frees the underlying memory (the bug)

In real usage, the caller often only cares about the side effects in the callback (e.g., rendering DOM nodes, saving state). They don't need the return value. But they have no safe way to satisfy the linearity obligation:

```ats
(* Real code from quire: import EPUB, decompress chapter, render *)
val p2 = ward_promise_then<int><int>(
  ward_decompress(blob_handle, uncompressed_size),
  llam (result: int): ward_promise_pending(int) => let
    (* ... render chapter to DOM ... *)
  in ward_promise_return<int>(0) end)
val () = ward_promise_discard<int>(p2)  (* only option — but crashes *)
```

## Observed crash

```
Uncaught RuntimeError: index out of bounds
  at $110 (quire.wasm:…)      ← call_indirect on garbage
  at wardSetTimer (quire.wasm) ← timer-based resolution
  at ward_timer_fire (quire.wasm)
```

Occurs on every EPUB import in the deployed app. The async chain is: `ward_file_open` → `ward_file_read` → `ward_decompress` → `ward_promise_then` → callback → timer fires → `_ward_resolve_chain` → use-after-free.

## Suggested fix

The returned promise from `ward_promise_then` should be safe to discard without freeing the chain node's memory. Options:

1. **Don't return the chain node directly.** Return a lightweight handle (e.g., a non-linear token or a separate wrapper) that the caller can discard without freeing the underlying chain memory. The chain node stays alive, owned solely by the parent.

2. **Add a `ward_promise_detach` operation** that consumes the linear return value without freeing memory — explicitly transferring sole ownership to the chain.

3. **Reference counting on chain nodes.** `ward_promise_then` increments a refcount; `ward_promise_discard` decrements it and only frees when it reaches zero.

## Affected quire call sites

Three sites in `src/quire.dats` (lines 821, 985, 1070) — all follow the pattern:
```ats
val p2 = ward_promise_then<int><int>(async_op, llam (...) => ...)
val () = ward_promise_discard<int>(p2)
```

All three crash when the async operation completes.
