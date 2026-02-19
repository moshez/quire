(* library.dats - Book library implementation
 *
 * Pure ATS2 implementation. Book data stored as flat byte records
 * in app_state's library_books buffer via per-byte/i32 accessors.
 *
 * Book record layout: 155 i32 slots = 620 bytes per book.
 *   Byte 0-255:   title (256 bytes)
 *   i32 slot 64:  title_len
 *   Byte 260-515: author (256 bytes)
 *   i32 slot 129: author_len
 *   Byte 520-583: book_id (64 bytes)
 *   i32 slot 146: book_id_len
 *   i32 slot 147: spine_count
 *   i32 slot 148: current_chapter
 *   i32 slot 149: current_page
 *   i32 slot 150: shelf_state (0=active, 1=archived, 2=hidden)
 *   i32 slot 151: date_added (Unix seconds)
 *   i32 slot 152: last_opened (Unix seconds)
 *   i32 slot 153: file_size (bytes)
 *   i32 slot 154: reserved2 (always 0)
 *
 * Serialization format v3 (to fetch buffer):
 *   [u16: 0xFFFF] [u16: version=3] [u16: count] [u16: sort_mode]
 *   per book: [u16: bid_len] [bytes: bid]
 *   [u16: tlen] [bytes: title] [u16: alen] [bytes: author]
 *   [u16: spine_count] [u16: chapter] [u16: page] [u16: archived]
 *   [u32: date_added] [u32: last_opened] [u32: file_size]
 *
 * v2 format (legacy, read-only): same as v3 minus u32 metadata
 * v1 format (legacy, read-only): same as v2 minus archived
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./library.sats"

staload "./arith.sats"
staload "./buf.sats"
staload "./app_state.sats"
staload "./quire_ext.sats"
staload "./../vendor/ward/lib/memory.sats"

(* Forward declaration for JS import — suppresses C99 warning *)
%{
extern int quire_time_now(void);
%}
staload "./../vendor/ward/lib/promise.sats"
staload "./../vendor/ward/lib/idb.sats"
staload "./../vendor/ward/lib/window.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/promise.dats"
staload _ = "./../vendor/ward/lib/idb.dats"

(* ========== Record layout constants ========== *)

#define REC_BYTES 620
#define REC_INTS 155
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
#define SHELF_STATE_SLOT 150
#define DATE_ADDED_SLOT 151
#define LAST_OPENED_SLOT 152
#define FILE_SIZE_SLOT 153
#define RESERVED2_SLOT 154

(* ========== Castfns for dependent return types ========== *)
extern castfn _clamp32(x: int): [n:nat | n <= 32] int n
(* Castfns for library_add_book return — each ties proof to specific index.
 * Proof erased at runtime; cast is identity on int. *)
extern castfn _mk_added(x: int)
  : [i:nat | i < 32] (ADD_BOOK_RESULT(i) | int(i))
extern castfn _mk_lib_full(x: int): (ADD_BOOK_RESULT(~1) | int(~1))
extern castfn _find_idx(x: int): [i:int | i >= ~1] int i
extern castfn _clamp_shelf_state(x: int): [s:nat | s <= 2] int s

(* ========== Helpers ========== *)

(* Copy book record via per-byte lib_books accessors *)
fn _copy_book(dst: int, src_idx: int): void = let
  val dst_off = dst * REC_BYTES
  val src_off = src_idx * REC_BYTES
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, doff: int, soff: int): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, REC_BYTES) then let
      val b = _app_lib_books_get_u8(soff + i)
      val () = _app_lib_books_set_u8(doff + i, b)
    in loop(sub_g1(rem, 1), i + 1, doff, soff) end
in loop(_checked_nat(REC_BYTES), 0, dst_off, src_off) end

