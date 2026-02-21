(* epub.dats - EPUB import pipeline implementation
 *
 * Pure ATS2 — all buffer access via ward_arr or app_state accessors.
 * No $UNSAFE, no raw ptr, no C blocks.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./../vendor/ward/lib/memory.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload "./epub.sats"
staload "./app_state.sats"
staload "./library.sats"

staload "./arith.sats"
staload "./buf.sats"
staload "./zip.sats"
staload "./../vendor/ward/lib/promise.sats"
staload _ = "./../vendor/ward/lib/promise.dats"
staload "./../vendor/ward/lib/idb.sats"
staload "./../vendor/ward/lib/file.sats"
staload "./../vendor/ward/lib/decompress.sats"
staload "./../vendor/ward/lib/xml.sats"
staload _ = "./../vendor/ward/lib/xml.dats"

(* ========== Ward arr byte helpers ========== *)

(* Read byte from ward_arr *)
fn _ab {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), off: int, cap: int n): int =
  byte2int0(ward_arr_get<byte>(a, _ward_idx(off, cap)))

(* Write byte to ward_arr *)
fn _wb {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), off: int, v: int, cap: int n): void =
  ward_arr_set<byte>(a, _ward_idx(off, cap), ward_int2byte(_checked_byte(v)))

(* ========== Byte search helper ========== *)

(* Find needle bytes in haystack starting at position start.
 * Returns index of first match, or -1 if not found.
 * hay_len is the search limit (<= hcap); hcap/ncap are physical capacities. *)
fn _find_bytes {lh:agz}{nh:pos}{ln:agz}{nn:pos}
  (hay: !ward_arr(byte, lh, nh), hay_len: int, hcap: int nh,
   needle: !ward_arr(byte, ln, nn), needle_len: int, ncap: int nn,
   start: int): int = let
  val limit = hay_len - needle_len
  fun outer {lh:agz}{nh:pos}{ln:agz}{nn:pos}
    (hay: !ward_arr(byte, lh, nh), ndl: !ward_arr(byte, ln, nn),
     i: int, hc: int nh, nc: int nn, lim: int, nlen: int): int =
    if gt_int_int(i, lim) then 0 - 1
    else let
      fun inner {lh:agz}{nh:pos}{ln:agz}{nn:pos}
        (hay: !ward_arr(byte, lh, nh), ndl: !ward_arr(byte, ln, nn),
         j: int, hc: int nh, nc: int nn, base: int, nlen: int): bool =
        if gte_int_int(j, nlen) then true
        else if neq_int_int(_ab(hay, base + j, hc), _ab(ndl, j, nc)) then false
        else inner(hay, ndl, j + 1, hc, nc, base, nlen)
    in
      if inner(hay, ndl, 0, hc, nc, i, nlen) then i
      else outer(hay, ndl, i + 1, hc, nc, lim, nlen)
    end
in outer(hay, needle, start, hcap, ncap, limit, needle_len) end

(* Scan forward to find closing quote *)
fn _find_quote {l:agz}{n:pos}
  (data: !ward_arr(byte, l, n), len: int, cap: int n, start: int): int = let
  fun loop {l:agz}{n:pos}
    (d: !ward_arr(byte, l, n), i: int, len: int, c: int n): int =
    if gte_int_int(i, len) then len
    else if eq_int_int(_ab(d, i, c), 34) then i (* 34 = '"' *)
    else loop(d, i + 1, len, c)
in loop(data, start, len, cap) end

(* Proof that a '>' was found in unquoted XML context.
 * GT_OUTSIDE_QUOTES can ONLY be constructed in loop_unquoted,
 * proving the returned position is not inside a quoted attribute value.
 *
 * BUG PREVENTED: _find_gt matching '>' inside id="author_0" on
 * <dc:creator>, causing metadata to include attribute text. *)
dataprop UNQUOTED_GT() = | GT_OUTSIDE_QUOTES()

(* Scan forward to find closing '>' outside quoted attributes.
 * Two mutually recursive functions as structural proof:
 * - loop_unquoted: the ONLY function that can match '>' (byte 62)
 * - loop_quoted: skips ALL bytes (including '>') until closing quote
 *
 * This structure makes it impossible to return a '>' inside quotes:
 * loop_quoted has no code path that matches byte 62.
 * Handles both double-quote (34) and single-quote (39) delimiters. *)
fn _find_gt {l:agz}{n:pos}
  (data: !ward_arr(byte, l, n), len: int, cap: int n, start: int)
  : (UNQUOTED_GT() | int) = let
  fun loop_unquoted {l:agz}{n:pos}
    (d: !ward_arr(byte, l, n), i: int, len: int, c: int n)
    : (UNQUOTED_GT() | int) =
    if gte_int_int(i, len) then (GT_OUTSIDE_QUOTES() | len)
    else let val b = _ab(d, i, c) in
      if eq_int_int(b, 34) then loop_quoted(d, i + 1, len, c, 34)
      else if eq_int_int(b, 39) then loop_quoted(d, i + 1, len, c, 39)
      else if eq_int_int(b, 62) then (GT_OUTSIDE_QUOTES() | i)
      else loop_unquoted(d, i + 1, len, c)
    end
  and loop_quoted {l:agz}{n:pos}
    (d: !ward_arr(byte, l, n), i: int, len: int, c: int n, q: int)
    : (UNQUOTED_GT() | int) =
    if gte_int_int(i, len) then (GT_OUTSIDE_QUOTES() | len)
    else if eq_int_int(_ab(d, i, c), q) then loop_unquoted(d, i + 1, len, c)
    else loop_quoted(d, i + 1, len, c, q)
in loop_unquoted(data, start, len, cap) end

(* Compare two byte regions within the same ward_arr *)
fn _arr_bytes_equal {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), a_off: int, b_off: int, count: int, cap: int n): bool = let
  fun loop {l:agz}{n:pos}
    (a: !ward_arr(byte, l, n), i: int, ao: int, bo: int, cnt: int, c: int n): bool =
    if gte_int_int(i, cnt) then true
    else if neq_int_int(_ab(a, ao + i, c), _ab(a, bo + i, c)) then false
    else loop(a, i + 1, ao, bo, cnt, c)
in loop(a, 0, a_off, b_off, count, cap) end

(* Copy bytes from ward_arr to an app_state buffer via setter function.
 * setter_fn is inlined at each call site via specific helpers below. *)

fn _copy_arr_to_opf {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), base: int, len: int, cap: int n): void = let
  fun loop {l:agz}{n:pos}
    (a: !ward_arr(byte, l, n), i: int, base: int, len: int, c: int n): void =
    if gte_int_int(i, len) then ()
    else let
      val () = _app_epub_opf_path_set_u8(i, _ab(a, base + i, c))
    in loop(a, i + 1, base, len, c) end
in loop(a, 0, base, len, cap) end

fn _copy_arr_to_title {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), base: int, len: int, cap: int n): void = let
  fun loop {l:agz}{n:pos}
    (a: !ward_arr(byte, l, n), i: int, base: int, len: int, c: int n): void =
    if gte_int_int(i, len) then ()
    else let
      val () = _app_epub_title_set_u8(i, _ab(a, base + i, c))
    in loop(a, i + 1, base, len, c) end
in loop(a, 0, base, len, cap) end

fn _copy_arr_to_author {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), base: int, len: int, cap: int n): void = let
  fun loop {l:agz}{n:pos}
    (a: !ward_arr(byte, l, n), i: int, base: int, len: int, c: int n): void =
    if gte_int_int(i, len) then ()
    else let
      val () = _app_epub_author_set_u8(i, _ab(a, base + i, c))
    in loop(a, i + 1, base, len, c) end
in loop(a, 0, base, len, cap) end

fn _copy_arr_to_bookid {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), base: int, len: int, cap: int n): void = let
  fun loop {l:agz}{n:pos}
    (a: !ward_arr(byte, l, n), i: int, base: int, len: int, c: int n): void =
    if gte_int_int(i, len) then ()
    else let
      val () = _app_epub_book_id_set_u8(i, _ab(a, base + i, c))
    in loop(a, i + 1, base, len, c) end
in loop(a, 0, base, len, cap) end

fn _copy_arr_to_cover_href {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), base: int, len: int, cap: int n): void = let
  fun loop {l:agz}{n:pos}
    (a: !ward_arr(byte, l, n), i: int, base: int, len: int, c: int n): void =
    if gte_int_int(i, len) then ()
    else let
      val () = _app_epub_cover_href_set_u8(i, _ab(a, base + i, c))
    in loop(a, i + 1, base, len, c) end
in loop(a, 0, base, len, cap) end

fn _copy_arr_to_spine_buf {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), src_base: int, dst_off: int, len: int, cap: int n): void = let
  fun loop {l:agz}{n:pos}
    (a: !ward_arr(byte, l, n), i: int, sb: int, db: int, len: int, c: int n): void =
    if gte_int_int(i, len) then ()
    else let
      val () = _app_epub_spine_buf_set_u8(db + i, _ab(a, sb + i, c))
    in loop(a, i + 1, sb, db, len, c) end
in loop(a, 0, src_base, dst_off, len, cap) end

(* ========== Needle builders ========== *)
(* Each returns a ward_arr that must be freed by the caller. *)

(* "full-path=\"" — 11 bytes *)
fn _n_full_path(): [l:agz] ward_arr(byte, l, 11) = let
  val a = ward_arr_alloc<byte>(11)
  val () = _wb(a,0,102,11) val () = _wb(a,1,117,11) val () = _wb(a,2,108,11)
  val () = _wb(a,3,108,11) val () = _wb(a,4,45,11)  val () = _wb(a,5,112,11)
  val () = _wb(a,6,97,11)  val () = _wb(a,7,116,11) val () = _wb(a,8,104,11)
  val () = _wb(a,9,61,11)  val () = _wb(a,10,34,11)
in a end

(* "<dc:title" — 9 bytes (without '>' to handle attributes) *)
fn _n_dc_title_open(): [l:agz] ward_arr(byte, l, 9) = let
  val a = ward_arr_alloc<byte>(9)
  val () = _wb(a,0,60,9)  val () = _wb(a,1,100,9) val () = _wb(a,2,99,9)
  val () = _wb(a,3,58,9)  val () = _wb(a,4,116,9) val () = _wb(a,5,105,9)
  val () = _wb(a,6,116,9) val () = _wb(a,7,108,9) val () = _wb(a,8,101,9)
in a end

(* "</dc:title>" — 11 bytes *)
fn _n_dc_title_close(): [l:agz] ward_arr(byte, l, 11) = let
  val a = ward_arr_alloc<byte>(11)
  val () = _wb(a,0,60,11)  val () = _wb(a,1,47,11)  val () = _wb(a,2,100,11)
  val () = _wb(a,3,99,11)  val () = _wb(a,4,58,11)  val () = _wb(a,5,116,11)
  val () = _wb(a,6,105,11) val () = _wb(a,7,116,11) val () = _wb(a,8,108,11)
  val () = _wb(a,9,101,11) val () = _wb(a,10,62,11)
in a end

(* "<dc:creator" — 11 bytes (without '>' to handle attributes) *)
fn _n_dc_creator_open(): [l:agz] ward_arr(byte, l, 11) = let
  val a = ward_arr_alloc<byte>(11)
  val () = _wb(a,0,60,11)  val () = _wb(a,1,100,11) val () = _wb(a,2,99,11)
  val () = _wb(a,3,58,11)  val () = _wb(a,4,99,11)  val () = _wb(a,5,114,11)
  val () = _wb(a,6,101,11) val () = _wb(a,7,97,11)  val () = _wb(a,8,116,11)
  val () = _wb(a,9,111,11) val () = _wb(a,10,114,11)
in a end

(* "</dc:creator>" — 13 bytes *)
fn _n_dc_creator_close(): [l:agz] ward_arr(byte, l, 13) = let
  val a = ward_arr_alloc<byte>(13)
  val () = _wb(a,0,60,13)  val () = _wb(a,1,47,13)  val () = _wb(a,2,100,13)
  val () = _wb(a,3,99,13)  val () = _wb(a,4,58,13)  val () = _wb(a,5,99,13)
  val () = _wb(a,6,114,13) val () = _wb(a,7,101,13) val () = _wb(a,8,97,13)
  val () = _wb(a,9,116,13) val () = _wb(a,10,111,13) val () = _wb(a,11,114,13)
  val () = _wb(a,12,62,13)
