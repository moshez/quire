(* ANTI-EXERCISER: extract from chained promise *)
(* This MUST fail to compile — chained promises cannot be extracted *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload "./../../lib/promise.sats"
staload _ = "./../../lib/memory.dats"
staload _ = "./../../lib/promise.dats"

fun bad (): void = let
  val @(p, r) = ward_promise_create<int> ()
  val p2 = ward_promise_then<int><int> (p, llam (x) => ward_promise_return<int>(x + 1))
  (* p2 is Chained, extract requires Resolved — type error *)
  val v = ward_promise_extract<int> (p2)
  val () = ward_promise_resolve<int> (r, 0)
in end
