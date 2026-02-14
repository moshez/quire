(* library.dats - Book library implementation
 *
 * Pure ATS2 implementation. Book data stored as flat byte records
 * in app_state's library_books buffer via per-byte/i32 accessors.
 * No $UNSAFE, no raw ptr, no sized_buf.
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
staload "./app_state.sats"

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

(* Copy book record via per-byte lib_books accessors *)
fn _copy_book(dst: int, src_idx: int): void = let
  val dst_off = dst * REC_BYTES
  val src_off = src_idx * REC_BYTES
  fun loop(i: int, doff: int, soff: int): void =
    if lt_int_int(i, REC_BYTES) then let
      val b = _app_lib_books_get_u8(soff + i)
      val () = _app_lib_books_set_u8(doff + i, b)
    in loop(i + 1, doff, soff) end
in loop(0, dst_off, src_off) end

(* ========== Library functions ========== *)

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
    val bid_len = _app_epub_book_id_len()
    (* Deduplicate by book_id *)
    fun find_dup(i: int, cnt: int, blen: int): int =
      if gte_int_int(i, cnt) then 0 - 1
      else let
        val stored_len = _app_lib_books_get_i32(i * REC_INTS + BOOKID_LEN_SLOT)
      in
        if neq_int_int(stored_len, blen) then find_dup(i + 1, cnt, blen)
        else if gt_int_int(_app_lib_books_match_bid(i * REC_BYTES + BOOKID_OFF, blen), 0)
        then i
        else find_dup(i + 1, cnt, blen)
      end
    val dup = find_dup(0, count, bid_len)
  in
    if gte_int_int(dup, 0) then _lib_idx(dup)
    else let
      val tlen = _app_epub_title_len()
      val alen = _app_epub_author_len()
      val sc = _app_epub_spine_count()
      val base_ints = count * REC_INTS
      val base_bytes = count * REC_BYTES

      (* Copy title: epub_title → sbuf → lib_books *)
      val tlen2 = if gt_int_int(tlen, TITLE_MAX) then TITLE_MAX else tlen
      val () = _app_copy_epub_title_to_sbuf(0, tlen2)
      val () = _app_copy_sbuf_to_lib_books(base_bytes + TITLE_OFF, 0, tlen2)
      val () = _app_lib_books_set_i32(base_ints + TITLE_LEN_SLOT, tlen2)

      (* Copy author: epub_author → sbuf → lib_books *)
      val alen2 = if gt_int_int(alen, AUTHOR_MAX) then AUTHOR_MAX else alen
      val () = _app_copy_epub_author_to_sbuf(0, alen2)
      val () = _app_copy_sbuf_to_lib_books(base_bytes + AUTHOR_OFF, 0, alen2)
      val () = _app_lib_books_set_i32(base_ints + AUTHOR_LEN_SLOT, alen2)

      (* Copy book_id: epub_book_id → sbuf → lib_books *)
      val blen2 = if gt_int_int(bid_len, BOOKID_MAX) then BOOKID_MAX else bid_len
      val () = _app_copy_epub_book_id_to_sbuf(0, blen2)
      val () = _app_copy_sbuf_to_lib_books(base_bytes + BOOKID_OFF, 0, blen2)
      val () = _app_lib_books_set_i32(base_ints + BOOKID_LEN_SLOT, blen2)

      val () = _app_lib_books_set_i32(base_ints + SPINE_SLOT, sc)
      val () = _app_lib_books_set_i32(base_ints + CHAPTER_SLOT, 0)
      val () = _app_lib_books_set_i32(base_ints + PAGE_SLOT, 0)
      val () = _app_set_lib_count(count + 1)
    in _lib_idx(count) end
  end
end

implement library_get_title(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val len = _app_lib_books_get_i32(index * REC_INTS + TITLE_LEN_SLOT)
    val () = _app_copy_lib_books_to_sbuf(index * REC_BYTES + TITLE_OFF, buf_offset, len)
  in _checked_nat(len) end

implement library_get_author(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val len = _app_lib_books_get_i32(index * REC_INTS + AUTHOR_LEN_SLOT)
    val () = _app_copy_lib_books_to_sbuf(index * REC_BYTES + AUTHOR_OFF, buf_offset, len)
  in _checked_nat(len) end

implement library_get_book_id(index, buf_offset) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val len = _app_lib_books_get_i32(index * REC_INTS + BOOKID_LEN_SLOT)
    val () = _app_copy_lib_books_to_sbuf(index * REC_BYTES + BOOKID_OFF, buf_offset, len)
  in _checked_nat(len) end

implement library_get_chapter(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _checked_nat(_app_lib_books_get_i32(index * REC_INTS + CHAPTER_SLOT))

implement library_get_page(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _checked_nat(_app_lib_books_get_i32(index * REC_INTS + PAGE_SLOT))

implement library_get_spine_count(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _checked_nat(_app_lib_books_get_i32(index * REC_INTS + SPINE_SLOT))

implement library_update_position(index, chapter, page) =
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, _app_lib_count()) then ()
  else let
    val base = index * REC_INTS
    val () = _app_lib_books_set_i32(base + CHAPTER_SLOT, chapter)
    val () = _app_lib_books_set_i32(base + PAGE_SLOT, page)
  in end

implement library_find_book_by_id() = let
  val count = _app_lib_count()
  val bid_len = _app_epub_book_id_len()
  fun loop(i: int, cnt: int, blen: int): int =
    if gte_int_int(i, cnt) then 0 - 1
    else let
      val stored_len = _app_lib_books_get_i32(i * REC_INTS + BOOKID_LEN_SLOT)
    in
      if neq_int_int(stored_len, blen) then loop(i + 1, cnt, blen)
      else if gt_int_int(_app_lib_books_match_bid(i * REC_BYTES + BOOKID_OFF, blen), 0)
      then i
      else loop(i + 1, cnt, blen)
    end
in _find_idx(loop(0, count, bid_len)) end

implement library_remove_book(index) = let
  val count = _app_lib_count()
in
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, count) then ()
  else let
    fun shift(i: int, cnt: int): void =
      if lt_int_int(i, cnt - 1) then let
        val () = _copy_book(i, i + 1)
      in shift(i + 1, cnt) end
    val () = shift(index, count)
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
