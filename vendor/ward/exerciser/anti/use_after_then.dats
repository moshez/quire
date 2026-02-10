(* ANTI-EXERCISER: use after then *)
(* This MUST fail to compile — then consumes the promise *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload "./../../lib/promise.sats"
staload _ = "./../../lib/memory.dats"
staload _ = "./../../lib/promise.dats"

fun bad (): void = let
  val @(p, r) = ward_promise_create<int> ()
  val p2 = ward_promise_then<int><int> (p, llam (x) => ward_promise_return<int>(x + 1))
  (* p already consumed by then — reuse is type error *)
  val p3 = ward_promise_then<int><int> (p, llam (x) => ward_promise_return<int>(x + 2))
  val () = ward_promise_resolve<int> (r, 0)
  val () = ward_promise_discard<int><Pending> (p2)
  val () = ward_promise_discard<int><Pending> (p3)
in end
