(* annotation.dats — Highlight/annotation storage implementation
 *
 * Annotations stored in C static arrays (up to 256 per book).
 * Each annotation: chapter (u16), start_offset (u32), end_offset (u32),
 * timestamp (u32). Text content not stored in this phase — just range.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./annotation.sats"
staload "./arith.sats"
staload "./dom.sats"
staload "./quire_ext.sats"
staload "./../vendor/ward/lib/memory.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload "./../vendor/ward/lib/dom.sats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload "./../vendor/ward/lib/blob.sats"
staload _ = "./../vendor/ward/lib/blob.dats"
staload UN = "prelude/SATS/unsafe.sats"

extern castfn _byte {c:int | 0 <= c; c <= 255} (c: int c): byte
extern castfn _checked_pos(x: int): [n:pos] int n
extern castfn _checked_url_len(x: int): [n:pos | n < 4096] int n

(* C static storage for annotations — up to 256 *)
%{
#define _ANNOT_MAX 256
#define _ANNOT_FIELDS 4  /* chapter, start, end, timestamp */
static int _annot_data[_ANNOT_MAX * _ANNOT_FIELDS];
static int _annot_count = 0;
%}

extern fun _annot_get_count(): int = "mac#"
extern fun _annot_set_count(v: int): void = "mac#"
extern fun _annot_get_field(idx: int, field: int): int = "mac#"
extern fun _annot_set_field(idx: int, field: int, v: int): void = "mac#"

%{
int _annot_get_count(void) { return _annot_count; }
void _annot_set_count(int v) { _annot_count = v; }
int _annot_get_field(int idx, int field) {
  if (idx < 0 || idx >= _annot_count || field < 0 || field >= _ANNOT_FIELDS) return 0;
  return _annot_data[idx * _ANNOT_FIELDS + field];
}
void _annot_set_field(int idx, int field, int v) {
  if (idx < 0 || idx >= _ANNOT_MAX || field < 0 || field >= _ANNOT_FIELDS) return;
  _annot_data[idx * _ANNOT_FIELDS + field] = v;
}
%}

extern castfn _clamp_annot_count(x: int): [n:nat | n <= 256] int(n)

implement annotation_init() = _annot_set_count(0)

implement annotation_get_count() = let
  val c = _annot_get_count()
in
  if c >= 0 then
    if c <= MAX_ANNOTATIONS then _clamp_annot_count(c)
    else _clamp_annot_count(0)
  else _clamp_annot_count(0)
end

implement annotation_add{c,s,e,t}(pf | chapter, start_off, end_off, total_chapters) = let
  prval ANNOTATION_OK() = pf
  val count = _annot_get_count()
in
  if lt_int_int(count, MAX_ANNOTATIONS) then let
    val () = _annot_set_field(count, 0, chapter)
    val () = _annot_set_field(count, 1, start_off)
    val () = _annot_set_field(count, 2, end_off)
    val () = _annot_set_field(count, 3, 0) (* timestamp — set externally *)
    val () = _annot_set_count(count + 1)
  in end
  else ()
end

implement annotation_remove(idx) = let
  val count = _annot_get_count()
in
  if gte_int_int(idx, 0) then
    if lt_int_int(idx, count) then let
      (* Shift remaining annotations down *)
      fun shift {k:nat} .<k>.
        (rem: int(k), src: int, cnt: int): void =
        if lte_g1(rem, 0) then ()
        else if gte_int_int(src, cnt) then ()
        else let
          val () = _annot_set_field(src - 1, 0, _annot_get_field(src, 0))
          val () = _annot_set_field(src - 1, 1, _annot_get_field(src, 1))
          val () = _annot_set_field(src - 1, 2, _annot_get_field(src, 2))
          val () = _annot_set_field(src - 1, 3, _annot_get_field(src, 3))
        in shift(sub_g1(rem, 1), src + 1, cnt) end
      val () = shift(_checked_nat(count - idx), idx + 1, count)
      val () = _annot_set_count(count - 1)
    in end
    else ()
  else ()
end

implement annotation_get_chapter{n}{i}(count, idx) = let
  val v = _annot_get_field(idx, 0)
in if v >= 0 then _checked_nat(v) else _checked_nat(0) end

implement annotation_get_start{n}{i}(count, idx) = let
  val v = _annot_get_field(idx, 1)
in if v >= 0 then _checked_nat(v) else _checked_nat(0) end

implement annotation_get_end{n}{i}(count, idx) = let
  val v = _annot_get_field(idx, 2)
in if v >= 0 then _checked_nat(v) else _checked_nat(0) end

implement annotation_get_timestamp{n}{i}(count, idx) = _annot_get_field(idx, 3)

(* Export annotations as Markdown.
 * Builds "# Annotations\n\nN highlights\n\n*Exported from Quire*\n"
 * in a ward_arr, extracts raw ptr for JS bridge call, downloads as .md file. *)
implement annotation_export_markdown() = let
  val count = _annot_get_count()
in
  if gt_int_int(count, 0) then let
    (* Build markdown content — 51 bytes *)
    val data_arr = ward_arr_alloc<byte>(51)
    (* "# Annotations\n\n" = 15 bytes *)
    val () = ward_arr_set<byte>(data_arr, 0, _byte(35))
    val () = ward_arr_set<byte>(data_arr, 1, _byte(32))
    val () = ward_arr_set<byte>(data_arr, 2, _byte(65))
    val () = ward_arr_set<byte>(data_arr, 3, _byte(110))
    val () = ward_arr_set<byte>(data_arr, 4, _byte(110))
    val () = ward_arr_set<byte>(data_arr, 5, _byte(111))
    val () = ward_arr_set<byte>(data_arr, 6, _byte(116))
    val () = ward_arr_set<byte>(data_arr, 7, _byte(97))
    val () = ward_arr_set<byte>(data_arr, 8, _byte(116))
    val () = ward_arr_set<byte>(data_arr, 9, _byte(105))
    val () = ward_arr_set<byte>(data_arr, 10, _byte(111))
    val () = ward_arr_set<byte>(data_arr, 11, _byte(110))
    val () = ward_arr_set<byte>(data_arr, 12, _byte(115))
    val () = ward_arr_set<byte>(data_arr, 13, _byte(10))
    val () = ward_arr_set<byte>(data_arr, 14, _byte(10))
    (* Count digit + " highlights\n\n" *)
    val raw_digit = if lt_int_int(count, 10) then 48 + count else 48
    val () = ward_arr_set<byte>(data_arr, 15, _byte(_checked_byte(band_int_int(raw_digit, 255))))
    val () = ward_arr_set<byte>(data_arr, 16, _byte(32))
    val () = ward_arr_set<byte>(data_arr, 17, _byte(104))
    val () = ward_arr_set<byte>(data_arr, 18, _byte(105))
    val () = ward_arr_set<byte>(data_arr, 19, _byte(103))
    val () = ward_arr_set<byte>(data_arr, 20, _byte(104))
    val () = ward_arr_set<byte>(data_arr, 21, _byte(108))
    val () = ward_arr_set<byte>(data_arr, 22, _byte(105))
    val () = ward_arr_set<byte>(data_arr, 23, _byte(103))
    val () = ward_arr_set<byte>(data_arr, 24, _byte(104))
    val () = ward_arr_set<byte>(data_arr, 25, _byte(116))
    val () = ward_arr_set<byte>(data_arr, 26, _byte(115))
    val () = ward_arr_set<byte>(data_arr, 27, _byte(10))
    val () = ward_arr_set<byte>(data_arr, 28, _byte(10))
    (* "*Exported from Quire*\n" = 22 bytes *)
    val () = ward_arr_set<byte>(data_arr, 29, _byte(42))
    val () = ward_arr_set<byte>(data_arr, 30, _byte(69))
    val () = ward_arr_set<byte>(data_arr, 31, _byte(120))
    val () = ward_arr_set<byte>(data_arr, 32, _byte(112))
    val () = ward_arr_set<byte>(data_arr, 33, _byte(111))
    val () = ward_arr_set<byte>(data_arr, 34, _byte(114))
    val () = ward_arr_set<byte>(data_arr, 35, _byte(116))
    val () = ward_arr_set<byte>(data_arr, 36, _byte(101))
    val () = ward_arr_set<byte>(data_arr, 37, _byte(100))
    val () = ward_arr_set<byte>(data_arr, 38, _byte(32))
    val () = ward_arr_set<byte>(data_arr, 39, _byte(102))
    val () = ward_arr_set<byte>(data_arr, 40, _byte(114))
    val () = ward_arr_set<byte>(data_arr, 41, _byte(111))
    val () = ward_arr_set<byte>(data_arr, 42, _byte(109))
    val () = ward_arr_set<byte>(data_arr, 43, _byte(32))
    val () = ward_arr_set<byte>(data_arr, 44, _byte(81))
    val () = ward_arr_set<byte>(data_arr, 45, _byte(117))
    val () = ward_arr_set<byte>(data_arr, 46, _byte(105))
    val () = ward_arr_set<byte>(data_arr, 47, _byte(114))
    val () = ward_arr_set<byte>(data_arr, 48, _byte(101))
    val () = ward_arr_set<byte>(data_arr, 49, _byte(42))
    val () = ward_arr_set<byte>(data_arr, 50, _byte(10))

    (* Build MIME type "text/plain" = 10 chars as content_text *)
    val mb = ward_content_text_build(10)
    val mb = ward_content_text_putc(mb, 0, char2int1('t'))
    val mb = ward_content_text_putc(mb, 1, char2int1('e'))
    val mb = ward_content_text_putc(mb, 2, char2int1('x'))
    val mb = ward_content_text_putc(mb, 3, char2int1('t'))
    val mb = ward_content_text_putc(mb, 4, 47)  (* / *)
    val mb = ward_content_text_putc(mb, 5, char2int1('p'))
    val mb = ward_content_text_putc(mb, 6, char2int1('l'))
    val mb = ward_content_text_putc(mb, 7, char2int1('a'))
    val mb = ward_content_text_putc(mb, 8, char2int1('i'))
    val mb = ward_content_text_putc(mb, 9, char2int1('n'))
    val mime = ward_content_text_done(mb)

    (* Create blob URL from data *)
    val @(data_frozen, data_borrow) = ward_arr_freeze<byte>(data_arr)
    val url_len = ward_create_blob_url(data_borrow, 51, mime, 10)
    val () = ward_safe_content_text_free(mime)
    val () = ward_arr_drop<byte>(data_frozen, data_borrow)
    val data_arr2 = ward_arr_thaw<byte>(data_frozen)
    val () = ward_arr_free<byte>(data_arr2)
  in
    if gt_int_int(url_len, 0) then
    if lt_int_int(url_len, 4096) then let
      val ul = _checked_url_len(url_len)
      val url_arr = ward_create_blob_url_get(ul)

      (* Build filename "annotations.md" = 14 bytes *)
      val name_arr = ward_arr_alloc<byte>(14)
      val () = ward_arr_set<byte>(name_arr, 0, _byte(97))   (* a *)
      val () = ward_arr_set<byte>(name_arr, 1, _byte(110))  (* n *)
      val () = ward_arr_set<byte>(name_arr, 2, _byte(110))  (* n *)
      val () = ward_arr_set<byte>(name_arr, 3, _byte(111))  (* o *)
      val () = ward_arr_set<byte>(name_arr, 4, _byte(116))  (* t *)
      val () = ward_arr_set<byte>(name_arr, 5, _byte(97))   (* a *)
      val () = ward_arr_set<byte>(name_arr, 6, _byte(116))  (* t *)
      val () = ward_arr_set<byte>(name_arr, 7, _byte(105))  (* i *)
      val () = ward_arr_set<byte>(name_arr, 8, _byte(111))  (* o *)
      val () = ward_arr_set<byte>(name_arr, 9, _byte(110))  (* n *)
      val () = ward_arr_set<byte>(name_arr, 10, _byte(115)) (* s *)
      val () = ward_arr_set<byte>(name_arr, 11, _byte(46))  (* . *)
      val () = ward_arr_set<byte>(name_arr, 12, _byte(109)) (* m *)
      val () = ward_arr_set<byte>(name_arr, 13, _byte(100)) (* d *)

      (* Create <a> element, set href + download, click, remove *)
      val nid = dom_next_id()
      val dom = ward_dom_init()
      val s = ward_dom_stream_begin(dom)
      val s = ward_dom_stream_create_element(s, nid, 0, tag_a(), 1)
      (* Set href = blob URL *)
      val @(uf, ub) = ward_arr_freeze<byte>(url_arr)
      val s = ward_dom_stream_set_attr(s, nid, attr_href(), 4, ub, ul)
      val () = ward_arr_drop<byte>(uf, ub)
      val url_arr = ward_arr_thaw<byte>(uf)
      (* Set download = filename *)
      val @(nf, nb) = ward_arr_freeze<byte>(name_arr)
      val s = ward_dom_stream_set_attr(s, nid, attr_download(), 8, nb, 14)
      val () = ward_arr_drop<byte>(nf, nb)
      val name_arr = ward_arr_thaw<byte>(nf)
      val () = ward_arr_free<byte>(name_arr)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)

      (* Click to trigger download *)
      val () = quire_click_node(nid)

      (* Remove the <a> element *)
      val dom2 = ward_dom_init()
      val s2 = ward_dom_stream_begin(dom2)
      val s2 = ward_dom_stream_remove_child(s2, nid)
      val dom2 = ward_dom_stream_end(s2)
      val () = ward_dom_fini(dom2)

      (* Revoke blob URL and free *)
      val @(uf2, ub2) = ward_arr_freeze<byte>(url_arr)
      val () = ward_revoke_blob_url(ub2, ul)
      val () = ward_arr_drop<byte>(uf2, ub2)
      val url_arr2 = ward_arr_thaw<byte>(uf2)
      val () = ward_arr_free<byte>(url_arr2)
    in end
    else ()  (* url_len >= 4096 — skip *)
    else ()  (* url_len = 0 — skip *)
  end
  else ()
end
