(* ANTI-EXERCISER: unsafe character in content text *)
(* This MUST fail to compile — '<' violates SAFE_CONTENT_CHAR constraint *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"

fun bad (): void = let
  val b = ward_content_text_build(1)
  (* '<' = 60, excluded from SAFE_CONTENT_CHAR *)
  val b = ward_content_text_putc(b, 0, char2int1('<'))
  val t = ward_content_text_done(b)
  val () = ward_safe_content_text_free(t)
in end