(* Swap two book records using sbuf as temp storage *)
fn swap_books(a: int, b: int): void = let
  val a_off = a * REC_BYTES
  val b_off = b * REC_BYTES
  (* Copy a → sbuf *)
  fun copy_to_sbuf {k:nat} .<k>.
    (rem: int(k), i: int, src: int): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, REC_BYTES) then let
      val v = _app_lib_books_get_u8(src + i)
      val () = _app_sbuf_set_u8(i, v)
    in copy_to_sbuf(sub_g1(rem, 1), i + 1, src) end
  (* Copy b → a *)
  fun copy_b_to_a {k:nat} .<k>.
    (rem: int(k), i: int, dst: int, src: int): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, REC_BYTES) then let
      val v = _app_lib_books_get_u8(src + i)
      val () = _app_lib_books_set_u8(dst + i, v)
    in copy_b_to_a(sub_g1(rem, 1), i + 1, dst, src) end
  (* Copy sbuf → b *)
  fun copy_sbuf_to_b {k:nat} .<k>.
    (rem: int(k), i: int, dst: int): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, REC_BYTES) then let
      val v = _app_sbuf_get_u8(i)
      val () = _app_lib_books_set_u8(dst + i, v)
    in copy_sbuf_to_b(sub_g1(rem, 1), i + 1, dst) end
  val () = copy_to_sbuf(_checked_nat(REC_BYTES), 0, a_off)
  val () = copy_b_to_a(_checked_nat(REC_BYTES), 0, a_off, b_off)
  val () = copy_sbuf_to_b(_checked_nat(REC_BYTES), 0, b_off)
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
    fun find_dup {k:nat} .<k>.
      (rem: int(k), i: int, cnt: int, blen: int): int =
      if lte_g1(rem, 0) then 0 - 1
      else if gte_int_int(i, cnt) then 0 - 1
      else let
        val stored_len = _app_lib_books_get_i32(i * REC_INTS + BOOKID_LEN_SLOT)
      in
        if neq_int_int(stored_len, blen) then find_dup(sub_g1(rem, 1), i + 1, cnt, blen)
        else if gt_int_int(_app_lib_books_match_bid(i * REC_BYTES + BOOKID_OFF, blen), 0)
        then i
        else find_dup(sub_g1(rem, 1), i + 1, cnt, blen)
      end
    val dup = find_dup(_checked_nat(count), 0, count, bid_len)
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
      val () = _app_lib_books_set_i32(base_ints + SHELF_STATE_SLOT, 0)
      val now = quire_time_now()
      val () = _app_lib_books_set_i32(base_ints + DATE_ADDED_SLOT, now)
      val () = _app_lib_books_set_i32(base_ints + LAST_OPENED_SLOT, now)
      val () = _app_lib_books_set_i32(base_ints + FILE_SIZE_SLOT, _app_epub_file_size())
      val () = _app_lib_books_set_i32(base_ints + RESERVED2_SLOT, 0)
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

implement library_get_shelf_state(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else let
    val v = _app_lib_books_get_i32(index * REC_INTS + SHELF_STATE_SLOT)
  in
    if eq_int_int(v, 1) then 1
    else if eq_int_int(v, 2) then 2
    else 0
  end

implement library_set_shelf_state {s} (pf | index, v) = let
  prval _ = pf
in
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, _app_lib_count()) then ()
  else _app_lib_books_set_i32(index * REC_INTS + SHELF_STATE_SLOT, v)
end

