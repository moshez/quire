(* ANTI-EXERCISER: array out of bounds *)
(* This MUST fail to compile — index >= array length *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val arr = ward_arr_alloc<int> (10)
  (* index 10 with array of length 10 — i < n violated *)
  val v = ward_arr_get<int> (arr, 10)
  val () = ward_arr_free<int> (arr)
in end