in a end

(* "<dc:identifier" — 14 bytes *)
(* "<itemref " — 9 bytes *)
fn _n_itemref(): [l:agz] ward_arr(byte, l, 9) = let
  val a = ward_arr_alloc<byte>(9)
  val () = _wb(a,0,60,9)  val () = _wb(a,1,105,9) val () = _wb(a,2,116,9)
  val () = _wb(a,3,101,9) val () = _wb(a,4,109,9) val () = _wb(a,5,114,9)
  val () = _wb(a,6,101,9) val () = _wb(a,7,102,9) val () = _wb(a,8,32,9)
in a end

(* "idref=\"" — 7 bytes *)
fn _n_idref(): [l:agz] ward_arr(byte, l, 7) = let
  val a = ward_arr_alloc<byte>(7)
  val () = _wb(a,0,105,7) val () = _wb(a,1,100,7) val () = _wb(a,2,114,7)
  val () = _wb(a,3,101,7) val () = _wb(a,4,102,7) val () = _wb(a,5,61,7)
  val () = _wb(a,6,34,7)
in a end

(* "<item " — 6 bytes *)
fn _n_item(): [l:agz] ward_arr(byte, l, 6) = let
  val a = ward_arr_alloc<byte>(6)
  val () = _wb(a,0,60,6)  val () = _wb(a,1,105,6) val () = _wb(a,2,116,6)
  val () = _wb(a,3,101,6) val () = _wb(a,4,109,6) val () = _wb(a,5,32,6)
in a end

(* " id=\"" — 5 bytes *)
fn _n_id(): [l:agz] ward_arr(byte, l, 5) = let
  val a = ward_arr_alloc<byte>(5)
  val () = _wb(a,0,32,5)  val () = _wb(a,1,105,5) val () = _wb(a,2,100,5)
  val () = _wb(a,3,61,5)  val () = _wb(a,4,34,5)
in a end

(* "href=\"" — 6 bytes *)
fn _n_href(): [l:agz] ward_arr(byte, l, 6) = let
  val a = ward_arr_alloc<byte>(6)
  val () = _wb(a,0,104,6) val () = _wb(a,1,114,6) val () = _wb(a,2,101,6)
  val () = _wb(a,3,102,6) val () = _wb(a,4,61,6)  val () = _wb(a,5,34,6)
in a end

(* ========== epub_init ========== *)

implement epub_init() = let
  val () = _app_set_epub_title_len(0)
  val () = _app_set_epub_author_len(0)
  val () = _app_set_epub_book_id_len(0)
  val () = _app_set_epub_opf_path_len(0)
  val () = _app_set_epub_opf_dir_len(0)
  val () = _app_set_epub_spine_count(0)
  val () = _app_set_epub_state(0) (* init-only: no proof required *)
  val () = _app_set_epub_spine_path_count(0)
  val () = _app_set_epub_spine_path_pos(0)
  val () = _app_set_epub_cover_href_len(0)
in end

(* ========== Simple accessors ========== *)

implement epub_get_state() = g1ofg0(_app_epub_state())

implement epub_get_progress() = 0

implement epub_get_error(_) = 0

implement epub_start_import(pf_idle | _) = let
  prval EPUB_IS_IDLE() = pf_idle
in 0 end

implement epub_get_title(buf_offset) = let
  val tlen = _app_epub_title_len()
  val () = _app_copy_epub_title_to_sbuf(buf_offset, tlen)
in tlen end

implement epub_get_author(buf_offset) = let
  val alen = _app_epub_author_len()
  val () = _app_copy_epub_author_to_sbuf(buf_offset, alen)
in alen end

implement epub_get_book_id(buf_offset) = let
  val blen = _app_epub_book_id_len()
  val () = _app_copy_epub_book_id_to_sbuf(buf_offset, blen)
in blen end

implement epub_get_chapter_count() = let
  val sc = _app_epub_spine_count()
  extern castfn _clamp256(x: int): [n:nat | n <= 256] int n
in
  if lt_int_int(sc, 0) then 0
  else if gt_int_int(sc, 256) then 256
  else _clamp256(sc)
end

implement epub_continue() = ()

implement epub_on_file_open(_, _) = ()

implement epub_on_decompress(_, _) = ()

implement epub_on_db_open(_) = ()

implement epub_on_db_put(_) = ()

implement epub_cancel() = _app_set_epub_state(0) (* cancel resets to idle *)

(* TOC stubs *)
implement epub_get_toc_count() = 0

implement epub_get_toc_label(_, _) = 0

implement epub_get_toc_chapter(_) = 0 - 1

implement epub_get_toc_level(_) = 0

implement epub_get_chapter_title(_, _) = 0

(* Serialization stubs *)
implement epub_serialize_metadata() = (SERIALIZE_OK() | 0)

implement epub_restore_metadata(pf | _) = let
  prval SERIALIZE_OK() = pf
in 0 end

implement epub_reset() = let
  val () = epub_init()
in (EPUB_IS_IDLE() | ()) end

(* ========== epub_parse_container_bytes ========== *)

(* Parse container.xml to extract OPF path from full-path="..." attribute.
 * Stores path and directory prefix in app_state.
 * Returns 1 on success, 0 on failure. *)
implement epub_parse_container_bytes(arr, len) = let
  val ndl = _n_full_path() (* "full-path=\"" 11 bytes *)
  val pos0 = _find_bytes(arr, len, len, ndl, 11, 11, 0)
  val () = ward_arr_free<byte>(ndl)
in
  if lt_int_int(pos0, 0) then 0
  else let
    val pos = pos0 + 11
    val qend = _find_quote(arr, len, len, pos)
  in
    if gte_int_int(qend, len) then 0
    else let
      val path_len = qend - pos
    in
      if lte_int_int(path_len, 0) then 0
      else if gte_int_int(path_len, 256) then 0
      else let
        (* Copy path bytes from arr to opf_path buffer in app_state *)
        val () = _copy_arr_to_opf(arr, pos, path_len, len)
        val () = _app_set_epub_opf_path_len(path_len)
        (* Extract directory prefix up to and including last '/' *)
        val pl = _checked_nat(path_len)
        fun find_last_slash {k:nat}{pl:nat | k <= pl} .<pl-k>.
          (i: int(k), last: int, plen: int(pl)): int =
          if gte_g1(i, plen) then last
          else if eq_int_int(_app_epub_opf_path_get_u8(_g0(i)), 47)
            then find_last_slash(add_g1(i, 1), _g0(i), plen)
          else find_last_slash(add_g1(i, 1), last, plen)
        val last_slash = find_last_slash(0, 0 - 1, pl)
      in
        if gte_int_int(last_slash, 0) then
          _app_set_epub_opf_dir_len(last_slash + 1)
        else
          _app_set_epub_opf_dir_len(0)
        ;
        1
      end
    end
  end
end

(* ========== epub_parse_opf_bytes (split into sub-functions for V8 WASM) ========== *)

(* V8's WASM compiler crashes on very large functions (>2000 WAT lines).
 * The OPF parser is split into 5 separate functions so each generates
 * a reasonably-sized WASM function body. *)

extern fun _opf_extract_title {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): void = "ext#"
implement _opf_extract_title(buf, len) = let
  val ndl_to = _n_dc_title_open()
  val ndl_tc = _n_dc_title_close()
  val pos_t = _find_bytes(buf, len, len, ndl_to, 9, 9, 0)
  val () = ward_arr_free<byte>(ndl_to)
in
  if lt_int_int(pos_t, 0) then ward_arr_free<byte>(ndl_tc)
  else let
    (* Find '>' to skip any attributes on the tag *)
    val (pf_gt | gt_pos) = _find_gt(buf, len, len, pos_t + 9)
    prval _ = pf_gt
  in
    if gte_int_int(gt_pos, len) then ward_arr_free<byte>(ndl_tc)
    else let
      val tstart = gt_pos + 1
      val tend = _find_bytes(buf, len, len, ndl_tc, 11, 11, tstart)
      val () = ward_arr_free<byte>(ndl_tc)
    in
      if lt_int_int(tend, 0) then ()
      else let
        val tlen0 = tend - tstart
        val tlen = if gt_int_int(tlen0, 255) then 255 else tlen0
        val () = _copy_arr_to_title(buf, tstart, tlen, len)
      in _app_set_epub_title_len(tlen) end
    end
  end
end

extern fun _opf_extract_author {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): void = "ext#"
implement _opf_extract_author(buf, len) = let
  val ndl_co = _n_dc_creator_open()
  val ndl_cc = _n_dc_creator_close()
  val pos_c = _find_bytes(buf, len, len, ndl_co, 11, 11, 0)
  val () = ward_arr_free<byte>(ndl_co)
in
  if lt_int_int(pos_c, 0) then ward_arr_free<byte>(ndl_cc)
  else let
    (* Find '>' to skip any attributes on the tag *)
    val (pf_gt | gt_pos) = _find_gt(buf, len, len, pos_c + 11)
    prval _ = pf_gt
  in
    if gte_int_int(gt_pos, len) then ward_arr_free<byte>(ndl_cc)
    else let
      val astart = gt_pos + 1
      val aend = _find_bytes(buf, len, len, ndl_cc, 13, 13, astart)
      val () = ward_arr_free<byte>(ndl_cc)
    in
      if lt_int_int(aend, 0) then ()
      else let
        val alen0 = aend - astart
        val alen = if gt_int_int(alen0, 255) then 255 else alen0
        val () = _copy_arr_to_author(buf, astart, alen, len)
      in _app_set_epub_author_len(alen) end
    end
  end
end

(* ========== Cover image detection ========== *)

(* Build needle: properties="cover-image" (24 bytes) *)
fn _n_cover_props(): [l:agz] ward_arr(byte, l, 24) = let
  val a = ward_arr_alloc<byte>(24)
  (* p=112 r=114 o=111 p=112 e=101 r=114 t=116 i=105 e=101 s=115 *)
  val () = _wb(a,0,112,24)  val () = _wb(a,1,114,24) val () = _wb(a,2,111,24)
  val () = _wb(a,3,112,24)  val () = _wb(a,4,101,24) val () = _wb(a,5,114,24)
  val () = _wb(a,6,116,24)  val () = _wb(a,7,105,24) val () = _wb(a,8,101,24)
  val () = _wb(a,9,115,24)
  (* ="cover-image" → =61 "=34 c=99 o=111 v=118 e=101 r=114 -=45 i=105 m=109 a=97 g=103 e=101 "=34 *)
  val () = _wb(a,10,61,24)  val () = _wb(a,11,34,24)
  val () = _wb(a,12,99,24)  val () = _wb(a,13,111,24) val () = _wb(a,14,118,24)
  val () = _wb(a,15,101,24) val () = _wb(a,16,114,24) val () = _wb(a,17,45,24)
  val () = _wb(a,18,105,24) val () = _wb(a,19,109,24) val () = _wb(a,20,97,24)
  val () = _wb(a,21,103,24) val () = _wb(a,22,101,24) val () = _wb(a,23,34,24)
in a end

(* Build needle: name="cover" (12 bytes) *)
fn _n_meta_cover(): [l:agz] ward_arr(byte, l, 12) = let
  val a = ward_arr_alloc<byte>(12)
  (* n=110 a=97 m=109 e=101 =61 "=34 c=99 o=111 v=118 e=101 r=114 "=34 *)
  val () = _wb(a,0,110,12) val () = _wb(a,1,97,12)  val () = _wb(a,2,109,12)
  val () = _wb(a,3,101,12) val () = _wb(a,4,61,12)  val () = _wb(a,5,34,12)
  val () = _wb(a,6,99,12)  val () = _wb(a,7,111,12) val () = _wb(a,8,118,12)
  val () = _wb(a,9,101,12) val () = _wb(a,10,114,12) val () = _wb(a,11,34,12)
in a end