implement library_get_date_added(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _app_lib_books_get_i32(index * REC_INTS + DATE_ADDED_SLOT)

implement library_get_last_opened(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _app_lib_books_get_i32(index * REC_INTS + LAST_OPENED_SLOT)

implement library_get_file_size(index) =
  if lt_int_int(index, 0) then 0
  else if gte_int_int(index, _app_lib_count()) then 0
  else _app_lib_books_get_i32(index * REC_INTS + FILE_SIZE_SLOT)

implement library_set_last_opened {t} (pf | index, ts) = let
  prval _ = pf
in
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, _app_lib_count()) then ()
  else _app_lib_books_set_i32(index * REC_INTS + LAST_OPENED_SLOT, ts)
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
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, cnt: int, blen: int): int =
    if lte_g1(rem, 0) then 0 - 1
    else if gte_int_int(i, cnt) then 0 - 1
    else let
      val stored_len = _app_lib_books_get_i32(i * REC_INTS + BOOKID_LEN_SLOT)
    in
      if neq_int_int(stored_len, blen) then loop(sub_g1(rem, 1), i + 1, cnt, blen)
      else if gt_int_int(_app_lib_books_match_bid(i * REC_BYTES + BOOKID_OFF, blen), 0)
      then i
      else loop(sub_g1(rem, 1), i + 1, cnt, blen)
    end
in _find_idx(loop(_checked_nat(count), 0, count, bid_len)) end

implement library_remove_book(index) = let
  val count = _app_lib_count()
in
  if lt_int_int(index, 0) then ()
  else if gte_int_int(index, count) then ()
  else let
    fun shift {k:nat} .<k>.
      (rem: int(k), i: int, cnt: int): void =
      if lte_g1(rem, 0) then ()
      else if lt_int_int(i, cnt - 1) then let
        val () = _copy_book(i, i + 1)
      in shift(sub_g1(rem, 1), i + 1, cnt) end
    val () = shift(_checked_nat(count), index, count)
    val () = _app_set_lib_count(count - 1)
  in end
end

(* ========== View filter ========== *)

implement should_render_book {vm}{s} (pf_vm, pf_ss | vm, ss) =
  if eq_g1(vm, 0) then
    if eq_g1(ss, 0) then (RENDER_ACTIVE() | 1)
    else if eq_g1(ss, 1) then (SKIP_ARCHIVED_IN_ACTIVE() | 0)
    else (SKIP_HIDDEN_IN_ACTIVE() | 0)
  else if eq_g1(vm, 1) then
    if eq_g1(ss, 1) then (RENDER_ARCHIVED() | 1)
    else if eq_g1(ss, 0) then (SKIP_ACTIVE_IN_ARCHIVED() | 0)
    else (SKIP_HIDDEN_IN_ARCHIVED() | 0)
  else
    if eq_g1(ss, 2) then (RENDER_HIDDEN() | 1)
    else if eq_g1(ss, 0) then (SKIP_ACTIVE_IN_HIDDEN() | 0)
    else (SKIP_ARCHIVED_IN_HIDDEN() | 0)

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
  .<l - k>.
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
      val oi = add_g1(mul_g1(book, 620), 0)
    in (FIELD_TITLE() | oi, 256) end
  else let
      val oi = add_g1(mul_g1(book, 620), 260)
    in (FIELD_AUTHOR() | oi, 256) end

