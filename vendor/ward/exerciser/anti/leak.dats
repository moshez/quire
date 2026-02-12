(* ANTI-EXERCISER: memory leak *)
(* This MUST fail to compile — linear value not consumed *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val arr = ward_arr_alloc<byte> (16)
  (* arr is never freed — linear type error *)
in end
