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
staload "./quire_ext.sats"
staload "./../vendor/ward/lib/memory.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload UN = "prelude/SATS/unsafe.sats"

%{
extern void quire_download_text(int data, int data_len, int name, int name_len);
%}

extern castfn _byte {c:int | 0 <= c; c <= 255} (c: int c): byte

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
    (* Allocate buffer for Markdown content + filename *)
    val arr = ward_arr_alloc<byte>(128)
    (* "# Annotations\n\n" = 16 bytes *)
    val () = ward_arr_set<byte>(arr, 0, _byte(35))
    val () = ward_arr_set<byte>(arr, 1, _byte(32))
    val () = ward_arr_set<byte>(arr, 2, _byte(65))
    val () = ward_arr_set<byte>(arr, 3, _byte(110))
    val () = ward_arr_set<byte>(arr, 4, _byte(110))
    val () = ward_arr_set<byte>(arr, 5, _byte(111))
    val () = ward_arr_set<byte>(arr, 6, _byte(116))
    val () = ward_arr_set<byte>(arr, 7, _byte(97))
    val () = ward_arr_set<byte>(arr, 8, _byte(116))
    val () = ward_arr_set<byte>(arr, 9, _byte(105))
    val () = ward_arr_set<byte>(arr, 10, _byte(111))
    val () = ward_arr_set<byte>(arr, 11, _byte(110))
    val () = ward_arr_set<byte>(arr, 12, _byte(115))
    val () = ward_arr_set<byte>(arr, 13, _byte(10))
    val () = ward_arr_set<byte>(arr, 14, _byte(10))
    (* Count digit + " highlights\n" *)
    val raw_digit = if lt_int_int(count, 10) then 48 + count else 48
    val () = ward_arr_set<byte>(arr, 15, _byte(_checked_byte(band_int_int(raw_digit, 255))))
    val () = ward_arr_set<byte>(arr, 16, _byte(32))
    val () = ward_arr_set<byte>(arr, 17, _byte(104))
    val () = ward_arr_set<byte>(arr, 18, _byte(105))
    val () = ward_arr_set<byte>(arr, 19, _byte(103))
    val () = ward_arr_set<byte>(arr, 20, _byte(104))
    val () = ward_arr_set<byte>(arr, 21, _byte(108))
    val () = ward_arr_set<byte>(arr, 22, _byte(105))
    val () = ward_arr_set<byte>(arr, 23, _byte(103))
    val () = ward_arr_set<byte>(arr, 24, _byte(104))
    val () = ward_arr_set<byte>(arr, 25, _byte(116))
    val () = ward_arr_set<byte>(arr, 26, _byte(115))
    val () = ward_arr_set<byte>(arr, 27, _byte(10))
    val () = ward_arr_set<byte>(arr, 28, _byte(10))
    (* "*Exported from Quire*\n" = 22 bytes *)
    val () = ward_arr_set<byte>(arr, 29, _byte(42))
    val () = ward_arr_set<byte>(arr, 30, _byte(69))
    val () = ward_arr_set<byte>(arr, 31, _byte(120))
    val () = ward_arr_set<byte>(arr, 32, _byte(112))
    val () = ward_arr_set<byte>(arr, 33, _byte(111))
    val () = ward_arr_set<byte>(arr, 34, _byte(114))
    val () = ward_arr_set<byte>(arr, 35, _byte(116))
    val () = ward_arr_set<byte>(arr, 36, _byte(101))
    val () = ward_arr_set<byte>(arr, 37, _byte(100))
    val () = ward_arr_set<byte>(arr, 38, _byte(32))
    val () = ward_arr_set<byte>(arr, 39, _byte(102))
    val () = ward_arr_set<byte>(arr, 40, _byte(114))
    val () = ward_arr_set<byte>(arr, 41, _byte(111))
    val () = ward_arr_set<byte>(arr, 42, _byte(109))
    val () = ward_arr_set<byte>(arr, 43, _byte(32))
    val () = ward_arr_set<byte>(arr, 44, _byte(81))
    val () = ward_arr_set<byte>(arr, 45, _byte(117))
    val () = ward_arr_set<byte>(arr, 46, _byte(105))
    val () = ward_arr_set<byte>(arr, 47, _byte(114))
    val () = ward_arr_set<byte>(arr, 48, _byte(101))
    val () = ward_arr_set<byte>(arr, 49, _byte(42))
    val () = ward_arr_set<byte>(arr, 50, _byte(10))
    val data_len = 51
    (* Filename at offset 64: "annotations.md" = 14 bytes *)
    val () = ward_arr_set<byte>(arr, 64, _byte(97))
    val () = ward_arr_set<byte>(arr, 65, _byte(110))
    val () = ward_arr_set<byte>(arr, 66, _byte(110))
    val () = ward_arr_set<byte>(arr, 67, _byte(111))
    val () = ward_arr_set<byte>(arr, 68, _byte(116))
    val () = ward_arr_set<byte>(arr, 69, _byte(97))
    val () = ward_arr_set<byte>(arr, 70, _byte(116))
    val () = ward_arr_set<byte>(arr, 71, _byte(105))
    val () = ward_arr_set<byte>(arr, 72, _byte(111))
    val () = ward_arr_set<byte>(arr, 73, _byte(110))
    val () = ward_arr_set<byte>(arr, 74, _byte(115))
    val () = ward_arr_set<byte>(arr, 75, _byte(46))
    val () = ward_arr_set<byte>(arr, 76, _byte(109))
    val () = ward_arr_set<byte>(arr, 77, _byte(100))
    val name_len = 14
    (* Extract raw pointer for JS call *)
    val raw_ptr = $UN.castvwtp1{ptr}(arr)
    val data_p = $UN.cast{int}(raw_ptr)
    val name_p = data_p + 64
    val () = quire_download_text(data_p, data_len, name_p, name_len)
    (* Release — castvwtp1 borrows, arr is still live *)
    val () = ward_arr_free<byte>(arr)
  in end
  else ()
end
