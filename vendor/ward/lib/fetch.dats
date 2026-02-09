(* fetch.dats — Network fetch implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./fetch.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(*
 * $UNSAFE justifications:
 * [U-res] castvwtp0{ptr}(r) / castvwtp0{resolver}(rp) — resolver erasure
 *   (same as event.dats [U4])
 * [U-arr] castvwtp0{ward_arr(byte,l,n)}(p) — wrap stashed ptr (same as idb.dats [U8])
 *)

extern fun _ward_js_fetch
  {un:pos}
  (url: ward_safe_text(un), url_len: int un, resolver: ptr)
  : void = "mac#ward_js_fetch"

extern fun _ward_bridge_stash_set_ptr
  (p: ptr): void = "mac#ward_bridge_stash_set_ptr"

extern fun _ward_bridge_stash_get_ptr
  (): ptr = "mac#ward_bridge_stash_get_ptr"

extern fun _ward_bridge_stash_set_int
  (slot: int, v: int): void = "mac#ward_bridge_stash_set_int"

extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

implement
ward_fetch{un}(url, url_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r) (* [U-res] *)
  val () = _ward_js_fetch(url, url_len, rp)
in p end

implement
ward_fetch_get_body_len() = _ward_bridge_stash_get_int(0)

implement
ward_fetch_get_body{n}(len) = let
  val p = _ward_bridge_stash_get_ptr()
in $UNSAFE.castvwtp0{[l:agz] ward_arr(byte, l, n)}(p) end (* [U-arr] *)

implement
ward_on_fetch_complete(rp, status, body_ptr, body_len) = let
  val () = _ward_bridge_stash_set_ptr(body_ptr)
  val () = _ward_bridge_stash_set_int(0, body_len)
  val r = $UNSAFE.castvwtp0{ward_promise_resolver(int)}(rp) (* [U-res] *)
in
  ward_promise_resolve<int>(r, status)
end
