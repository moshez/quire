(* dom.sats — Ward DOM: type-safe DOM diffing with streaming *)
(* Safety by construction: attribute names must be ward_safe_text,
   dangerous attributes (style) get dedicated setters.
   Stream API batches multiple ops before flushing to JS bridge. *)

staload "./memory.sats"

(* DOM state — linear, owns the 256KB diff buffer *)
absvtype ward_dom_state(l:addr)

(* DOM stream — linear, accumulates ops, auto-flushes when full *)
absvtype ward_dom_stream(l:addr)

(* Diff buffer capacity *)
stadef WARD_DOM_BUF_CAP = 262144
#define WARD_DOM_BUF_CAP_DYN 262144

(* --- Lifecycle (2) --- *)

fun ward_dom_init
  (): [l:agz] ward_dom_state(l)

fun ward_dom_fini
  {l:agz}
  (state: ward_dom_state(l))
  : void

(* --- Stream lifecycle (2) --- *)

fun ward_dom_stream_begin
  {l:agz}
  (state: ward_dom_state(l))
  : [l2:agz] ward_dom_stream(l2)

fun ward_dom_stream_end
  {l:agz}
  (stream: ward_dom_stream(l))
  : [l2:agz] ward_dom_state(l2)

(* --- Stream ops (7) --- *)

fun ward_dom_stream_create_element
  {l:agz}{tl:pos | tl + 10 <= WARD_DOM_BUF_CAP; tl < 256}
  (stream: ward_dom_stream(l),
   node_id: int, parent_id: int,
   tag: ward_safe_text(tl), tag_len: int tl)
  : ward_dom_stream(l)

fun ward_dom_stream_set_text
  {l:agz}{lb:agz}{tl:nat | tl + 7 <= WARD_DOM_BUF_CAP; tl < 65536}
  (stream: ward_dom_stream(l),
   node_id: int,
   text: !ward_arr_borrow(byte, lb, tl), text_len: int tl)
  : ward_dom_stream(l)

fun ward_dom_stream_set_attr
  {l:agz}{lb:agz}{nl:pos | nl < 256}{vl:nat | nl + vl + 8 <= WARD_DOM_BUF_CAP; vl < 65536}
  (stream: ward_dom_stream(l),
   node_id: int,
   attr_name: ward_safe_text(nl), name_len: int nl,
   value: !ward_arr_borrow(byte, lb, vl), value_len: int vl)
  : ward_dom_stream(l)

fun ward_dom_stream_set_style
  {l:agz}{lb:agz}{vl:nat | vl + 13 <= WARD_DOM_BUF_CAP; vl < 65536}
  (stream: ward_dom_stream(l),
   node_id: int,
   value: !ward_arr_borrow(byte, lb, vl), value_len: int vl)
  : ward_dom_stream(l)

fun ward_dom_stream_remove_children
  {l:agz}
  (stream: ward_dom_stream(l), node_id: int)
  : ward_dom_stream(l)

fun ward_dom_stream_remove_child
  {l:agz}
  (stream: ward_dom_stream(l), node_id: int)
  : ward_dom_stream(l)

(* --- Safe text stream variants (no borrow needed) --- *)

fun ward_dom_stream_set_safe_text
  {l:agz}{tl:nat | tl + 7 <= WARD_DOM_BUF_CAP; tl < 65536}
  (stream: ward_dom_stream(l), node_id: int,
   text: ward_safe_text(tl), text_len: int tl)
  : ward_dom_stream(l)

fun ward_dom_stream_set_attr_safe
  {l:agz}{nl:pos | nl < 256}{vl:nat | nl + vl + 8 <= WARD_DOM_BUF_CAP; vl < 65536}
  (stream: ward_dom_stream(l), node_id: int,
   attr_name: ward_safe_text(nl), name_len: int nl,
   value: ward_safe_text(vl), value_len: int vl)
  : ward_dom_stream(l)
