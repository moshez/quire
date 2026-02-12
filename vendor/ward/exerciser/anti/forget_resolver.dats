(* ANTI-EXERCISER: forget resolver *)
(* This MUST fail to compile — resolver is linear, must be consumed *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload "./../../lib/promise.sats"
staload _ = "./../../lib/memory.dats"
staload _ = "./../../lib/promise.dats"

fun bad (): void = let
  val @(p, r) = ward_promise_create<int> ()
  (* r is never resolved — linear type error *)
  val () = ward_promise_discard<int><Pending> (p)
in end
