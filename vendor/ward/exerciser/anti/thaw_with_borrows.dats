(* ANTI-EXERCISER: thaw with outstanding borrows *)
(* This MUST fail to compile — can't thaw when borrow count > 0 *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val arr = ward_arr_alloc<byte> (16)
  val @(frozen, borrow) = ward_arr_freeze<byte> (arr)
  (* thaw requires borrow count == 0, but we still have borrow *)
  val arr2 = ward_arr_thaw<byte> (frozen)
  val () = ward_arr_free<byte> (arr2)
in end
