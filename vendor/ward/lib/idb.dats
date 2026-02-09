(* idb.dats — IndexedDB key-value storage implementation *)
(* Trusted core: erases resolver/value to ptr for JS host, recovers on callback. *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./idb.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(*
 * $UNSAFE justifications:
 *
 * [U5] castvwtp0{ptr}(r) and castvwtp0{ward_promise_resolver(int)}(rp):
 *   Same pattern as event.dats [U4]. Erases/recovers ward_promise_resolver(int)
 *   to/from ptr for passage through the JS host. The ptr is created by
 *   ward_idb_put/get/delete and echoed back verbatim by JS via ward_idb_fire
 *   or ward_idb_fire_get.
 *
 * [U7] castvwtp1{ptr}(val_data) for ward_arr_borrow -> ptr:
 *   Same pattern as dom.dats [U2]. castvwtp1 (not castvwtp0) preserves the
 *   borrow — the value is !-qualified and not consumed.
 *
 * [U8] castvwtp0{ward_arr(byte,l,n)}(p) for stashed ptr -> ward_arr:
 *   Wraps a ptr allocated by WASM malloc (called from JS) as a ward_arr.
 *   Justified: JS calls malloc(data_len), copies data_len bytes into the
 *   allocation, then stashes the ptr for ATS2 to recover. The resulting
 *   ward_arr(byte, l, n) is correctly sized and owned by the caller.
 *)

(* JS imports — pass key/value pointers to host for async IDB operations *)
extern fun _ward_js_idb_put
  {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn,
   val_data: ptr, val_len: int, resolver: ptr)
  : void = "mac#ward_idb_js_put"

extern fun _ward_js_idb_get
  {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn, resolver: ptr)
  : void = "mac#ward_idb_js_get"

extern fun _ward_js_idb_delete
  {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn, resolver: ptr)
  : void = "mac#ward_idb_js_delete"

(* IDB result stash — implemented in runtime.c *)
extern fun _ward_idb_stash_set
  (p: ptr, len: int): void = "mac#ward_idb_stash_set"

extern fun _ward_idb_stash_get_ptr
  (): ptr = "mac#ward_idb_stash_get_ptr"

implement
ward_idb_put{kn}{lv}{vn}(key, key_len, val_data, val_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r)          (* [U5] *)
  val vp = $UNSAFE.castvwtp1{ptr}(val_data)   (* [U7] *)
  val () = _ward_js_idb_put(key, key_len, vp, val_len, rp)
in p end

implement
ward_idb_get{kn}(key, key_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r)          (* [U5] *)
  val () = _ward_js_idb_get(key, key_len, rp)
in p end

implement
ward_idb_get_result{n}(len) = let
  val p = _ward_idb_stash_get_ptr()
in $UNSAFE.castvwtp0{[l:agz] ward_arr(byte, l, n)}(p) end (* [U8] *)

implement
ward_idb_delete{kn}(key, key_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r)          (* [U5] *)
  val () = _ward_js_idb_delete(key, key_len, rp)
in p end

implement
ward_idb_fire(rp, status) = let
  val r = $UNSAFE.castvwtp0{ward_promise_resolver(int)}(rp)  (* [U5] *)
in
  ward_promise_resolve<int>(r, status)
end

implement
ward_idb_fire_get(rp, data_ptr, data_len) = let
  val () = _ward_idb_stash_set(data_ptr, data_len)
  val r = $UNSAFE.castvwtp0{ward_promise_resolver(int)}(rp)  (* [U5] *)
in
  ward_promise_resolve<int>(r, data_len)
end
