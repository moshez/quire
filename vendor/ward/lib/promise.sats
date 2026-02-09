(* promise.sats — Linear promise system for ward *)
(* Promise(a, s) — no error parameter. Use Result(a, e) as your a if needed. *)

staload "./memory.sats"

(* Resolution state — compile-time only *)
datasort PromiseState =
  | Pending
  | Resolved

(* Linear promise indexed by state *)
absvtype ward_promise(a:t@ype, s:PromiseState)

(* Linear resolver — the write end. Must be consumed exactly once. *)
absvtype ward_promise_resolver(a:t@ype)

(* Convenience aliases *)
vtypedef ward_promise_pending(a:t@ype) = ward_promise(a, Pending)
vtypedef ward_promise_resolved(a:t@ype) = ward_promise(a, Resolved)

(* ============================================================
   Creation
   ============================================================ *)

fun{a:t@ype}
ward_promise_create
  (): @(ward_promise_pending(a), ward_promise_resolver(a))

fun{a:t@ype}
ward_promise_resolved
  (v: a): ward_promise_resolved(a)

(* Lift a value into a pending promise (monadic return). *)
fun{a:t@ype}
ward_promise_return
  (v: a): ward_promise_pending(a)

(* ============================================================
   Resolution — consumes the resolver
   ============================================================ *)

fun{a:t@ype}
ward_promise_resolve
  (r: ward_promise_resolver(a), v: a): void

(* ============================================================
   Consumption
   ============================================================ *)

fun{a:t@ype}
ward_promise_extract
  (p: ward_promise_resolved(a)): a

fun{a:t@ype} {s:PromiseState}
ward_promise_discard
  (p: ward_promise(a, s)): void

(* Monadic bind: attach a callback that returns a promise.
   Use ward_promise_return for immediate values. *)
fun{a:t@ype} {b:t@ype}
ward_promise_then
  (p: ward_promise_pending(a),
   f: a -<cloref1> ward_promise_pending(b)
  ): ward_promise_pending(b)
