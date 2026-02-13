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
staload "./app_state.sats"

(* Module-private raw ptr buffer access — stays within library.dats *)
extern fun buf_get_u8(p: ptr, off: int): int = "mac#buf_get_u8"
extern fun buf_set_u8(p: ptr, off: int, v: int): void = "mac#buf_set_u8"
extern fun buf_get_i32(p: ptr, idx: int): int = "mac#buf_get_i32"
extern fun buf_set_i32(p: ptr, idx: int, v: int): void = "mac#buf_set_i32"
extern fun get_string_buffer_ptr(): ptr = "mac#get_string_buffer_ptr"

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

(* ========== Castfns for dependent return types ========== *)
extern castfn _clamp32(x: int): [n:nat | n <= 32] int n
extern castfn _lib_idx(x: int): [i:int | i >= ~1; i < 32] int i
extern castfn _find_idx(x: int): [i:int | i >= ~1] int i

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

implement library_init() = _app_set_lib_count(0)

implement library_get_count() = let
  val c = _app_lib_count()
in
  if lt_int_int(c, 0) then 0
  else if gt_int_int(c, 32) then 32
  else _clamp32(c)
end

implement library_add_book() = let
  val count = _app_lib_count()
in
  if gte_int_int(count, 32) then _lib_idx(0 - 1)
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
    if gte_int_int(dup, 0) then _lib_idx(dup)
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
    in _lib_idx(count) end
  end
end

implement library_get_title(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val books = _app_lib_books_ptr()
    val len = buf_get_i32(books, index * REC_INTS + TITLE_LEN_SLOT)
    val () = _copy_bytes_to_sbuf(books, index, TITLE_OFF, len,
                                 get_string_buffer_ptr(), buf_offset)
  in _checked_nat(len) end

implement library_get_author(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val books = _app_lib_books_ptr()
    val len = buf_get_i32(books, index * REC_INTS + AUTHOR_LEN_SLOT)
    val () = _copy_bytes_to_sbuf(books, index, AUTHOR_OFF, len,
                                 get_string_buffer_ptr(), buf_offset)
  in _checked_nat(len) end

implement library_get_book_id(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val books = _app_lib_books_ptr()
    val len = buf_get_i32(books, index * REC_INTS + BOOKID_LEN_SLOT)
    val () = _copy_bytes_to_sbuf(books, index, BOOKID_OFF, len,
                                 get_string_buffer_ptr(), buf_offset)
  in _checked_nat(len) end

implement library_get_chapter(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _checked_nat(buf_get_i32(_app_lib_books_ptr(), index * REC_INTS + CHAPTER_SLOT))

implement library_get_page(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _checked_nat(buf_get_i32(_app_lib_books_ptr(), index * REC_INTS + PAGE_SLOT))

implement library_get_spine_count(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _checked_nat(buf_get_i32(_app_lib_books_ptr(), index * REC_INTS + SPINE_SLOT))

implement library_update_position(index, chapter, page) =
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, _app_lib_count()) then ()
  else let
    val books = _app_lib_books_ptr()
    val base = index * REC_INTS
    val () = buf_set_i32(books, base + CHAPTER_SLOT, chapter)
    val () = buf_set_i32(books, base + PAGE_SLOT, page)
  in end

implement library_find_book_by_id() = let
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
in _find_idx(loop(0)) end

implement library_remove_book(index) = let
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

implement library_serialize() = 0

implement library_deserialize(len) = 0

implement library_save() = ()

implement library_load() = ()

implement library_on_load_complete(len) = ()

implement library_on_save_complete(success) = ()

implement library_save_book_metadata() = ()

implement library_load_book_metadata(index) = ()

implement library_on_metadata_load_complete(len) = ()

implement library_on_metadata_save_complete(success) = ()

implement library_is_save_pending() = 0

implement library_is_load_pending() = 0

implement library_is_metadata_pending() = 0