(* Build needle: content=" (9 bytes) *)
fn _n_content(): [l:agz] ward_arr(byte, l, 9) = let
  val a = ward_arr_alloc<byte>(9)
  (* c=99 o=111 n=110 t=116 e=101 n=110 t=116 =61 "=34 *)
  val () = _wb(a,0,99,9)  val () = _wb(a,1,111,9) val () = _wb(a,2,110,9)
  val () = _wb(a,3,116,9) val () = _wb(a,4,101,9) val () = _wb(a,5,110,9)
  val () = _wb(a,6,116,9) val () = _wb(a,7,61,9)  val () = _wb(a,8,34,9)
in a end

(* Extract cover image href from OPF.
 * EPUB3: find <item ... properties="cover-image" ... href="...">
 * EPUB2 fallback: find <meta name="cover" content="[id]"/> then look up <item id="[id]" href="...">
 * Stores result in app_state cover_href buffer. Length 0 = no cover found. *)
extern fun _opf_extract_cover {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): void = "ext#"
implement _opf_extract_cover(buf, len) = let
  val () = _app_set_epub_cover_href_len(0)
  val opf_dir_len = _app_epub_opf_dir_len()

  (* Try EPUB3 first: search for properties="cover-image" *)
  val ndl_cp = _n_cover_props()
  val cp_pos = _find_bytes(buf, len, len, ndl_cp, 24, 24, 0)
  val () = ward_arr_free<byte>(ndl_cp)
in
  if gte_int_int(cp_pos, 0) then let
    (* Found properties="cover-image" at cp_pos. Backtrack to find enclosing <item *)
    val nit = _n_item()
    (* Search forward from 0 for <item tags; find the one that contains cp_pos *)
    fun find_enclosing_item {lb:agz}{nb:pos}{ln:agz}
      (buf: !ward_arr(byte, lb, nb), ndl: !ward_arr(byte, ln, 6),
       pos: int, target: int, cap: int nb, hlen: int): int =
      let val found = _find_bytes(buf, hlen, cap, ndl, 6, 6, pos) in
        if lt_int_int(found, 0) then 0 - 1
        else if gt_int_int(found, target) then 0 - 1
        else let
          val next = _find_bytes(buf, hlen, cap, ndl, 6, 6, found + 6)
        in
          if lt_int_int(next, 0) then found  (* last item before target *)
          else if gt_int_int(next, target) then found  (* next item is past target *)
          else find_enclosing_item(buf, ndl, found + 6, target, cap, hlen)
        end
      end
    val item_pos = find_enclosing_item(buf, nit, 0, cp_pos, len, len)
    val () = ward_arr_free<byte>(nit)
  in
    if lt_int_int(item_pos, 0) then ()
    else let
      (* Extract href from this <item> tag *)
      val nhr = _n_href()
      val item_limit0 = item_pos + 500
      val item_limit = if gt_int_int(item_limit0, len) then len else item_limit0
      val href_pos = _find_bytes(buf, item_limit, len, nhr, 6, 6, item_pos)
      val () = ward_arr_free<byte>(nhr)
    in
      if lt_int_int(href_pos, 0) then ()
      else let
        val href_start = href_pos + 6
        val href_end = _find_quote(buf, len, len, href_start)
        val href_len = href_end - href_start
        val full_len = opf_dir_len + href_len
      in
        if lte_int_int(href_len, 0) then ()
        else if gte_int_int(full_len, 256) then ()
        else let
          (* Copy opf_dir prefix to cover_href[0..opf_dir_len-1] *)
          fun copy_dir {k:nat} .<k>.
            (rem: int(k), i: int, dlen: int): void =
            if lte_g1(rem, 0) then ()
            else if gte_int_int(i, dlen) then ()
            else let
              val () = _app_epub_cover_href_set_u8(i, _app_epub_opf_path_get_u8(i))
            in copy_dir(sub_g1(rem, 1), i + 1, dlen) end
          val () = copy_dir(_checked_nat(opf_dir_len), 0, opf_dir_len)
          (* Copy href from arr to cover_href[opf_dir_len..full_len-1] *)
          fun copy_h {l:agz}{n:pos}{k:nat} .<k>.
            (rem: int(k), a: !ward_arr(byte, l, n), i: int, src: int, dst: int, hl: int, c: int n): void =
            if lte_g1(rem, 0) then ()
            else if gte_int_int(i, hl) then ()
            else let
              val () = _app_epub_cover_href_set_u8(dst + i, _ab(a, src + i, c))
            in copy_h(sub_g1(rem, 1), a, i + 1, src, dst, hl, c) end
          val () = copy_h(_checked_nat(href_len), buf, 0, href_start, opf_dir_len, href_len, len)
          val () = _app_set_epub_cover_href_len(full_len)
        in end
      end
    end
  end
  else let
    (* EPUB3 not found, try EPUB2: <meta name="cover" content="[id]"/> *)
    val ndl_mc = _n_meta_cover()
    val mc_pos = _find_bytes(buf, len, len, ndl_mc, 12, 12, 0)
    val () = ward_arr_free<byte>(ndl_mc)
  in
    if lt_int_int(mc_pos, 0) then ()
    else let
      (* Found name="cover" — extract content="[id]" *)
      val ndl_ct = _n_content()
      val ct_limit = if gt_int_int(mc_pos + 200, len) then len else mc_pos + 200
      val ct_pos = _find_bytes(buf, ct_limit, len, ndl_ct, 9, 9, mc_pos)
      val () = ward_arr_free<byte>(ndl_ct)
    in
      if lt_int_int(ct_pos, 0) then ()
      else let
        val id_start = ct_pos + 9
        val id_end = _find_quote(buf, len, len, id_start)
        val id_len = id_end - id_start
      in
        if lte_int_int(id_len, 0) then ()
        else if gt_int_int(id_len, 63) then ()
        else let
          (* Look up <item id="[id]" href="..."> *)
          val nit = _n_item()
          val nmid = _n_id()
          val nhr = _n_href()
          fun find_item_by_id
            {lb:agz}{nb:pos}{l3:agz}{l4:agz}{l5:agz}
            (buf: !ward_arr(byte, lb, nb),
             nit: !ward_arr(byte, l3, 6),
             nmid: !ward_arr(byte, l4, 5),
             nhr: !ward_arr(byte, l5, 6),
             item_pos: int, id_start: int, idref_len: int,
             cap: int nb, hlen: int): @(int, int) = let
            val found_item = _find_bytes(buf, hlen, cap, nit, 6, 6, item_pos)
          in
            if lt_int_int(found_item, 0) then @(0 - 1, 0 - 1)
            else let
              val il0 = found_item + 500
              val il = if gt_int_int(il0, hlen) then hlen else il0
              val mid_pos = _find_bytes(buf, il, cap, nmid, 5, 5, found_item)
            in
              if lt_int_int(mid_pos, 0) then
                find_item_by_id(buf, nit, nmid, nhr, found_item + 6, id_start, idref_len, cap, hlen)
              else let
                val mid_start = mid_pos + 5
                val mid_end = _find_quote(buf, hlen, cap, mid_start)
                val mid_len = mid_end - mid_start
              in
                if neq_int_int(mid_len, idref_len) then
                  find_item_by_id(buf, nit, nmid, nhr, found_item + 6, id_start, idref_len, cap, hlen)
                else if _arr_bytes_equal(buf, mid_start, id_start, idref_len, cap) then let
                  val hp = _find_bytes(buf, il, cap, nhr, 6, 6, found_item)
                in
                  if lt_int_int(hp, 0) then @(0 - 1, 0 - 1)
                  else let
                    val hs = hp + 6
                    val he = _find_quote(buf, hlen, cap, hs)
                  in @(hs, he) end
                end
                else find_item_by_id(buf, nit, nmid, nhr, found_item + 6, id_start, idref_len, cap, hlen)
              end
            end
          end
          val @(href_s, href_e) = find_item_by_id(buf, nit, nmid, nhr, 0, id_start, id_len, len, len)
          val () = ward_arr_free<byte>(nit)
          val () = ward_arr_free<byte>(nmid)
          val () = ward_arr_free<byte>(nhr)
        in
          if lt_int_int(href_s, 0) then ()
          else let
            val h_len = href_e - href_s
            val full_len = opf_dir_len + h_len
          in
            if lte_int_int(h_len, 0) then ()
            else if gte_int_int(full_len, 256) then ()
            else let
              fun cp_dir {k:nat} .<k>.
                (rem: int(k), i: int, dlen: int): void =
                if lte_g1(rem, 0) then ()
                else if gte_int_int(i, dlen) then ()
                else let
                  val () = _app_epub_cover_href_set_u8(i, _app_epub_opf_path_get_u8(i))
                in cp_dir(sub_g1(rem, 1), i + 1, dlen) end
              val () = cp_dir(_checked_nat(opf_dir_len), 0, opf_dir_len)
              fun cp_href {l:agz}{n:pos}{k:nat} .<k>.
                (rem: int(k), a: !ward_arr(byte, l, n), i: int, src: int, dst: int, hl: int, c: int n): void =
                if lte_g1(rem, 0) then ()
                else if gte_int_int(i, hl) then ()
                else let
                  val () = _app_epub_cover_href_set_u8(dst + i, _ab(a, src + i, c))
                in cp_href(sub_g1(rem, 1), a, i + 1, src, dst, hl, c) end
              val () = cp_href(_checked_nat(h_len), buf, 0, href_s, opf_dir_len, h_len, len)
              val () = _app_set_epub_cover_href_len(full_len)
            in end
          end
        end
      end
    end
  end
end

extern fun _opf_count_spine {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): int = "ext#"
implement _opf_count_spine(buf, len) = let
  val ndl_ir = _n_itemref()
  fun count_loop {lb:agz}{nb:pos}{ln:agz}
    (buf: !ward_arr(byte, lb, nb), ndl: !ward_arr(byte, ln, 9),
     pos: int, cnt: int, hc: int nb): int = let
    val found = _find_bytes(buf, len, hc, ndl, 9, 9, pos)
  in
    if lt_int_int(found, 0) then cnt
    else count_loop(buf, ndl, found + 9, cnt + 1, hc)
  end
  val result = count_loop(buf, ndl_ir, 0, 0, len)
  val () = ward_arr_free<byte>(ndl_ir)
in result end

extern fun _opf_resolve_spine {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n, spine_count: int): void = "ext#"
implement _opf_resolve_spine(buf, len, spine_count) = let
  val () = _app_set_epub_spine_path_count(0)
  val () = _app_set_epub_spine_path_pos(0)

  val nir = _n_itemref()
  val nidr = _n_idref()
  val nit = _n_item()
  val nmid = _n_id()
  val nhr = _n_href()
  val opf_dir_len = _app_epub_opf_dir_len()

  (* Find <item> with id matching idref, return href bounds or @(-1,-1) *)
  fun find_matching_item
    {lb:agz}{nb:pos}{l3:agz}{l4:agz}{l5:agz}
    (buf: !ward_arr(byte, lb, nb),
     nit: !ward_arr(byte, l3, 6),
     nmid: !ward_arr(byte, l4, 5),
     nhr: !ward_arr(byte, l5, 6),
     item_pos: int, id_start: int, idref_len: int,
     cap: int nb, hlen: int): @(int, int) = let
    val found_item = _find_bytes(buf, hlen, cap, nit, 6, 6, item_pos)
  in
    if lt_int_int(found_item, 0) then @(0 - 1, 0 - 1)
    else let
      val item_limit0 = found_item + 500
      val item_limit = if gt_int_int(item_limit0, hlen) then hlen else item_limit0
      val mid_pos = _find_bytes(buf, item_limit, cap, nmid, 5, 5, found_item)
    in
      if lt_int_int(mid_pos, 0) then
        find_matching_item(buf, nit, nmid, nhr, found_item + 6, id_start, idref_len, cap, hlen)
      else let
        val mid_start = mid_pos + 5
        val mid_end = _find_quote(buf, hlen, cap, mid_start)
        val mid_len = mid_end - mid_start
      in
        if neq_int_int(mid_len, idref_len) then
          find_matching_item(buf, nit, nmid, nhr, found_item + 6, id_start, idref_len, cap, hlen)
        else if _arr_bytes_equal(buf, mid_start, id_start, idref_len, cap) then let
          val href_pos = _find_bytes(buf, item_limit, cap, nhr, 6, 6, found_item)
        in
          if lt_int_int(href_pos, 0) then @(0 - 1, 0 - 1)
          else let
            val href_start = href_pos + 6
            val href_end = _find_quote(buf, hlen, cap, href_start)
          in @(href_start, href_end) end
        end
        else find_matching_item(buf, nit, nmid, nhr, found_item + 6, id_start, idref_len, cap, hlen)
      end
    end
  end

  (* Main spine resolution loop *)
  fun resolve_loop
    {lb:agz}{nb:pos}{l1:agz}{l2:agz}{l3:agz}{l4:agz}{l5:agz}
    (buf: !ward_arr(byte, lb, nb),
     nir: !ward_arr(byte, l1, 9),
     nidr: !ward_arr(byte, l2, 7),
     nit: !ward_arr(byte, l3, 6),
     nmid: !ward_arr(byte, l4, 5),
     nhr: !ward_arr(byte, l5, 6),
     si: int, pos: int, sp_count: int, sp_pos: int,
     cap: int nb, odir_len: int, sc: int, hlen: int): void = let
    fun done(spc: int, spp: int): void = let
      val () = _app_set_epub_spine_path_count(spc)
      val () = _app_set_epub_spine_path_pos(spp)
    in end
  in
    if gte_int_int(si, sc) then done(sp_count, sp_pos)
    else if gte_int_int(si, 32) then done(sp_count, sp_pos)
    else let
      val ir_pos = _find_bytes(buf, hlen, cap, nir, 9, 9, pos)
    in
      if lt_int_int(ir_pos, 0) then done(sp_count, sp_pos)
      else let
        val idref_pos = _find_bytes(buf, hlen, cap, nidr, 7, 7, ir_pos)
      in
        if lt_int_int(idref_pos, 0) then
          resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count, sp_pos, cap, odir_len, sc, hlen)
        else if gt_int_int(idref_pos, ir_pos + 200) then
          resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count, sp_pos, cap, odir_len, sc, hlen)
        else let
          val id_start = idref_pos + 7
          val id_end = _find_quote(buf, hlen, cap, id_start)
          val idref_len = id_end - id_start
        in
          if lte_int_int(idref_len, 0) then
            resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count, sp_pos, cap, odir_len, sc, hlen)
          else if gt_int_int(idref_len, 63) then
            resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count, sp_pos, cap, odir_len, sc, hlen)
          else let
            val @(href_start, href_end) = find_matching_item(buf, nit, nmid, nhr, 0, id_start, idref_len, cap, hlen)
          in
            if lt_int_int(href_start, 0) then
              resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count, sp_pos, cap, odir_len, sc, hlen)
            else let
              val href_len = href_end - href_start
              val full_len = odir_len + href_len
            in
              if lte_int_int(full_len, 0) then
                resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count, sp_pos, cap, odir_len, sc, hlen)
              else if gt_int_int(full_len, 255) then
                resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count, sp_pos, cap, odir_len, sc, hlen)
              else if gt_int_int(sp_pos + full_len, 4096) then
                resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count, sp_pos, cap, odir_len, sc, hlen)
              else let
                val () = _app_copy_opf_path_to_epub_spine_buf(sp_pos, odir_len)
                val () = _copy_arr_to_spine_buf(buf, href_start, sp_pos + odir_len, href_len, cap)
                val () = _app_epub_spine_offsets_set_i32(sp_count, sp_pos)
                val () = _app_epub_spine_lens_set_i32(sp_count, full_len)
              in
                resolve_loop(buf, nir, nidr, nit, nmid, nhr, si + 1, ir_pos + 9, sp_count + 1, sp_pos + full_len, cap, odir_len, sc, hlen)
              end
            end
          end
        end
      end
    end
  end

  val () = resolve_loop(buf, nir, nidr, nit, nmid, nhr, 0, 0, 0, 0, len, opf_dir_len, spine_count, len)

  val () = ward_arr_free<byte>(nir)
  val () = ward_arr_free<byte>(nidr)
  val () = ward_arr_free<byte>(nit)
  val () = ward_arr_free<byte>(nmid)
  val () = ward_arr_free<byte>(nhr)