(* Compute i32 slot for a book's timestamp field (modes 2-3) *)
fn int_field_slot {m:nat | m >= 2; m <= 3}{i:nat | i < 32}
  (mode: int(m), book: int(i))
  : [sl:nat] (FIELD_INT_SPEC(m, i, sl) | int(sl)) =
  if eq_g1(mode, 2) then let
    val sl = add_g1(mul_g1(book, 155), 152)
  in (FIELD_LAST_OPENED() | sl) end
  else let
    val sl = add_g1(mul_g1(book, 155), 151)
  in (FIELD_DATE_ADDED() | sl) end

(* Compare two i32 slots — reverse chronological (higher value = first).
 * Returns (INT_CMP | int): 0 if val_i >= val_j (in order), 1 if val_i < val_j (out of order). *)
fn int_compare {mi,mj:int}{ii,ij:int}{si,sj:int}
  (pf_fi: FIELD_INT_SPEC(mi, ii, si), pf_fj: FIELD_INT_SPEC(mj, ij, sj) |
   slot_i: int(si), slot_j: int(sj))
  : [r:int] (INT_CMP(si, sj, r) | int(r)) = let
  prval _ = pf_fi
  prval _ = pf_fj
  val vi = _app_lib_books_get_i32(slot_i)
  val vj = _app_lib_books_get_i32(slot_j)
in
  if gte_int_int(vi, vj) then (INT_GTE() | 0)
  else (INT_LT_VAL() | 1)
end

(* Compare, conditionally swap, verify post-state (integer path for modes 2-3).
 * Same swap-and-verify pattern as lex path. *)
fun ensure_ordered_int {m:nat | m >= 2; m <= 3}{i,j:nat | j == i + 1; i < 32; j < 32}
  (mode: int(m), i: int(i), j: int(j))
  : (PAIR_IN_ORDER(m, i, j) | int) = let
  val (pf_fi | si) = int_field_slot(mode, i)
  val (pf_fj | sj) = int_field_slot(mode, j)
  val (pf_cmp | cmp) = int_compare(pf_fi, pf_fj | si, sj)
in
  if lte_g1(cmp, 0) then
    (PAIR_INT_VERIFIED(pf_fi, pf_fj, pf_cmp) | 0)
  else let
    val () = swap_books(i, j)
    val (pf_fi2 | si2) = int_field_slot(mode, i)
    val (pf_fj2 | sj2) = int_field_slot(mode, j)
    val (pf_cmp2 | cmp2) = int_compare(pf_fi2, pf_fj2 | si2, sj2)
  in
    if lte_g1(cmp2, 0) then
      (PAIR_INT_VERIFIED(pf_fi2, pf_fj2, pf_cmp2) | 0)
    else
      ensure_ordered_int(mode, i, j)
  end
end

(* Compare, conditionally swap, verify post-state (lex path for modes 0-1).
 * Returns (PROOF | int) — dummy int prevents erasure of effectful function.
 *
 * TERMINATION NOTE: This function recurses only when swap_books doesn't
 * reverse the lex comparison — which never happens in practice because
 * swap literally exchanges the compared bytes. Proving this requires
 * modeling buffer contents pre/post swap, which is beyond ATS2's integer
 * constraint solver. The function terminates after at most one swap. *)
fun ensure_ordered_lex {m:nat | m <= 1}{i,j:nat | j == i + 1; i < 32; j < 32}
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
      ensure_ordered_lex(pf_mode | mode, i, j)
  end
end

(* Dispatch: modes 0-1 use lex comparison, modes 2-3 use integer comparison *)
fn ensure_ordered {m:nat | m <= 3}{i,j:nat | j == i + 1; i < 32; j < 32}
  (pf_mode: SORT_MODE_VALID(m) | mode: int(m), i: int(i), j: int(j))
  : (PAIR_IN_ORDER(m, i, j) | int) =
  if lte_g1(mode, 1) then
    ensure_ordered_lex(pf_mode | mode, i, j)
  else
    ensure_ordered_int(mode, i, j)

(* Insert element k into sorted prefix, extending proof.
 * Walks backwards from position k-1 down to 0, calling ensure_ordered
 * on each adjacent pair. Each call may swap, producing a PAIR_IN_ORDER
 * proof for that pair. *)
fn insertion_pass_inner {m:nat | m <= 3}{k:nat | k < 32}
  (pf_mode: SORT_MODE_VALID(m) | mode: int(m), k: int(k)): void = let
  fun loop {j:nat | j <= k} .<j>.
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
    fun outer {n2:nat | n2 <= 32}{k:nat | k <= n2} .<n2 - k>.
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
      fun verify_pairs {k:int | k >= 3; k <= n} .<n - k>.
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

(* Write u32 little-endian to fetch buffer *)
fn _fbuf_write_u32(off: int, v: int): void = let
  val () = _app_fbuf_set_u8(off, band_int_int(v, 255))
  val () = _app_fbuf_set_u8(off + 1, band_int_int(bsr_int_int(v, 8), 255))
  val () = _app_fbuf_set_u8(off + 2, band_int_int(bsr_int_int(v, 16), 255))
  val () = _app_fbuf_set_u8(off + 3, band_int_int(bsr_int_int(v, 24), 255))
in end

(* Read u32 little-endian from fetch buffer *)
fn _fbuf_read_u32(off: int): int = let
  val b0 = _app_fbuf_get_u8(off)
  val b1 = _app_fbuf_get_u8(off + 1)
  val b2 = _app_fbuf_get_u8(off + 2)
  val b3 = _app_fbuf_get_u8(off + 3)
in bor_int_int(bor_int_int(b0, bsl_int_int(b1, 8)),
               bor_int_int(bsl_int_int(b2, 16), bsl_int_int(b3, 24))) end

(* Copy bytes from lib_books to fetch buffer *)
fn _copy_lib_to_fbuf(src_base: int, dst_off: int, n: int): void = let
  fun loop {k:nat} .<k>.
    (rem: int(k), j: int): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(j, n) then let
      val b = _app_lib_books_get_u8(src_base + j)
      val () = _app_fbuf_set_u8(dst_off + j, b)
    in loop(sub_g1(rem, 1), j + 1) end
in loop(_checked_nat(n), 0) end

(* Copy bytes from fetch buffer to lib_books *)
fn _copy_fbuf_to_lib(src_off: int, dst_base: int, n: int): void = let
  fun loop {k:nat} .<k>.
    (rem: int(k), j: int): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(j, n) then let
      val b = _app_fbuf_get_u8(src_off + j)
      val () = _app_lib_books_set_u8(dst_base + j, b)
    in loop(sub_g1(rem, 1), j + 1) end
in loop(_checked_nat(n), 0) end

(* Clamp value to [0, max] *)
fn _clamp(v: int, mx: int): int =
  if lt_int_int(v, 0) then 0
  else if gt_int_int(v, mx) then mx
  else v

(* ========== Serialization format proofs ========== *)

(* Single source of truth: version → fixed metadata bytes per book *)
implement ser_fixed_bytes {v} (version) =
  if eq_g1(version, 1) then (SER_FMT_V1() | 6)
  else if eq_g1(version, 2) then (SER_FMT_V2() | 8)
  else (SER_FMT_V3() | 20)

(* Single source of truth: field index → byte_off, max_len, len_slot *)
implement ser_var_field_spec {f} (field) =
  if eq_g1(field, 0) then (SFIELD_BID() | 520, 64, 146)
  else if eq_g1(field, 1) then (SFIELD_TITLE() | 0, 256, 64)
  else (SFIELD_AUTHOR() | 260, 256, 129)

(* Serialize one variable field: write u16 length + bytes to fbuf.
 * Returns new offset. *)
fn _ser_var_field {f:nat | f <= 2}
  (field: int(f), book_base_ints: int, book_base_bytes: int, off: int): int = let
  val (pf_field | byte_off, max_len, len_slot) = ser_var_field_spec(field)
  prval _ = pf_field
  val flen = _clamp(_app_lib_books_get_i32(book_base_ints + len_slot), max_len)
  val () = _fbuf_write_u16(off, flen)
  val () = _copy_lib_to_fbuf(book_base_bytes + byte_off, off + 2, flen)
in off + 2 + flen end

(* Deserialize one variable field: read u16 length + bytes from fbuf.
 * Returns new offset, or -1 on bounds error. *)
fn _deser_var_field {f:nat | f <= 2}
  (field: int(f), book_base_ints: int, book_base_bytes: int,
   off: int, len: int): int = let
  val (pf_field | byte_off, max_len, len_slot) = ser_var_field_spec(field)
  prval _ = pf_field
  val flen = _clamp(_fbuf_read_u16(off), max_len)
  val off2 = off + 2
in
  if gt_int_int(off2 + flen, len) then 0 - 1
  else let
    val () = _copy_fbuf_to_lib(off2, book_base_bytes + byte_off, flen)
    val () = _app_lib_books_set_i32(book_base_ints + len_slot, flen)
  in off2 + flen end
end

(* ========== Serialization v3 ========== *)

implement library_serialize() = let
  val count = _app_lib_count()
  val count2 = _clamp(count, 32)
  (* v3 header: 0xFFFF, version=3, count, sort_mode *)
  val () = _fbuf_write_u16(0, 65535)
  val () = _fbuf_write_u16(2, 3)
  val () = _fbuf_write_u16(4, count2)
  val () = _fbuf_write_u16(6, _app_lib_sort_mode())
  val (pf_fmt | fixed_bytes) = ser_fixed_bytes(3)
  prval _ = pf_fmt
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, off: int, fb: int): int =
    if lte_g1(rem, 0) then off
    else if gte_int_int(i, count2) then off
    else if gt_int_int(off + 602, 16384) then off (* overflow guard *)
    else let
      val bi = i * REC_INTS
      val bb = i * REC_BYTES
      (* Variable fields via shared helpers *)
      val off = _ser_var_field(0, bi, bb, off)  (* book_id *)
      val off = _ser_var_field(1, bi, bb, off)  (* title *)
      val off = _ser_var_field(2, bi, bb, off)  (* author *)
      (* Fixed metadata: u16 spine, chapter, page, archived + u32 timestamps *)
      val () = _fbuf_write_u16(off, _app_lib_books_get_i32(bi + SPINE_SLOT))
      val () = _fbuf_write_u16(off + 2, _app_lib_books_get_i32(bi + CHAPTER_SLOT))
      val () = _fbuf_write_u16(off + 4, _app_lib_books_get_i32(bi + PAGE_SLOT))
      val () = _fbuf_write_u16(off + 6, _app_lib_books_get_i32(bi + SHELF_STATE_SLOT))
      val () = _fbuf_write_u32(off + 8, _app_lib_books_get_i32(bi + DATE_ADDED_SLOT))
      val () = _fbuf_write_u32(off + 12, _app_lib_books_get_i32(bi + LAST_OPENED_SLOT))
      val () = _fbuf_write_u32(off + 16, _app_lib_books_get_i32(bi + FILE_SIZE_SLOT))
    in loop(sub_g1(rem, 1), i + 1, off + fb, fb) end
  val total = loop(_checked_nat(count2), 0, 8, fixed_bytes)
