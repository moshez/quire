(* idb.dats — IndexedDB key-value storage implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./idb.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(*
 * $<M>UNSAFE justification:
 *
 * [U7] castvwtp1{ptr}(val_data) for ward_arr_borrow -> ptr:
 *   Same pattern as dom.dats [U2]. castvwtp1 (not castvwtp0) preserves the
 *   borrow — the value is !-qualified and not consumed.
 *)

(* JS imports — pass key/value pointers to host for async IDB operations *)
extern fun _ward_js_idb_put
  {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn,
   val_data: ptr, val_len: int, resolver_id: int)
  : void = "mac#ward_idb_js_put"

extern fun _ward_js_idb_get
  {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn, resolver_id: int)
  : void = "mac#ward_idb_js_get"

extern fun _ward_js_idb_delete
  {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn, resolver_id: int)
  : void = "mac#ward_idb_js_delete"

(* Bridge int stash — stash_id in slot 1 *)
extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

implement
ward_idb_put{kn}{lv}{vn}(key, key_len, val_data, val_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val vp = $UNSAFE.castvwtp1{ptr}(val_data)   (* [U7] *)
  val () = _ward_js_idb_put(key, key_len, vp, val_len, rid)
in p end

implement
ward_idb_get{kn}(key, key_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_idb_get(key, key_len, rid)
in p end

implement
ward_idb_get_result{n}(len) =
  ward_bridge_recv(_ward_bridge_stash_get_int(1), len)

implement
ward_idb_delete{kn}(key, key_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_idb_delete(key, key_len, rid)
in p end

implement
ward_idb_fire(resolver_id, status) =
  ward_promise_fire(resolver_id, status)

implement
ward_idb_fire_get(resolver_id, data_len) =
  ward_promise_fire(resolver_id, data_len)
