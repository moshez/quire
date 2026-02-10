(* file.sats — File I/O bridge primitives (user-selected files) *)

staload "./memory.sats"
staload "./promise.sats"

(* Open a file from an input element. Resolves with file handle.
   File size is stashed — read with ward_file_get_size. *)
fun ward_file_open
  (input_node_id: int): ward_promise_pending(int)

fun ward_file_get_size(): int

(* Synchronous read from cached ArrayBuffer. Returns bytes_read. *)
fun ward_file_read
  {l:agz}{n:pos}
  (handle: int, file_offset: int, out: !ward_arr(byte, l, n), len: int n): int

fun ward_file_close(handle: int): void

(* WASM export — called by JS when file opens *)
fun ward_on_file_open
  (resolver_id: int, handle: int, size: int): void = "ext#ward_on_file_open"
