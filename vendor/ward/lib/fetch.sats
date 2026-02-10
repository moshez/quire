(* fetch.sats — Network fetch bridge primitives *)

staload "./memory.sats"
staload "./promise.sats"

(* Fetch a URL. Resolves with HTTP status code. *)
fun ward_fetch
  {un:pos}
  (url: ward_safe_text(un), url_len: int un)
  : ward_promise_pending(int)

(* Retrieve response body after fetch resolves.
   Body length is stashed — read with ward_fetch_get_body_len. *)
fun ward_fetch_get_body_len(): int

fun ward_fetch_get_body
  {n:pos}
  (len: int n): [l:agz] ward_arr(byte, l, n)

(* WASM export — called by JS when fetch completes *)
fun ward_on_fetch_complete
  (resolver_id: int, status: int, body_len: int)
  : void = "ext#ward_on_fetch_complete"