in _checked_nat(total) end

(* Deserialize v1 format — legacy, no archived flag *)
fn _deserialize_v1(len: int, count2: int): int = let
  val (pf_fmt | fixed_bytes) = ser_fixed_bytes(1)
  prval _ = pf_fmt
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, off: int, fb: int): int =
    if gte_int_int(i, count2) then 1
    else if lte_g1(rem, 0) then 0
    else if gt_int_int(off + 8, len) then 0
    else let
      val bi = i * REC_INTS
      val bb = i * REC_BYTES
      (* Variable fields via shared helpers *)
      val off2 = _deser_var_field(0, bi, bb, off, len)  (* book_id *)
    in
      if lt_int_int(off2, 0) then 0
      else let val off2 = _deser_var_field(1, bi, bb, off2, len) in  (* title *)
        if lt_int_int(off2, 0) then 0
        else let val off2 = _deser_var_field(2, bi, bb, off2, len) in  (* author *)
          if lt_int_int(off2, 0) then 0
          else if gt_int_int(off2 + fb, len) then 0
          else let
            val () = _app_lib_books_set_i32(bi + SPINE_SLOT, _fbuf_read_u16(off2))
            val () = _app_lib_books_set_i32(bi + CHAPTER_SLOT, _fbuf_read_u16(off2 + 2))
            val () = _app_lib_books_set_i32(bi + PAGE_SLOT, _fbuf_read_u16(off2 + 4))
            val () = _app_lib_books_set_i32(bi + SHELF_STATE_SLOT, 0)
            val () = _app_lib_books_set_i32(bi + DATE_ADDED_SLOT, 0)
            val () = _app_lib_books_set_i32(bi + LAST_OPENED_SLOT, 0)
            val () = _app_lib_books_set_i32(bi + FILE_SIZE_SLOT, 0)
            val () = _app_lib_books_set_i32(bi + RESERVED2_SLOT, 0)
          in loop(sub_g1(rem, 1), i + 1, off2 + fb, fb) end
        end
      end
    end