in end

implement epub_parse_opf_bytes(arr, len) = let
  val () = _opf_extract_title(arr, len)
  val () = _opf_extract_author(arr, len)
  val () = _opf_extract_cover(arr, len)
  (* book_id is now set by sha256_file_hash in quire.dats import path,
   * not extracted from dc:identifier. See BOOK_IDENTITY_IS_CONTENT_HASH. *)
  val spine_count = _opf_count_spine(arr, len)
  val () = _app_set_epub_spine_count(spine_count)
  val () = _opf_resolve_spine(arr, len, spine_count)
in
  _app_set_epub_state(8); (* EPUB_STATE_DONE — set by OPF parse *)
  spine_count
end

(* ========== Path copy accessors ========== *)

implement epub_copy_opf_path(buf_offset) = let
  val olen = _app_epub_opf_path_len()
  val () = _app_copy_epub_opf_path_to_sbuf(buf_offset, olen)
in _checked_nat(olen) end

implement epub_copy_container_path(buf_offset) = let
  (* "META-INF/container.xml" — 22 bytes, written directly to sbuf *)
  val () = _app_sbuf_set_u8(buf_offset, 77)       (* M *)
  val () = _app_sbuf_set_u8(buf_offset + 1, 69)   (* E *)
  val () = _app_sbuf_set_u8(buf_offset + 2, 84)   (* T *)
  val () = _app_sbuf_set_u8(buf_offset + 3, 65)   (* A *)
  val () = _app_sbuf_set_u8(buf_offset + 4, 45)   (* - *)
  val () = _app_sbuf_set_u8(buf_offset + 5, 73)   (* I *)
  val () = _app_sbuf_set_u8(buf_offset + 6, 78)   (* N *)
  val () = _app_sbuf_set_u8(buf_offset + 7, 70)   (* F *)
  val () = _app_sbuf_set_u8(buf_offset + 8, 47)   (* / *)
  val () = _app_sbuf_set_u8(buf_offset + 9, 99)   (* c *)
  val () = _app_sbuf_set_u8(buf_offset + 10, 111) (* o *)
  val () = _app_sbuf_set_u8(buf_offset + 11, 110) (* n *)
  val () = _app_sbuf_set_u8(buf_offset + 12, 116) (* t *)
  val () = _app_sbuf_set_u8(buf_offset + 13, 97)  (* a *)
  val () = _app_sbuf_set_u8(buf_offset + 14, 105) (* i *)
  val () = _app_sbuf_set_u8(buf_offset + 15, 110) (* n *)
  val () = _app_sbuf_set_u8(buf_offset + 16, 101) (* e *)
  val () = _app_sbuf_set_u8(buf_offset + 17, 114) (* r *)
  val () = _app_sbuf_set_u8(buf_offset + 18, 46)  (* . *)
  val () = _app_sbuf_set_u8(buf_offset + 19, 120) (* x *)
  val () = _app_sbuf_set_u8(buf_offset + 20, 109) (* m *)
  val () = _app_sbuf_set_u8(buf_offset + 21, 108) (* l *)
in 22 end

(* Spine path copy — proof-guarded, no bounds check needed.
 * SPINE_ORDERED(c, t) guarantees index is valid.
 * Parser invariant: stored lengths are always positive
 * (_opf_resolve_spine rejects lte_int_int(full_len, 0)). *)
implement epub_copy_spine_path(pf | index, _count, buf_offset) = let
  prval SPINE_ENTRY() = pf
  val off = _app_epub_spine_offsets_get_i32(index)
  val slen = _app_epub_spine_lens_get_i32(index)
  val () = _app_copy_epub_spine_buf_to_sbuf(off, buf_offset, slen)
in _checked_pos(slen) end

(* ========== M1.2 Exploded Resource Storage ========== *)

(* Hex nibble: 0-15 → ASCII code of '0'-'9','a'-'f' *)
fn _hex_nibble(n: int): int =
  if lt_int_int(n, 10) then n + 48 (* '0' = 48 *)
  else n + 87 (* 'a' - 10 = 87, so 10→97='a' *)

(* Bridge runtime hex digit to SAFE_CHAR.
 * Hex digits 0-9 map to 48-57, a-f map to 97-102 — all within SAFE_CHAR range.
 * The castfn trusts that _hex_nibble produces only these values. *)
extern castfn _safe_hex_char(c: int): [c2:int | SAFE_CHAR(c2)] int(c2)

(* Build 20-char IDB resource key: {16 hex book_id}-{3 hex entry_idx}
 * Hex chars: 0-9 (48-57), a-f (97-102) — all SAFE_CHAR.
 * Hyphen (45) — SAFE_CHAR. *)
implement epub_build_resource_key(entry_idx) = let
  val b0 = _app_epub_book_id_get_u8(0)
  val b1 = _app_epub_book_id_get_u8(1)
  val b2 = _app_epub_book_id_get_u8(2)
  val b3 = _app_epub_book_id_get_u8(3)
  val b4 = _app_epub_book_id_get_u8(4)
  val b5 = _app_epub_book_id_get_u8(5)
  val b6 = _app_epub_book_id_get_u8(6)
  val b7 = _app_epub_book_id_get_u8(7)
  (* Each byte → 2 hex chars: high nibble then low nibble *)
  val bld = ward_text_build(20)
  val bld = ward_text_putc(bld, 0, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b0, 255), 16))))
  val bld = ward_text_putc(bld, 1, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b0, 255), 16))))
  val bld = ward_text_putc(bld, 2, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b1, 255), 16))))
  val bld = ward_text_putc(bld, 3, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b1, 255), 16))))
  val bld = ward_text_putc(bld, 4, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b2, 255), 16))))
  val bld = ward_text_putc(bld, 5, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b2, 255), 16))))
  val bld = ward_text_putc(bld, 6, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b3, 255), 16))))
  val bld = ward_text_putc(bld, 7, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b3, 255), 16))))
  val bld = ward_text_putc(bld, 8, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b4, 255), 16))))
  val bld = ward_text_putc(bld, 9, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b4, 255), 16))))
  val bld = ward_text_putc(bld, 10, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b5, 255), 16))))
  val bld = ward_text_putc(bld, 11, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b5, 255), 16))))
  val bld = ward_text_putc(bld, 12, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b6, 255), 16))))
  val bld = ward_text_putc(bld, 13, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b6, 255), 16))))
  val bld = ward_text_putc(bld, 14, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b7, 255), 16))))
  val bld = ward_text_putc(bld, 15, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b7, 255), 16))))
  (* Hyphen separator: '-' = 45, which is SAFE_CHAR *)
  val bld = ward_text_putc(bld, 16, 45)
  (* 3-digit hex entry index (0-4095 range, 12 bits) *)
  val ei = band_int_int(entry_idx, 4095)
  val bld = ward_text_putc(bld, 17, _safe_hex_char(_hex_nibble(div_int_int(ei, 256))))
  val bld = ward_text_putc(bld, 18, _safe_hex_char(_hex_nibble(mod_int_int(div_int_int(ei, 16), 16))))
  val bld = ward_text_putc(bld, 19, _safe_hex_char(_hex_nibble(mod_int_int(ei, 16))))
in ward_text_done(bld) end

(* Build 20-char IDB manifest key: {16 hex book_id}-man *)
implement epub_build_manifest_key() = let
  val b0 = _app_epub_book_id_get_u8(0)
  val b1 = _app_epub_book_id_get_u8(1)
  val b2 = _app_epub_book_id_get_u8(2)
  val b3 = _app_epub_book_id_get_u8(3)
  val b4 = _app_epub_book_id_get_u8(4)
  val b5 = _app_epub_book_id_get_u8(5)
  val b6 = _app_epub_book_id_get_u8(6)
  val b7 = _app_epub_book_id_get_u8(7)
  val bld = ward_text_build(20)
  val bld = ward_text_putc(bld, 0, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b0, 255), 16))))
  val bld = ward_text_putc(bld, 1, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b0, 255), 16))))
  val bld = ward_text_putc(bld, 2, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b1, 255), 16))))
  val bld = ward_text_putc(bld, 3, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b1, 255), 16))))
  val bld = ward_text_putc(bld, 4, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b2, 255), 16))))
  val bld = ward_text_putc(bld, 5, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b2, 255), 16))))
  val bld = ward_text_putc(bld, 6, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b3, 255), 16))))
  val bld = ward_text_putc(bld, 7, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b3, 255), 16))))
  val bld = ward_text_putc(bld, 8, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b4, 255), 16))))
  val bld = ward_text_putc(bld, 9, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b4, 255), 16))))
  val bld = ward_text_putc(bld, 10, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b5, 255), 16))))
  val bld = ward_text_putc(bld, 11, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b5, 255), 16))))
  val bld = ward_text_putc(bld, 12, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b6, 255), 16))))
  val bld = ward_text_putc(bld, 13, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b6, 255), 16))))
  val bld = ward_text_putc(bld, 14, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b7, 255), 16))))
  val bld = ward_text_putc(bld, 15, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b7, 255), 16))))
  (* "-man" suffix: '-'=45, 'm'=109, 'a'=97, 'n'=110 — all SAFE_CHAR *)
  val bld = ward_text_putc(bld, 16, 45)
  val bld = ward_text_putc(bld, 17, 109)
  val bld = ward_text_putc(bld, 18, 97)
  val bld = ward_text_putc(bld, 19, 110)
