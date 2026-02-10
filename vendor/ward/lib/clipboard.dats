(* clipboard.dats — Clipboard bridge implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./clipboard.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

extern fun _ward_js_clipboard_write_text
  {n:nat}
  (text: ward_safe_text(n), text_len: int n, resolver_id: int)
  : void = "mac#ward_js_clipboard_write_text"

implement
ward_clipboard_write_text{n}(text, text_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_clipboard_write_text(text, text_len, rid)
in p end

implement
ward_on_clipboard_complete(resolver_id, success) =
  ward_promise_fire(resolver_id, success)
