(* idb.sats — IndexedDB key-value storage for ward *)
(* Keys are ward_safe_text, values are byte arrays via borrow protocol. *)

staload "./memory.sats"
staload "./promise.sats"

(* Put a value into IndexedDB under a safe-text key.
   Borrows the value array — caller retains ownership. *)
fun ward_idb_put
  {kn:pos}{lv:agz}{vn:nat}
  (key: ward_safe_text(kn), key_len: int kn,
   val_data: !ward_arr_borrow(byte, lv, vn), val_len: int vn)
  : ward_promise_pending(int)

(* Get a value from IndexedDB. Resolves with length (0 = not found). *)
fun ward_idb_get
  {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn)
  : ward_promise_pending(int)

(* Retrieve the result buffer after a successful get.
   Only valid when the get promise resolved with n > 0. *)
fun ward_idb_get_result
  {n:pos}
  (len: int n)
  : [l:agz] ward_arr(byte, l, n)

(* Delete a key from IndexedDB. Resolves with 0. *)
fun ward_idb_delete
  {kn:pos}
  (key: ward_safe_text(kn), key_len: int kn)
  : ward_promise_pending(int)

(* WASM exports — called by JS host to fire resolvers *)
fun ward_idb_fire
  (resolver_ptr: ptr, status: int): void = "ext#ward_idb_fire"

fun ward_idb_fire_get
  (resolver_ptr: ptr, data_ptr: ptr, data_len: int): void = "ext#ward_idb_fire_get"
