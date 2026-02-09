(* clipboard.dats — Clipboard bridge implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./clipboard.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(*
 * $UNSAFE justification:
 * [U-res] castvwtp0 resolver erasure (same as event.dats [U4])
 *)

extern fun _ward_js_clipboard_write_text
  {n:nat}
  (text: ward_safe_text(n), text_len: int n, resolver: ptr)
  : void = "mac#ward_js_clipboard_write_text"

implement
ward_clipboard_write_text{n}(text, text_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r) (* [U-res] *)
  val () = _ward_js_clipboard_write_text(text, text_len, rp)
in p end

implement
ward_on_clipboard_complete(rp, success) = let
  val r = $UNSAFE.castvwtp0{ward_promise_resolver(int)}(rp) (* [U-res] *)
in
  ward_promise_resolve<int>(r, success)
end
