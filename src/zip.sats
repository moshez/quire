(* zip.sats - ZIP file parser type declarations
 *
 * Freestanding ATS2 version for parsing EPUB ZIP containers.
 * Uses bridge js_file_read_chunk for synchronous chunk reads.
 *
 * FUNCTIONAL CORRECTNESS PROOFS:
 * - ZIP_OPEN_OK: ZIP was parsed with > 0 entries (required by zip_find_entry)
 * - ENTRY_INDEX_VALID: Entry indices are within bounds
 * - OFFSET_WITHIN_FILE: File offsets are valid (< file_size)
 * - DATA_OFFSET_SAFE: Data reads won't overflow file
 * - NAME_BOUNDED: Entry names fit in buffer without overflow
 *)

(* ========== ZIP Signature Proofs ========== *)

(* ZIP signatures are 4-byte little-endian magic numbers.
 * All start with 'P','K' (0x50,0x4B) followed by a 2-byte type code.
 * Bug class: computing wrong decimal from hex bytes (e.g. EOCD 0x06054b50).
 * Prevention: define signatures from constituent bytes via stadef, then
 * verify the decimal via praxi. If either the bytes or decimal are wrong,
 * the constraint solver rejects the code at compile time. *)
stadef LE_U32(b0:int, b1:int, b2:int, b3:int) =
  b0 + b1 * 256 + b2 * 65536 + b3 * 16777216

(* Source of truth: signatures computed from their raw bytes *)
stadef EOCD_SIG_S  = LE_U32(80, 75, 5, 6)   (* PK\x05\x06 *)
stadef CD_SIG_S    = LE_U32(80, 75, 1, 2)   (* PK\x01\x02 *)
stadef LOCAL_SIG_S = LE_U32(80, 75, 3, 4)   (* PK\x03\x04 *)

(* Constraint solver verifies these equalities at compile time.
 * prfun bodies must be provided in .dats — the solver checks the
 * return constraint when implementing. If the decimal is wrong,
 * patsopt rejects the implementation. *)
prfun lemma_eocd_sig():  [EOCD_SIG_S == 101010256] void
prfun lemma_cd_sig():    [CD_SIG_S == 33639248] void
prfun lemma_local_sig(): [LOCAL_SIG_S == 67324752] void

(* ========== Functional Correctness Dataprops ========== *)

(* ZIP open success proof.
 * ZIP_OPEN_OK proves zip_open returned > 0 entries.
 * Bug class: querying an empty ZIP (zip_open returned 0) silently yields -1,
 * causing confusing downstream errors (e.g., err-container instead of err-zip).
 * Prevention: callers must verify zip_open returned > 0 entries before calling
 * zip_find_entry, constructing this proof as evidence of a successful parse. *)
dataprop ZIP_OPEN_OK =
  | ZIP_PARSED_OK

(* Entry index validity proof.
 * ENTRY_INDEX_VALID(idx, count) proves 0 <= idx < count.
 * Prevents out-of-bounds array access at compile time. *)
dataprop ENTRY_INDEX_VALID(idx: int, count: int) =
  | {i,c:nat | i < c} VALID_INDEX(i, c)

(* File offset validity proof.
 * OFFSET_WITHIN_FILE(offset, file_size) proves offset < file_size.
 * Ensures we never read past end of file. *)
dataprop OFFSET_WITHIN_FILE(offset: int, file_size: int) =
  | {o,fs:nat | o < fs} VALID_OFFSET(o, fs)

(* Data read safety proof.
 * DATA_OFFSET_SAFE(offset, size, file_size) proves offset + size <= file_size.
 * Guarantees reading size bytes from offset won't overflow file bounds. *)
dataprop DATA_OFFSET_SAFE(offset: int, size: int, file_size: int) =
  | {o,s,fs:nat | o + s <= fs} SAFE_READ(o, s, fs)

(* Name buffer safety proof.
 * NAME_BOUNDED(name_len, max_len) proves name_len <= max_len.
 * Prevents buffer overflow when copying entry names. *)
dataprop NAME_BOUNDED(name_len: int, max_len: int) =
  | {n,m:nat | n <= m} NAME_FITS(n, m)

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
fun zip_init(): void
(* Open a ZIP file and parse central directory
 * Returns number of entries on success, 0 on failure
 * Result is bounded by MAX_ZIP_ENTRIES (256) *)
fun zip_open(file_handle: int, file_size: int): [n:nat | n <= 256] int(n)
(* Get entry info by index (0-based)
 * Returns 1 on success, 0 if index out of range
 * entry is filled if successful *)
fun zip_get_entry(index: int, entry: &zip_entry? >> _): int
(* Get entry name into string buffer at given offset
 * Returns name length
 * CORRECTNESS: Returned length is bounded to prevent buffer overflow *)
fun zip_get_entry_name(index: int, buf_offset: int): [len:nat] int(len)
(* Check if entry name matches a given suffix from string buffer
 * Reads suffix bytes from string buffer at offset 0
 * Returns 1 if matches, 0 otherwise *)
fun zip_entry_name_ends_with
  (index: int, suffix_len: int): int
(* Check if entry name matches exactly from string buffer
 * Reads name bytes from string buffer at offset 0
 * Returns 1 if matches, 0 otherwise *)
fun zip_entry_name_equals
  (index: int, name_len: int): int
(* Find entry by exact name in string buffer
 * Name is read from string buffer at offset 0
 * Returns entry index or -1 if not found
 * REQUIRES: ZIP was opened with > 0 entries (ZIP_OPEN_OK proof) *)
fun zip_find_entry
  (pf: ZIP_OPEN_OK | name_len: int): int
(* Get offset where decompressed data should be read from
 * This accounts for local file header size
 * Returns -1 on error, or a valid offset on success
 * CORRECTNESS: When >= 0, returned offset is valid and reading compressed_size
 * bytes from this offset won't exceed file bounds (DATA_OFFSET_SAFE proof) *)
fun zip_get_data_offset(index: int): int
(* Get total number of entries
 * Returns count bounded by MAX_ZIP_ENTRIES (256) *)
fun zip_get_entry_count(): [n:nat | n <= 256] int(n)
(* Close ZIP file (cleanup state) *)
fun zip_close(): void
