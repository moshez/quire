(* decompress.sats — Decompression bridge primitives *)

staload "./memory.sats"
staload "./promise.sats"

(* Decompress data. method: 0=gzip, 1=deflate, 2=deflate-raw.
   Resolves with blob handle. Decompressed length stashed. *)
fun ward_decompress
  {lb:agz}{n:pos}
  (data: !ward_arr_borrow(byte, lb, n), data_len: int n, method: int)
  : ward_promise_pending(int)

fun ward_decompress_get_len(): int

(* Synchronous read from decompressed blob. Returns bytes_read. *)
fun ward_blob_read
  {l:agz}{n:pos}
  (handle: int, blob_offset: int, out: !ward_arr(byte, l, n), len: int n): int

fun ward_blob_free(handle: int): void

(* WASM export — called by JS when decompression completes *)
fun ward_on_decompress_complete
  (resolver_id: int, handle: int, decompressed_len: int)
  : void = "ext#ward_on_decompress_complete"
