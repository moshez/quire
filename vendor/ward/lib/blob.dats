(* blob.dats — Blob URL creation and revocation implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./blob.sats"
staload _ = "./memory.dats"

extern fun _ward_js_create_blob_url
  (data: ptr, data_len: int, mime: ptr, mime_len: int)
  : int = "mac#ward_js_create_blob_url"

extern fun _ward_js_revoke_blob_url
  (url: ptr, url_len: int): void = "mac#ward_js_revoke_blob_url"

extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

(*
 * $UNSAFE justifications:
 *
 * [B1] castvwtp1{ptr}(data), castvwtp1{ptr}(mime) in ward_create_blob_url:
 *   Extracts raw pointers from ward_arr_borrow(byte) and
 *   ward_safe_content_text to pass to ward_js_create_blob_url bridge
 *   import. This crosses the WASM/JS boundary — the host API requires
 *   raw memory addresses.
 *   Alternative considered: castfn cannot convert abstract viewtypes
 *   to ptr. No prelude function extracts ptr from ward_arr_borrow or
 *   ward_safe_content_text.
 *   User safety: both are !T (not consumed), lengths are
 *   dependent-typed. MIME uses ward_safe_content_text (compile-time
 *   character checked). No sequence of public API calls can trigger
 *   unsoundness.
 *
 * [B2] castvwtp1{ptr}(url) in ward_revoke_blob_url:
 *   Same WASM/JS boundary crossing as [B1]. Extracts raw pointer
 *   from borrow to pass URL bytes to the bridge for revocation.
 *   Alternative considered: same as [B1].
 *   User safety: url is !T (not consumed), length is dependent-typed.
 *)

implement
ward_create_blob_url{lb}{n}{lm}{m}(data, data_len, mime, mime_len) = let
  val dp = $UNSAFE.castvwtp1{ptr}(data) (* [B1] *)
  val mp = $UNSAFE.castvwtp1{ptr}(mime) (* [B1] *)
in
  _ward_js_create_blob_url(dp, data_len, mp, mime_len)
end

implement
ward_create_blob_url_get{n}(len) =
  ward_bridge_recv(_ward_bridge_stash_get_int(1), len)

implement
ward_revoke_blob_url{lb}{n}(url, url_len) = let
  val up = $UNSAFE.castvwtp1{ptr}(url) (* [B2] *)
in
  _ward_js_revoke_blob_url(up, url_len)
end
