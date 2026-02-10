(* notify.sats — Push/notification bridge primitives *)

staload "./memory.sats"
staload "./promise.sats"

(* Request notification permission. Resolves with 1=granted, 0=denied. *)
fun ward_notification_request_permission
  (): ward_promise_pending(int)

(* Show a notification with title (no options variant). *)
fun ward_notification_show
  {tn:pos}
  (title: ward_safe_text(tn), title_len: int tn): void

(* Subscribe to push. Resolves with JSON length.
   JSON bytes stashed — retrieve with ward_push_get_result. *)
fun ward_push_subscribe
  {vn:pos}
  (vapid: ward_safe_text(vn), vapid_len: int vn)
  : ward_promise_pending(int)

fun ward_push_get_result
  {n:pos}
  (len: int n): [l:agz] ward_arr(byte, l, n)

(* Get existing push subscription. Same stash pattern. *)
fun ward_push_get_subscription
  (): ward_promise_pending(int)

(* WASM exports — called by JS *)
fun ward_on_permission_result
  (resolver_id: int, granted: int): void = "ext#ward_on_permission_result"

fun ward_on_push_subscribe
  (resolver_id: int, json_len: int)
  : void = "ext#ward_on_push_subscribe"
