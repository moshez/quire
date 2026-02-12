(* listener.sats — DOM event listener bridge primitives *)

staload "./memory.sats"

(* Register an event listener. Callback receives payload_len;
   use ward_event_get_payload to retrieve the payload bytes. *)
fun ward_add_event_listener
  {tn:pos}
  (node_id: int, event_type: ward_safe_text(tn), type_len: int tn,
   listener_id: int, callback: int -<cloref1> int): void

fun ward_remove_event_listener(listener_id: int): void

(* Must be called synchronously within event callback *)
fun ward_prevent_default(): void

(* Retrieve event payload after callback fires *)
fun ward_event_get_payload
  {n:pos}
  (len: int n): [l:agz] ward_arr(byte, l, n)

(* WASM export — called by JS when event fires *)
fun ward_on_event
  (listener_id: int, payload_len: int): void = "ext#ward_on_event"
