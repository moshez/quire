(* dom.sats — Ward DOM: type-safe DOM diffing *)
(* Safety by construction: attribute names must be ward_safe_text,
   dangerous attributes (style) get dedicated setters. *)

staload "./memory.sats"

(* DOM state — linear, owns the diff buffer *)
absvtype ward_dom_state(l:addr)

(* Diff buffer capacity *)
stadef WARD_DOM_BUF_CAP = 4096
#define WARD_DOM_BUF_CAP_DYN 4096

(* Opcode whitelist — only valid opcodes can be emitted *)
dataprop WARD_DOM_OPCODE(int) =
  | WARD_DOM_OP_SET_TEXT(1)
  | WARD_DOM_OP_SET_ATTR(2)
  | WARD_DOM_OP_REMOVE_CHILDREN(3)
  | WARD_DOM_OP_CREATE_ELEMENT(4)

(* --- Lifecycle --- *)

fun ward_dom_init
  (): [l:agz] ward_dom_state(l)

fun ward_dom_fini
  {l:agz}
  (state: ward_dom_state(l))
  : void

(* --- DOM operations (consume and return state) --- *)

fun ward_dom_create_element
  {l:agz}{tl:pos | tl + 10 <= WARD_DOM_BUF_CAP}
  (state: ward_dom_state(l),
   node_id: int, parent_id: int,
   tag: ward_safe_text(tl), tag_len: int tl)
  : ward_dom_state(l)

fun ward_dom_set_text
  {l:agz}{lb:agz}{tl:nat | tl + 7 <= WARD_DOM_BUF_CAP}
  (state: ward_dom_state(l),
   node_id: int,
   text: !ward_arr_borrow(byte, lb, tl), text_len: int tl)
  : ward_dom_state(l)

fun ward_dom_set_attr
  {l:agz}{lb:agz}{nl:pos}{vl:nat | nl + vl + 8 <= WARD_DOM_BUF_CAP}
  (state: ward_dom_state(l),
   node_id: int,
   attr_name: ward_safe_text(nl), name_len: int nl,
   value: !ward_arr_borrow(byte, lb, vl), value_len: int vl)
  : ward_dom_state(l)

(* Dedicated setter for 'style' — dangerous attribute gets own API *)
fun ward_dom_set_style
  {l:agz}{lb:agz}{vl:nat | vl + 13 <= WARD_DOM_BUF_CAP}
  (state: ward_dom_state(l),
   node_id: int,
   value: !ward_arr_borrow(byte, lb, vl), value_len: int vl)
  : ward_dom_state(l)

fun ward_dom_remove_children
  {l:agz}
  (state: ward_dom_state(l), node_id: int)
  : ward_dom_state(l)

(* --- DOM state persistence (for async boundaries) --- *)

fun ward_dom_store
  {l:agz}
  (state: ward_dom_state(l))
  : void

fun ward_dom_load
  (): [l:agz] ward_dom_state(l)

(* --- Safe text variants (no borrow needed) --- *)

fun ward_dom_set_safe_text
  {l:agz}{tl:nat | tl + 7 <= WARD_DOM_BUF_CAP}
  (state: ward_dom_state(l), node_id: int,
   text: ward_safe_text(tl), text_len: int tl)
  : ward_dom_state(l)

fun ward_dom_set_attr_safe
  {l:agz}{nl:pos}{vl:nat | nl + vl + 8 <= WARD_DOM_BUF_CAP}
  (state: ward_dom_state(l), node_id: int,
   attr_name: ward_safe_text(nl), name_len: int nl,
   value: ward_safe_text(vl), value_len: int vl)
  : ward_dom_state(l)
