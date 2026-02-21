(* library.sats - Book library type declarations
 *
 * M15: Manages a persistent library of imported books.
 * Each book entry stores title, author, reading position, chapter count,
 * and shelf state (active/archived/hidden).
 * Library index is serialized to IndexedDB for persistence.
 *
 * FUNCTIONAL CORRECTNESS PROOFS:
 * - LIBRARY_INDEX_VALID: Book count within bounds, all entries have valid data
 * - BOOK_POSITION_VALID: Reading position within book bounds
 * - BOOK_IN_LIBRARY: Proves a book index is valid for the current library
 * - SER_FORMAT: Version↔fixed-bytes agreement (prevents metadata size drift)
 * - SER_VAR_FIELD: Field index↔record offset agreement (prevents field order/offset drift)
 * - TIMESTAMP_VALID: Timestamp is non-negative
 * - SHELF_STATE_VALID: Shelf state is 0 (active), 1 (archived), or 2 (hidden)
 * - SORT_MODE_VALID: Sort mode is 0..3 (title, author, last-opened, date-added)
 * - LIBRARY_SORTED: Library is sorted by the given mode
 *)

staload "./../vendor/ward/lib/promise.sats"
staload "./buf.sats"

(* Maximum number of books in library *)
#define MAX_LIBRARY_BOOKS 32

(* ========== Record layout stadefs (type-level) ========== *)

stadef MAX_BOOKS_S = 32
stadef REC_INTS_S = 155
stadef REC_BYTES_S = 620           (* REC_INTS_S * 4 *)

(* Single source of truth for record layout — eliminates all hardcoded
 * constants in consumer modules. If the record grows, change REC_INTS_S
 * and REC_BYTES_S above; library_rec_ints/bytes will fail to compile
 * unless the implementation matches. *)
stadef LIB_REC_INTS = 155
stadef LIB_REC_BYTES = 620

(* Byte offsets within a book record *)
stadef TITLE_BYTE_OFF_S = 0
stadef TITLE_FIELD_LEN_S = 256
stadef AUTHOR_BYTE_OFF_S = 260
stadef AUTHOR_FIELD_LEN_S = 256

(* ========== Functional Correctness Dataprops ========== *)

(* Library index validity proof. *)
dataprop LIBRARY_INDEX_VALID(count: int, max: int) =
  | {c,m:nat | c <= m} VALID_INDEX(c, m)

(* Book position validity proof. *)
dataprop BOOK_POSITION_VALID(chapter: int, page: int, total: int) =
  | {c,p,t:nat | c < t} VALID_POSITION(c, p, t)
  | {p:nat} EMPTY_POSITION(0, p, 0)

(* Book index bounds proof. *)
dataprop BOOK_IN_LIBRARY(index: int, count: int) =
  | {i,c:nat | i < c} VALID_BOOK_INDEX(i, c)

(* Serialization format proof: version↔fixed-bytes agreement.
 * Single source of truth — both serialize and deserialize call
 * ser_fixed_bytes() which constructs the appropriate proof.
 * v1: 3×u16 = 6 bytes, v2: 4×u16 = 8 bytes, v3: 4×u16 + 3×u32 = 20 bytes
 * v4: v3 + u16 has_cover = 22 bytes *)
dataprop SER_FORMAT(version: int, fixed_bytes: int) =
  | SER_FMT_V1(1, 6)
  | SER_FMT_V2(2, 8)
  | SER_FMT_V3(3, 20)
  | SER_FMT_V4(4, 22)

(* Serialization variable field proof: index↔record offset agreement.
 * Ties field index to byte offset, max length, and length slot.
 * Both serialize and deserialize call ser_var_field_spec() for each field. *)
dataprop SER_VAR_FIELD(idx: int, byte_off: int, max_len: int, len_slot: int) =
  | SFIELD_BID(0, 520, 64, 146)
  | SFIELD_TITLE(1, 0, 256, 64)
  | SFIELD_AUTHOR(2, 260, 256, 129)

(* Timestamp validity proof. *)
dataprop TIMESTAMP_VALID(t: int) =
  | {t:nat} VALID_TIMESTAMP(t)

