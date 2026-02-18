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

staload "./arith.sats"

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
  val () = _app_set_epub_state(0)
  val () = _app_set_epub_spine_path_count(0)
  val () = _app_set_epub_spine_path_pos(0)
in end

(* ========== Simple accessors ========== *)

implement epub_get_state() = g1ofg0(_app_epub_state())

implement epub_get_progress() = 0

implement epub_get_error(_) = 0

implement epub_start_import(_) = 0

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

implement epub_get_chapter_key(_, _) = 0

implement epub_continue() = ()

implement epub_on_file_open(_, _) = ()

implement epub_on_decompress(_, _) = ()

implement epub_on_db_open(_) = ()

implement epub_on_db_put(_) = ()

implement epub_cancel() = _app_set_epub_state(0)

(* TOC stubs *)
implement epub_get_toc_count() = 0

implement epub_get_toc_label(_, _) = 0

implement epub_get_toc_chapter(_) = 0 - 1

implement epub_get_toc_level(_) = 0

implement epub_get_chapter_title(_, _) = 0

(* Serialization stubs *)
implement epub_serialize_metadata() = 0

implement epub_restore_metadata(_) = 0

implement epub_reset() = epub_init()

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
        fun find_last_slash(i: int, last: int, plen: int): int =
          if gte_int_int(i, plen) then last
          else if eq_int_int(_app_epub_opf_path_get_u8(i), 47) then find_last_slash(i + 1, i, plen)
          else find_last_slash(i + 1, last, plen)
        val last_slash = find_last_slash(0, 0 - 1, path_len)
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
  (* book_id is now set by sha256_file_hash in quire.dats import path,
   * not extracted from dc:identifier. See BOOK_IDENTITY_IS_CONTENT_HASH. *)
  val spine_count = _opf_count_spine(arr, len)
  val () = _app_set_epub_spine_count(spine_count)
  val () = _opf_resolve_spine(arr, len, spine_count)
in
  _app_set_epub_state(8); (* EPUB_STATE_DONE *)
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
