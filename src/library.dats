(* library.dats - Book library implementation
 *
 * Pure ATS2 implementation. Book data stored as flat byte records
 * in a calloc'd buffer held in app_state.
 *
 * Book record layout: 150 i32 slots = 600 bytes per book.
 *   Byte 0-255:   title (256 bytes)
 *   i32 slot 64:  title_len
 *   Byte 260-515: author (256 bytes)
 *   i32 slot 129: author_len
 *   Byte 520-583: book_id (64 bytes)
 *   i32 slot 146: book_id_len
 *   i32 slot 147: spine_count
 *   i32 slot 148: current_chapter
 *   i32 slot 149: current_page
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./library.sats"

staload "./arith.sats"
staload "./buf.sats"

(* ========== App state ext# wrappers ========== *)

extern fun _app_lib_count(): int = "mac#"
extern fun _app_set_lib_count(v: int): void = "mac#"
extern fun _app_lib_books_ptr(): ptr = "mac#"
extern fun _app_epub_book_id_ptr(): ptr = "mac#"
extern fun _app_epub_book_id_len(): int = "mac#"
extern fun _app_epub_title_ptr(): ptr = "mac#"
extern fun _app_epub_title_len(): int = "mac#"
extern fun _app_epub_author_ptr(): ptr = "mac#"
extern fun _app_epub_author_len(): int = "mac#"
extern fun _app_epub_spine_count(): int = "mac#"
extern fun get_string_buffer_ptr(): ptr = "mac#"

(* ========== Record layout constants ========== *)

#define REC_BYTES 600
#define REC_INTS 150
#define TITLE_OFF 0
#define TITLE_MAX 256
#define TITLE_LEN_SLOT 64
#define AUTHOR_OFF 260
#define AUTHOR_MAX 256
#define AUTHOR_LEN_SLOT 129
#define BOOKID_OFF 520
#define BOOKID_MAX 64
#define BOOKID_LEN_SLOT 146
#define SPINE_SLOT 147
#define CHAPTER_SLOT 148
#define PAGE_SLOT 149

(* ========== Helpers ========== *)

fn _copy_bytes_to_book(books: ptr, book_idx: int, field_off: int,
    src: ptr, src_len: int, max_len: int): int = let
  val len = if gt_int_int(src_len, max_len) then max_len else src_len
  val base = book_idx * REC_BYTES + field_off
  fun loop(i: int): void =
    if lt_int_int(i, len) then let
      val b = buf_get_u8(src, i)
      val () = buf_set_u8(books, base + i, b)
    in loop(i + 1) end
in loop(0); len end

fn _copy_bytes_to_sbuf(books: ptr, book_idx: int, field_off: int,
    field_len: int, sbuf: ptr, sbuf_off: int): void = let
  val base = book_idx * REC_BYTES + field_off
  fun loop(i: int): void =
    if lt_int_int(i, field_len) then let
      val b = buf_get_u8(books, base + i)
      val () = buf_set_u8(sbuf, sbuf_off + i, b)
    in loop(i + 1) end
in loop(0) end

fn _bytes_match(books: ptr, book_idx: int, field_off: int,
    src: ptr, src_len: int, field_len: int): bool =
  if neq_int_int(field_len, src_len) then false
  else let
    val base = book_idx * REC_BYTES + field_off
    fun loop(j: int): bool =
      if gte_int_int(j, src_len) then true
      else if neq_int_int(buf_get_u8(books, base + j),
                          buf_get_u8(src, j)) then false
      else loop(j + 1)
  in loop(0) end

fn _copy_book(books: ptr, dst: int, src_idx: int): void = let
  val dst_off = dst * REC_BYTES
  val src_off = src_idx * REC_BYTES
  fun loop(i: int): void =
    if lt_int_int(i, REC_BYTES) then let
      val b = buf_get_u8(books, src_off + i)
      val () = buf_set_u8(books, dst_off + i, b)
    in loop(i + 1) end
in loop(0) end

(* ========== Library functions (ext#) ========== *)

extern fun library_init_impl(): void = "ext#library_init"
implement library_init_impl() = _app_set_lib_count(0)

extern fun library_get_count_impl(): int = "ext#library_get_count"
implement library_get_count_impl() = let
  val c = _app_lib_count()
in
  if lt_int_int(c, 0) then 0
  else if gt_int_int(c, 32) then 32
  else c
end

extern fun library_add_book_impl(): int = "ext#library_add_book"
implement library_add_book_impl() = let
  val count = _app_lib_count()
in
  if gte_int_int(count, 32) then 0 - 1
  else let
    val books = _app_lib_books_ptr()
    val bid_ptr = _app_epub_book_id_ptr()
    val bid_len = _app_epub_book_id_len()
    (* Deduplicate by book_id *)
    fun find_dup(i: int): int =
      if gte_int_int(i, count) then 0 - 1
      else let
        val stored_len = buf_get_i32(books, i * REC_INTS + BOOKID_LEN_SLOT)
      in
        if _bytes_match(books, i, BOOKID_OFF, bid_ptr, bid_len, stored_len)
        then i
        else find_dup(i + 1)
      end
    val dup = find_dup(0)
  in
    if gte_int_int(dup, 0) then dup
    else let
      val tptr = _app_epub_title_ptr()
      val tlen = _app_epub_title_len()
      val aptr = _app_epub_author_ptr()
      val alen = _app_epub_author_len()
      val sc = _app_epub_spine_count()
      val base = count * REC_INTS
      val tlen2 = _copy_bytes_to_book(books, count, TITLE_OFF, tptr, tlen, TITLE_MAX)
      val () = buf_set_i32(books, base + TITLE_LEN_SLOT, tlen2)
      val alen2 = _copy_bytes_to_book(books, count, AUTHOR_OFF, aptr, alen, AUTHOR_MAX)
      val () = buf_set_i32(books, base + AUTHOR_LEN_SLOT, alen2)
      val blen2 = _copy_bytes_to_book(books, count, BOOKID_OFF, bid_ptr, bid_len, BOOKID_MAX)
      val () = buf_set_i32(books, base + BOOKID_LEN_SLOT, blen2)
      val () = buf_set_i32(books, base + SPINE_SLOT, sc)
      val () = buf_set_i32(books, base + CHAPTER_SLOT, 0)
      val () = buf_set_i32(books, base + PAGE_SLOT, 0)
      val () = _app_set_lib_count(count + 1)
    in count end
  end
end

extern fun library_get_title_impl(index: int, buf_offset: int): int = "ext#library_get_title"
implement library_get_title_impl(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val books = _app_lib_books_ptr()
    val len = buf_get_i32(books, index * REC_INTS + TITLE_LEN_SLOT)
    val () = _copy_bytes_to_sbuf(books, index, TITLE_OFF, len,
                                 get_string_buffer_ptr(), buf_offset)
  in len end

extern fun library_get_author_impl(index: int, buf_offset: int): int = "ext#library_get_author"
implement library_get_author_impl(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val books = _app_lib_books_ptr()
    val len = buf_get_i32(books, index * REC_INTS + AUTHOR_LEN_SLOT)
    val () = _copy_bytes_to_sbuf(books, index, AUTHOR_OFF, len,
                                 get_string_buffer_ptr(), buf_offset)
  in len end

extern fun library_get_book_id_impl(index: int, buf_offset: int): int = "ext#library_get_book_id"
implement library_get_book_id_impl(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val books = _app_lib_books_ptr()
    val len = buf_get_i32(books, index * REC_INTS + BOOKID_LEN_SLOT)
    val () = _copy_bytes_to_sbuf(books, index, BOOKID_OFF, len,
                                 get_string_buffer_ptr(), buf_offset)
  in len end

extern fun library_get_chapter_impl(index: int): int = "ext#library_get_chapter"
implement library_get_chapter_impl(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else buf_get_i32(_app_lib_books_ptr(), index * REC_INTS + CHAPTER_SLOT)

extern fun library_get_page_impl(index: int): int = "ext#library_get_page"
implement library_get_page_impl(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else buf_get_i32(_app_lib_books_ptr(), index * REC_INTS + PAGE_SLOT)

extern fun library_get_spine_count_impl(index: int): int = "ext#library_get_spine_count"
implement library_get_spine_count_impl(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else buf_get_i32(_app_lib_books_ptr(), index * REC_INTS + SPINE_SLOT)

extern fun library_update_position_impl(index: int, chapter: int, page: int): void = "ext#library_update_position"
implement library_update_position_impl(index, chapter, page) =
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, _app_lib_count()) then ()
  else let
    val books = _app_lib_books_ptr()
    val base = index * REC_INTS
    val () = buf_set_i32(books, base + CHAPTER_SLOT, chapter)
    val () = buf_set_i32(books, base + PAGE_SLOT, page)
  in end

extern fun library_find_book_by_id_impl(): int = "ext#library_find_book_by_id"
implement library_find_book_by_id_impl() = let
  val count = _app_lib_count()
  val bid_ptr = _app_epub_book_id_ptr()
  val bid_len = _app_epub_book_id_len()
  val books = _app_lib_books_ptr()
  fun loop(i: int): int =
    if gte_int_int(i, count) then 0 - 1
    else let
      val stored_len = buf_get_i32(books, i * REC_INTS + BOOKID_LEN_SLOT)
    in
      if _bytes_match(books, i, BOOKID_OFF, bid_ptr, bid_len, stored_len)
      then i
      else loop(i + 1)
    end
in loop(0) end

extern fun library_remove_book_impl(index: int): void = "ext#library_remove_book"
implement library_remove_book_impl(index) = let
  val count = _app_lib_count()
in
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, count) then ()
  else let
    val books = _app_lib_books_ptr()
    fun shift(i: int): void =
      if lt_int_int(i, count - 1) then let
        val () = _copy_book(books, i, i + 1)
      in shift(i + 1) end
    val () = shift(index)
    val () = _app_set_lib_count(count - 1)
  in end
end

(* ========== Persistence stubs ========== *)

extern fun library_serialize_impl(): int = "ext#library_serialize"
implement library_serialize_impl() = 0

extern fun library_deserialize_impl(len: int): int = "ext#library_deserialize"
implement library_deserialize_impl(len) = 0

extern fun library_save_impl(): void = "ext#library_save"
implement library_save_impl() = ()

extern fun library_load_impl(): void = "ext#library_load"
implement library_load_impl() = ()

extern fun library_on_load_complete_impl(len: int): void = "ext#library_on_load_complete"
implement library_on_load_complete_impl(len) = ()

extern fun library_on_save_complete_impl(success: int): void = "ext#library_on_save_complete"
implement library_on_save_complete_impl(success) = ()

extern fun library_save_book_metadata_impl(): void = "ext#library_save_book_metadata"
implement library_save_book_metadata_impl() = ()

extern fun library_load_book_metadata_impl(index: int): void = "ext#library_load_book_metadata"
implement library_load_book_metadata_impl(index) = ()

extern fun library_on_metadata_load_complete_impl(len: int): void = "ext#library_on_metadata_load_complete"
implement library_on_metadata_load_complete_impl(len) = ()

extern fun library_on_metadata_save_complete_impl(success: int): void = "ext#library_on_metadata_save_complete"
implement library_on_metadata_save_complete_impl(success) = ()

extern fun library_is_save_pending_impl(): int = "ext#library_is_save_pending"
implement library_is_save_pending_impl() = 0

extern fun library_is_load_pending_impl(): int = "ext#library_is_load_pending"
implement library_is_load_pending_impl() = 0

extern fun library_is_metadata_pending_impl(): int = "ext#library_is_metadata_pending"
implement library_is_metadata_pending_impl() = 0
