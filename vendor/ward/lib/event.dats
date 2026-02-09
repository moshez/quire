(* event.dats — Promise-based timer implementation *)
(* Trusted core: erases resolver to ptr for JS host, recovers on callback. *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload "./event.sats"
staload _ = "./memory.dats"
staload _ = "./promise.dats"

(*
 * $UNSAFE justifications:
 *
 * [U4] castvwtp0{ptr}(r) and castvwtp0{ward_promise_resolver(int)}(rp):
 *   Erases/recovers ward_promise_resolver(int) to/from ptr for passage
 *   through the JS host. The ptr is created by ward_timer_set and echoed
 *   back verbatim by JS via ward_timer_fire. No corruption is possible
 *   as long as JS doesn't modify the pointer value.
 *)

(* JS import — passes resolver ptr to host for later callback *)
extern fun _ward_js_set_timer
  (delay_ms: int, resolver_ptr: ptr): void = "mac#ward_set_timer"

implement
ward_timer_set(delay_ms) = let
  val @(p, r) = ward_promise_create<int>()
  val rp = $UNSAFE.castvwtp0{ptr}(r)   (* [U4] *)
  val () = _ward_js_set_timer(delay_ms, rp)
in p end

implement
ward_timer_fire(rp) = let
  val r = $UNSAFE.castvwtp0{ward_promise_resolver(int)}(rp)  (* [U4] *)
in
  ward_promise_resolve<int>(r, 0)
end
