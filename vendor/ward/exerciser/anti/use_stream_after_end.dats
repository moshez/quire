(* ANTI-EXERCISER: use stream after end *)
(* This MUST fail to compile — stream is consumed by stream_end *)

#include "share/atspre_staload.hats"
staload "./../../lib/memory.sats"
staload "./../../lib/dom.sats"
staload _ = "./../../lib/memory.dats"
staload _ = "./../../lib/dom.dats"

fun bad (): void = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val dom = ward_dom_stream_end(s)
  (* s is consumed by stream_end — can't use it again *)
  val s2 = ward_dom_stream_remove_children(s, 1)
  val dom2 = ward_dom_stream_end(s2)
  val () = ward_dom_fini(dom)
  val () = ward_dom_fini(dom2)
in end
