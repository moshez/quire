(* callback.sats — General-purpose callback registry *)
(* Uses same listener table (IDs 0-127). Caller manages ID space. *)

fun ward_callback_register
  (id: int, cb: int -<cloref1> int): void

fun ward_callback_fire
  (id: int, payload: int): void

fun ward_callback_remove
  (id: int): void

(* WASM export — JS calls this to fire a general callback *)
fun ward_on_callback
  (id: int, payload: int): void = "ext#ward_on_callback"
