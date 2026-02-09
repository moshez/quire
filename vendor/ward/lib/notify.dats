(* notify.dats — Push/notification bridge implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./notify.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(*
 * $UNSAFE justifications:
 * [U-res] castvwtp0 resolver erasure (same as event.dats [U4])
 * [U-arr] castvwtp0{ward_arr(byte,l,n)}(p) — wrap stashed ptr (same as idb.dats [U8])
 *)

extern fun _ward_js_notification_request_permission
  (resolver: ptr): void = "mac#ward_js_notification_request_permission"

extern fun _ward_js_notification_show
  {tn:pos}
  (title: ward_safe_text(tn), title_len: int tn)
  : void = "mac#ward_js_notification_show"

extern fun _ward_js_push_subscribe
  {vn:pos}
  (vapid: ward_safe_text(vn), vapid_len: int vn, resolver: ptr)
  : void = "mac#ward_js_push_subscribe"

extern fun _ward_js_push_get_subscription
  (resolver: ptr): void = "mac#ward_js_push_get_subscription"

extern fun _ward_bridge_stash_set_ptr
  (p: ptr): void = "mac#ward_bridge_stash_set_ptr"

extern fun _ward_bridge_stash_get_ptr
  (): ptr = "mac#ward_bridge_stash_get_ptr"

implement
ward_notification_request_permission() = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r) (* [U-res] *)
  val () = _ward_js_notification_request_permission(rp)
in p end

implement
ward_notification_show{tn}(title, title_len) =
  _ward_js_notification_show(title, title_len)

implement
ward_push_subscribe{vn}(vapid, vapid_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r) (* [U-res] *)
  val () = _ward_js_push_subscribe(vapid, vapid_len, rp)
in p end

implement
ward_push_get_result{n}(len) = let
  val p = _ward_bridge_stash_get_ptr()
in $UNSAFE.castvwtp0{[l:agz] ward_arr(byte, l, n)}(p) end (* [U-arr] *)

implement
ward_push_get_subscription() = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r) (* [U-res] *)
  val () = _ward_js_push_get_subscription(rp)
in p end

implement
ward_on_permission_result(rp, granted) = let
  val r = $UNSAFE.castvwtp0{ward_promise_resolver(int)}(rp) (* [U-res] *)
in
  ward_promise_resolve<int>(r, granted)
end

implement
ward_on_push_subscribe(rp, json_ptr, json_len) = let
  val () = _ward_bridge_stash_set_ptr(json_ptr)
  val r = $UNSAFE.castvwtp0{ward_promise_resolver(int)}(rp) (* [U-res] *)
in
  ward_promise_resolve<int>(r, json_len)
end
