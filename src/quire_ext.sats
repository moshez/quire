(* quire_ext.sats — Bridge function declarations not in ward .sats files *)

staload "./../vendor/ward/lib/memory.sats"

(* Read f64 clientX from click payload, return as int.
 * Reads bytes 5-7 of the ward_arr for IEEE 754 extraction.
 * Requires at least 8 bytes (click payload is 20 bytes). *)
fun read_payload_click_x {l:agz}{n:nat | n >= 8}
  (arr: !ward_arr(byte, l, n)): int

(* Get current Unix timestamp in seconds *)
fun quire_time_now(): int = "mac#quire_time_now"

(* Read int32 target_node_id from click/contextmenu event payload.
 * Click payload layout: [f64:clientX][f64:clientY][i32:target_node_id]
 * Target node ID is at bytes 16-19, little-endian.
 * Requires at least 20 bytes. *)
fun read_payload_target_id {l:agz}{n:nat | n >= 20}
  (arr: !ward_arr(byte, l, n)): int

(* Factory reset: delete IndexedDB database and reload page *)
fun quire_factory_reset(): void = "mac#quire_factory_reset"

(* Check system dark mode preference. Returns 1 if dark, 0 if light. *)
fun quire_get_dark_mode(): int = "mac#quire_get_dark_mode"

(* Setup link click handler on chapter container.
 * External links open in new tab, footnote links intercepted for popup. *)
fun quire_setup_link_handler(container_node_id: int): void = "mac#quire_setup_link_handler"

(* Read input element value as UTF-8. Writes to dest buffer, returns byte length. *)
fun quire_get_input_value(
  node_id: int, dest_ptr: int, dest_max_len: int): int = "mac#quire_get_input_value"

fun quire_download_text(
  data_ptr: int, data_len: int,
  name_ptr: int, name_len: int): void = "mac#quire_download_text"

(* Search book's IDB index for chapters containing query text.
 * Async: calls ward_on_callback(callback_id, chapter_idx) for each match,
 * then ward_on_callback(callback_id, -1) when done. *)
fun quire_search_book(
  query_ptr: int, query_len: int,
  spine_count: int, callback_id: int): void = "mac#quire_search_book"
