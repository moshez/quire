(* quire_ext.dats — Quire bridge extensions *)

#define ATS_DYNLOADFLAG 0

staload "./../vendor/ward/lib/memory.sats"
staload "./quire_ext.sats"

(* ========== Primitives ========== *)

extern fun sub_int_int(a: int, b: int): int = "mac#quire_sub"
extern fun eq_int_int(a: int, b: int): bool = "mac#quire_eq"
extern fun lt_int_int(a: int, b: int): bool = "mac#quire_lt"
extern fun gt_int_int(a: int, b: int): bool = "mac#quire_gt"
overload - with sub_int_int of 10

extern fun buf_get_u8(p: ptr, off: int): int = "mac#"
extern fun bor_int_int(a: int, b: int): int = "mac#quire_bor"
extern fun bsl_int_int(a: int, n: int): int = "mac#quire_bsl"
extern fun band_int_int(a: int, b: int): int = "mac#quire_band"
extern fun bsr_int_int(a: int, n: int): int = "mac#quire_bsr"

(* Ward listener table — used for parse stash storage *)
extern fun ward_listener_set(id: int, ctx: ptr): void = "mac#"
extern fun ward_listener_get(id: int): ptr = "mac#"

#define PARSE_STASH_SLOT 126

(* ========== HTML parse stash ========== *)
(* Uses listener slot 126 (separate from app_state at slot 127)
 * to avoid sync-call double-load issues. ward_parse_html_stash
 * is called synchronously by JS during ward_js_parse_html. *)

extern fun ward_parse_html_stash_impl(p: ptr): void = "ext#ward_parse_html_stash"
implement ward_parse_html_stash_impl(p) = ward_listener_set(PARSE_STASH_SLOT, p)

extern fun ward_parse_html_get_ptr_impl(): ptr = "ext#ward_parse_html_get_ptr"
implement ward_parse_html_get_ptr_impl() = ward_listener_get(PARSE_STASH_SLOT)

(* ========== IEEE 754 f64 → int extraction ========== *)
(* Reads LE f64 from bytes 0-7 of the payload, returns integer part.
 * Valid for pixel coordinates 0-4096 (positive values with exp <= 12).
 *
 * IEEE 754 double (LE):
 *   byte 7: sign(1) | exp_high(7)
 *   byte 6: exp_low(4) | mantissa_high(4)
 *   byte 5: mantissa[47:40]
 *   bytes 0-4: mantissa low bits (not needed for 0-4096)
 *
 * For integer V in [0, 4096]:
 *   exp = ((b7 & 0x7F) << 4 | b6 >> 4) - 1023
 *   top13 = (1 << 12) | ((b6 & 0x0F) << 8) | b5
 *   result = top13 >> (12 - exp)
 *)

extern fun read_payload_click_x_impl(arr: ptr): int = "ext#read_payload_click_x"
implement read_payload_click_x_impl(arr) = let
  val b5 = buf_get_u8(arr, 5)
  val b6 = buf_get_u8(arr, 6)
  val b7 = buf_get_u8(arr, 7)
  val exp_raw = bor_int_int(bsl_int_int(band_int_int(b7, 127), 4),
                            bsr_int_int(b6, 4))
in
  if eq_int_int(exp_raw, 0) then 0
  else let
    val exp = exp_raw - 1023
  in
    if lt_int_int(exp, 0) then 0
    else if gt_int_int(exp, 12) then 4096
    else let
      val mant_high = bor_int_int(bsl_int_int(band_int_int(b6, 15), 8), b5)
      val top13 = bor_int_int(bsl_int_int(1, 12), mant_high)
    in bsr_int_int(top13, 12 - exp) end
  end
end
