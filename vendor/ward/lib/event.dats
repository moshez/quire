(* event.dats — Promise-based timer implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./event.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(* JS import — passes resolver ID to host for later callback *)
extern fun _ward_js_set_timer
  (delay_ms: int, resolver_id: int): void = "mac#ward_set_timer"

implement
ward_timer_set(delay_ms) = let
  val @(p, r) = ward_promise_create<int>()
  val rid = ward_promise_stash(r)
  val () = _ward_js_set_timer(delay_ms, rid)
in p end

implement
ward_timer_fire(resolver_id) =
  ward_promise_fire(resolver_id, 0)
