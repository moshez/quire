(* ANTI-EXERCISER: arena destroy with outstanding tokens *)
#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload _ = "./../../lib/memory.dats"
fun bad (): void = let
  val arena = ward_arena_create(4096)
  val @(tok, arr) = ward_arena_alloc<byte>(arena, 16)
  val () = ward_arena_destroy(arena)
in end
