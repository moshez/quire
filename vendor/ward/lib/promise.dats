(* promise.dats — Linear promise implementation *)
(* Trusted core. Chain resolution + then via C helpers *)
(* ward_promise_resolve_chain / ward_promise_then_impl. *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload _ = "./memory.dats"

(*
 * Promise layout: 4 pointer-sized slots
 *   [0] = state (0=pending, 1=resolved), cast to/from ptr
 *   [1] = value (resolved value, cast to ptr)
 *   [2] = callback (cloref1 or null)
 *   [3] = chain (downstream promise or null)
 *)

extern fun _ward_promise_alloc
  (): [l:agz] ptr l = "mac#ward_promise_alloc"

local

assume ward_promise(a, s) = ptr
assume ward_promise_resolver(a) = ptr

in

(*
 * $UNSAFE justifications — each use is marked with its pattern tag.
 *
 * [U1] castvwtp0{ptr}(v) and castvwtp0{a}(vp) (resolved, return, resolve,
 *   extract, then):
 *   Erases/recovers typed value a to/from ptr for storage in pointer-sized
 *   slots, or erases closure to ptr for passage to C helper.
 *   Alternative considered: use ward_arr<ptr> for the 4 slots, replacing
 *   $extfcall slot access with safe ward_arr_get/set.
 *   Rejected: ward_arr introduces existential [l:addr] that cannot be
 *   unified with assume ward_promise(a,s) at type-assume time. Even if it
 *   could, the a<->ptr erasure casts remain unavoidable — the slot type
 *   is ptr but the stored values are heterogeneous (a, closure, chain ptr).
 *
 * [U2] cast{ptr}(1) (resolved, return):
 *   Stores integer state flag (1=resolved) in a ptr-sized slot.
 *   Inherent to the slot layout: all 4 fields are ptr-sized. No way to
 *   store an int in a ptr slot without a cast.
 *)

implement{a}
ward_promise_create() = let
  val p = _ward_promise_alloc()
in @(p, p) end

implement{a}
ward_promise_resolved(v) = let
  val p = _ward_promise_alloc()
  val () = $extfcall(void, "ward_slot_set", p, 0, $UNSAFE.cast{ptr}(1)) (* [U2] *)
  val () = $extfcall(void, "ward_slot_set", p, 1,
                     $UNSAFE.castvwtp0{ptr}(v)) (* [U1] *)
in p end

implement{a}
ward_promise_return(v) = let
  val p = _ward_promise_alloc()
  val () = $extfcall(void, "ward_slot_set", p, 0, $UNSAFE.cast{ptr}(1)) (* [U2] *)
  val () = $extfcall(void, "ward_slot_set", p, 1,
                     $UNSAFE.castvwtp0{ptr}(v)) (* [U1] *)
in p end

implement{a}
ward_promise_resolve(r, v) = let
  val vp = $UNSAFE.castvwtp0{ptr}(v) (* [U1] *)
in
  $extfcall(void, "ward_promise_resolve_chain", r, vp)
end

implement{a}
ward_promise_extract(p) = let
  val vp = $extfcall(ptr, "ward_slot_get", p, 1)
  val () = $extfcall(void, "free", p)
in $UNSAFE.castvwtp0{a}(vp) end (* [U1] *)

implement{a}{s}
ward_promise_discard(p) = $extfcall(void, "free", p)

implement{a}{b}
ward_promise_then(p, f) =
  $extfcall(ptr, "ward_promise_then_impl", p,
            $UNSAFE.castvwtp0{ptr}(f)) (* [U1] *)

end (* local *)
