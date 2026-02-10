(* callback.sats — General-purpose callback registry
 *
 * Single mutable global table mapping integer IDs to closures,
 * each with an optional context pointer. Applications register
 * closures that use context to thread state across async boundaries.
 *
 * Implementation: flat array with linear scan, max 128 entries.
 *)

(* Register a callback for the given ID.
 * Overwrites any existing callback with the same ID. *)
fun ward_callback_register
  (id: int, cb: (int) -<cloref1> int): void

(* Register a callback with an associated context pointer.
 * The callback retrieves context via ward_callback_get_ctx. *)
fun ward_callback_register_ctx
  (id: int, ctx: ptr, cb: (int) -<cloref1> int): void

(* Fire the callback registered for the given ID.
 * No-op if no callback is registered for that ID. *)
fun ward_callback_fire
  (id: int, payload: int): void

(* Remove the callback for the given ID. No-op if not found. *)
fun ward_callback_remove
  (id: int): void

(* Get the context pointer for a registered callback.
 * Returns null if not found. *)
fun ward_callback_get_ctx
  (id: int): ptr

(* Update the context pointer for a registered callback.
 * No-op if not found. *)
fun ward_callback_set_ctx
  (id: int, ctx: ptr): void