in ward_text_done(bld) end

(* Build 20-char IDB cover key: {16 hex book_id}-cvr *)
implement epub_build_cover_key() = let
  val b0 = _app_epub_book_id_get_u8(0)
  val b1 = _app_epub_book_id_get_u8(1)
  val b2 = _app_epub_book_id_get_u8(2)
  val b3 = _app_epub_book_id_get_u8(3)
  val b4 = _app_epub_book_id_get_u8(4)
  val b5 = _app_epub_book_id_get_u8(5)
  val b6 = _app_epub_book_id_get_u8(6)
  val b7 = _app_epub_book_id_get_u8(7)
  val bld = ward_text_build(20)
  val bld = ward_text_putc(bld, 0, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b0, 255), 16))))
  val bld = ward_text_putc(bld, 1, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b0, 255), 16))))
  val bld = ward_text_putc(bld, 2, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b1, 255), 16))))
  val bld = ward_text_putc(bld, 3, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b1, 255), 16))))
  val bld = ward_text_putc(bld, 4, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b2, 255), 16))))
  val bld = ward_text_putc(bld, 5, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b2, 255), 16))))
  val bld = ward_text_putc(bld, 6, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b3, 255), 16))))
  val bld = ward_text_putc(bld, 7, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b3, 255), 16))))
  val bld = ward_text_putc(bld, 8, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b4, 255), 16))))
  val bld = ward_text_putc(bld, 9, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b4, 255), 16))))
  val bld = ward_text_putc(bld, 10, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b5, 255), 16))))
  val bld = ward_text_putc(bld, 11, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b5, 255), 16))))
  val bld = ward_text_putc(bld, 12, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b6, 255), 16))))
  val bld = ward_text_putc(bld, 13, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b6, 255), 16))))
  val bld = ward_text_putc(bld, 14, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b7, 255), 16))))
  val bld = ward_text_putc(bld, 15, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b7, 255), 16))))
  (* "-cvr" suffix: '-'=45, 'c'=99, 'v'=118, 'r'=114 — all SAFE_CHAR *)
  val bld = ward_text_putc(bld, 16, 45)
  val bld = ward_text_putc(bld, 17, 99)
  val bld = ward_text_putc(bld, 18, 118)
  val bld = ward_text_putc(bld, 19, 114)
in ward_text_done(bld) end

(* ========== epub_store_cover ========== *)

(* Store cover image: copy resource blob from its resource key to the cover key.
 * Requires manifest to be loaded (for epub_find_resource). *)
implement epub_store_cover() = let
  val href_len0 = _app_epub_cover_href_len()
  val href_len = g1ofg0(href_len0)
in
  if lte_g1(href_len, 0) then ward_promise_return<int>(0)
  else let
    (* href_len > 0 — constraint solver tracks this *)
    (* Copy cover href to sbuf[0..href_len-1] for epub_find_resource *)
    val () = _app_copy_epub_cover_href_to_sbuf(0, _g0(href_len))
    val entry_idx = epub_find_resource(_g0(href_len))
  in
    if lt_g1(entry_idx, 0) then ward_promise_return<int>(0)
    else let
      (* entry_idx >= 0 — constraint solver tracks this *)
      val key = epub_build_resource_key(_g0(entry_idx))
      val p = ward_idb_get(key, 20)
    in
      ward_promise_then<int><int>(p,
        llam (data_len: int): ward_promise_chained(int) =>
          if lte_int_int(data_len, 0) then ward_promise_return<int>(0)
          else let
            val dl = _checked_pos(data_len)
            val arr = ward_idb_get_result(dl)
            val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
            val cvr_key = epub_build_cover_key()
            val p2 = ward_idb_put(cvr_key, 20, borrow, dl)
            val () = ward_arr_drop<byte>(frozen, borrow)
            val arr = ward_arr_thaw<byte>(frozen)
            val () = ward_arr_free<byte>(arr)
          in ward_promise_vow(p2) end)
    end
  end
end

(* ========== epub_store_all_resources ========== *)

(* Store a single ZIP entry to IDB. Handles stored (compression=0) and
 * deflated (compression=8) entries. Returns a chained promise. *)
fn _store_single_entry(file_handle: int, entry_idx: int): ward_promise_chained(int) = let
  var entry: zip_entry
  val found = zip_get_entry(entry_idx, entry)
in
  if lte_int_int(found, 0) then ward_promise_return<int>(1)
  else let
    val compression = entry.compression
    val compressed_size = entry.compressed_size
    val uncompressed_size = entry.uncompressed_size
    val data_off = zip_get_data_offset(entry_idx)
  in
    if lte_int_int(data_off, 0) then ward_promise_return<int>(1)
    else if lte_int_int(uncompressed_size, 0) then ward_promise_return<int>(1)
    else if eq_int_int(compression, 0) then let
      (* Stored — read directly and put to IDB *)
      val sz1 = (if gt_int_int(uncompressed_size, 0) then uncompressed_size else 1): int
      val sz = _checked_arr_size(sz1)
      val arr = ward_arr_alloc<byte>(sz)
      val _rd = ward_file_read(file_handle, data_off, arr, sz)
      val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
      val key = epub_build_resource_key(entry_idx)
      val p = ward_idb_put(key, 20, borrow, sz)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val arr = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(arr)
    in ward_promise_vow(p) end
    else if eq_int_int(compression, 8) then let
      (* Deflated — decompress then store *)
      val cs1 = (if gt_int_int(compressed_size, 0) then compressed_size else 1): int
      val cs = _checked_arr_size(cs1)
      val arr = ward_arr_alloc<byte>(cs)
      val _rd = ward_file_read(file_handle, data_off, arr, cs)
      val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
      val p = ward_decompress(borrow, cs, 2) (* deflate-raw *)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val arr = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(arr)
      val saved_idx = entry_idx
    in
      ward_promise_then<int><int>(p,
        llam (blob_handle: int): ward_promise_chained(int) => let
          val dlen = ward_decompress_get_len()
        in
          if lte_int_int(dlen, 0) then let
            val () = ward_blob_free(blob_handle)
          in ward_promise_return<int>(1) end
          else let
            val dl = _checked_arr_size(dlen)
            val arr2 = ward_arr_alloc<byte>(dl)
            val _rd = ward_blob_read(blob_handle, 0, arr2, dl)
            val () = ward_blob_free(blob_handle)
            val @(frozen2, borrow2) = ward_arr_freeze<byte>(arr2)
            val key = epub_build_resource_key(saved_idx)
            val p2 = ward_idb_put(key, 20, borrow2, dl)
            val () = ward_arr_drop<byte>(frozen2, borrow2)
            val arr2 = ward_arr_thaw<byte>(frozen2)
            val () = ward_arr_free<byte>(arr2)
          in ward_promise_vow(p2) end
        end)
    end
    else ward_promise_return<int>(1) (* unknown compression, skip *)
  end
end

implement epub_store_all_resources(file_handle) = let
  val entry_count = zip_get_entry_count()
  val ec = _g0(entry_count): int
  fun loop {k:nat} .<k>.
    (rem: int(k), idx: int, count: int, fh: int): ward_promise_chained(int) =
    if lte_g1(rem, 0) then ward_promise_return<int>(1)
    else if gte_int_int(idx, count) then ward_promise_return<int>(1)
    else let
      val saved_idx = idx + 1
      val saved_count = count
      val saved_fh = fh
      val saved_rem = sub_g1(rem, 1)
      val p = _store_single_entry(fh, idx)
    in
      ward_promise_then<int><int>(p,
        llam (_status: int): ward_promise_chained(int) =>
          loop(saved_rem, saved_idx, saved_count, saved_fh))
    end
in loop(_checked_nat(ec), 0, ec, file_handle) end

(* ========== epub_store_manifest ========== *)

(* Manifest binary format:
 * [u16: entry_count] [u16: spine_count]
 * For each zip entry:  [u16: name_len] [name bytes...]
 * For each spine entry: [u16: zip_entry_index_for_this_spine_slot]
 *)
implement epub_store_manifest(pf_zip | (* *)) = let
  val entry_count = zip_get_entry_count()
  val spine_count = _app_epub_spine_count()
  val ec = _g0(entry_count): int
  val sc: int = if gt_int_int(spine_count, 32) then 32 else spine_count

  (* Calculate total manifest size *)
  (* Header: 4 bytes (2 u16s) *)
  (* Per entry: 2 + name_len bytes *)
  (* Per spine: 2 bytes *)
  fun calc_entries_size {k:nat} .<k>.
    (rem: int(k), idx: int, count: int, acc: int): int =
    if lte_g1(rem, 0) then acc
    else if gte_int_int(idx, count) then acc
    else let
      val nlen = zip_get_entry_name(idx, 0) (* writes name to sbuf *)
    in calc_entries_size(sub_g1(rem, 1), idx + 1, count, acc + 2 + nlen) end
  val entries_size = calc_entries_size(_checked_nat(ec), 0, ec, 0)
  val total_size = add_int_int(add_int_int(4, entries_size), mul_int_int(sc, 2))

in
  if lt_int_int(total_size, 4) then ward_promise_return<int>(0)
  else if gt_int_int(total_size, 262144) then ward_promise_return<int>(0)
  else let
    extern castfn _manifest_size(x: int): [n:int | n >= 4; n <= 1048576] int n
    val tsz = _manifest_size(total_size)
    val arr = ward_arr_alloc<byte>(tsz)
    (* Write header — tsz >= 4 guaranteed by check above *)
    extern castfn _u16(x: int): [v:nat | v < 65536] int v
    extern castfn _u16_off {n:int}(x: int, sz: int n): [i:nat | i + 2 <= n] int i
    val () = ward_arr_write_u16le(arr, 0, _u16(ec))
    val () = ward_arr_write_u16le(arr, 2, _u16(sc))

    (* Write entry names — read directly from ZIP name buffer, not sbuf *)
    fun write_entries {k:nat}{la:agz}{na:pos} .<k>.
      (rem: int(k), idx: int, count: int, off: int,
       arr: !ward_arr(byte, la, na), asz: int na): int =
      if lte_g1(rem, 0) then off
      else if gte_int_int(idx, count) then off
      else let
        val nlen = zip_get_entry_name(idx, 0)
        val name_off = _zip_entry_name_offset(idx)
        val () = ward_arr_write_u16le(arr, _u16_off(off, asz), _u16(nlen))
        (* Copy name bytes from ZIP name buffer to arr *)
        fun copy_name {k2:nat}{la2:agz}{na2:pos} .<k2>.
          (rem2: int(k2), i: int, name_len: int, base: int, noff: int,
           arr: !ward_arr(byte, la2, na2), asz: int na2): void =
          if lte_g1(rem2, 0) then ()
          else if gte_int_int(i, name_len) then ()
          else let
            val b = _zip_name_char(noff + i)
            val () = ward_arr_write_byte(arr, _ward_idx(base + i, asz), _checked_byte(band_int_int(b, 255)))
          in copy_name(sub_g1(rem2, 1), i + 1, name_len, base, noff, arr, asz) end
        val () = copy_name(_checked_nat(nlen), 0, nlen, off + 2, name_off, arr, asz)
      in write_entries(sub_g1(rem, 1), idx + 1, count, off + 2 + nlen, arr, asz) end
    val off1 = write_entries(_checked_nat(ec), 0, ec, 4, arr, tsz)

    (* Write spine→entry index mapping *)
    (* Spine paths in spine_buf are already fully qualified (include OPF dir) *)
    fun write_spine {k:nat}{la:agz}{na:pos} .<k>.
      (pf_z: ZIP_OPEN_OK |
       rem: int(k), si: int, scount: int, off: int,
       arr: !ward_arr(byte, la, na), asz: int na): void =
      if lte_g1(rem, 0) then ()
      else if gte_int_int(si, scount) then ()
      else let
        val sp_off = _app_epub_spine_offsets_get_i32(si)
        val sp_len = _app_epub_spine_lens_get_i32(si)
        val () = _app_copy_epub_spine_buf_to_sbuf(sp_off, 0, sp_len)
        val zip_idx = zip_find_entry(pf_z | sp_len)
        val idx_val: int = if lt_int_int(zip_idx, 0) then 65535 else zip_idx
        val () = ward_arr_write_u16le(arr, _u16_off(off, asz), _u16(idx_val))
      in write_spine(pf_z | sub_g1(rem, 1), si + 1, scount, off + 2, arr, asz) end
    val () = write_spine(pf_zip | _checked_nat(sc), 0, sc, off1, arr, tsz)

    (* Store to IDB *)
    val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
    val key = epub_build_manifest_key()
    val p = ward_idb_put(key, 20, borrow, tsz)
    val () = ward_arr_drop<byte>(frozen, borrow)
    val arr = ward_arr_thaw<byte>(frozen)
    val () = ward_arr_free<byte>(arr)
  in ward_promise_vow(p) end