in loop(_checked_nat(count2), 0, 2, fixed_bytes) end

(* Deserialize v2 format — includes archived flag, no timestamps *)
fn _deserialize_v2(len: int, count2: int, sort_mode: int): int = let
  val (pf_fmt | fixed_bytes) = ser_fixed_bytes(2)
  prval _ = pf_fmt
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, off: int, fb: int): int =
    if gte_int_int(i, count2) then 1
    else if lte_g1(rem, 0) then 0
    else if gt_int_int(off + 8, len) then 0
    else let
      val bi = i * REC_INTS
      val bb = i * REC_BYTES
      (* Variable fields via shared helpers *)
      val off2 = _deser_var_field(0, bi, bb, off, len)  (* book_id *)
    in
      if lt_int_int(off2, 0) then 0
      else let val off2 = _deser_var_field(1, bi, bb, off2, len) in  (* title *)
        if lt_int_int(off2, 0) then 0
        else let val off2 = _deser_var_field(2, bi, bb, off2, len) in  (* author *)
          if lt_int_int(off2, 0) then 0
          else if gt_int_int(off2 + fb, len) then 0
          else let
            val () = _app_lib_books_set_i32(bi + SPINE_SLOT, _fbuf_read_u16(off2))
            val () = _app_lib_books_set_i32(bi + CHAPTER_SLOT, _fbuf_read_u16(off2 + 2))
            val () = _app_lib_books_set_i32(bi + PAGE_SLOT, _fbuf_read_u16(off2 + 4))
            val shelf_st = _fbuf_read_u16(off2 + 6)
            val () = _app_lib_books_set_i32(bi + SHELF_STATE_SLOT,
              if eq_int_int(shelf_st, 1) then 1 else 0)
            val () = _app_lib_books_set_i32(bi + DATE_ADDED_SLOT, 0)
            val () = _app_lib_books_set_i32(bi + LAST_OPENED_SLOT, 0)
            val () = _app_lib_books_set_i32(bi + FILE_SIZE_SLOT, 0)
            val () = _app_lib_books_set_i32(bi + RESERVED2_SLOT, 0)
          in loop(sub_g1(rem, 1), i + 1, off2 + fb, fb) end
        end
      end
    end
  val ok = loop(_checked_nat(count2), 0, 8, fixed_bytes)
  val () = if eq_int_int(ok, 1) then
    _app_set_lib_sort_mode(
      if eq_int_int(sort_mode, 1) then 1 else 0)
