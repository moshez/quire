(* ANTI-EXERCISER: array too large for ward_arr *)
#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"
fun bad (): void = let
  val arr = ward_arr_alloc<byte> (1048577)
  val () = ward_arr_free<byte> (arr)
in end
