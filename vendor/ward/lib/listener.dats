(* listener.dats — DOM event listener implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./listener.sats"
staload _ = "./memory.dats"

(*
 * $<M>UNSAFE justification:
 * [U-cb] castvwtp0{ptr}(callback) — erase closure to ptr for table storage.
 *   Same as promise.dats [U1]. Closure is heap-allocated cloref1, survives
 *   across multiple event fires. Recovered in ward_on_event.
 *)

extern fun _ward_js_add_event_listener
  {tn:pos}
  (node_id: int, event_type: ward_safe_text(tn), type_len: int tn,
   listener_id: int)
  : void = "mac#ward_js_add_event_listener"

extern fun _ward_js_remove_event_listener
  (listener_id: int): void = "mac#ward_js_remove_event_listener"

extern fun _ward_js_prevent_default
  (): void = "mac#ward_js_prevent_default"

(* Listener table — implemented in runtime.c *)
extern fun _ward_listener_set
  (id: int, cb: ptr): void = "mac#ward_listener_set"

extern fun _ward_listener_get
  (id: int): ptr = "mac#ward_listener_get"

(* Bridge int stash — stash_id in slot 1 *)
extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

implement
ward_add_event_listener{tn}
  (node_id, event_type, type_len, listener_id, callback) = let
  val cbp = $UNSAFE.castvwtp0{ptr}(callback) (* [U-cb] *)
  val () = _ward_listener_set(listener_id, cbp)
in _ward_js_add_event_listener(node_id, event_type, type_len, listener_id) end

implement
ward_remove_event_listener(listener_id) = let
  val () = _ward_listener_set(listener_id, the_null_ptr)
in _ward_js_remove_event_listener(listener_id) end

implement
ward_prevent_default() = _ward_js_prevent_default()

implement
ward_event_get_payload{n}(len) =
  ward_bridge_recv(_ward_bridge_stash_get_int(1), len)

implement
ward_on_event(listener_id, payload_len) = let
  val cbp = _ward_listener_get(listener_id)
in
  if ptr_isnot_null(cbp) then let
    val cb = $UNSAFE.cast{int -<cloref1> int}(cbp) (* [U-cb] recover *)
    val _ = cb(payload_len)
  in () end
  else ()
end
