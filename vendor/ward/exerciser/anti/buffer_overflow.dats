(* ANTI-EXERCISER: buffer overflow via split *)
(* This MUST fail to compile — access beyond split boundary *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val arr = ward_arr_alloc<byte> (16)
  val @(head, tail) = ward_arr_split<byte> (arr, 8)
  (* head has 8 elements — index 8 is out of bounds (i < n violated) *)
  val v = ward_arr_get<byte> (head, 8)
  val whole = ward_arr_join<byte> (head, tail)
  val () = ward_arr_free<byte> (whole)
in end
