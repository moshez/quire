(* notify.dats — Push/notification bridge implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./notify.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"


extern fun _ward_js_notification_request_permission
  (resolver_id: int): void = "mac#ward_js_notification_request_permission"

extern fun _ward_js_notification_show
  {tn:pos}
  (title: ward_safe_text(tn), title_len: int tn)
  : void = "mac#ward_js_notification_show"

extern fun _ward_js_push_subscribe
  {vn:pos}
  (vapid: ward_safe_text(vn), vapid_len: int vn, resolver_id: int)
  : void = "mac#ward_js_push_subscribe"

extern fun _ward_js_push_get_subscription
  (resolver_id: int): void = "mac#ward_js_push_get_subscription"

(* Bridge int stash — stash_id in slot 1 *)
extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

implement
ward_notification_request_permission() = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_notification_request_permission(rid)
in p end

implement
ward_notification_show{tn}(title, title_len) =
  _ward_js_notification_show(title, title_len)

implement
ward_push_subscribe{vn}(vapid, vapid_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_push_subscribe(vapid, vapid_len, rid)
in p end

implement
ward_push_get_result{n}(len) =
  ward_bridge_recv(_ward_bridge_stash_get_int(1), len)

implement
ward_push_get_subscription() = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_push_get_subscription(rid)
in p end

implement
ward_on_permission_result(resolver_id, granted) =
  ward_promise_fire(resolver_id, granted)

implement
ward_on_push_subscribe(resolver_id, json_len) =
  ward_promise_fire(resolver_id, json_len)