end

(* ========== epub_load_manifest ========== *)

(* Helper to read u16 LE from ward_arr *)
fn _arr_read_u16 {l:agz}{n:pos}
  (a: !ward_arr(byte, l, n), off: int, cap: int n): int = let
  val lo = _ab(a, off, cap)
  val hi = _ab(a, off + 1, cap)
in add_int_int(lo, mul_int_int(hi, 256)) end

implement epub_load_manifest() = let
  val key = epub_build_manifest_key()
  val p = ward_idb_get(key, 20)
in
  ward_promise_then<int><int>(p,
    llam (data_len: int): ward_promise_chained(int) =>
      if lte_int_int(data_len, 4) then ward_promise_return<int>(0)
      else let
        val dl = _checked_pos(data_len)
        val arr = ward_idb_get_result(dl)
        val ec = _arr_read_u16(arr, 0, dl)
        val sc = _arr_read_u16(arr, 2, dl)
        val () = _app_set_epub_manifest_count(ec)
        val () = _app_set_epub_spine_count(sc)
        (* Parse entry names into manifest tables *)
        fun parse_entries {k:nat}{la:agz}{na:pos} .<k>.
          (rem: int(k), idx: int, count: int, off: int, name_pos: int,
           arr: !ward_arr(byte, la, na), asz: int na): int =
          if lte_g1(rem, 0) then off
          else if gte_int_int(idx, count) then off
          else if gt_int_int(off + 2, _g0(asz)) then off
          else let
            val nlen = _arr_read_u16(arr, off, asz)
            val () = _app_epub_manifest_offsets_set_i32(idx, name_pos)
            val () = _app_epub_manifest_lens_set_i32(idx, nlen)
            (* Copy name bytes from arr to manifest_names buffer *)
            fun copy_name {k2:nat}{la2:agz}{na2:pos} .<k2>.
              (rem2: int(k2), i: int, name_len: int, src_off: int, dst_off: int,
               arr: !ward_arr(byte, la2, na2), asz: int na2): void =
              if lte_g1(rem2, 0) then ()
              else if gte_int_int(i, name_len) then ()
              else if gte_int_int(src_off + i, _g0(asz)) then ()
              else let
                val b = _ab(arr, src_off + i, asz)
                val () = _app_epub_manifest_names_set_u8(dst_off + i, b)
              in copy_name(sub_g1(rem2, 1), i + 1, name_len, src_off, dst_off, arr, asz) end
            val () = copy_name(_checked_nat(nlen), 0, nlen, off + 2, name_pos, arr, asz)
          in parse_entries(sub_g1(rem, 1), idx + 1, count, off + 2 + nlen, name_pos + nlen, arr, asz) end
        val off1 = parse_entries(_checked_nat(ec), 0, ec, 4, 0, arr, dl)
        (* Parse spine→entry index mapping *)
        fun parse_spine {k:nat}{la:agz}{na:pos} .<k>.
          (rem: int(k), si: int, scount: int, off: int,
           arr: !ward_arr(byte, la, na), asz: int na): void =
          if lte_g1(rem, 0) then ()
          else if gte_int_int(si, scount) then ()
          else if gt_int_int(off + 2, _g0(asz)) then ()
          else let
            val zip_idx = _arr_read_u16(arr, off, asz)
            val () = _app_epub_spine_entry_idx_set(si, zip_idx)
          in parse_spine(sub_g1(rem, 1), si + 1, scount, off + 2, arr, asz) end
        val () = parse_spine(_checked_nat(sc), 0, sc, off1, arr, dl)
        val () = ward_arr_free<byte>(arr)
      in ward_promise_return<int>(1) end)
end

(* ========== epub_find_resource ========== *)

(* Linear scan of manifest names, comparing against sbuf[0..path_len-1].
 * Returns [r:int | r >= ~1] int(r) — -1 for not found, >= 0 for index. *)
implement epub_find_resource(path_len) = let
  val count = _app_epub_manifest_count()
  fun scan {k:nat} .<k>.
    (rem: int(k), idx: int, cnt: int, plen: int): [r:int | r >= ~1] int(r) =
    if lte_g1(rem, 0) then ~1
    else if gte_int_int(idx, cnt) then ~1
    else let
      val noff = _app_epub_manifest_offsets_get_i32(idx)
      val nlen = _app_epub_manifest_lens_get_i32(idx)
    in
      if neq_int_int(nlen, plen) then scan(sub_g1(rem, 1), idx + 1, cnt, plen)
      else if gt_int_int(_app_manifest_name_match_sbuf(noff, nlen, plen), 0) then let
        extern castfn _res_idx(x: int): [r:int | r >= ~1] int(r)
      in _res_idx(idx) end
      else scan(sub_g1(rem, 1), idx + 1, cnt, plen)
    end
in scan(_checked_nat(count), 0, count, path_len) end

(* ========== epub_set_book_id_from_library ========== *)

