(* ANTI-EXERCISER: unsafe character in safe text *)
(* This MUST fail to compile — '<' violates SAFE_CHAR constraint *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val b = ward_text_build(1)
  (* '<' = 60, not in [a-zA-Z0-9-] — SAFE_CHAR violated *)
  val b = ward_text_putc(b, 0, char2int1('<'))
  val t = ward_text_done(b)
in end
