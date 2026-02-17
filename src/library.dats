(* library.dats - Book library implementation
 *
 * Pure ATS2 implementation. Book data stored as flat byte records
 * in app_state's library_books buffer via per-byte/i32 accessors.
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
 *
 * Serialization format (to fetch buffer):
 *   [u16: count] per book: [u16: bid_len] [bytes: bid]
 *   [u16: tlen] [bytes: title] [u16: alen] [bytes: author]
 *   [u16: spine_count] [u16: chapter] [u16: page]
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./library.sats"

staload "./arith.sats"
staload "./app_state.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/promise.sats"
staload "./../vendor/ward/lib/idb.sats"
staload "./../vendor/ward/lib/window.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/promise.dats"
staload _ = "./../vendor/ward/lib/idb.dats"

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

(* ========== Persistence helpers ========== *)

(* IDB key "lib" — safe chars: l=108 i=105 b=98 *)
fn _idb_key_lib(): ward_safe_text(3) = let
  val t = ward_text_build(3)
  val t = ward_text_putc(t, 0, 108) (* l *)
  val t = ward_text_putc(t, 1, 105) (* i *)
  val t = ward_text_putc(t, 2, 98)  (* b *)
in ward_text_done(t) end

(* Log messages for persistence *)
fn _log_lib_saved(): ward_safe_text(9) = let
  val t = ward_text_build(9)
  val t = ward_text_putc(t, 0, 108) (* l *)
  val t = ward_text_putc(t, 1, 105) (* i *)
  val t = ward_text_putc(t, 2, 98)  (* b *)
  val t = ward_text_putc(t, 3, 45)  (* - *)
  val t = ward_text_putc(t, 4, 115) (* s *)
  val t = ward_text_putc(t, 5, 97)  (* a *)
  val t = ward_text_putc(t, 6, 118) (* v *)
  val t = ward_text_putc(t, 7, 101) (* e *)
  val t = ward_text_putc(t, 8, 100) (* d *)
in ward_text_done(t) end

fn _log_lib_loaded(): ward_safe_text(10) = let
  val t = ward_text_build(10)
  val t = ward_text_putc(t, 0, 108) (* l *)
  val t = ward_text_putc(t, 1, 105) (* i *)
  val t = ward_text_putc(t, 2, 98)  (* b *)
  val t = ward_text_putc(t, 3, 45)  (* - *)
  val t = ward_text_putc(t, 4, 108) (* l *)
  val t = ward_text_putc(t, 5, 111) (* o *)
  val t = ward_text_putc(t, 6, 97)  (* a *)
  val t = ward_text_putc(t, 7, 100) (* d *)
  val t = ward_text_putc(t, 8, 101) (* e *)
  val t = ward_text_putc(t, 9, 100) (* d *)
in ward_text_done(t) end

(* Write u16 little-endian to fetch buffer *)
fn _fbuf_write_u16(off: int, v: int): void = let
  val () = _app_fbuf_set_u8(off, band_int_int(v, 255))
  val () = _app_fbuf_set_u8(off + 1, band_int_int(bsr_int_int(v, 8), 255))
in end

(* Read u16 little-endian from fetch buffer *)
fn _fbuf_read_u16(off: int): int = let
  val lo = _app_fbuf_get_u8(off)
  val hi = _app_fbuf_get_u8(off + 1)
in bor_int_int(lo, bsl_int_int(hi, 8)) end

(* Copy bytes from lib_books to fetch buffer *)
fn _copy_lib_to_fbuf(src_base: int, dst_off: int, n: int): void = let
  fun loop(j: int): void =
    if lt_int_int(j, n) then let
      val b = _app_lib_books_get_u8(src_base + j)
      val () = _app_fbuf_set_u8(dst_off + j, b)
    in loop(j + 1) end
in loop(0) end

(* Copy bytes from fetch buffer to lib_books *)
fn _copy_fbuf_to_lib(src_off: int, dst_base: int, n: int): void = let
  fun loop(j: int): void =
    if lt_int_int(j, n) then let
      val b = _app_fbuf_get_u8(src_off + j)
      val () = _app_lib_books_set_u8(dst_base + j, b)
    in loop(j + 1) end
in loop(0) end

(* Clamp value to [0, max] *)
fn _clamp(v: int, mx: int): int =
  if lt_int_int(v, 0) then 0
  else if gt_int_int(v, mx) then mx
  else v

(* ========== Serialization ========== *)

implement library_serialize() = let
  val count = _app_lib_count()
  val count2 = _clamp(count, 32)
  val () = _fbuf_write_u16(0, count2)
  fun loop(i: int, off: int): int =
    if gte_int_int(i, count2) then off
    else if gt_int_int(off + 588, 16384) then off (* overflow guard *)
    else let
      val bi = i * REC_INTS
      val bb = i * REC_BYTES
      (* book_id *)
      val bid_len = _clamp(_app_lib_books_get_i32(bi + BOOKID_LEN_SLOT), BOOKID_MAX)
      val () = _fbuf_write_u16(off, bid_len)
      val () = _copy_lib_to_fbuf(bb + BOOKID_OFF, off + 2, bid_len)
      val off = off + 2 + bid_len
      (* title *)
      val tlen = _clamp(_app_lib_books_get_i32(bi + TITLE_LEN_SLOT), TITLE_MAX)
      val () = _fbuf_write_u16(off, tlen)
      val () = _copy_lib_to_fbuf(bb + TITLE_OFF, off + 2, tlen)
      val off = off + 2 + tlen
      (* author *)
      val alen = _clamp(_app_lib_books_get_i32(bi + AUTHOR_LEN_SLOT), AUTHOR_MAX)
      val () = _fbuf_write_u16(off, alen)
      val () = _copy_lib_to_fbuf(bb + AUTHOR_OFF, off + 2, alen)
      val off = off + 2 + alen
      (* spine_count, chapter, page *)
      val () = _fbuf_write_u16(off, _app_lib_books_get_i32(bi + SPINE_SLOT))
      val () = _fbuf_write_u16(off + 2, _app_lib_books_get_i32(bi + CHAPTER_SLOT))
      val () = _fbuf_write_u16(off + 4, _app_lib_books_get_i32(bi + PAGE_SLOT))
    in loop(i + 1, off + 6) end
  val total = loop(0, 2)
in _checked_nat(total) end

implement library_deserialize(len) =
  if lt_int_int(len, 2) then 0
  else let
    val count = _fbuf_read_u16(0)
    val count2 = _clamp(count, 32)
    fun loop(i: int, off: int): int =
      if gte_int_int(i, count2) then 1
      else if gt_int_int(off + 8, len) then 0 (* truncated *)
      else let
        val bi = i * REC_INTS
        val bb = i * REC_BYTES
        (* book_id *)
        val bid_len = _clamp(_fbuf_read_u16(off), BOOKID_MAX)
        val off = off + 2
      in
        if gt_int_int(off + bid_len, len) then 0
        else let
          val () = _copy_fbuf_to_lib(off, bb + BOOKID_OFF, bid_len)
          val () = _app_lib_books_set_i32(bi + BOOKID_LEN_SLOT, bid_len)
          val off = off + bid_len
          (* title *)
          val tlen = _clamp(_fbuf_read_u16(off), TITLE_MAX)
          val off = off + 2
        in
          if gt_int_int(off + tlen, len) then 0
          else let
            val () = _copy_fbuf_to_lib(off, bb + TITLE_OFF, tlen)
            val () = _app_lib_books_set_i32(bi + TITLE_LEN_SLOT, tlen)
            val off = off + tlen
            (* author *)
            val alen = _clamp(_fbuf_read_u16(off), AUTHOR_MAX)
            val off = off + 2
          in
            if gt_int_int(off + alen, len) then 0
            else let
              val () = _copy_fbuf_to_lib(off, bb + AUTHOR_OFF, alen)
              val () = _app_lib_books_set_i32(bi + AUTHOR_LEN_SLOT, alen)
              val off = off + alen
            in
              if gt_int_int(off + 6, len) then 0
              else let
                val () = _app_lib_books_set_i32(bi + SPINE_SLOT, _fbuf_read_u16(off))
                val () = _app_lib_books_set_i32(bi + CHAPTER_SLOT, _fbuf_read_u16(off + 2))
                val () = _app_lib_books_set_i32(bi + PAGE_SLOT, _fbuf_read_u16(off + 4))
              in loop(i + 1, off + 6) end
            end
          end
        end
      end
    val ok = loop(0, 2)
    val () = if eq_int_int(ok, 1) then _app_set_lib_count(count2)
  in
    if eq_int_int(ok, 1) then 1 else 0
  end

implement library_save() = let
  val slen = library_serialize()
in
  if gt_int_int(slen, 0) then let
    val slen1 = _checked_arr_size(slen)
    val arr = ward_arr_alloc<byte>(slen1)
    (* Copy fetch buffer to ward_arr — arr passed as ! to avoid linear capture *)
    fun copy {l:agz}{n:pos}
      (arr: !ward_arr(byte, l, n), i: int, cnt: int, sz: int n): void =
      if lt_int_int(i, cnt) then let
        val b = _app_fbuf_get_u8(i)
        val () = ward_arr_set<byte>(arr, _ward_idx(i, sz),
          ward_int2byte(_checked_byte(band_int_int(b, 255))))
      in copy(arr, i + 1, cnt, sz) end
    val () = copy(arr, 0, slen, slen1)
    val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
    val key = _idb_key_lib()
    val p = ward_idb_put(key, 3, borrow, slen1)
    val () = ward_arr_drop<byte>(frozen, borrow)
    val arr = ward_arr_thaw<byte>(frozen)
    val () = ward_arr_free<byte>(arr)
    val p2 = ward_promise_then<int><int>(p,
      llam (_status: int): ward_promise_chained(int) => let
        val () = ward_log(1, _log_lib_saved(), 9)
      in ward_promise_return<int>(0) end)
    val () = ward_promise_discard<int>(p2)
  in end
  else ()
end

implement library_load() = let
  val key = _idb_key_lib()
  val p = ward_idb_get(key, 3)
in
  ward_promise_then<int><int>(p,
    llam (data_len: int): ward_promise_chained(int) =>
      if gt_int_int(data_len, 0) then let
        val dlen = _checked_pos(data_len)
        val arr = ward_idb_get_result(dlen)
        (* Copy ward_arr to fetch buffer — arr passed as ! to avoid linear capture *)
        fun copy {l:agz}{n:pos}
          (arr: !ward_arr(byte, l, n), i: int, cnt: int, sz: int n): void =
          if lt_int_int(i, cnt) then let
            val b = byte2int0(ward_arr_get<byte>(arr, _ward_idx(i, sz)))
            val () = _app_fbuf_set_u8(i, b)
          in copy(arr, i + 1, cnt, sz) end
        val () = copy(arr, 0, data_len, dlen)
        val () = ward_arr_free<byte>(arr)
        val ok = library_deserialize(data_len)
        val () = if eq_int_int(ok, 1) then ward_log(1, _log_lib_loaded(), 10)
      in ward_promise_return<int>(ok) end
      else ward_promise_return<int>(0))
end

implement library_on_load_complete(len) = ()

implement library_on_save_complete(success) = ()

(* Metadata persistence stubs — not yet needed for basic persistence *)
implement library_save_book_metadata() = ()

implement library_load_book_metadata(index) = ()

implement library_on_metadata_load_complete(len) = ()

implement library_on_metadata_save_complete(success) = ()

implement library_is_save_pending() = 0

implement library_is_load_pending() = 0

implement library_is_metadata_pending() = 0
