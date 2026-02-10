(* callback.dats — Callback registry implementation
 *
 * All dispatch logic in ATS2. Storage backed by C arrays in runtime.c
 * accessed via mac# extern functions.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./callback.sats"

#define WARD_MAX_CALLBACKS 128

(*
 * $UNSAFE justifications:
 * [U-store] castvwtp0{ptr}(cb) — erase closure to ptr for table storage.
 *   Same pattern as listener.dats [U-cb]. Closure is heap-allocated cloref1,
 *   survives across multiple fires. Recovered in ward_callback_fire.
 * [U-invoke] cast{ptr}(payload) — pass int as ptr to ward_cloref1_invoke.
 *   Same as listener.dats ward_on_event. The closure extracts the int.
 *)

(* Storage accessors — implemented in runtime.c *)
extern fun _ward_cb_get_id(idx: int): int = "mac#ward_cb_get_id"
extern fun _ward_cb_set_id(idx: int, v: int): void = "mac#ward_cb_set_id"
extern fun _ward_cb_get_fn(idx: int): ptr = "mac#ward_cb_get_fn"
extern fun _ward_cb_set_fn(idx: int, v: ptr): void = "mac#ward_cb_set_fn"
extern fun _ward_cb_get_ctx(idx: int): ptr = "mac#ward_cb_get_ctx"
extern fun _ward_cb_set_ctx(idx: int, v: ptr): void = "mac#ward_cb_set_ctx"
extern fun _ward_cb_get_count(): int = "mac#ward_cb_get_count"
extern fun _ward_cb_set_count(n: int): void = "mac#ward_cb_set_count"

(* Linear scan helper — find entry index for id, or count if not found *)
fn _find_entry(id: int): int = let
  val n = _ward_cb_get_count()
  fun loop(i: int): int =
    if i >= n then n
    else if _ward_cb_get_id(i) = id then i
    else loop(i + 1)
in loop(0) end

implement
ward_callback_register(id, cb) = let
  val cbp = $UNSAFE.castvwtp0{ptr}(cb) (* [U-store] *)
  val n = _ward_cb_get_count()
  val idx = _find_entry(id)
in
  if idx < WARD_MAX_CALLBACKS then let
    val () = _ward_cb_set_id(idx, id)
    val () = _ward_cb_set_fn(idx, cbp)
  in
    if idx = n then _ward_cb_set_count(n + 1)
    else ()
  end
  else () (* table full *)
end

implement
ward_callback_register_ctx(id, ctx, cb) = let
  val cbp = $UNSAFE.castvwtp0{ptr}(cb) (* [U-store] *)
  val n = _ward_cb_get_count()
  val idx = _find_entry(id)
in
  if idx < WARD_MAX_CALLBACKS then let
    val () = _ward_cb_set_id(idx, id)
    val () = _ward_cb_set_fn(idx, cbp)
    val () = _ward_cb_set_ctx(idx, ctx)
  in
    if idx = n then _ward_cb_set_count(n + 1)
    else ()
  end
  else () (* table full *)
end

implement
ward_callback_fire(id, payload) = let
  val n = _ward_cb_get_count()
  fun find(i: int): void =
    if i >= n then ()
    else if _ward_cb_get_id(i) = id then let
      val cbp = _ward_cb_get_fn(i)
    in
      if $UNSAFE.cast{int}(cbp) > 0 then let
        val _ = $extfcall(ptr, "ward_cloref1_invoke", cbp,
                          $UNSAFE.cast{ptr}(payload)) (* [U-invoke] *)
      in () end
      else ()
    end
    else find(i + 1)
in find(0) end

implement
ward_callback_remove(id) = let
  val n = _ward_cb_get_count()
  val idx = _find_entry(id)
in
  if idx < n then let
    val last = n - 1
    val () = if idx < last then let
      val () = _ward_cb_set_id(idx, _ward_cb_get_id(last))
      val () = _ward_cb_set_fn(idx, _ward_cb_get_fn(last))
      val () = _ward_cb_set_ctx(idx, _ward_cb_get_ctx(last))
    in end
    else ()
    val () = _ward_cb_set_count(last)
  in end
  else ()
end

implement
ward_callback_get_ctx(id) = let
  val n = _ward_cb_get_count()
  val idx = _find_entry(id)
in
  if idx < n then _ward_cb_get_ctx(idx)
  else the_null_ptr
end

implement
ward_callback_set_ctx(id, ctx) = let
  val n = _ward_cb_get_count()
  val idx = _find_entry(id)
in
  if idx < n then _ward_cb_set_ctx(idx, ctx)
  else ()
end
