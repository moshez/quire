(* promise.dats — Linear promise implementation *)
(* Trusted core. Promise struct is an ATS2 datavtype with @/fold@ access. *)
(* Chain resolution + then logic in ATS2. Closure helpers stay in C. *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./promise.sats"
staload _ = "./memory.dats"

(* Forward declaration with stable C name — callable from templates *)
extern fun _ward_resolve_chain
  (p: ptr, v: ptr): void = "mac#_ward_resolve_chain"

local

datavtype promise_vt =
  | promise_mk of (int(*state: 0=pending, 1=resolved*),
                    ptr(*value*), ptr(*cb*), ptr(*chain*))

assume ward_promise(a, s) = promise_vt
assume ward_promise_resolver(a) = ptr

(*
 * $<M>UNSAFE justifications — each use is marked with its pattern tag.
 *
 * [U1] castvwtp0{ptr}(v) and castvwtp0{a}(vp) (resolved, return, resolve,
 *   extract, then):
 *   Erases/recovers typed value a to/from ptr for storage in the datavtype's
 *   value field. The field type is ptr but the stored values are typed (a,
 *   closure, chain ptr). This erasure is unavoidable: ATS2 can't express
 *   existentially-typed fields in a datavtype shared across different a types.
 *
 * [U3] castvwtp0{promise_vt}(p) and castvwtp1{ptr}(pv):
 *   Recovers datavtype from resolver ptr or chain ptr for @/fold@ access.
 *   Necessary because resolver crosses JS boundary as raw ptr, and chain
 *   links are existentially typed (each may carry a different type a).
 *
 * [U4] castvwtp0{ptr}(pv) to consume datavtype without freeing:
 *   Used when promise stays alive in the chain but ATS2's linear tracker
 *   needs the value consumed. The underlying memory is not freed — it is
 *   still reachable via chain pointers or resolver aliases.
 *)

(* --- Internal: resolve chain (replaces C ward_promise_resolve_chain) ---
   Walks the chain starting at promise ptr p, setting each node resolved with
   value v. When a callback returns a pending inner promise, wires forwarding. *)

implement
_ward_resolve_chain(p, v) = let
  val pv = $UNSAFE.castvwtp0{promise_vt}(p)  (* [U3] recover from ptr *)
  val+ @promise_mk(state, value, cb, chain) = pv
  val () = state := 1
  val () = value := v
  val cb_val = cb
  val chain_val = chain
  prval () = fold@(pv)
  val _  = $UNSAFE.castvwtp0{ptr}(pv)  (* [U4] forget — node stays alive *)
in
  if ptr_isnot_null(cb_val) then
    if ptr_isnot_null(chain_val) then let
      val inner_ptr = $extfcall(ptr, "ward_cloref1_invoke", cb_val, v)
      val ipv = $UNSAFE.castvwtp0{promise_vt}(inner_ptr)  (* [U3] *)
      val+ @promise_mk(is2, iv, _, ic) = ipv
    in
      if is2 > 0 then let
        val iv_val = iv
        prval () = fold@(ipv)
        val _ = $UNSAFE.castvwtp0{ptr}(ipv)  (* [U4] forget *)
      in _ward_resolve_chain(chain_val, iv_val) end  (* tail call *)
      else let
        val () = ic := chain_val  (* wire inner -> chain *)
        prval () = fold@(ipv)
        val _ = $UNSAFE.castvwtp0{ptr}(ipv)  (* [U4] forget *)
      in end
    end
    else ()
  else if ptr_isnot_null(chain_val) then
    _ward_resolve_chain(chain_val, v)  (* tail call *)
  else ()
end

in

implement{a}
ward_promise_create() = let
  val pv = promise_mk(0, the_null_ptr, the_null_ptr, the_null_ptr)
  val rp = $UNSAFE.castvwtp1{ptr}(pv)  (* [U3] borrow — resolver aliases promise *)
in @(pv, rp) end

implement{a}
ward_promise_resolved(v) =
  promise_mk(1, $UNSAFE.castvwtp0{ptr}(v), the_null_ptr, the_null_ptr) (* [U1] *)

implement{a}
ward_promise_return(v) =
  promise_mk(1, $UNSAFE.castvwtp0{ptr}(v), the_null_ptr, the_null_ptr) (* [U1] *)

implement{a}
ward_promise_resolve(r, v) = let
  val vp = $UNSAFE.castvwtp0{ptr}(v) (* [U1] *)
in
  _ward_resolve_chain(r, vp)
end

implement{a}
ward_promise_extract(p) = let
  val+ ~promise_mk(_, vp, _, _) = p
in $UNSAFE.castvwtp0{a}(vp) end (* [U1] *)

implement{a}{s}
ward_promise_discard(p) = let
  val+ ~promise_mk(_, _, _, _) = p
in end

implement{a}{b}
ward_promise_then(p, f) = let
  val chain = promise_mk(0, the_null_ptr, the_null_ptr, the_null_ptr)
  val+ @promise_mk(state, value, cb, chain_field) = p
  val is_resolved = state > 0
  val v = value
  val result =
    if is_resolved then let
      prval () = fold@(p)
      val _ = $UNSAFE.castvwtp0{ptr}(p)  (* [U4] forget consumed promise *)
      val fp = $UNSAFE.castvwtp0{ptr}(f) (* [U1] erase closure to ptr *)
      val inner_ptr = $extfcall(ptr, "ward_cloref1_invoke", fp, v)
      val () = $extfcall(void, "free", fp)  (* free linear closure *)
      val ipv = $UNSAFE.castvwtp0{promise_vt}(inner_ptr)  (* [U3] *)
      val+ @promise_mk(is2, iv, _, ic) = ipv
      val inner_resolved = is2 > 0
    in
      if inner_resolved then let
        val iv_val = iv
        prval () = fold@(ipv)
        val _ = $UNSAFE.castvwtp0{ptr}(ipv)  (* [U4] forget *)
        val+ @promise_mk(cs, cv, _, _) = chain
        val () = cs := 1
        val () = cv := iv_val
        prval () = fold@(chain)
      in $UNSAFE.castvwtp0{ptr}(chain) end  (* [U4] return as ptr *)
      else let
        val chain_ptr = $UNSAFE.castvwtp1{ptr}(chain)  (* [U3] borrow *)
        val () = ic := chain_ptr  (* wire inner -> chain *)
        prval () = fold@(ipv)
        val _ = $UNSAFE.castvwtp0{ptr}(ipv)  (* [U4] forget *)
        val _ = $UNSAFE.castvwtp0{ptr}(chain)  (* [U4] forget — owned by inner *)
      in chain_ptr end
    end
    else let
      val fp = $UNSAFE.castvwtp0{ptr}(f) (* [U1] erase closure to ptr *)
      val wrapped = $extfcall(ptr, "_ward_cloptr1_wrap", fp)
      val chain_ptr = $UNSAFE.castvwtp1{ptr}(chain)  (* [U3] borrow *)
      val () = cb := wrapped
      val () = chain_field := chain_ptr
      prval () = fold@(p)
      val _ = $UNSAFE.castvwtp0{ptr}(p)  (* [U4] forget — stays in chain *)
      val _ = $UNSAFE.castvwtp0{ptr}(chain)  (* [U4] forget — owned by p *)
    in chain_ptr end
  : ptr (* if returns ptr *)
in
  $UNSAFE.castvwtp0{promise_vt}(result)  (* [U3] recover *)
end

end (* local *)
