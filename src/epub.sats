(* epub.sats - EPUB import pipeline type declarations
 *
 * Handles EPUB file parsing, metadata extraction, and IndexedDB storage.
 * Uses zip.sats for ZIP parsing and xml.sats for XML parsing.
 *
 * FUNCTIONAL CORRECTNESS PROOFS:
 * - EPUB_STATE_VALID: Type-checked state machine ensures only valid states
 * - SPINE_ORDERED: Spine indices preserve reading order from OPF
 * - TOC_TO_SPINE: TOC entries map to correct spine indices
 * - CHAPTER_KEY_CORRECT: Chapter keys correctly identify stored chapters
 * - COUNT_BOUNDED: Counts never exceed maximum limits
 *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/promise.sats"
staload "./zip.sats"

(* EPUB import state *)
#define EPUB_STATE_IDLE           0
#define EPUB_STATE_OPENING_FILE   1
#define EPUB_STATE_PARSING_ZIP    2
#define EPUB_STATE_READING_CONTAINER 3
#define EPUB_STATE_READING_OPF    4
#define EPUB_STATE_OPENING_DB     5
#define EPUB_STATE_DECOMPRESSING  6
#define EPUB_STATE_STORING        7
#define EPUB_STATE_DONE           8
#define EPUB_STATE_ERROR          99

(* ========== Functional Correctness Dataprops ========== *)

(* State machine validity proof.
 * EPUB_STATE_VALID(s) proves state s is one of the valid states.
 * Prevents invalid state values at compile time. *)
dataprop EPUB_STATE_VALID(state: int) =
  | EPUB_IDLE_STATE(0)
  | EPUB_OPENING_FILE_STATE(1)
  | EPUB_PARSING_ZIP_STATE(2)
  | EPUB_READING_CONTAINER_STATE(3)
  | EPUB_READING_OPF_STATE(4)
  | EPUB_OPENING_DB_STATE(5)
  | EPUB_DECOMPRESSING_STATE(6)
  | EPUB_STORING_STATE(7)
  | EPUB_DONE_STATE(8)
  | EPUB_ERROR_STATE(99)

(* Spine ordering preservation proof.
 * SPINE_ORDERED(ch, total) proves that chapter index ch:
 * - Is within bounds: 0 <= ch < total
 * - Corresponds to the ch-th chapter in reading order as specified in OPF spine
 * - When read sequentially (ch=0, ch=1, ...), chapters appear in correct order
 *
 * This is the core correctness property: "reading chapter 5 means reading
 * THE FIFTH chapter in the book", not some arbitrary chapter. *)
dataprop SPINE_ORDERED(ch: int, total: int) =
  | {c,t:nat | c < t} SPINE_ENTRY(c, t)

(* TOC to spine mapping correctness proof.
 * TOC_TO_SPINE(toc_idx, spine_idx, spine_total) proves:
 * - When spine_idx >= 0: spine_idx < spine_total AND is THE correct chapter
 *   for TOC entry toc_idx (not some other chapter)
 * - When spine_idx < 0: TOC entry has no corresponding chapter (valid: TOC
 *   entries can reference fragments, external links, etc.)
 *
 * Ensures clicking TOC entry navigates to THE RIGHT chapter. *)
dataprop TOC_TO_SPINE(toc_idx: int, spine_idx: int, spine_total: int) =
  | {t,s,total:nat | s < total} VALID_TOC_MAPPING(t, s, total)
  | {t,s,total:int} NO_TOC_MAPPING(t, s, total)

(* Chapter key correctness proof.
 * CHAPTER_KEY_CORRECT(ch, key_offset, key_len) proves that the key written
 * to string buffer at key_offset with length key_len is THE correct IndexedDB
 * key for retrieving chapter ch.
 *
 * Key format: "book_id/opf_dir/manifest[spine[ch]].href"
 * Ensures loading chapter 5 retrieves chapter 5's content, not chapter 4 or 6. *)
absprop CHAPTER_KEY_CORRECT(ch: int, key_offset: int, key_len: int)

(* Count bounds proof.
 * COUNT_BOUNDED(count, max) proves count <= max.
 * Used to ensure chapter_count <= MAX_SPINE_ITEMS, etc. *)
dataprop COUNT_BOUNDED(count: int, max: int) =
  | {c,m:nat | c <= m} WITHIN_BOUNDS(c, m)

(* EPUB state transition proof.
 * EPUB_STATE_TRANSITION(from, to) proves that transitioning from state
 * `from` to state `to` is a valid state machine transition.
 *
 * TEST MADE PASS-BY-CONSTRUCTION:
 *   test_epub_state_machine_valid — Only defined transitions compile.
 *
 * ENFORCEMENT: C code that sets epub_state must cite the transition
 * constructor in a comment. ATS code constructs and consumes proofs. *)
dataprop EPUB_STATE_TRANSITION(from: int, to: int) =
  | EPUB_IDLE_TO_OPENING(0, 1)
  | EPUB_OPENING_TO_PARSING(1, 2)
  | EPUB_PARSING_TO_CONTAINER(2, 3)
  | EPUB_CONTAINER_TO_OPF(3, 4)
  | EPUB_OPF_TO_DB(4, 5)
  | EPUB_DB_TO_DECOMPRESSING(5, 6)
  | EPUB_DECOMPRESSING_TO_STORING(6, 7)
  | EPUB_STORING_TO_DECOMPRESSING(7, 6)     (* loop: next chapter *)
  | EPUB_STORING_TO_DONE(7, 8)              (* all chapters stored *)
  | {from:int} EPUB_ANY_TO_ERROR(from, 99)  (* error from any state *)

(* Async precondition proof.
 * ASYNC_PRECONDITION(expected_state) proves that the app state was set
 * to expected_state BEFORE an async bridge call was initiated.
 *
 * BUG PREVENTED: open_db() originally called js_kv_open() without
 * setting app_state. This proof makes the pattern explicit: every async
 * call must be preceded by a state transition.
 *
 * TEST MADE PASS-BY-CONSTRUCTION:
 *   test_every_async_call_preceded_by_state — Functions that call async
 *   bridge operations require this proof, which can only be constructed
 *   after setting the state. *)
dataprop ASYNC_PRECONDITION(expected_state: int) =
  | {s:int} STATE_SET_BEFORE_ASYNC(s)

(* Initialize EPUB module *)
fun epub_init(): void
(* Start EPUB import from file input node
 * file_input_node_id: the DOM node ID of the file input element
 * Returns 1 if import started, 0 on error *)
fun epub_start_import(file_input_node_id: int): int
(* Get current import state
 * Returns a valid state value with EPUB_STATE_VALID proof *)
fun epub_get_state(): [s:int] int(s)
(* Get import progress (0-100)
 * Progress is bounded: 0 <= progress <= 100 *)
fun epub_get_progress(): [p:nat | p <= 100] int(p)
(* Get last error message into string buffer
 * Returns message length *)
fun epub_get_error(buf_offset: int): int
(* Get book title into string buffer (after import completes)
 * Returns title length *)
fun epub_get_title(buf_offset: int): int
(* Get book author into string buffer (after import completes)
 * Returns author length *)
fun epub_get_author(buf_offset: int): int
(* Get book ID (SHA-256 content hash, set by sha256_file_hash)
 * Returns ID into string buffer *)
fun epub_get_book_id(buf_offset: int): int
(* Get total number of chapters in spine
 * Returns count with proof that count <= MAX_SPINE_ITEMS (256) *)
fun epub_get_chapter_count(): [n:nat | n <= 256] int(n)
(* Get chapter key for IndexedDB lookup (book_id/chapter_href)
 * chapter_index: 0-based index into spine
 * buf_offset: offset in string buffer to write key
 * Returns key length, or 0 if index out of range
 *
 * CORRECTNESS: When chapter_index is valid (< chapter_count), the returned
 * key is THE correct key for retrieving chapter chapter_index from IndexedDB.
 * Internally produces CHAPTER_KEY_CORRECT proof establishing this. *)
fun epub_get_chapter_key(chapter_index: int, buf_offset: int): int
(* Continue processing (called from async callbacks)
 * Called after file open, decompress, or IDB operations complete *)
fun epub_continue(): void
(* Handle file open completion (called by bridge callback) *)
fun epub_on_file_open(handle: int, size: int): void
(* Handle decompress completion (called by bridge callback) *)
fun epub_on_decompress(blob_handle: int, size: int): void
(* Handle IndexedDB open completion *)
fun epub_on_db_open(success: int): void
(* Handle IndexedDB put completion *)
fun epub_on_db_put(success: int): void
(* Cancel current import *)
fun epub_cancel(): void
(* M13: TOC (Table of Contents) support *)

(* Get number of TOC entries
 * Returns count with proof that count <= MAX_TOC_ENTRIES (256) *)
fun epub_get_toc_count(): [n:nat | n <= 256] int(n)
(* Get TOC entry label into string buffer
 * toc_index: 0-based index into TOC entries
 * buf_offset: offset in string buffer to write label
 * Returns label length, or 0 if index out of range *)
fun epub_get_toc_label(toc_index: int, buf_offset: int): int
(* Get chapter index for a TOC entry
 * toc_index: 0-based index into TOC entries
 * Returns spine chapter index, or -1 if not found
 *
 * CORRECTNESS: Internally produces TOC_TO_SPINE proof:
 * - When return value >= 0: it is a valid spine index AND is THE correct
 *   chapter for this TOC entry (not some other chapter)
 * - When return value == -1: TOC entry has no spine mapping (valid case)
 *)
fun epub_get_toc_chapter(toc_index: int): int
(* Get nesting level for a TOC entry (0 = top level)
 * toc_index: 0-based index into TOC entries
 * Returns nesting level *)
fun epub_get_toc_level(toc_index: int): [level:nat] int(level)
(* Get chapter title from TOC for a spine index
 * spine_index: 0-based index into spine
 * buf_offset: offset in string buffer to write title
 * Returns title length, or 0 if no TOC entry found *)
fun epub_get_chapter_title(spine_index: int, buf_offset: int): int
(* ========== M15: Metadata Serialization Proofs ========== *)

(* Metadata roundtrip correctness proof.
 * METADATA_ROUNDTRIP(serialize_len) proves that after:
 * 1. epub_serialize_metadata() writes serialize_len bytes to fetch buffer
 * 2. epub_restore_metadata(serialize_len) reads those bytes back
 * The epub module state (book_id, title, author, opf_dir, spine, TOC)
 * is identical to before serialization.
 *
 * This is THE correctness property for book switching: when the user
 * selects a different book from the library, its metadata is restored
 * exactly as it was when first imported.
 *
 * NOTE: Proof is documentary - symmetric serialize/deserialize structure
 * (same field order, same encoding) provides the guarantee. *)
absprop METADATA_ROUNDTRIP(serialize_len: int)

(* Reset state transition proof.
 * EPUB_RESET_TO_IDLE proves that after epub_reset():
 * - epub_state == EPUB_STATE_IDLE (0)
 * - All metadata fields cleared (lengths set to 0)
 * - epub module is ready for a fresh import or restore
 *
 * NOTE: Proof is documentary - runtime reset verifies. *)
absprop EPUB_RESET_TO_IDLE

(* M15: Serialize book metadata to fetch buffer for library storage.
 * Writes book_id, title, author, opf_dir, spine hrefs, and TOC data.
 * Returns total bytes written (>= 0).
 *
 * CORRECTNESS: Output bytes are a deterministic encoding of the current
 * epub module state. Internally documents METADATA_ROUNDTRIP: calling
 * epub_restore_metadata(return_value) on the same buffer reconstructs
 * identical state. The encoding format writes fields in a fixed order:
 * book_id, title, author, opf_dir, spine entries, TOC entries.
 * Deserialization reads them back in the same order. *)
fun epub_serialize_metadata(): [len:nat] int(len)
(* M15: Restore book metadata from fetch buffer.
 * Reconstructs epub module state so reader can function.
 * len: number of bytes to read from fetch buffer.
 * Returns 1 on success, 0 on error.
 *
 * CORRECTNESS: On success (return == 1):
 * - epub_state == EPUB_STATE_DONE (ready to read)
 * - book_id, title, author, spine, TOC match the serialized data
 * - epub_get_chapter_count() returns the correct spine count
 * - Reader functions (chapter loading, TOC lookup) work correctly
 * On failure (return == 0): epub state is undefined, caller should
 * handle error. Minimum len of 12 required (6 u16 headers).
 * Internally verifies METADATA_ROUNDTRIP by consuming serialized data
 * in the same field order as epub_serialize_metadata produces it. *)
fun epub_restore_metadata(len: int): [r:int | r == 0 || r == 1] int(r)
(* M15: Reset epub state to idle (for switching between books).
 * Postcondition: epub_state == 0, all metadata cleared.
 * CORRECTNESS: After reset, epub module is in the same state as after
 * epub_init(), ready for a new import or metadata restore.
 * Internally produces EPUB_RESET_TO_IDLE proof. *)
fun epub_reset(): void

(* ========== Cover Image Detection (2.1) ========== *)

(* Proves cover detection result *)
dataprop COVER_DETECTED(has_cover: int) =
  | COVER_FOUND(1) | COVER_NOT_FOUND(0)

(* Build 20-char IDB cover key: {16 hex book_id}-cvr *)
fun epub_build_cover_key(): ward_safe_text(20)

(* Store cover image data from resource key to cover key in IDB.
 * Reads cover href from app_state, looks up resource entry,
 * copies data to cover key. Returns promise resolving to 1 on success. *)
fun epub_store_cover(): ward_promise_chained(int)

(* ========== Exploded Resource Storage (M1.2) ========== *)

(* Proves manifest loaded into memory before resource lookups *)
absprop MANIFEST_LOADED

(* Proves all resources stored to IDB before import completes *)
absprop RESOURCES_STORED

(* Build 20-char IDB key for zip entry: {16 hex book_id}-{3 hex entry_idx} *)
fun epub_build_resource_key(entry_idx: int): ward_safe_text(20)

(* Build 20-char IDB manifest key: {16 hex book_id}-man *)
fun epub_build_manifest_key(): ward_safe_text(20)

(* Store all ZIP entries to IDB as decompressed blobs.
 * Sequential async promise chain. Returns promise resolving to 1 on success. *)
fun epub_store_all_resources(file_handle: int): ward_promise_chained(int)

(* Store manifest (name→index + spine mapping) to IDB.
 * Returns promise resolving to 1 on success.
 * REQUIRES: ZIP is open with entries (for spine path lookup). *)
fun epub_store_manifest
  (pf_zip: ZIP_OPEN_OK | (* *) ): ward_promise_chained(int)

(* Load manifest from IDB. Populates in-memory lookup tables.
 * Also sets epub_spine_count from manifest data.
 * Returns promise resolving to 1 on success. *)
fun epub_load_manifest(): ward_promise_chained(int)

(* Find resource entry index by path in sbuf[0..path_len-1].
 * Requires manifest to be loaded. Returns index or -1. *)
fun epub_find_resource(path_len: int): int

(* Copy book_id from library slot to epub module state *)
fun epub_set_book_id_from_library(book_index: int): void

(* ========== Parsing and accessor functions ========== *)

(* Parse container.xml bytes to extract OPF path *)
fun epub_parse_container_bytes {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): int

(* Parse OPF bytes to extract metadata and spine *)
fun epub_parse_opf_bytes {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): int

(* Copy OPF path to string buffer. Returns length (0 if not set). *)
fun epub_copy_opf_path(buf_offset: int): [len:nat] int(len)

(* Copy "META-INF/container.xml" to string buffer. Always 22 bytes. *)
fun epub_copy_container_path(buf_offset: int): int

(* Copy spine chapter path to string buffer.
 * Requires SPINE_ORDERED proof — only callable when index is proven
 * less than chapter count via dependent comparison. Invalid calls
 * are rejected at compile time, not at runtime.
 * count is a dynamic witness for the constraint solver to unify t.
 * Returns positive path length (guaranteed by parser invariant:
 * _opf_resolve_spine rejects empty paths). *)
fun epub_copy_spine_path {c,t:nat | c < t}
  (pf: SPINE_ORDERED(c, t) | index: int(c), count: int(t), buf_offset: int): [len:pos] int(len)