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

(* Caret position from viewport coordinates.
   Returns character offset at (x,y), or -1 if no text.
   Populates measure stash slot 0 with target node_id. *)
fun ward_caret_position_from_point(x: int, y: int): int

(* Read target node_id from caret position result (stash slot 0). *)
fun ward_caret_get_node_id(): int

(* Read textContent of a node as UTF-8.
   Returns byte length, 0 if not found. Stashes encoded text. *)
fun ward_read_text_content(node_id: int): int

(* Retrieve stashed text content. Call after ward_read_text_content. *)
fun ward_read_text_content_get
  {n:pos}
  (len: int n): [l:agz] ward_arr(byte, l, n)

(* Measure bounding rect at character offset in node's first text child.
   Returns 1 if found, 0 if not. Fills measure stash (x, y, w, h). *)
fun ward_measure_text_offset(node_id: int, offset: int): int

(* Get selected text as UTF-8. Returns byte length (0 if no selection).
   Stashes encoded text for retrieval via ward_get_selection_text_get. *)
fun ward_get_selection_text(): int

(* Retrieve stashed selection text. Call after ward_get_selection_text. *)
fun ward_get_selection_text_get
  {n:pos}
  (len: int n): [l:agz] ward_arr(byte, l, n)

(* Get bounding rect of current selection.
   Returns 1 if selection exists, 0 if not.
   Fills measure stash slots 0-3 (x, y, w, h). *)
fun ward_get_selection_rect(): int

(* Get character range offsets of current selection.
   Returns 1 if selection exists, 0 if not.
   Fills measure stash: 0=start_offset, 1=end_offset,
   2=start_node_id, 3=end_node_id. *)
fun ward_get_selection_range(): int
