(* dom_read.dats — DOM read primitives implementation *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./dom_read.sats"
staload _ = "./memory.dats"

(* No $UNSAFE needed — all parameters are non-linear ATS2 types *)

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
