(* nav.sats — Navigation bridge primitives *)

staload "./memory.sats"

fun ward_get_url
  {l:agz}{n:pos}
  (out: !ward_arr(byte, l, n), max_len: int n): int

fun ward_get_url_hash
  {l:agz}{n:pos}
  (out: !ward_arr(byte, l, n), max_len: int n): int

fun ward_set_url_hash
  {n:nat}
  (hash: ward_safe_text(n), hash_len: int n): void

fun ward_replace_state
  {n:nat}
  (url: ward_safe_text(n), url_len: int n): void

fun ward_push_state
  {n:nat}
  (url: ward_safe_text(n), url_len: int n): void
