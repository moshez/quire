(* ANTI-EXERCISER: use after free *)
(* This MUST fail to compile — ward_arr_free consumes the linear value *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val arr = ward_arr_alloc<byte> (16)
  val () = ward_arr_free<byte> (arr)
  (* arr is consumed — using it again is a type error *)
  val () = ward_arr_set<byte> (arr, 0, $UNSAFE.cast{byte}(0))
in end