(* Constants eliminated: uses library_rec_ints/bytes as single source of truth.
 * Previously: #define LIB_REC_BYTES 608 (WRONG, was 620), hardcoded 152 (WRONG, was 155). *)

extern castfn _clamp_bid_len(x: int): [n:nat | n <= 64] int n

implement epub_set_book_id_from_library {i} (pf | book_index) = let
  prval _ = pf
  val rec_ints = library_rec_ints()
  val rec_bytes = library_rec_bytes()
  val base_bytes = mul_g1(book_index, rec_bytes)
  val base_ints = mul_g1(book_index, rec_ints)
  val bid_len0 = _app_lib_books_get_i32(_g0(add_g1(base_ints, 146)))
  val bid_len = if gt_int_int(bid_len0, 64) then 64 else bid_len0
  val bid_len = if lt_int_int(bid_len, 0) then 0 else bid_len
  val () = _app_copy_lib_book_id_to_epub(_g0(add_g1(base_bytes, 520)), bid_len)
  val () = _app_set_epub_book_id_len(bid_len)
in _clamp_bid_len(bid_len) end

(* ========== Search Index (2.2) ========== *)

(* Module-level castfns for search index functions *)
extern castfn _si_tcap {n:pos}(x: int, sz: int n): [m:nat | m < n] int m
extern castfn _si_bv(x: int): [v:nat | v < 256] int v
extern castfn _si_u16v(x: int): [v:nat | v < 65536] int v
extern castfn _si_u16_off {n:pos}(x: int, sz: int n): [i:nat | i + 2 <= n] int i
extern castfn _si_i32_off {n:pos}(x: int, sz: int n): [i:nat | i + 4 <= n] int i
extern castfn _si_rcap {n:pos}(x: int, sz: int n): [i:nat | i + 2 <= n] int i
extern castfn _si_buf_size(x: int): [n:pos | n <= 1048576] int n

(* Fold uppercase ASCII [65-90] to lowercase [97-122].
 * Solver verifies: 65+32=97, 90+32=122. *)
fn _fold_upper {b:int | b >= 65; b <= 90}
  (b: int(b)): [out:int | out >= 97; out <= 122] int(out) =
  add_g1(b, 32)

(* Fold Latin-1 diacritics (0xC0-0xFF after 0xC3 prefix in UTF-8).
 * byte is the second byte of a 0xC3 two-byte sequence (0x80-0xBF = 128-191).
 * Returns > 0: folded ASCII letter (proven <= 122, thus NOT a diacritics byte).
 * Returns 0: non-letter passthrough (multiply sign, thorn, eth, etc.).
 *
 * Toddler test: can't return 200 — violates out <= 122. *)
fn _fold_latin1 {b:int | b >= 128; b <= 191}
  (b: int(b)): [out:nat | out <= 122] int(out) = let
  extern castfn _fl(x: int): [r:nat | r <= 122] int(r)
in
  (* À-Æ = 192-198 → 0x80-0x86 = 128-134 → 'a' = 97 *)
  if lte_g1(b, 134) then _fl(97) (* a *)
  (* Ç = 199 → 0x87 = 135 → 'c' = 99 *)
  else if eq_g1(b, 135) then _fl(99)
  (* È-Ë = 200-203 → 0x88-0x8B = 136-139 → 'e' = 101 *)
  else if lte_g1(b, 139) then _fl(101)
  (* Ì-Ï = 204-207 → 0x8C-0x8F = 140-143 → 'i' = 105 *)
  else if lte_g1(b, 143) then _fl(105)
  (* Ð = 208 → 0x90 = 144 → 'd' = 100 *)
  else if eq_g1(b, 144) then _fl(100)
  (* Ñ = 209 → 0x91 = 145 → 'n' = 110 *)
  else if eq_g1(b, 145) then _fl(110)
  (* Ò-Ö = 210-214 → 0x92-0x96 = 146-150 → 'o' = 111 *)
  else if lte_g1(b, 150) then _fl(111)
  (* × = 215 → 0x97 = 151 → passthrough *)
  else if eq_g1(b, 151) then _fl(0)
  (* Ø = 216 → 0x98 = 152 → 'o' = 111 *)
  else if eq_g1(b, 152) then _fl(111)
  (* Ù-Ü = 217-220 → 0x99-0x9C = 153-156 → 'u' = 117 *)
  else if lte_g1(b, 156) then _fl(117)
  (* Ý = 221 → 0x9D = 157 → 'y' = 121 *)
  else if eq_g1(b, 157) then _fl(121)
  (* Þ = 222 → 0x9E = 158 → passthrough *)
  else if eq_g1(b, 158) then _fl(0)
  (* ß = 223 → 0x9F = 159 → 's' = 115 *)
  else if eq_g1(b, 159) then _fl(115)
  (* à-æ = 224-230 → 0xA0-0xA6 = 160-166 → 'a' = 97 *)
  else if lte_g1(b, 166) then _fl(97)
  (* ç = 231 → 0xA7 = 167 → 'c' = 99 *)
  else if eq_g1(b, 167) then _fl(99)
  (* è-ë = 232-235 → 0xA8-0xAB = 168-171 → 'e' = 101 *)
  else if lte_g1(b, 171) then _fl(101)
  (* ì-ï = 236-239 → 0xAC-0xAF = 172-175 → 'i' = 105 *)
  else if lte_g1(b, 175) then _fl(105)
  (* ð = 240 → 0xB0 = 176 → 'd' = 100 *)
  else if eq_g1(b, 176) then _fl(100)
  (* ñ = 241 → 0xB1 = 177 → 'n' = 110 *)
  else if eq_g1(b, 177) then _fl(110)
  (* ò-ö = 242-246 → 0xB2-0xB6 = 178-182 → 'o' = 111 *)
  else if lte_g1(b, 182) then _fl(111)
  (* ÷ = 247 → 0xB7 = 183 → passthrough *)
  else if eq_g1(b, 183) then _fl(0)
  (* ø = 248 → 0xB8 = 184 → 'o' = 111 *)
  else if eq_g1(b, 184) then _fl(111)
  (* ù-ü = 249-252 → 0xB9-0xBC = 185-188 → 'u' = 117 *)
  else if lte_g1(b, 188) then _fl(117)
  (* ý = 253 → 0xBD = 189 → 'y' = 121 *)
  else if eq_g1(b, 189) then _fl(121)
  (* þ = 254 → 0xBE = 190 → passthrough *)
  else if eq_g1(b, 190) then _fl(0)
  (* ÿ = 255 → 0xBF = 191 → 'y' = 121 *)
  else _fl(121)
end

(* Check if a tag name (by length and first letter) is a block-level element.
 * Used to insert space separators between block content.
 * Length-first dispatch avoids string comparison for most tags. *)
fn _is_block_tag {lb:agz}{nb:pos}
  (buf: !ward_arr_borrow(byte, lb, nb), tag_off: int, tag_len: int, cap: int nb): bool =
  if eq_int_int(tag_len, 1) then let
    val c = ward_arr_read<byte>(buf, _ward_idx(tag_off, cap))
  in eq_int_int(byte2int0(c), 112) end (* p *)
  else if eq_int_int(tag_len, 2) then let
    val c = ward_arr_read<byte>(buf, _ward_idx(tag_off, cap))
    val ch = byte2int0(c)
  in (* br, dd, dl, dt, hr, li, ol, td, th, tr, ul *)
    eq_int_int(ch, 98) || eq_int_int(ch, 100) || eq_int_int(ch, 104) ||
    eq_int_int(ch, 108) || eq_int_int(ch, 111) || eq_int_int(ch, 116) ||
    eq_int_int(ch, 117)
  end
  else if eq_int_int(tag_len, 3) then let
    val c = ward_arr_read<byte>(buf, _ward_idx(tag_off, cap))
    val ch = byte2int0(c)
  in (* div, nav, pre *)
    eq_int_int(ch, 100) || eq_int_int(ch, 110) || eq_int_int(ch, 112)
  end
  else if eq_int_int(tag_len, 4) then let
    val c = ward_arr_read<byte>(buf, _ward_idx(tag_off, cap))
  in eq_int_int(byte2int0(c), 109) end (* main *)
  else if eq_int_int(tag_len, 5) then let
    val c = ward_arr_read<byte>(buf, _ward_idx(tag_off, cap))
    val ch = byte2int0(c)
  in (* aside, table, tbody, tfoot, thead *)
    eq_int_int(ch, 97) || eq_int_int(ch, 116)
  end
  else if eq_int_int(tag_len, 6) then let
    val c = ward_arr_read<byte>(buf, _ward_idx(tag_off, cap))
    val ch = byte2int0(c)
  in (* figure, footer, header *)
    eq_int_int(ch, 102) || eq_int_int(ch, 104)
  end
  else if eq_int_int(tag_len, 7) then let
    val c = ward_arr_read<byte>(buf, _ward_idx(tag_off, cap))
    val ch = byte2int0(c)
  in (* article, details, section *)
    eq_int_int(ch, 97) || eq_int_int(ch, 100) || eq_int_int(ch, 115)
  end
  else if eq_int_int(tag_len, 10) then let
    val c = ward_arr_read<byte>(buf, _ward_idx(tag_off, cap))
    val ch = byte2int0(c)
  in (* blockquote, figcaption *)
    eq_int_int(ch, 98) || eq_int_int(ch, 102)
  end
  else false

(* Check if tag is "script" (6 bytes: 115,99,114,105,112,116) or
 * "style" (5 bytes: 115,116,121,108,101) *)
fn _is_skip_tag {lb:agz}{nb:pos}
  (buf: !ward_arr_borrow(byte, lb, nb), tag_off: int, tag_len: int, cap: int nb): bool =
  if eq_int_int(tag_len, 6) then let
    val c0 = byte2int0(ward_arr_read<byte>(buf, _ward_idx(tag_off, cap)))
    val c1 = byte2int0(ward_arr_read<byte>(buf, _ward_idx(tag_off + 1, cap)))
  in eq_int_int(c0, 115) && eq_int_int(c1, 99) end (* sc... = script *)
  else if eq_int_int(tag_len, 5) then let
    val c0 = byte2int0(ward_arr_read<byte>(buf, _ward_idx(tag_off, cap)))
    val c1 = byte2int0(ward_arr_read<byte>(buf, _ward_idx(tag_off + 1, cap)))
  in eq_int_int(c0, 115) && eq_int_int(c1, 116) end (* st... = style *)
  else false

(* Extract plain text from SAX buffer into a text output buffer.
 * Folds diacritics and lowercases as it goes. Records offset map runs.
 *
 * Parameters:
 *   sax_buf: borrowed SAX buffer from ward_xml_parse_html
 *   sax_len: length of SAX buffer
 *   text_arr: output buffer for folded plain text
 *   text_cap: capacity of text_arr
 *   run_arr: output buffer for offset map runs (u16 pairs: text_off, sax_pos)
 *   run_cap: capacity of run_arr (in bytes, must be divisible by 4)
 *
 * Returns @(text_len, run_count) *)
extern fun _extract_chapter_text
  {ls:agz}{ns:pos}{lt:agz}{nt:pos}{lr:agz}{nr:pos}
  (sax_buf: !ward_arr_borrow(byte, ls, ns), sax_len: int ns,
   text_arr: !ward_arr(byte, lt, nt), text_cap: int nt,
   run_arr: !ward_arr(byte, lr, nr), run_cap: int nr
  ): @(int, int) = "ext#"

implement _extract_chapter_text
  (sax_buf, sax_len, text_arr, text_cap, run_arr, run_cap) = let

  fun walk {ls:agz}{ns:pos}{lt:agz}{nt:pos}{lr:agz}{nr:pos}{k:nat} .<k>.
    (rem: int(k),
     sax: !ward_arr_borrow(byte, ls, ns), slen: int ns,
     txt: !ward_arr(byte, lt, nt), tcap: int nt,
     runs: !ward_arr(byte, lr, nr), rcap: int nr,
     sax_pos: int, txt_off: int, run_count: int,
     skip_depth: int, pending_c3: int): @(int, int) =
    if lte_g1(rem, 0) then @(txt_off, run_count)
    else if gte_int_int(sax_pos, _g0(slen)) then @(txt_off, run_count)
    else if gte_int_int(txt_off, _g0(tcap)) then @(txt_off, run_count)
    else let
      val opc = ward_xml_opcode(sax, _ward_idx(sax_pos, slen))
    in
      if eq_int_int(opc, 1) then let
        (* ELEMENT_OPEN *)
        val @(tag_off, tag_len, _attr_count, next_pos) =
          ward_xml_element_open(sax, _ward_idx(sax_pos, slen), slen)
      in
        if lt_int_int(next_pos, 0) then @(txt_off, run_count)
        else if gt_int_int(skip_depth, 0) then
          walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
               next_pos, txt_off, run_count, skip_depth + 1, pending_c3)
        else if _is_skip_tag(sax, tag_off, tag_len, slen) then
          walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
               next_pos, txt_off, run_count, 1, pending_c3)
        else let
          (* If block element, append space *)
          val is_block = _is_block_tag(sax, tag_off, tag_len, slen)
        in
          if is_block then
            if gt_int_int(txt_off, 0) then
              if lt_int_int(txt_off, _g0(tcap)) then let
                val () = ward_arr_write_byte(txt, _si_tcap(txt_off, tcap), _si_bv(32))
              in walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
                      next_pos, txt_off + 1, run_count, 0, pending_c3)
              end
              else @(txt_off, run_count)
            else walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
                      next_pos, txt_off, run_count, 0, pending_c3)
          else walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
                    next_pos, txt_off, run_count, 0, pending_c3)
        end
      end
      else if eq_int_int(opc, 2) then let
        (* ELEMENT_CLOSE: 1 byte opcode *)
        val next_pos = sax_pos + 1
      in
        if gt_int_int(skip_depth, 0) then
          walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
               next_pos, txt_off, run_count, skip_depth - 1, pending_c3)
        else
          walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
               next_pos, txt_off, run_count, 0, pending_c3)
      end
      else if eq_int_int(opc, 3) then let
        (* TEXT *)
        val @(text_off, text_len, next_pos) =
          ward_xml_read_text(sax, _ward_idx(sax_pos, slen), slen)
      in
        if lt_int_int(next_pos, 0) then @(txt_off, run_count)
        else if gt_int_int(skip_depth, 0) then
          walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
               next_pos, txt_off, run_count, skip_depth, pending_c3)
        else if lte_int_int(text_len, 0) then
          walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
               next_pos, txt_off, run_count, 0, pending_c3)
        else let
          (* Record run entry: (txt_off, sax_pos) *)
          val run_off = mul_int_int(run_count, 4)
          val new_rc =
            if lt_int_int(run_off + 4, _g0(rcap)) then let
              val () = ward_arr_write_u16le(runs, _si_rcap(run_off, rcap), _si_u16v(txt_off))
              val () = ward_arr_write_u16le(runs, _si_rcap(run_off + 2, rcap), _si_u16v(sax_pos))
            in run_count + 1 end
            else run_count
          (* Copy text bytes with folding *)
          fun fold_text {ls2:agz}{ns2:pos}{lt2:agz}{nt2:pos}{k2:nat} .<k2>.
            (rem2: int(k2),
             sax2: !ward_arr_borrow(byte, ls2, ns2), slen2: int ns2,
             txt2: !ward_arr(byte, lt2, nt2), tcap2: int nt2,
             si: int, send: int, ti: int, pc3: int): @(int, int) =
            if lte_g1(rem2, 0) then @(ti, pc3)
            else if gte_int_int(si, send) then @(ti, pc3)
            else if gte_int_int(ti, _g0(tcap2)) then @(ti, pc3)
            else let
              val b = byte2int0(ward_arr_read<byte>(sax2, _ward_idx(si, slen2)))
            in
              if eq_int_int(pc3, 1) then let
                (* Previous byte was 0xC3 — this is the second byte *)
                val b1 = g1ofg0(b)
              in
                if gte_g1(b1, 128) then
                  if lte_g1(b1, 191) then let
                    val folded = _fold_latin1(b1)
                  in
                    if gt_g1(folded, 0) then let
                      val () = ward_arr_write_byte(txt2, _si_tcap(ti, tcap2), _si_bv(_g0(folded)))
                    in fold_text(sub_g1(rem2, 1), sax2, slen2, txt2, tcap2,
                                 si + 1, send, ti + 1, 0) end
                    else
                      (* Non-letter: output original 2 bytes (0xC3 + b) *)
                      if lt_int_int(ti + 1, _g0(tcap2)) then let
                        val () = ward_arr_write_byte(txt2, _si_tcap(ti, tcap2), _si_bv(195))
                        val () = ward_arr_write_byte(txt2, _si_tcap(ti + 1, tcap2), _si_bv(b))
                      in fold_text(sub_g1(rem2, 1), sax2, slen2, txt2, tcap2,
                                   si + 1, send, ti + 2, 0) end
                      else @(ti, 0)
                  end
                  else let
                    (* Out of Latin-1 range — output raw bytes *)
                    val () = ward_arr_write_byte(txt2, _si_tcap(ti, tcap2), _si_bv(195))
                  in
                    if lt_int_int(ti + 1, _g0(tcap2)) then let
                      val () = ward_arr_write_byte(txt2, _si_tcap(ti + 1, tcap2), _si_bv(b))
                    in fold_text(sub_g1(rem2, 1), sax2, slen2, txt2, tcap2,
                                 si + 1, send, ti + 2, 0) end
                    else @(ti + 1, 0)
                  end
                else let
                  (* byte < 128 after 0xC3 — shouldn't happen, output raw *)
                  val () = ward_arr_write_byte(txt2, _si_tcap(ti, tcap2), _si_bv(195))
                in
                  if lt_int_int(ti + 1, _g0(tcap2)) then let
                    val () = ward_arr_write_byte(txt2, _si_tcap(ti + 1, tcap2), _si_bv(b))
                  in fold_text(sub_g1(rem2, 1), sax2, slen2, txt2, tcap2,
                               si + 1, send, ti + 2, 0) end
                  else @(ti + 1, 0)
                end
              end
              (* 0xC3 prefix — set pending *)
              else if eq_int_int(b, 195) then
                fold_text(sub_g1(rem2, 1), sax2, slen2, txt2, tcap2,
                          si + 1, send, ti, 1)
              (* Uppercase ASCII [65-90] → lowercase *)
              else let val b1 = g1ofg0(b) in
                if gte_g1(b1, 65) then
                  if lte_g1(b1, 90) then let
                    val folded = _fold_upper(b1)
                    val () = ward_arr_write_byte(txt2, _si_tcap(ti, tcap2), _si_bv(_g0(folded)))
                  in fold_text(sub_g1(rem2, 1), sax2, slen2, txt2, tcap2,
                               si + 1, send, ti + 1, 0) end
                  else let
                    (* Regular byte — copy as-is *)
                    val () = ward_arr_write_byte(txt2, _si_tcap(ti, tcap2), _si_bv(b))
                  in fold_text(sub_g1(rem2, 1), sax2, slen2, txt2, tcap2,
                               si + 1, send, ti + 1, 0) end
                else let
                  val () = ward_arr_write_byte(txt2, _si_tcap(ti, tcap2), _si_bv(b))
                in fold_text(sub_g1(rem2, 1), sax2, slen2, txt2, tcap2,
                             si + 1, send, ti + 1, 0) end
              end
            end
          val @(new_ti, new_pc3) = fold_text(
            _checked_nat(text_len), sax, slen, txt, tcap,
            text_off, text_off + text_len, txt_off, pending_c3)
        in
          walk(sub_g1(rem, 1), sax, slen, txt, tcap, runs, rcap,
               next_pos, new_ti, new_rc, 0, new_pc3)
        end
      end
      else (* Unknown opcode — skip *)
        @(txt_off, run_count)
    end
in
  walk(_checked_nat(_g0(sax_len)), sax_buf, sax_len,
       text_arr, text_cap, run_arr, run_cap,
       0, 0, 0, 0, 0)
end

(* Build 20-char IDB search key: {16 hex book_id}s{3 hex spine_idx} *)
implement epub_build_search_key(pf | spine_idx, _count) = let
  prval SPINE_ENTRY() = pf
  val b0 = _app_epub_book_id_get_u8(0)
  val b1 = _app_epub_book_id_get_u8(1)
  val b2 = _app_epub_book_id_get_u8(2)
  val b3 = _app_epub_book_id_get_u8(3)
  val b4 = _app_epub_book_id_get_u8(4)
  val b5 = _app_epub_book_id_get_u8(5)
  val b6 = _app_epub_book_id_get_u8(6)
  val b7 = _app_epub_book_id_get_u8(7)
  val bld = ward_text_build(20)
  val bld = ward_text_putc(bld, 0, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b0, 255), 16))))
  val bld = ward_text_putc(bld, 1, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b0, 255), 16))))
  val bld = ward_text_putc(bld, 2, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b1, 255), 16))))
  val bld = ward_text_putc(bld, 3, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b1, 255), 16))))
  val bld = ward_text_putc(bld, 4, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b2, 255), 16))))
  val bld = ward_text_putc(bld, 5, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b2, 255), 16))))
  val bld = ward_text_putc(bld, 6, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b3, 255), 16))))
  val bld = ward_text_putc(bld, 7, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b3, 255), 16))))
  val bld = ward_text_putc(bld, 8, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b4, 255), 16))))
  val bld = ward_text_putc(bld, 9, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b4, 255), 16))))
  val bld = ward_text_putc(bld, 10, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b5, 255), 16))))
  val bld = ward_text_putc(bld, 11, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b5, 255), 16))))
  val bld = ward_text_putc(bld, 12, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b6, 255), 16))))
  val bld = ward_text_putc(bld, 13, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b6, 255), 16))))
  val bld = ward_text_putc(bld, 14, _safe_hex_char(_hex_nibble(div_int_int(band_int_int(b7, 255), 16))))
  val bld = ward_text_putc(bld, 15, _safe_hex_char(_hex_nibble(mod_int_int(band_int_int(b7, 255), 16))))
  (* 's' separator: ASCII 115, SAFE_CHAR [97-122] *)
  val bld = ward_text_putc(bld, 16, 115)
  (* 3-digit hex spine index *)
  val si = band_int_int(_g0(spine_idx), 4095)
  val bld = ward_text_putc(bld, 17, _safe_hex_char(_hex_nibble(div_int_int(si, 256))))
  val bld = ward_text_putc(bld, 18, _safe_hex_char(_hex_nibble(mod_int_int(div_int_int(si, 16), 16))))
  val bld = ward_text_putc(bld, 19, _safe_hex_char(_hex_nibble(mod_int_int(si, 16))))
