(* ANTI-EXERCISER: double free *)
(* This MUST fail to compile — can't free the same linear value twice *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val arr = ward_arr_alloc<byte> (16)
  val () = ward_arr_free<byte> (arr)
  val () = ward_arr_free<byte> (arr)
in end
