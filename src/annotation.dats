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

implement annotation_get_chapter(idx) = _annot_get_field(idx, 0)
implement annotation_get_start(idx) = _annot_get_field(idx, 1)
implement annotation_get_end(idx) = _annot_get_field(idx, 2)
implement annotation_get_timestamp(idx) = _annot_get_field(idx, 3)
