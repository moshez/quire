(* dom_read.dats — DOM read primitives implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./dom_read.sats"
staload _ = "./memory.dats"

(* No $<M>UNSAFE needed — all parameters are non-linear ATS2 types *)

extern fun _ward_js_measure_node
  (node_id: int): int = "mac#ward_js_measure_node"

extern fun _ward_js_query_selector
  {n:pos}
  (selector: ward_safe_text(n), selector_len: int n)
  : int = "mac#ward_js_query_selector"

(* Measure result stash — implemented in runtime.c *)
extern fun _ward_measure_get
  (slot: int): int = "mac#ward_measure_get"

implement
ward_measure_node(node_id) = _ward_js_measure_node(node_id)

implement ward_measure_get_x() = _ward_measure_get(0)
implement ward_measure_get_y() = _ward_measure_get(1)
implement ward_measure_get_w() = _ward_measure_get(2)
implement ward_measure_get_h() = _ward_measure_get(3)
implement ward_measure_get_top() = _ward_measure_get(4)
implement ward_measure_get_left() = _ward_measure_get(5)

implement
ward_query_selector{n}(selector, selector_len) =
  _ward_js_query_selector(selector, selector_len)

(* --- Character position measurement --- *)

extern fun _ward_js_caret_position_from_point
  (x: int, y: int): int = "mac#ward_js_caret_position_from_point"

extern fun _ward_js_read_text_content
  (node_id: int): int = "mac#ward_js_read_text_content"

extern fun _ward_js_measure_text_offset
  (node_id: int, offset: int): int = "mac#ward_js_measure_text_offset"

extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

implement
ward_caret_position_from_point(x, y) =
  _ward_js_caret_position_from_point(x, y)

implement
ward_caret_get_node_id() = _ward_measure_get(0)

implement
ward_read_text_content(node_id) =
  _ward_js_read_text_content(node_id)

implement
ward_read_text_content_get{n}(len) =
  ward_bridge_recv(_ward_bridge_stash_get_int(1), len)

implement
ward_measure_text_offset(node_id, offset) =
  _ward_js_measure_text_offset(node_id, offset)

(* --- Selection APIs --- *)

extern fun _ward_js_get_selection_text
  (): int = "mac#ward_js_get_selection_text"

extern fun _ward_js_get_selection_rect
  (): int = "mac#ward_js_get_selection_rect"

extern fun _ward_js_get_selection_range
  (): int = "mac#ward_js_get_selection_range"

implement
ward_get_selection_text() =
  _ward_js_get_selection_text()

implement
ward_get_selection_text_get{n}(len) =
  ward_bridge_recv(_ward_bridge_stash_get_int(1), len)

implement
ward_get_selection_rect() =
  _ward_js_get_selection_rect()

implement
ward_get_selection_range() =
  _ward_js_get_selection_range()