in ok end

(* Deserialize v3 format — includes timestamps and file_size *)
fn _deserialize_v3(len: int, count2: int, sort_mode: int): int = let
  val (pf_fmt | fixed_bytes) = ser_fixed_bytes(3)
  prval _ = pf_fmt
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, off: int, fb: int): int =
    if gte_int_int(i, count2) then 1
    else if lte_g1(rem, 0) then 0
    else if gt_int_int(off + 22, len) then 0
    else let
      val bi = i * REC_INTS
      val bb = i * REC_BYTES
      (* Variable fields via shared helpers *)
      val off2 = _deser_var_field(0, bi, bb, off, len)  (* book_id *)
    in
      if lt_int_int(off2, 0) then 0
      else let val off2 = _deser_var_field(1, bi, bb, off2, len) in  (* title *)
        if lt_int_int(off2, 0) then 0
        else let val off2 = _deser_var_field(2, bi, bb, off2, len) in  (* author *)
          if lt_int_int(off2, 0) then 0
          else if gt_int_int(off2 + fb, len) then 0
          else let
            val () = _app_lib_books_set_i32(bi + SPINE_SLOT, _fbuf_read_u16(off2))
            val () = _app_lib_books_set_i32(bi + CHAPTER_SLOT, _fbuf_read_u16(off2 + 2))
            val () = _app_lib_books_set_i32(bi + PAGE_SLOT, _fbuf_read_u16(off2 + 4))
            val shelf_st = _fbuf_read_u16(off2 + 6)
            val () = _app_lib_books_set_i32(bi + SHELF_STATE_SLOT,
              if eq_int_int(shelf_st, 1) then 1
              else if eq_int_int(shelf_st, 2) then 2
              else 0)
            val () = _app_lib_books_set_i32(bi + DATE_ADDED_SLOT, _fbuf_read_u32(off2 + 8))
            val () = _app_lib_books_set_i32(bi + LAST_OPENED_SLOT, _fbuf_read_u32(off2 + 12))
            val () = _app_lib_books_set_i32(bi + FILE_SIZE_SLOT, _fbuf_read_u32(off2 + 16))
            val () = _app_lib_books_set_i32(bi + RESERVED2_SLOT, 0)
          in loop(sub_g1(rem, 1), i + 1, off2 + fb, fb) end
        end
      end
    end
  val ok = loop(_checked_nat(count2), 0, 8, fixed_bytes)
  val () = if eq_int_int(ok, 1) then
    _app_set_lib_sort_mode(
      if eq_int_int(sort_mode, 1) then 1
      else if eq_int_int(sort_mode, 2) then 2
      else if eq_int_int(sort_mode, 3) then 3
      else 0)
