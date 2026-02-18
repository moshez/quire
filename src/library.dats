(* library.dats - Book library implementation
 *
 * Pure ATS2 implementation. Book data stored as flat byte records
 * in app_state's library_books buffer via per-byte/i32 accessors.
 *
 * Book record layout: 152 i32 slots = 608 bytes per book.
 *   Byte 0-255:   title (256 bytes)
 *   i32 slot 64:  title_len
 *   Byte 260-515: author (256 bytes)
 *   i32 slot 129: author_len
 *   Byte 520-583: book_id (64 bytes)
 *   i32 slot 146: book_id_len
 *   i32 slot 147: spine_count
 *   i32 slot 148: current_chapter
 *   i32 slot 149: current_page
 *   i32 slot 150: archived (0=active, 1=archived)
 *   i32 slot 151: reserved (always 0)
 *
 * Serialization format v2 (to fetch buffer):
 *   [u16: 0xFFFF] [u16: version=2] [u16: count] [u16: sort_mode]
 *   per book: [u16: bid_len] [bytes: bid]
 *   [u16: tlen] [bytes: title] [u16: alen] [bytes: author]
 *   [u16: spine_count] [u16: chapter] [u16: page] [u16: archived]
 *
 * v1 format (legacy, read-only):
 *   [u16: count] per book: same as v2 minus [u16: archived]
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./library.sats"

staload "./arith.sats"
staload "./buf.sats"
staload "./app_state.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/promise.sats"
staload "./../vendor/ward/lib/idb.sats"
staload "./../vendor/ward/lib/window.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/promise.dats"
staload _ = "./../vendor/ward/lib/idb.dats"

(* ========== Record layout constants ========== *)

#define REC_BYTES 608
#define REC_INTS 152
#define TITLE_OFF 0
#define TITLE_MAX 256
#define TITLE_LEN_SLOT 64
#define TITLE_BYTE_OFF 0
#define TITLE_FIELD_LEN 256
#define AUTHOR_OFF 260
#define AUTHOR_MAX 256
#define AUTHOR_LEN_SLOT 129
#define AUTHOR_BYTE_OFF 260
#define AUTHOR_FIELD_LEN 256
#define BOOKID_OFF 520
#define BOOKID_MAX 64
#define BOOKID_LEN_SLOT 146
#define SPINE_SLOT 147
#define CHAPTER_SLOT 148
#define PAGE_SLOT 149
#define ARCHIVED_SLOT 150
#define RESERVED_SLOT 151

(* ========== Castfns for dependent return types ========== *)
extern castfn _clamp32(x: int): [n:nat | n <= 32] int n
(* Castfns for library_add_book return — each ties proof to specific index.
 * Proof erased at runtime; cast is identity on int. *)
extern castfn _mk_added(x: int)
  : [i:nat | i < 32] (ADD_BOOK_RESULT(i) | int(i))
extern castfn _mk_lib_full(x: int): (ADD_BOOK_RESULT(~1) | int(~1))
extern castfn _find_idx(x: int): [i:int | i >= ~1] int i
extern castfn _clamp_archived(x: int): [a:nat | a <= 1] int a

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

(* Swap two book records using sbuf as temp storage *)
fn swap_books(a: int, b: int): void = let
  val a_off = a * REC_BYTES
  val b_off = b * REC_BYTES
  (* Copy a → sbuf *)
  fun copy_to_sbuf(i: int, src: int): void =
    if lt_int_int(i, REC_BYTES) then let
      val v = _app_lib_books_get_u8(src + i)
      val () = _app_sbuf_set_u8(i, v)
    in copy_to_sbuf(i + 1, src) end
  (* Copy b → a *)
  fun copy_b_to_a(i: int, dst: int, src: int): void =
    if lt_int_int(i, REC_BYTES) then let
      val v = _app_lib_books_get_u8(src + i)
      val () = _app_lib_books_set_u8(dst + i, v)
    in copy_b_to_a(i + 1, dst, src) end
  (* Copy sbuf → b *)
  fun copy_sbuf_to_b(i: int, dst: int): void =
    if lt_int_int(i, REC_BYTES) then let
      val v = _app_sbuf_get_u8(i)
      val () = _app_lib_books_set_u8(dst + i, v)
    in copy_sbuf_to_b(i + 1, dst) end
  val () = copy_to_sbuf(0, a_off)
  val () = copy_b_to_a(0, a_off, b_off)
  val () = copy_sbuf_to_b(0, b_off)
in end

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
  if gte_int_int(count, 32) then _mk_lib_full(0 - 1)
  else let
    val bid_len = _app_epub_book_id_len()
    (* Deduplicate by content hash (book_id = SHA-256).
     * Same hash = same book by definition. No title check needed.
     * Returns: -1 = no match, >= 0 = existing book index *)
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
    if gte_int_int(dup, 0) then _mk_added(dup)
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
      val () = _app_lib_books_set_i32(base_ints + ARCHIVED_SLOT, 0)
      val () = _app_lib_books_set_i32(base_ints + RESERVED_SLOT, 0)
      val () = _app_set_lib_count(count + 1)
    in _mk_added(count) end
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

implement library_get_archived(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val v = _app_lib_books_get_i32(index * REC_INTS + ARCHIVED_SLOT)
  in
    if eq_int_int(v, 1) then 1
    else 0
  end

implement library_set_archived {a} (pf | index, v) = let
  prval _ = pf
in
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, _app_lib_count()) then ()
  else _app_lib_books_set_i32(index * REC_INTS + ARCHIVED_SLOT, v)
end

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

(* ========== View filter ========== *)

implement should_render_book {vm}{a} (pf_vm, pf_a | vm, a) =
  if eq_g1(vm, 0) then
    if eq_g1(a, 0) then (RENDER_ACTIVE() | 1)
    else (SKIP_ARCHIVED_IN_ACTIVE() | 0)
  else
    if eq_g1(a, 1) then (RENDER_ARCHIVED() | 1)
    else (SKIP_ACTIVE_IN_ARCHIVED() | 0)

(* ========== Sort infrastructure ========== *)

(* Read byte from lib_books, returning dependent int in [0, 255] *)
fn lib_books_get_u8_dep(off: int): [v:nat | v <= 255] int(v) =
  band_g1(_checked_nat(_app_lib_books_get_u8(off)), 255)

(* Case normalization: if byte is A-Z (65-90), add 32. Otherwise identity. *)
fn to_lower_dep {b:nat | b <= 255}(b: int(b))
  : [r:nat | r <= 255] (TO_LOWER_CORRECT(b, r) | int(r)) =
  if gte_g1(b, 65) then
    if lte_g1(b, 90) then (LOWERED() | add_g1(b, 32))
    else (KEPT_HIGH() | b)
  else (KEPT_LOW() | b)

(* Lexicographic comparison loop *)
fun lex_compare_loop
  {oi,oj:int | oi >= 0; oj >= 0}
  {l,k:nat | k <= l; oi + l <= LIB_BOOKS_CAP_S; oj + l <= LIB_BOOKS_CAP_S}
  (pf_eq: BYTES_EQ_UPTO(oi, oj, k) |
   off_i: int(oi), off_j: int(oj), len: int(l), pos: int(k))
  : [r:int] (LEX_CMP(oi, oj, l, r) | int(r)) =
  if eq_g1(pos, len) then
    (LEX_EQ(pf_eq) | 0)
  else let
    val (_ | bi) = to_lower_dep(lib_books_get_u8_dep(add_g1(off_i, pos)))
    val (_ | bj) = to_lower_dep(lib_books_get_u8_dep(add_g1(off_j, pos)))
  in
    if lt_g1(bi, bj) then
      (LEX_LT(pf_eq) | sub_g1(0, 1))
    else if gt_g1(bi, bj) then
      (LEX_GT(pf_eq) | 1)
    else
      lex_compare_loop(EQ_STEP(pf_eq) | off_i, off_j, len, add_g1(pos, 1))
  end

(* Compute byte offset and length for a book's field *)
fn field_offset {m:nat | m <= 1}{i:nat | i < 32}
  (pf_mode: SORT_MODE_VALID(m) | mode: int(m), book: int(i))
  : [oi:nat | oi + 256 <= LIB_BOOKS_CAP_S] (FIELD_SPEC(m, i, oi, 256) | int(oi), int(256)) =
  if eq_g1(mode, 0) then let
      val oi = add_g1(mul_g1(book, 608), 0)
    in (FIELD_TITLE() | oi, 256) end
  else let
      val oi = add_g1(mul_g1(book, 608), 260)
    in (FIELD_AUTHOR() | oi, 256) end

(* Compare, conditionally swap, verify post-state.
 * Returns (PROOF | int) — dummy int prevents erasure of effectful function. *)
fun ensure_ordered {m:nat | m <= 1}{i,j:nat | j == i + 1; i < 32; j < 32}
  (pf_mode: SORT_MODE_VALID(m) | mode: int(m), i: int(i), j: int(j))
  : (PAIR_IN_ORDER(m, i, j) | int) = let
  val (pf_fi | oi, l) = field_offset(pf_mode | mode, i)
  val (pf_fj | oj, _) = field_offset(pf_mode | mode, j)
  val (pf_lex | cmp) = lex_compare_loop(EQ_BASE() | oi, oj, l, 0)
in
  if lte_g1(cmp, 0) then
    (PAIR_VERIFIED(pf_fi, pf_fj, pf_lex) | 0)
  else let
    val () = swap_books(i, j)
    val (pf_fi2 | oi2, l2) = field_offset(pf_mode | mode, i)
    val (pf_fj2 | oj2, _) = field_offset(pf_mode | mode, j)
    val (pf_lex2 | cmp2) = lex_compare_loop(EQ_BASE() | oi2, oj2, l2, 0)
  in
    if lte_g1(cmp2, 0) then
      (PAIR_VERIFIED(pf_fi2, pf_fj2, pf_lex2) | 0)
    else
      ensure_ordered(pf_mode | mode, i, j)
  end
end

(* Insert element k into sorted prefix, extending proof.
 * Walks backwards from position k-1 down to 0, calling ensure_ordered
 * on each adjacent pair. Each call may swap, producing a PAIR_IN_ORDER
 * proof for that pair. *)
fn insertion_pass_inner {m:nat | m <= 1}{k:nat | k < 32}
  (pf_mode: SORT_MODE_VALID(m) | mode: int(m), k: int(k)): void = let
  fun loop {j:nat | j <= k}
    (pf_mode: SORT_MODE_VALID(m) | mode: int(m), j: int(j), k: int(k)): void =
    if eq_g1(j, 0) then ()
    else let
      val j1 = sub_g1(j, 1)
      val (_ | _) = ensure_ordered(pf_mode | mode, j1, j)
    in loop(pf_mode | mode, j1, k) end
in loop(pf_mode | mode, k, k) end

implement library_sort {m} (pf_mode | mode) = let
  val count = library_get_count()
in
  if eq_g1(count, 0) then (SORTED_NIL() | count)
  else if eq_g1(count, 1) then (SORTED_ONE() | count)
  else let
    (* Insertion sort: for each element k from 1 to count-1,
     * bubble it into sorted position *)
    fun outer {k:nat | k <= 32}{n2:nat | n2 <= 32}
      (pf_mode: SORT_MODE_VALID(m) | mode: int(m), k: int(k), n: int(n2)): void =
      if gte_g1(k, n) then ()
      else let
        val () = insertion_pass_inner(pf_mode | mode, k)
      in outer(pf_mode | mode, add_g1(k, 1), n) end
    val () = outer(pf_mode | mode, 1, count)

    (* Build sorted proof by verifying all adjacent pairs post-sort.
     * Returns (PROOF | int) to prevent erasure — reads buffer. *)
    fun build_proof {n:nat | n >= 2; n <= 32}
      (pf_mode: SORT_MODE_VALID(m) | mode: int(m), n: int(n))
      : (LIBRARY_SORTED(m, n) | int) = let
      fun verify_pairs {k:int | k >= 3; k <= n}
        (pf_sorted: LIBRARY_SORTED(m, k-1), pf_mode: SORT_MODE_VALID(m) |
         mode: int(m), k: int(k), n: int(n))
        : (LIBRARY_SORTED(m, n) | int) =
        if eq_g1(k, n) then let
          val (pf_pair | _) = ensure_ordered(pf_mode | mode, sub_g1(k, 2), sub_g1(k, 1))
        in (SORTED_CONS(pf_sorted, pf_pair) | 0) end
        else let
          val (pf_pair | _) = ensure_ordered(pf_mode | mode, sub_g1(k, 2), sub_g1(k, 1))
          prval pf_next = SORTED_CONS(pf_sorted, pf_pair)
        in verify_pairs(pf_next, pf_mode | mode, add_g1(k, 1), n) end
      val (pf_pair0 | _) = ensure_ordered(pf_mode | mode, 0, 1)
    in
      if eq_g1(n, 2) then (SORTED_CONS(SORTED_ONE(), pf_pair0) | 0)
      else let
        prval pf_base = SORTED_CONS(SORTED_ONE(), pf_pair0)
      in verify_pairs(pf_base, pf_mode | mode, 3, n) end
    end
    val (pf_sorted | _) = build_proof(pf_mode | mode, count)
  in (pf_sorted | count) end
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

(* ========== Serialization v2 ========== *)

implement library_serialize() = let
  val count = _app_lib_count()
  val count2 = _clamp(count, 32)
  (* v2 header: 0xFFFF, version=2, count, sort_mode *)
  val () = _fbuf_write_u16(0, 65535)
  val () = _fbuf_write_u16(2, 2)
  val () = _fbuf_write_u16(4, count2)
  val () = _fbuf_write_u16(6, _app_lib_sort_mode())
  fun loop(i: int, off: int): int =
    if gte_int_int(i, count2) then off
    else if gt_int_int(off + 590, 16384) then off (* overflow guard *)
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
      (* spine_count, chapter, page, archived *)
      val () = _fbuf_write_u16(off, _app_lib_books_get_i32(bi + SPINE_SLOT))
      val () = _fbuf_write_u16(off + 2, _app_lib_books_get_i32(bi + CHAPTER_SLOT))
      val () = _fbuf_write_u16(off + 4, _app_lib_books_get_i32(bi + PAGE_SLOT))
      val () = _fbuf_write_u16(off + 6, _app_lib_books_get_i32(bi + ARCHIVED_SLOT))
    in loop(i + 1, off + 8) end
  val total = loop(0, 8)
in _checked_nat(total) end

(* Deserialize v1 format — legacy, no archived flag *)
fn _deserialize_v1(len: int, count2: int): int = let
  fun loop(i: int, off: int): int =
    if gte_int_int(i, count2) then 1
    else if gt_int_int(off + 8, len) then 0
    else let
      val bi = i * REC_INTS
      val bb = i * REC_BYTES
      val bid_len = _clamp(_fbuf_read_u16(off), BOOKID_MAX)
      val off = off + 2
    in
      if gt_int_int(off + bid_len, len) then 0
      else let
        val () = _copy_fbuf_to_lib(off, bb + BOOKID_OFF, bid_len)
        val () = _app_lib_books_set_i32(bi + BOOKID_LEN_SLOT, bid_len)
        val off = off + bid_len
        val tlen = _clamp(_fbuf_read_u16(off), TITLE_MAX)
        val off = off + 2
      in
        if gt_int_int(off + tlen, len) then 0
        else let
          val () = _copy_fbuf_to_lib(off, bb + TITLE_OFF, tlen)
          val () = _app_lib_books_set_i32(bi + TITLE_LEN_SLOT, tlen)
          val off = off + tlen
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
              val () = _app_lib_books_set_i32(bi + ARCHIVED_SLOT, 0)
              val () = _app_lib_books_set_i32(bi + RESERVED_SLOT, 0)
            in loop(i + 1, off + 6) end
          end
        end
      end
    end
in loop(0, 2) end

(* Deserialize v2 format — includes archived flag *)
fn _deserialize_v2(len: int, count2: int, sort_mode: int): int = let
  fun loop(i: int, off: int): int =
    if gte_int_int(i, count2) then 1
    else if gt_int_int(off + 8, len) then 0
    else let
      val bi = i * REC_INTS
      val bb = i * REC_BYTES
      val bid_len = _clamp(_fbuf_read_u16(off), BOOKID_MAX)
      val off = off + 2
    in
      if gt_int_int(off + bid_len, len) then 0
      else let
        val () = _copy_fbuf_to_lib(off, bb + BOOKID_OFF, bid_len)
        val () = _app_lib_books_set_i32(bi + BOOKID_LEN_SLOT, bid_len)
        val off = off + bid_len
        val tlen = _clamp(_fbuf_read_u16(off), TITLE_MAX)
        val off = off + 2
      in
        if gt_int_int(off + tlen, len) then 0
        else let
          val () = _copy_fbuf_to_lib(off, bb + TITLE_OFF, tlen)
          val () = _app_lib_books_set_i32(bi + TITLE_LEN_SLOT, tlen)
          val off = off + tlen
          val alen = _clamp(_fbuf_read_u16(off), AUTHOR_MAX)
          val off = off + 2
        in
          if gt_int_int(off + alen, len) then 0
          else let
            val () = _copy_fbuf_to_lib(off, bb + AUTHOR_OFF, alen)
            val () = _app_lib_books_set_i32(bi + AUTHOR_LEN_SLOT, alen)
            val off = off + alen
          in
            if gt_int_int(off + 8, len) then 0
            else let
              val () = _app_lib_books_set_i32(bi + SPINE_SLOT, _fbuf_read_u16(off))
              val () = _app_lib_books_set_i32(bi + CHAPTER_SLOT, _fbuf_read_u16(off + 2))
              val () = _app_lib_books_set_i32(bi + PAGE_SLOT, _fbuf_read_u16(off + 4))
              val archived = _fbuf_read_u16(off + 6)
              val () = _app_lib_books_set_i32(bi + ARCHIVED_SLOT,
                if eq_int_int(archived, 1) then 1 else 0)
              val () = _app_lib_books_set_i32(bi + RESERVED_SLOT, 0)
            in loop(i + 1, off + 8) end
          end
        end
      end
    end
  val ok = loop(0, 8)
  val () = if eq_int_int(ok, 1) then
    _app_set_lib_sort_mode(
      if eq_int_int(sort_mode, 1) then 1 else 0)
in ok end

implement library_deserialize(len) =
  if lt_int_int(len, 2) then 0
  else let
    val marker = _fbuf_read_u16(0)
  in
    if eq_int_int(marker, 65535) then let
      (* v2 format *)
      val () =
        if lt_int_int(len, 8) then ()
      val version = _fbuf_read_u16(2)
    in
      if neq_int_int(version, 2) then 0
      else if lt_int_int(len, 8) then 0
      else let
        val count = _fbuf_read_u16(4)
        val count2 = _clamp(count, 32)
        val sort_mode = _fbuf_read_u16(6)
        val ok = _deserialize_v2(len, count2, sort_mode)
        val () = if eq_int_int(ok, 1) then _app_set_lib_count(count2)
      in
        if eq_int_int(ok, 1) then 1 else 0
      end
    end
    else let
      (* v1 format — marker IS the count *)
      val count2 = _clamp(marker, 32)
      val ok = _deserialize_v1(len, count2)
      val () = if eq_int_int(ok, 1) then let
        val () = _app_set_lib_count(count2)
        val () = _app_set_lib_sort_mode(0)
      in end
    in
      if eq_int_int(ok, 1) then 1 else 0
    end
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
