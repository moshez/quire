(* dom.dats — Ward DOM implementation *)
(* Trusted core: writes diff protocol bytes to owned buffer, flushes to bridge. *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./dom.sats"
staload _ = "./memory.dats"

(* Bridge flush — host-provided *)
extern fun _ward_dom_flush
  (buf: ptr, len: int): void = "mac#ward_dom_flush"

(* Allocator *)
extern fun _ward_malloc_bytes
  (n: int): [l:agz] ptr l = "mac#malloc"

local

assume ward_dom_state(l) = ptr l

in

(*
 * $UNSAFE justifications — each use is marked with its pattern tag.
 *
 * [U1] cast{ptr}(tag) for ward_safe_text -> ptr (create_element, set_attr):
 *   ward_safe_text is abstype assumed as ptr in memory.dats, but that
 *   assumption is invisible from this module (cross-module abstraction).
 *   Alternative considered: expose ward_safe_text_ptr in memory.sats.
 *   Rejected: would let user code obtain raw pointers, breaking encapsulation.
 *
 * [U2] castvwtp1{ptr}(text/value) for ward_arr_borrow -> ptr
 *   (set_text, set_attr, set_style):
 *   Same cross-module barrier. castvwtp1 (not castvwtp0) preserves the
 *   borrow — the value is !-qualified and not consumed.
 *   Alternative considered: expose ward_arr_borrow_ptr in memory.sats.
 *   Rejected: same reason — would expose raw pointers to user code.
 *)

implement
ward_dom_init() = _ward_malloc_bytes(WARD_DOM_BUF_CAP_DYN)

implement
ward_dom_fini{l}(state) = $extfcall(void, "free", state)

(*
 * Diff protocol (little-endian):
 *   CREATE_ELEMENT: [1:op=4] [4:node_id] [4:parent_id] [1:tag_len] [tag_data]
 *   SET_TEXT:       [1:op=1] [4:node_id] [1:lo] [1:hi]  [text_data]
 *   SET_ATTR:       [1:op=2] [4:node_id] [1:name_len]   [name_data]
 *                                        [1:lo] [1:hi]  [value_data]
 *   REMOVE_CHILDREN:[1:op=3] [4:node_id]
 *)

implement
ward_dom_create_element{l}{tl}
  (state, node_id, parent_id, tag, tag_len) = let
  val tl: int = tag_len
  val () = $extfcall(void, "ward_set_byte", state, 0, 4)
  val () = $extfcall(void, "ward_set_i32", state, 1, node_id)
  val () = $extfcall(void, "ward_set_i32", state, 5, parent_id)
  val () = $extfcall(void, "ward_set_byte", state, 9, tl)
  val () = $extfcall(void, "ward_copy_at", state, 10,
                     $UNSAFE.cast{ptr}(tag), tl) (* [U1] *)
  val () = _ward_dom_flush(state, 10 + tl)
in state end

implement
ward_dom_set_text{l}{lb}{tl}
  (state, node_id, text, text_len) = let
  val tl: int = text_len
  val () = $extfcall(void, "ward_set_byte", state, 0, 1)
  val () = $extfcall(void, "ward_set_i32", state, 1, node_id)
  val () = $extfcall(void, "ward_set_byte", state, 5, tl)
  val () = $extfcall(void, "ward_set_byte", state, 6, 0)
  val () = $extfcall(void, "ward_copy_at", state, 7,
                     $UNSAFE.castvwtp1{ptr}(text), tl) (* [U2] *)
  val () = _ward_dom_flush(state, 7 + tl)
in state end

implement
ward_dom_set_attr{l}{lb}{nl}{vl}
  (state, node_id, attr_name, name_len, value, value_len) = let
  val nl: int = name_len
  val vl: int = value_len
  val () = $extfcall(void, "ward_set_byte", state, 0, 2)
  val () = $extfcall(void, "ward_set_i32", state, 1, node_id)
  val () = $extfcall(void, "ward_set_byte", state, 5, nl)
  val () = $extfcall(void, "ward_copy_at", state, 6,
                     $UNSAFE.cast{ptr}(attr_name), nl) (* [U1] *)
  val off = 6 + nl
  val () = $extfcall(void, "ward_set_byte", state, off, vl)
  val () = $extfcall(void, "ward_set_byte", state, off + 1, 0)
  val () = $extfcall(void, "ward_copy_at", state, off + 2,
                     $UNSAFE.castvwtp1{ptr}(value), vl) (* [U2] *)
  val () = _ward_dom_flush(state, off + 2 + vl)
in state end

implement
ward_dom_set_style{l}{lb}{vl}
  (state, node_id, value, value_len) = let
  val vl: int = value_len
  (* Hardcoded "style" = 115 116 121 108 101 *)
  val () = $extfcall(void, "ward_set_byte", state, 0, 2)
  val () = $extfcall(void, "ward_set_i32", state, 1, node_id)
  val () = $extfcall(void, "ward_set_byte", state, 5, 5)
  val () = $extfcall(void, "ward_set_byte", state, 6, 115)
  val () = $extfcall(void, "ward_set_byte", state, 7, 116)
  val () = $extfcall(void, "ward_set_byte", state, 8, 121)
  val () = $extfcall(void, "ward_set_byte", state, 9, 108)
  val () = $extfcall(void, "ward_set_byte", state, 10, 101)
  val () = $extfcall(void, "ward_set_byte", state, 11, vl)
  val () = $extfcall(void, "ward_set_byte", state, 12, 0)
  val () = $extfcall(void, "ward_copy_at", state, 13,
                     $UNSAFE.castvwtp1{ptr}(value), vl) (* [U2] *)
  val () = _ward_dom_flush(state, 13 + vl)
in state end

implement
ward_dom_remove_children{l}(state, node_id) = let
  val () = $extfcall(void, "ward_set_byte", state, 0, 3)
  val () = $extfcall(void, "ward_set_i32", state, 1, node_id)
  val () = _ward_dom_flush(state, 5)
in state end

(*
 * [U3] ward_dom_store / ward_dom_load:
 *   Erases/recovers ward_dom_state to/from ptr via global storage.
 *   Justified: cross-module async boundary requires global stash.
 *   Alternative considered: pass state through promise chain.
 *   Rejected: promise chain carries t@ype values, not viewtypes.
 *)

implement
ward_dom_store{l}(state) =
  $extfcall(void, "ward_dom_global_set", state)

implement
ward_dom_load() = let
  val p = $extfcall(ptr, "ward_dom_global_get")
in $UNSAFE.cast{[l:agz] ptr l}(p) end (* [U3] *)

(*
 * [U1] cast{ptr}(text) for ward_safe_text -> ptr (set_safe_text, set_attr_safe):
 *   Same cross-module barrier as create_element. ward_safe_text is abstype
 *   assumed as ptr in memory.dats but opaque here.
 *)

implement
ward_dom_set_safe_text{l}{tl}
  (state, node_id, text, text_len) = let
  val tl: int = text_len
  val () = $extfcall(void, "ward_set_byte", state, 0, 1)
  val () = $extfcall(void, "ward_set_i32", state, 1, node_id)
  val () = $extfcall(void, "ward_set_byte", state, 5, tl)
  val () = $extfcall(void, "ward_set_byte", state, 6, 0)
  val () = $extfcall(void, "ward_copy_at", state, 7,
                     $UNSAFE.cast{ptr}(text), tl) (* [U1] *)
  val () = _ward_dom_flush(state, 7 + tl)
in state end

implement
ward_dom_set_attr_safe{l}{nl}{vl}
  (state, node_id, attr_name, name_len, value, value_len) = let
  val nl: int = name_len
  val vl: int = value_len
  val () = $extfcall(void, "ward_set_byte", state, 0, 2)
  val () = $extfcall(void, "ward_set_i32", state, 1, node_id)
  val () = $extfcall(void, "ward_set_byte", state, 5, nl)
  val () = $extfcall(void, "ward_copy_at", state, 6,
                     $UNSAFE.cast{ptr}(attr_name), nl) (* [U1] *)
  val off = 6 + nl
  val () = $extfcall(void, "ward_set_byte", state, off, vl)
  val () = $extfcall(void, "ward_set_byte", state, off + 1, 0)
  val () = $extfcall(void, "ward_copy_at", state, off + 2,
                     $UNSAFE.cast{ptr}(value), vl) (* [U1] *)
  val () = _ward_dom_flush(state, off + 2 + vl)
in state end

end (* local *)