in ok end

implement library_deserialize(len) =
  if lt_int_int(len, 2) then 0
  else let
    val marker = _fbuf_read_u16(0)
  in
    if eq_int_int(marker, 65535) then let
      (* v2 or v3 format *)
      val () =
        if lt_int_int(len, 8) then ()
      val version = _fbuf_read_u16(2)
    in
      if lt_int_int(len, 8) then 0
      else let
        val count = _fbuf_read_u16(4)
        val count2 = _clamp(count, 32)
        val sort_mode = _fbuf_read_u16(6)
        val ok =
          if eq_int_int(version, 3) then _deserialize_v3(len, count2, sort_mode)
          else if eq_int_int(version, 2) then _deserialize_v2(len, count2, sort_mode)
          else 0
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
    fun copy {l:agz}{n:pos}{k:nat} .<k>.
      (rem: int(k), arr: !ward_arr(byte, l, n), i: int, cnt: int, sz: int n): void =
      if lte_g1(rem, 0) then ()
      else if lt_int_int(i, cnt) then let
        val b = _app_fbuf_get_u8(i)
        val () = ward_arr_set<byte>(arr, _ward_idx(i, sz),
          ward_int2byte(_checked_byte(band_int_int(b, 255))))
      in copy(sub_g1(rem, 1), arr, i + 1, cnt, sz) end
    val () = copy(_checked_nat(slen), arr, 0, slen, slen1)
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
        fun copy {l:agz}{n:pos}{k:nat} .<k>.
          (rem: int(k), arr: !ward_arr(byte, l, n), i: int, cnt: int, sz: int n): void =
          if lte_g1(rem, 0) then ()
          else if lt_int_int(i, cnt) then let
            val b = byte2int0(ward_arr_get<byte>(arr, _ward_idx(i, sz)))
            val () = _app_fbuf_set_u8(i, b)
          in copy(sub_g1(rem, 1), arr, i + 1, cnt, sz) end
        val () = copy(_checked_nat(data_len), arr, 0, data_len, dlen)
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
