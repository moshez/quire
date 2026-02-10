(* file.dats — File I/O bridge implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./file.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(*
 * $<M>UNSAFE justification:
 * [U-bw] castvwtp1{ptr}(out) — borrow ward_arr -> ptr for JS write
 *   (same as dom.dats [U2])
 *)

extern fun _ward_js_file_open
  (input_node_id: int, resolver_id: int): void = "mac#ward_js_file_open"

extern fun _ward_js_file_read
  (handle: int, file_offset: int, len: int, out: ptr): int = "mac#ward_js_file_read"

extern fun _ward_js_file_close
  (handle: int): void = "mac#ward_js_file_close"

extern fun _ward_bridge_stash_set_int
  (slot: int, v: int): void = "mac#ward_bridge_stash_set_int"

extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

implement
ward_file_open(input_node_id) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_file_open(input_node_id, rid)
in p end

implement
ward_file_get_size() = _ward_bridge_stash_get_int(0)

implement
ward_file_read{l}{n}(handle, file_offset, out, len) = let
  val outp = $UNSAFE.castvwtp1{ptr}(out) (* [U-bw] *)
in _ward_js_file_read(handle, file_offset, len, outp) end

implement
ward_file_close(handle) = _ward_js_file_close(handle)

implement
ward_on_file_open(resolver_id, handle, size) = let
  val () = _ward_bridge_stash_set_int(0, size)
in
  ward_promise_fire(resolver_id, handle)
end
