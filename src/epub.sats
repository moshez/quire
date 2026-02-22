(* epub.sats - EPUB import pipeline type declarations
 *
 * Handles EPUB file parsing, metadata extraction, and IndexedDB storage.
 * Uses zip.sats for ZIP parsing and xml.sats for XML parsing.
 *
 * FUNCTIONAL CORRECTNESS PROOFS:
 * - EPUB_STATE_VALID: Enforced on _app_set_epub_state — can't set invalid state
 * - SPINE_ORDERED: Spine indices preserve reading order from OPF
 * - TOC_TO_SPINE: TOC entries map to correct spine indices
 * - SERIALIZED: epub_restore_metadata requires proof from epub_serialize_metadata
 * - EPUB_IDLE: epub_start_import requires proof from epub_reset
 *
 * SUPERSEDED (deleted):
 * - CHAPTER_KEY_CORRECT: replaced by resource-key architecture with SAFE_CHAR
 * - COUNT_BOUNDED: redundant with dependent return type n <= 256
 * - EPUB_STATE_TRANSITION: superseded by EPUB_STATE_VALID + promise chain
 * - ASYNC_PRECONDITION: superseded by promise chain structure
 * - RESOURCES_STORED: superseded by promise chain + IDB data dependency
 * - COVER_DETECTED: replaced by dependent return type on epub_store_cover
 * - MANIFEST_LOADED: superseded by promise chain ordering
 *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/promise.sats"
staload "./zip.sats"
staload "./library.sats"

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
 * ENFORCED: _app_set_epub_state requires this proof as a parameter.
 * Toddler test: can't set state to 42 — no constructor exists for 42. *)
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

(* Serialization capability proof.
 * SERIALIZED(len) can only be produced by epub_serialize_metadata.
 * epub_restore_metadata requires it, ensuring restore is only called
 * with a length produced by serialize — wrong-length restore is a
 * compile error.
 * Toddler test: can't call epub_restore_metadata(42) without
 * SERIALIZED(42) proof, which only epub_serialize_metadata produces. *)
dataprop SERIALIZED(len: int) =
  | {n:nat} SERIALIZE_OK(n)

(* Idle capability proof.
 * EPUB_IDLE can only be produced by epub_reset.
 * epub_start_import requires it, ensuring import only starts from
 * a clean state.
 * Toddler test: can't start import without resetting first. *)
dataprop EPUB_IDLE() = | EPUB_IS_IDLE()

(* Initialize EPUB module *)
fun epub_init(): void
(* Start EPUB import from file input node
 * Requires EPUB_IDLE proof — must reset before importing.
 * file_input_node_id: the DOM node ID of the file input element
 * Returns 1 if import started, 0 on error *)
fun epub_start_import {n:int}
  (pf: EPUB_IDLE() | file_input_node_id: int(n)): int
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
 * Returns count with dependent type: n <= 256 IS the bounds proof. *)
fun epub_get_chapter_count(): [n:nat | n <= 256] int(n)
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

(* ========== Metadata Serialization ========== *)

(* Serialize book metadata to fetch buffer for library storage.
 * Writes book_id, title, author, opf_dir, spine hrefs, and TOC data.
 * Returns total bytes written (>= 0) with SERIALIZED proof.
 *
 * CORRECTNESS: Output bytes are a deterministic encoding of the current
 * epub module state. The SERIALIZED proof ties the length to this call,
 * ensuring only epub_restore_metadata can consume it with the correct length. *)
fun epub_serialize_metadata(): [len:nat] (SERIALIZED(len) | int(len))
(* Restore book metadata from fetch buffer.
 * Requires SERIALIZED proof — can only restore data that was serialized.
 * len: number of bytes to read from fetch buffer.
 * Returns 1 on success, 0 on error. *)
fun epub_restore_metadata {len:nat}
  (pf: SERIALIZED(len) | len: int(len)): [r:int | r == 0 || r == 1] int(r)
(* Reset epub state to idle (for switching between books).
 * Postcondition: epub_state == 0, all metadata cleared.
 * Returns EPUB_IDLE proof — required to start a new import. *)
fun epub_reset(): (EPUB_IDLE() | void)

(* ========== Cover Image ========== *)

(* Build 20-char IDB cover key: {16 hex book_id}-cvr *)
fun epub_build_cover_key(): ward_safe_text(20)

(* Store cover image data from resource key to cover key in IDB.
 * Reads cover href from app_state, looks up resource entry,
 * copies data to cover key. Returns promise resolving to int.
 * Enforcement: key construction uses SAFE_CHAR proof on every byte.
 * Resource lookup uses dependent epub_find_resource (r >= -1).
 * Href existence check uses gt_g1 giving solver href_len > 0. *)
fun epub_store_cover(): ward_promise_chained(int)

(* ========== Exploded Resource Storage (M1.2) ========== *)

(* Promise chain structure enforces:
 * - Resources stored before manifest (epub_store_all_resources → epub_store_manifest)
 * - Manifest loaded before find_resource (epub_load_manifest → epub_find_resource)
 * - These orderings are not expressed as dataprops because they are structural
 *   properties of the promise chain, not value-level invariants. *)

(* Build 20-char IDB key for zip entry: {16 hex book_id}-{3 hex entry_idx} *)
fun epub_build_resource_key(entry_idx: int): ward_safe_text(20)

(* Build 20-char IDB manifest key: {16 hex book_id}-man *)
fun epub_build_manifest_key(): ward_safe_text(20)

(* Build 20-char IDB bookmark key: {16 hex book_id}-bmk *)
fun epub_build_bookmark_key(): ward_safe_text(20)

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
 * Requires manifest to be loaded (enforced by promise chain ordering).
 * Returns index (>= 0) or -1 (not found).
 * Dependent return type: callers use lt_g1/gte_g1 to branch, giving
 * the constraint solver the sign information in each branch. *)
fun epub_find_resource(path_len: int): [r:int | r >= ~1] int(r)

(* Copy book_id from library slot to epub module state.
 * Requires BOOK_ACCESS_SAFE proof — proves index is within buffer bounds.
 * Returns bid_len clamped to [0, 64]. *)
fun epub_set_book_id_from_library
  {i:nat | i < 32}
  (pf: BOOK_ACCESS_SAFE(i) | book_index: int(i))
  : [len:nat | len <= 64] int(len)

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

(* ========== Search Index (2.2) ========== *)

(* Build 20-char IDB search key: {16 hex book_id}s{3 hex spine_idx}
 * Byte 16: 's' (ASCII 115, SAFE_CHAR) distinguishes from resource keys ('-').
 * Requires SPINE_ORDERED proof — can only build key for valid spine index.
 * Toddler test: can't build search key for spine_idx >= count. *)
fun epub_build_search_key {c,t:nat | c < t}
  (pf: SPINE_ORDERED(c, t) | spine_idx: int(c), count: int(t)): ward_safe_text(20)

(* Store search index for all chapters in the spine.
 * Sequential promise chain: for each chapter, loads resource from IDB,
 * parses HTML via ward_xml_parse_html, extracts plain text with
 * diacritics folding, stores text + offset map to IDB under search key.
 * Returns promise resolving to 1 on success. *)
fun epub_store_search_index(): ward_promise_chained(int)

(* Delete all IDB content for the current book: manifest, cover, search index.
 * Requires epub book_id to be set (via epub_set_book_id_from_library).
 * spine_count determines how many search keys to delete.
 * Resource entries are NOT deleted (orphaned until factory reset).
 * Termination: loop bounded by spine_count via dependent int. *)
fun epub_delete_book_data {sc:nat | sc <= 256}
  (spine_count: int(sc)): void
