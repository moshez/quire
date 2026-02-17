(* library.sats - Book library type declarations
 *
 * M15: Manages a persistent library of imported books.
 * Each book entry stores title, author, reading position, chapter count,
 * and archived flag.
 * Library index is serialized to IndexedDB for persistence.
 *
 * FUNCTIONAL CORRECTNESS PROOFS:
 * - LIBRARY_INDEX_VALID: Book count within bounds, all entries have valid data
 * - BOOK_POSITION_VALID: Reading position within book bounds
 * - BOOK_IN_LIBRARY: Proves a book index is valid for the current library
 * - SERIALIZE_ROUNDTRIP: Serialize then deserialize preserves library data
 * - ARCHIVE_STATE_VALID: Archived flag is 0 or 1
 * - SORT_MODE_VALID: Sort mode is 0 (title) or 1 (author)
 * - LIBRARY_SORTED: Library is sorted by the given mode
 *)

staload "./../vendor/ward/lib/promise.sats"
staload "./buf.sats"

(* Maximum number of books in library *)
#define MAX_LIBRARY_BOOKS 32

(* ========== Record layout stadefs (type-level) ========== *)

stadef MAX_BOOKS_S = 32
stadef REC_INTS_S = 152
stadef REC_BYTES_S = 608           (* REC_INTS_S * 4 *)

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

(* Serialization roundtrip correctness proof. *)
absprop SERIALIZE_ROUNDTRIP(len: int)

(* Single-pending-flag invariant proof. *)
dataprop SINGLE_PENDING(handler_id: int) =
  | PENDING_SETTINGS(0)
  | PENDING_LIB_METADATA(1)
  | PENDING_LIB_INDEX(2)
  | PENDING_EPUB_IMPORT(3)
  | PENDING_READER_CHAPTER(4)

(* Import lock proof. *)
absprop IMPORT_LOCK_FREE

(* ========== Archive/Sort Dataprops ========== *)

(* Archive flag: only 0 or 1 are valid *)
dataprop ARCHIVE_STATE_VALID(a: int) =
  | ACTIVE(0)
  | ARCHIVED(1)

(* Sort mode: only title or author *)
dataprop SORT_MODE_VALID(m: int) =
  | SORT_BY_TITLE(0)
  | SORT_BY_AUTHOR(1)

(* View mode: active books or archived books *)
dataprop VIEW_MODE_VALID(m: int) =
  | VIEW_ACTIVE(0)
  | VIEW_ARCHIVED(1)

(* View filtering: compile-time proof that the render decision is correct *)
dataprop VIEW_FILTER_CORRECT(view_mode: int, archived: int, render: int) =
  | RENDER_ACTIVE(0, 0, 1)
  | SKIP_ARCHIVED_IN_ACTIVE(0, 1, 0)
  | RENDER_ARCHIVED(1, 1, 1)
  | SKIP_ACTIVE_IN_ARCHIVED(1, 0, 0)

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

(* Pair ordering: verified by post-state comparison *)
dataprop PAIR_IN_ORDER(mode: int, i: int, j: int) =
  | {m:int}{i,j:nat | j == i + 1; i < 32; j < 32}
    {oi,oj:int}{l:pos}{r:int | r <= 0}
    PAIR_VERIFIED(m, i, j) of
      (FIELD_SPEC(m, i, oi, l), FIELD_SPEC(m, j, oj, l), LEX_CMP(oi, oj, l, r))

(* Sorted: every adjacent pair is in order — inductive *)
dataprop LIBRARY_SORTED(mode: int, count: int) =
  | {m:int} SORTED_NIL(m, 0)
  | {m:int} SORTED_ONE(m, 1)
  | {m:int}{n:int | n >= 2}
    SORTED_CONS(m, n) of (LIBRARY_SORTED(m, n-1), PAIR_IN_ORDER(m, n-2, n-1))

(* Serialization version marker *)
stadef SER_VERSION_MARKER = 65535
stadef SER_VERSION_2 = 2

dataprop SER_VERSION_DETECTED(marker: int, version: int) =
  | {m:int | m == 65535} IS_V2(m, 2)
  | {m:nat | m <= 32} IS_V1(m, 1)

(* ========== Module Functions ========== *)

fun library_init(): void
fun library_get_count(): [n:nat | n <= 32] int(n)
fun library_get_title(index: int, buf_offset: int): [len:nat] int(len)
fun library_get_author(index: int, buf_offset: int): [len:nat] int(len)
fun library_get_book_id(index: int, buf_offset: int): [len:nat] int(len)
fun library_get_chapter(index: int): [ch:nat] int(ch)
fun library_get_page(index: int): [pg:nat] int(pg)
fun library_get_spine_count(index: int): [sc:nat] int(sc)

(* Get/set archived flag *)
fun library_get_archived(index: int): [a:nat | a <= 1] int(a)
fun library_set_archived {a:int}
  (pf: ARCHIVE_STATE_VALID(a) | index: int, v: int(a)): void

fun library_add_book(): [i:int | i >= ~1; i < 32] int(i)
fun library_remove_book(index: int): void
fun library_update_position(index: int, chapter: int, page: int): void
fun library_find_book_by_id(): [i:int | i >= ~1] int(i)

(* Sort library in place. Returns book count with sorted proof. *)
fun library_sort {m:nat | m <= 1}
  (pf_mode: SORT_MODE_VALID(m) | mode: int(m))
  : [n:nat | n <= 32] (LIBRARY_SORTED(m, n) | int(n))

(* View filter — requires precondition proofs, returns render decision *)
fun should_render_book {vm:nat | vm <= 1}{a:nat | a <= 1}
  (pf_vm: VIEW_MODE_VALID(vm), pf_a: ARCHIVE_STATE_VALID(a) |
   vm: int(vm), a: int(a))
  : [r:int] (VIEW_FILTER_CORRECT(vm, a, r) | int(r))

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