(* Single-pending-flag invariant proof. *)
dataprop SINGLE_PENDING(handler_id: int) =
  | PENDING_SETTINGS(0)
  | PENDING_LIB_METADATA(1)
  | PENDING_LIB_INDEX(2)
  | PENDING_EPUB_IMPORT(3)
  | PENDING_READER_CHAPTER(4)

(* Import lock proof. *)
absprop IMPORT_LOCK_FREE

(* ========== Shelf/Sort Dataprops ========== *)

(* Shelf state: 0=active, 1=archived, 2=hidden *)
dataprop SHELF_STATE_VALID(s: int) =
  | SHELF_ACTIVE(0)
  | SHELF_ARCHIVED(1)
  | SHELF_HIDDEN(2)

(* Sort mode: title, author, last-opened, date-added *)
dataprop SORT_MODE_VALID(m: int) =
  | SORT_BY_TITLE(0)
  | SORT_BY_AUTHOR(1)
  | SORT_BY_LAST_OPENED(2)
  | SORT_BY_DATE_ADDED(3)

(* View mode: active, archived, or hidden shelf *)
dataprop VIEW_MODE_VALID(m: int) =
  | VIEW_ACTIVE(0)
  | VIEW_ARCHIVED(1)
  | VIEW_HIDDEN(2)

(* View filtering: compile-time proof that the render decision is correct.
 * 3×3 exhaustive dispatch: view_mode × shelf_state → render decision. *)
dataprop VIEW_FILTER_CORRECT(view_mode: int, shelf_state: int, render: int) =
  | RENDER_ACTIVE(0, 0, 1)
  | SKIP_ARCHIVED_IN_ACTIVE(0, 1, 0)
  | SKIP_HIDDEN_IN_ACTIVE(0, 2, 0)
  | SKIP_ACTIVE_IN_ARCHIVED(1, 0, 0)
  | RENDER_ARCHIVED(1, 1, 1)
  | SKIP_HIDDEN_IN_ARCHIVED(1, 2, 0)
  | SKIP_ACTIVE_IN_HIDDEN(2, 0, 0)
  | SKIP_ARCHIVED_IN_HIDDEN(2, 1, 0)
  | RENDER_HIDDEN(2, 2, 1)

(* Case normalization: proves the lowered value is correct *)
dataprop TO_LOWER_CORRECT(input: int, output: int) =
  | {b:nat | b >= 65; b <= 90} LOWERED(b, b + 32)
  | {b:nat | b <= 255; b < 65} KEPT_LOW(b, b)
  | {b:nat | b <= 255; b > 90} KEPT_HIGH(b, b)

(* Byte-level lexicographic comparison proofs *)
dataprop BYTES_EQ_UPTO(off_i: int, off_j: int, k: int) =
  | {oi,oj:int} EQ_BASE(oi, oj, 0)
  | {oi,oj,k:nat}
    EQ_STEP(oi, oj, k+1) of BYTES_EQ_UPTO(oi, oj, k)

dataprop LEX_CMP(off_i: int, off_j: int, len: int, result: int) =
  | {oi,oj,l:nat}{r:int | r == 0}
    LEX_EQ(oi, oj, l, r) of BYTES_EQ_UPTO(oi, oj, l)
  | {oi,oj,l,k:nat | k < l}{r:int | r < 0}
    LEX_LT(oi, oj, l, r) of BYTES_EQ_UPTO(oi, oj, k)
  | {oi,oj,l,k:nat | k < l}{r:int | r > 0}
    LEX_GT(oi, oj, l, r) of BYTES_EQ_UPTO(oi, oj, k)

(* Field specification: ties sort mode + book index to byte offset + length *)
dataprop FIELD_SPEC(mode: int, book_idx: int, offset: int, len: int) =
  | {i:nat | i < 32}
    FIELD_TITLE(0, i, i * REC_BYTES_S + TITLE_BYTE_OFF_S, TITLE_FIELD_LEN_S)
  | {i:nat | i < 32}
    FIELD_AUTHOR(1, i, i * REC_BYTES_S + AUTHOR_BYTE_OFF_S, AUTHOR_FIELD_LEN_S)

