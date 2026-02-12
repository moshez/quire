(* decompress.dats — Decompression bridge implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./decompress.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(*
 * $<M>UNSAFE justification:
 * [U-bw] castvwtp1{ptr}(data/out) — borrow -> ptr (same as dom.dats [U2])
 *)

extern fun _ward_js_decompress
  (data: ptr, data_len: int, method: int, resolver_id: int)
  : void = "mac#ward_js_decompress"

extern fun _ward_js_blob_read
  (handle: int, blob_offset: int, len: int, out: ptr): int = "mac#ward_js_blob_read"

extern fun _ward_js_blob_free
  (handle: int): void = "mac#ward_js_blob_free"

extern fun _ward_bridge_stash_set_int
  (slot: int, v: int): void = "mac#ward_bridge_stash_set_int"

extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

implement
ward_decompress{lb}{n}(data, data_len, method) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val dp = $UNSAFE.castvwtp1{ptr}(data) (* [U-bw] *)
  val () = _ward_js_decompress(dp, data_len, method, rid)
in p end

implement
ward_decompress_get_len() = _ward_bridge_stash_get_int(0)

implement
ward_blob_read{l}{n}(handle, blob_offset, out, len) = let
  val outp = $UNSAFE.castvwtp1{ptr}(out) (* [U-bw] *)
in _ward_js_blob_read(handle, blob_offset, len, outp) end

implement
ward_blob_free(handle) = _ward_js_blob_free(handle)

implement
ward_on_decompress_complete(resolver_id, handle, decompressed_len) = let
  val () = _ward_bridge_stash_set_int(0, decompressed_len)
in
  ward_promise_fire(resolver_id, handle)
end
