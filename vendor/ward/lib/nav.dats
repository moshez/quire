(* nav.dats — Navigation bridge implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./nav.sats"
staload _ = "./memory.dats"

(*
 * $<M>UNSAFE justification:
 * [U-bw] castvwtp1{ptr}(arr) — borrow ward_arr -> ptr for JS out-buffer
 *   (same as dom.dats [U2]). JS writes synchronously during the call.
 *)

extern fun _ward_js_get_url
  (out: ptr, max_len: int): int = "mac#ward_js_get_url"

extern fun _ward_js_get_url_hash
  (out: ptr, max_len: int): int = "mac#ward_js_get_url_hash"

extern fun _ward_js_set_url_hash
  {n:nat}
  (hash: ward_safe_text(n), hash_len: int n)
  : void = "mac#ward_js_set_url_hash"

extern fun _ward_js_replace_state
  {n:nat}
  (url: ward_safe_text(n), url_len: int n)
  : void = "mac#ward_js_replace_state"

extern fun _ward_js_push_state
  {n:nat}
  (url: ward_safe_text(n), url_len: int n)
  : void = "mac#ward_js_push_state"

implement
ward_get_url{l}{n}(out, max_len) = let
  val outp = $UNSAFE.castvwtp1{ptr}(out) (* [U-bw] *)
in _ward_js_get_url(outp, max_len) end

implement
ward_get_url_hash{l}{n}(out, max_len) = let
  val outp = $UNSAFE.castvwtp1{ptr}(out) (* [U-bw] *)
in _ward_js_get_url_hash(outp, max_len) end

implement
ward_set_url_hash{n}(hash, hash_len) =
  _ward_js_set_url_hash(hash, hash_len)

implement
ward_replace_state{n}(url, url_len) =
  _ward_js_replace_state(url, url_len)

implement
ward_push_state{n}(url, url_len) =
  _ward_js_push_state(url, url_len)