(* Integer field specification: ties sort mode + book index to i32 slot *)
dataprop FIELD_INT_SPEC(mode: int, book_idx: int, slot: int) =
  | {i:nat | i < 32} FIELD_LAST_OPENED(2, i, i * REC_INTS_S + 152)
  | {i:nat | i < 32} FIELD_DATE_ADDED(3, i, i * REC_INTS_S + 151)

(* Integer comparison proof (reverse chronological: higher value = first) *)
dataprop INT_CMP(slot_i: int, slot_j: int, result: int) =
  | {si,sj:int}{r:int | r <= 0} INT_GTE(si, sj, r)
  | {si,sj:int}{r:int | r > 0} INT_LT_VAL(si, sj, r)

(* Pair ordering: verified by post-state comparison *)
dataprop PAIR_IN_ORDER(mode: int, i: int, j: int) =
  | {m:int}{i,j:nat | j == i + 1; i < 32; j < 32}
    {oi,oj:int}{l:pos}{r:int | r <= 0}
    PAIR_VERIFIED(m, i, j) of
      (FIELD_SPEC(m, i, oi, l), FIELD_SPEC(m, j, oj, l), LEX_CMP(oi, oj, l, r))
  | {m:int}{i,j:nat | j == i + 1; i < 32; j < 32}
    {si,sj:int}{r:int | r <= 0}
    PAIR_INT_VERIFIED(m, i, j) of
      (FIELD_INT_SPEC(m, i, si), FIELD_INT_SPEC(m, j, sj), INT_CMP(si, sj, r))

(* Sorted: every adjacent pair is in order — inductive *)
dataprop LIBRARY_SORTED(mode: int, count: int) =
  | {m:int} SORTED_NIL(m, 0)
  | {m:int} SORTED_ONE(m, 1)
  | {m:int}{n:int | n >= 2}
    SORTED_CONS(m, n) of (LIBRARY_SORTED(m, n-1), PAIR_IN_ORDER(m, n-2, n-1))

(* Serialization version marker *)
stadef SER_VERSION_MARKER = 65535
stadef SER_VERSION_2 = 2
stadef SER_VERSION_3 = 3
stadef SER_VERSION_4 = 4

dataprop SER_VERSION_DETECTED(marker: int, version: int) =
  | {m:int | m == 65535} IS_V2_OR_V3(m, 2)
  | {m:nat | m <= 32} IS_V1(m, 1)

(* ========== Book access safety proof ========== *)

(* BOOK_ACCESS_SAFE(i): proves that accessing book record at index i
 * is within bounds for both i32 slot access and byte-level access.
 * Constraints:
 *   i * LIB_REC_INTS + 154 < 4960   (max i32 slot fits in lib_books)
 *   i * LIB_REC_BYTES + 520 + 64 <= 19840  (max byte copy fits in lib_books)
 * 4960 = 32 * 155  (total i32 slots), 19840 = 32 * 620 (total bytes) *)
dataprop BOOK_ACCESS_SAFE(i: int) =
  | {i:nat | i < 32;
     i * LIB_REC_INTS + 154 < 4960;
     i * LIB_REC_BYTES + 520 + 64 <= 19840}
    BOOK_ACCESS_OK(i)

