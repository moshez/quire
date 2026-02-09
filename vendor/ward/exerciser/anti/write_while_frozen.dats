(* ANTI-EXERCISER: write while frozen *)
(* This MUST fail to compile — can't use array after freezing *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val arr = ward_arr_alloc<byte> (16)
  val @(frozen, borrow) = ward_arr_freeze<byte> (arr)
  (* arr is consumed by freeze — can't write through it *)
  val () = ward_arr_set<byte> (arr, 0, $UNSAFE.cast{byte}(0))
  val () = ward_arr_drop<byte> (frozen, borrow)
  val arr2 = ward_arr_thaw<byte> (frozen)
  val () = ward_arr_free<byte> (arr2)
in end
