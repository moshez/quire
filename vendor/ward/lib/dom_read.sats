(* dom_read.sats — DOM read primitives (measure, querySelector) *)

staload "./memory.sats"

(* Measure a DOM node. Returns 1 if found, 0 if not.
   Results stored in stash — read with ward_measure_get_*. *)
fun ward_measure_node(node_id: int): int

fun ward_measure_get_x(): int
fun ward_measure_get_y(): int
fun ward_measure_get_w(): int
fun ward_measure_get_h(): int
fun ward_measure_get_top(): int
fun ward_measure_get_left(): int

(* Query a DOM element by CSS selector. Returns node_id or -1. *)
fun ward_query_selector
  {n:pos}
  (selector: ward_safe_text(n), selector_len: int n): int
