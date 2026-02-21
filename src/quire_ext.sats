(* quire_ext.sats — Bridge function declarations not in ward .sats files *)

staload "./../vendor/ward/lib/memory.sats"

(* Read f64 clientX from click payload, return as int.
 * Reads bytes 5-7 of the ward_arr for IEEE 754 extraction.
 * Requires at least 8 bytes (click payload is 20 bytes). *)
fun read_payload_click_x {l:agz}{n:nat | n >= 8}
  (arr: !ward_arr(byte, l, n)): int

(* Set document.title: 0="Quire", 1="Quire (importing)" *)
fun quire_set_title(mode: int): void = "mac#quireSetTitle"

(* Get current Unix timestamp in seconds *)
fun quire_time_now(): int = "mac#quire_time_now"

(* Factory reset: delete IndexedDB database and reload page *)
fun quire_factory_reset(): void = "mac#quire_factory_reset"
