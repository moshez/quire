(* promise.sats — Linear promise system for ward *)
(* Promise(a, s) — no error parameter. Use Result(a, e) as your a if needed. *)

staload "./memory.sats"

(* Resolution state — compile-time only *)
datasort PromiseState =
  | Pending
  | Resolved
  | Chained

(* Linear promise indexed by state *)
absvtype ward_promise(a:vt@ype, s:PromiseState)

(* Linear resolver — the write end. Must be consumed exactly once. *)
absvtype ward_promise_resolver(a:vt@ype)

(* Convenience aliases *)
vtypedef ward_promise_pending(a:vt@ype) = ward_promise(a, Pending)
vtypedef ward_promise_resolved(a:vt@ype) = ward_promise(a, Resolved)
vtypedef ward_promise_chained(a:vt@ype) = ward_promise(a, Chained)

(* Zero-cost coercion: Pending -> Chained.
   Used when returning a bridge-created promise from a then callback.
   At runtime all promise states have the same representation. *)
castfn ward_promise_vow{a:vt@ype}
  (p: ward_promise_pending(a)): ward_promise_chained(a)

(* ============================================================
   Creation
   ============================================================ *)

fun{a:vt@ype}
ward_promise_create
  (): @(ward_promise_pending(a), ward_promise_resolver(a))

fun{a:vt@ype}
ward_promise_resolved
  (v: a): ward_promise_resolved(a)

(* Lift a value into a chain-context promise (monadic return).
   Used exclusively inside ward_promise_then callbacks. *)
fun{a:vt@ype}
ward_promise_return
  (v: a): ward_promise_chained(a)

(* ============================================================
   Resolution — consumes the resolver
   ============================================================ *)

fun{a:vt@ype}
ward_promise_resolve
  (r: ward_promise_resolver(a), v: a): void

(* ============================================================
   Consumption
   ============================================================ *)

fun{a:vt@ype}
ward_promise_extract
  (p: ward_promise_resolved(a)): a

fun{a:vt@ype} {s:PromiseState}
ward_promise_discard
  (p: ward_promise(a, s)): void

(* Monadic bind: attach a callback that returns a promise.
   The closure is linear (cloptr1) — it can capture linear values
   and is freed after invocation. Use ward_promise_return for immediate
   values, ward_promise_vow to coerce bridge results.
   Returns Chained: the result is chain-owned by the parent promise.
   Accepts any state via {s:PromiseState} — inferred, no call-site change. *)
fun{a:vt@ype}{b:vt@ype}
ward_promise_then
  {s:PromiseState}
  (p: ward_promise(a, s),
   f: (a) -<lin,cloptr1> ward_promise_chained(b)
  ): ward_promise_chained(b)

(* ============================================================
   Resolver stash — stores resolver in table, returns integer ID.
   Used by bridge modules to pass resolvers through JS host.
   Linear: stash consumes the resolver, unstash produces it.
   ============================================================ *)

fun ward_promise_stash
  (r: ward_promise_resolver(int)): int = "mac#ward_resolver_stash"

fun ward_promise_unstash
  (id: int): ward_promise_resolver(int) = "mac#ward_resolver_unstash"

(* Combined unstash + resolve — safe against bad IDs from JS.
   If ID is invalid or already consumed, silently no-ops. *)
fun ward_promise_fire
  (id: int, value: int): void = "mac#ward_resolver_fire"
