(* zip.sats - ZIP file parser type declarations
 *
 * Freestanding ATS2 version for parsing EPUB ZIP containers.
 * Uses bridge js_file_read_chunk for synchronous chunk reads.
 *)

(* ZIP entry information extracted from central directory *)
typedef zip_entry = @{
    file_handle = int,           (* source file handle *)
    name_offset = int,           (* offset in string buffer where name is stored *)
    name_len = int,              (* length of entry name *)
    compression = int,           (* 0=stored, 8=deflate *)
    compressed_size = int,       (* size of compressed data *)
    uncompressed_size = int,     (* size when decompressed *)
    local_header_offset = int    (* offset of local file header in ZIP *)
}

(* Initialize ZIP parser state *)
fun zip_init(): void = "mac#"

(* Open a ZIP file and parse central directory
 * Returns number of entries on success, 0 on failure *)
fun zip_open(file_handle: int, file_size: int): int = "mac#"

(* Get entry info by index (0-based)
 * Returns 1 on success, 0 if index out of range
 * entry is filled if successful *)
fun zip_get_entry(index: int, entry: &zip_entry? >> _): int = "mac#"

(* Get entry name into string buffer at given offset
 * Returns name length *)
fun zip_get_entry_name(index: int, buf_offset: int): int = "mac#"

(* Check if entry name matches a given suffix (e.g., ".opf", ".xhtml")
 * Returns 1 if matches, 0 otherwise *)
fun zip_entry_name_ends_with(index: int, suffix_ptr: ptr, suffix_len: int): int = "mac#"

(* Check if entry name matches exactly
 * Returns 1 if matches, 0 otherwise *)
fun zip_entry_name_equals(index: int, name_ptr: ptr, name_len: int): int = "mac#"

(* Find entry by exact name
 * Returns entry index or -1 if not found *)
fun zip_find_entry(name_ptr: ptr, name_len: int): int = "mac#"

(* Get offset where decompressed data should be read from
 * This accounts for local file header size *)
fun zip_get_data_offset(index: int): int = "mac#"

(* Get total number of entries *)
fun zip_get_entry_count(): int = "mac#"

(* Close ZIP file (cleanup state) *)
fun zip_close(): void = "mac#"
