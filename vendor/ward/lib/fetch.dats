(* fetch.dats — Network fetch implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./fetch.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

extern fun _ward_js_fetch
  {un:pos}
  (url: ward_safe_text(un), url_len: int un, resolver_id: int)
  : void = "mac#ward_js_fetch"

extern fun _ward_bridge_stash_set_int
  (slot: int, v: int): void = "mac#ward_bridge_stash_set_int"

extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

implement
ward_fetch{un}(url, url_len) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_fetch(url, url_len, rid)
in p end

implement
ward_fetch_get_body_len() = _ward_bridge_stash_get_int(0)

implement
ward_fetch_get_body{n}(len) =
  ward_bridge_recv(_ward_bridge_stash_get_int(1), len)

implement
ward_on_fetch_complete(resolver_id, status, body_len) = let
  val () = _ward_bridge_stash_set_int(0, body_len)
in
  ward_promise_fire(resolver_id, status)
end