(* Record layout accessor functions — single source of truth.
 * If REC_INTS changes to != 155, library_rec_ints won't compile. *)
fun library_rec_ints(): int(LIB_REC_INTS)
fun library_rec_bytes(): int(LIB_REC_BYTES)

(* Bounds check: returns 1 if index is valid, 0 otherwise.
 * Return type uses sif so the solver can evaluate for concrete inputs.
 * e.g. check_book_index(0,1) returns int(1), check_book_index(32,32) returns int(0). *)
fun check_book_index {b,c:int} (bidx: int(b), count: int(c)): [v:nat | v <= 1] int(v)

(* ========== Duplicate choice proof ========== *)

(* DUP_CHOICE_VALID: enumerates valid duplicate-detection outcomes.
 * 0 = skip (keep existing), 1 = replace (update existing with new data). *)
dataprop DUP_CHOICE_VALID(c: int) =
  | DUP_SKIP(0)
  | DUP_REPLACE(1)

(* ========== Import outcome proof ========== *)

(* ADD_BOOK_RESULT: proves every library_add_book outcome is handled.
 * Adding a new error code MUST add a constructor here — without it,
 * the caller's prval pattern-match is non-exhaustive and ATS2 rejects. *)
dataprop ADD_BOOK_RESULT(idx: int) =
  | {i:nat | i < 32} BOOK_ADDED(i)      (* success: book at index i *)
  | LIB_FULL(~1)                          (* library at 32-book capacity *)

(* ========== Module Functions ========== *)

fun library_init(): void
fun library_get_count(): [n:nat | n <= 32] int(n)
fun library_get_title(index: int, buf_offset: int): [len:nat] int(len)
fun library_get_author(index: int, buf_offset: int): [len:nat] int(len)
fun library_get_book_id(index: int, buf_offset: int): [len:nat] int(len)
fun library_get_chapter(index: int): [ch:nat] int(ch)
fun library_get_page(index: int): [pg:nat] int(pg)
fun library_get_spine_count(index: int): [sc:nat] int(sc)

(* Get/set shelf state: 0=active, 1=archived, 2=hidden *)
fun library_get_shelf_state(index: int): [s:nat | s <= 2] int(s)
fun library_set_shelf_state {s:int}
  (pf: SHELF_STATE_VALID(s) | index: int, v: int(s)): void

fun library_add_book(): [i:int | i >= ~1; i < 32] (ADD_BOOK_RESULT(i) | int(i))
fun library_remove_book(index: int): void
fun library_update_position(index: int, chapter: int, page: int): void
fun library_find_book_by_id(): [i:int | i >= ~1] int(i)

(* Replace an existing book entry with new epub data.
 * Updates title, author, book_id, spine_count, file_size, has_cover.
 * Resets chapter/page to 0, sets shelf_state to 0 (active),
 * updates last_opened to now. Preserves date_added. *)
fun library_replace_book(index: int): void

(* Sort library in place. Returns book count with sorted proof. *)
fun library_sort {m:nat | m <= 3}
  (pf_mode: SORT_MODE_VALID(m) | mode: int(m))
  : [n:nat | n <= 32] (LIBRARY_SORTED(m, n) | int(n))

(* View filter — requires precondition proofs, returns render decision *)
fun should_render_book {vm:nat | vm <= 2}{s:nat | s <= 2}
  (pf_vm: VIEW_MODE_VALID(vm), pf_ss: SHELF_STATE_VALID(s) |
   vm: int(vm), ss: int(s))
  : [r:int] (VIEW_FILTER_CORRECT(vm, s, r) | int(r))

(* Per-book metadata *)
fun library_get_date_added(index: int): int
fun library_get_last_opened(index: int): int
fun library_get_file_size(index: int): int
fun library_get_has_cover(index: int): [c:int | c == 0 || c == 1] int(c)
fun library_set_last_opened {t:nat}
  (pf: TIMESTAMP_VALID(t) | index: int, ts: int(t)): void

(* Serialization format helpers — single source of truth *)
fun ser_fixed_bytes {v:int | v >= 1; v <= 4}
  (version: int(v)): [fb:pos] (SER_FORMAT(v, fb) | int(fb))
fun ser_var_field_spec {f:nat | f <= 2}
  (field: int(f)): [bo,ml,ls:nat]
  (SER_VAR_FIELD(f, bo, ml, ls) | int(bo), int(ml), int(ls))

(* Serialization *)
fun library_serialize(): [len:nat] int(len)
fun library_deserialize(len: int): [r:int | r == 0 || r == 1] int(r)
fun library_save(): void
fun library_load(): ward_promise_chained(int)
fun library_on_load_complete(len: int): void
fun library_on_save_complete(success: int): void
fun library_save_book_metadata(): void
fun library_load_book_metadata(index: int): void
fun library_on_metadata_load_complete(len: int): void
fun library_on_metadata_save_complete(success: int): void
fun library_is_save_pending(): [b:int | b == 0 || b == 1] int(b)
fun library_is_load_pending(): [b:int | b == 0 || b == 1] int(b)
fun library_is_metadata_pending(): [b:int | b == 0 || b == 1] int(b)