in ward_text_done(bld) end

(* Process one chapter: load resource from IDB, parse HTML, extract text,
 * store search index record. Returns chained promise. *)
fn _build_chapter_search_index {c,t:nat | c < t}
  (pf: SPINE_ORDERED(c, t) | ch_idx: int(c), ch_count: int(t)): ward_promise_chained(int) = let
  (* Get spine entry index for this chapter *)
  val entry_idx = _app_epub_spine_entry_idx_get(_g0(ch_idx))
  val key = epub_build_resource_key(entry_idx)
  val p = ward_idb_get(key, 20)
  val saved_idx = ch_idx
  val saved_count = ch_count
in
  ward_promise_then<int><int>(p,
    llam (data_len: int): ward_promise_chained(int) =>
      if lte_int_int(data_len, 0) then ward_promise_return<int>(1)
      else let
        val dl = _checked_pos(data_len)
        val html_arr = ward_idb_get_result(dl)
        val @(frozen, borrow) = ward_arr_freeze<byte>(html_arr)
        (* Parse HTML to SAX *)
        val sax_len = ward_xml_parse_html(borrow, dl)
        val () = ward_arr_drop<byte>(frozen, borrow)
        val html_arr = ward_arr_thaw<byte>(frozen)
        val () = ward_arr_free<byte>(html_arr)
      in
        if lte_int_int(sax_len, 0) then ward_promise_return<int>(1)
        else let
          val sl = _checked_pos(sax_len)
          val sax_arr = ward_xml_get_result(sl)
          val @(sax_frozen, sax_borrow) = ward_arr_freeze<byte>(sax_arr)
          (* Allocate text and run buffers *)
          val text_sz = _si_buf_size(65536) (* 64K text buffer *)
          val run_sz = _si_buf_size(16384) (* 16K = 4096 runs * 4 bytes *)
          val text_buf = ward_arr_alloc<byte>(text_sz)
          val run_buf = ward_arr_alloc<byte>(run_sz)
          (* Extract text *)
          val @(text_len, run_count) =
            _extract_chapter_text(sax_borrow, sl,
              text_buf, text_sz, run_buf, run_sz)
          val () = ward_arr_drop<byte>(sax_frozen, sax_borrow)
          val sax_arr = ward_arr_thaw<byte>(sax_frozen)
          val () = ward_arr_free<byte>(sax_arr)
          (* Build final IDB record:
           * Header (8 bytes): [u32 text_len] [u16 run_count] [u16 reserved]
           * Runs (run_count * 4 bytes): per run [u16 text_off] [u16 sax_pos]
           * Text (text_len bytes): folded plain text *)
          val run_bytes = mul_int_int(run_count, 4)
          val total_size = add_int_int(8, add_int_int(run_bytes, text_len))
        in
          if lte_int_int(total_size, 8) then let
            val () = ward_arr_free<byte>(text_buf)
            val () = ward_arr_free<byte>(run_buf)
          in ward_promise_return<int>(1) end
          else if gt_int_int(total_size, 1048576) then let
            val () = ward_arr_free<byte>(text_buf)
            val () = ward_arr_free<byte>(run_buf)
          in ward_promise_return<int>(1) end
          else let
            val tsz = _si_buf_size(total_size)
            val final_arr = ward_arr_alloc<byte>(tsz)
            (* Write header *)
            val () = ward_arr_write_i32(final_arr, _si_i32_off(0, tsz), text_len)
            val () = ward_arr_write_u16le(final_arr, _si_u16_off(4, tsz), _si_u16v(run_count))
            val () = ward_arr_write_u16le(final_arr, _si_u16_off(6, tsz), _si_u16v(0))
            (* Copy run data *)
            fun copy_runs {la:agz}{na:pos}{lr:agz}{nr:pos}{k:nat} .<k>.
              (rem: int(k), i: int, cnt: int,
               dst: !ward_arr(byte, la, na), dsz: int na,
               src: !ward_arr(byte, lr, nr), ssz: int nr): void =
              if lte_g1(rem, 0) then ()
              else if gte_int_int(i, cnt) then ()
              else let
                val src_off = mul_int_int(i, 4)
                val dst_off = 8 + src_off
                val v0 = _ab(src, src_off, ssz)
                val v1 = _ab(src, src_off + 1, ssz)
                val v2 = _ab(src, src_off + 2, ssz)
                val v3 = _ab(src, src_off + 3, ssz)
                val () = _wb(dst, dst_off, v0, dsz)
                val () = _wb(dst, dst_off + 1, v1, dsz)
                val () = _wb(dst, dst_off + 2, v2, dsz)
                val () = _wb(dst, dst_off + 3, v3, dsz)
              in copy_runs(sub_g1(rem, 1), i + 1, cnt, dst, dsz, src, ssz) end
            val () = copy_runs(_checked_nat(run_count), 0, run_count,
              final_arr, tsz, run_buf, run_sz)
            val () = ward_arr_free<byte>(run_buf)
            (* Copy text data *)
            val text_base = 8 + run_bytes
            fun copy_text {la:agz}{na:pos}{lt2:agz}{nt2:pos}{k:nat} .<k>.
              (rem: int(k), i: int, tlen: int,
               dst: !ward_arr(byte, la, na), dsz: int na,
               src: !ward_arr(byte, lt2, nt2), ssz: int nt2,
               base: int): void =
              if lte_g1(rem, 0) then ()
              else if gte_int_int(i, tlen) then ()
              else let
                val () = _wb(dst, base + i, _ab(src, i, ssz), dsz)
              in copy_text(sub_g1(rem, 1), i + 1, tlen, dst, dsz, src, ssz, base) end
            val () = copy_text(_checked_nat(text_len), 0, text_len,
              final_arr, tsz, text_buf, text_sz, text_base)
            val () = ward_arr_free<byte>(text_buf)
            (* Store to IDB *)
            val @(final_frozen, final_borrow) = ward_arr_freeze<byte>(final_arr)
            val search_key = epub_build_search_key(SPINE_ENTRY() | saved_idx, saved_count)
            val p2 = ward_idb_put(search_key, 20, final_borrow, tsz)
            val () = ward_arr_drop<byte>(final_frozen, final_borrow)
            val final_arr = ward_arr_thaw<byte>(final_frozen)
            val () = ward_arr_free<byte>(final_arr)
          in ward_promise_vow(p2) end
        end
      end)
end

(* Store search index for all chapters. Sequential promise chain. *)
implement epub_store_search_index() = let
  val count0 = epub_get_chapter_count()
  val count = count0: int
  fun loop {c:nat}{t:nat | c <= t; t <= 256}{k:nat} .<k>.
    (rem: int(k), idx: int(c), total: int(t)): ward_promise_chained(int) =
    if lte_g1(rem, 0) then ward_promise_return<int>(1)
    else if gte_g1(idx, total) then ward_promise_return<int>(1)
    else let
      val saved_idx = add_g1(idx, 1)
      val saved_total = total
      val saved_rem = sub_g1(rem, 1)
      val p = _build_chapter_search_index(SPINE_ENTRY() | idx, total)
    in
      ward_promise_then<int><int>(p,
        llam (_status: int): ward_promise_chained(int) =>
          loop(saved_rem, saved_idx, saved_total))
    end
in loop(count0, 0, count0) end

(* Delete all IDB content for current book: manifest, cover, search keys.
 * Fire-and-forget: each ward_idb_delete returns a promise which we discard.
 * Termination: _delete_search_keys loop bounded by sc-idx via dependent int. *)
implement epub_delete_book_data {sc} (spine_count) = let
  (* sc <= 256 from signature, needed for epub_build_search_key's t <= 256 *)
  (* Delete manifest key *)
  val manifest_key = epub_build_manifest_key()
  val () = ward_promise_discard<int>(ward_idb_delete(manifest_key, 20))
  (* Delete cover key *)
  val cover_key = epub_build_cover_key()
  val () = ward_promise_discard<int>(ward_idb_delete(cover_key, 20))
  (* Delete search index keys for each spine entry *)
  fun _delete_search_keys {idx:nat}{t:nat | idx <= t; t <= 256}{k:nat} .<k>.
    (rem: int(k), idx: int(idx), total: int(t)): void =
    if lte_g1(rem, 0) then ()
    else if gte_g1(idx, total) then ()
    else let
      val search_key = epub_build_search_key(SPINE_ENTRY() | idx, total)
      val () = ward_promise_discard<int>(ward_idb_delete(search_key, 20))
    in _delete_search_keys(sub_g1(rem, 1), add_g1(idx, 1), total) end
in _delete_search_keys(spine_count, 0, spine_count) end
