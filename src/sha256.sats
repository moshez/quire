(* sha256.sats — SHA-256 content hash for book identity
 *
 * Computes SHA-256 of file bytes via ward_file_read, writes 64-char
 * hex result to caller-provided ward_arr(byte, l, 64).
 *
 * BOOK_IDENTITY_IS_CONTENT_HASH: structural invariant.
 * The only code that sets epub_book_id is sha256_file_hash
 * in the import path of quire.dats. _opf_extract_identifier is deleted.
 * Same hash = same book by definition, eliminating the
 * "duplicate book ID, different title" failure class entirely.
 *)

staload "./../vendor/ward/lib/memory.sats"

(* Book identity invariant: epub_book_id is always a SHA-256 content hash.
 * Structural: the only code that sets epub_book_id is sha256_file_hash
 * in the import path of quire.dats. _opf_extract_identifier is deleted. *)
absprop BOOK_IDENTITY_IS_CONTENT_HASH

(* Compute SHA-256 of file at handle, write 64 hex chars to out.
 * handle: file handle from ward_file_open
 * file_size: total file size in bytes
 * out: ward_arr(byte, l, 64) — receives 64 ASCII hex digits *)
fun sha256_file_hash {l:agz}
  (handle: int, file_size: int, out: !ward_arr(byte, l, 64)): void
