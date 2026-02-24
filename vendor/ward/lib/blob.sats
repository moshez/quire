(* blob.sats — Blob URL creation and revocation *)

staload "./memory.sats"

(* Create a blob URL from binary data and MIME type.
   Returns URL byte length (0 on failure).
   Stashes URL bytes for retrieval via ward_create_blob_url_get. *)
fun ward_create_blob_url
  {lb:agz}{n:pos}{m:pos}
  (data: !ward_arr_borrow(byte, lb, n), data_len: int n,
   mime: ward_safe_text(m), mime_len: int m): int

(* Retrieve stashed blob URL. Call after ward_create_blob_url. *)
fun ward_create_blob_url_get
  {n:pos}
  (len: int n): [l:agz] ward_arr(byte, l, n)

(* Revoke a previously created blob URL. *)
fun ward_revoke_blob_url
  {lb:agz}{n:pos}
  (url: !ward_arr_borrow(byte, lb, n), url_len: int n): void
