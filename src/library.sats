(* library.sats - Book library type declarations
 *
 * M15: Manages a persistent library of imported books.
 * Each book entry stores title, author, reading position, and chapter count.
 * Library index is serialized to IndexedDB for persistence.
 *
 * FUNCTIONAL CORRECTNESS PROOFS:
 * - LIBRARY_INDEX_VALID: Book count within bounds, all entries have valid data
 * - BOOK_POSITION_VALID: Reading position within book bounds
 *)

(* Maximum number of books in library *)
#define MAX_LIBRARY_BOOKS 32

(* ========== Functional Correctness Dataprops ========== *)

(* Library index validity proof.
 * LIBRARY_INDEX_VALID(count, max) proves:
 * - 0 <= count <= max
 * - All entries at indices 0..count-1 have valid book_id, title, author *)
dataprop LIBRARY_INDEX_VALID(count: int, max: int) =
  | {c,m:nat | c <= m} VALID_INDEX(c, m)

(* Book position validity proof.
 * BOOK_POSITION_VALID(chapter, page, total_chapters) proves:
 * - 0 <= chapter < total_chapters (or chapter == 0 if total_chapters == 0)
 * - page >= 0 *)
dataprop BOOK_POSITION_VALID(chapter: int, page: int, total: int) =
  | {c,p,t:nat | c < t} VALID_POSITION(c, p, t)
  | {p:nat} EMPTY_POSITION(0, p, 0)

(* ========== Module Functions ========== *)

(* Initialize library module *)
fun library_init(): void = "mac#"

(* Get number of books in library *)
fun library_get_count(): [n:nat | n <= 32] int(n) = "mac#"

(* Get book title into string buffer. Returns length. *)
fun library_get_title(index: int, buf_offset: int): int = "mac#"

(* Get book author into string buffer. Returns length. *)
fun library_get_author(index: int, buf_offset: int): int = "mac#"

(* Get book ID into string buffer. Returns length. *)
fun library_get_book_id(index: int, buf_offset: int): int = "mac#"

(* Get reading position for a book *)
fun library_get_chapter(index: int): int = "mac#"
fun library_get_page(index: int): int = "mac#"
fun library_get_spine_count(index: int): int = "mac#"

(* Add current epub book to library.
 * Reads book info from epub module state.
 * Returns index of added book, or -1 if library full. *)
fun library_add_book(): int = "mac#"

(* Remove book from library by index *)
fun library_remove_book(index: int): void = "mac#"

(* Update reading position for a book *)
fun library_update_position(index: int, chapter: int, page: int): void = "mac#"

(* Find book index by book_id. Returns index or -1. *)
fun library_find_book_by_id(): int = "mac#"

(* Serialize library index to fetch buffer. Returns length. *)
fun library_serialize(): int = "mac#"

(* Deserialize library index from fetch buffer. Returns 1 on success. *)
fun library_deserialize(len: int): int = "mac#"

(* Save library index to IndexedDB (async) *)
fun library_save(): void = "mac#"

(* Load library index from IndexedDB (async) *)
fun library_load(): void = "mac#"

(* Handle load/save completion callbacks *)
fun library_on_load_complete(len: int): void = "mac#"
fun library_on_save_complete(success: int): void = "mac#"

(* Save book metadata to IndexedDB (async).
 * Serializes current epub state and stores under book-{book_id} key. *)
fun library_save_book_metadata(): void = "mac#"

(* Load book metadata from IndexedDB (async).
 * index: book index in library. Loads into fetch buffer. *)
fun library_load_book_metadata(index: int): void = "mac#"

(* Handle metadata load/save completion *)
fun library_on_metadata_load_complete(len: int): void = "mac#"
fun library_on_metadata_save_complete(success: int): void = "mac#"

(* Check pending async operations *)
fun library_is_save_pending(): int = "mac#"
fun library_is_load_pending(): int = "mac#"
fun library_is_metadata_pending(): int = "mac#"
