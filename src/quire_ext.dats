(* quire_ext.dats — Quire bridge extensions *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./../vendor/ward/lib/memory.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload "./quire_ext.sats"


staload "./arith.sats"

(* Ward listener table — used for parse stash storage *)
extern fun ward_listener_set(id: int, ctx: ptr): void = "mac#"

#define PARSE_STASH_SLOT 126

(* ========== HTML parse stash ========== *)
(* Uses listener slot 126 (separate from app_state at slot 127)
 * to avoid sync-call double-load issues. ward_parse_html_stash
 * is called synchronously by JS during ward_js_parse_html. *)

extern fun ward_parse_html_stash_impl(p: ptr): void = "ext#ward_parse_html_stash"
implement ward_parse_html_stash_impl(p) = ward_listener_set(PARSE_STASH_SLOT, p)

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

(* ========== read_payload_target_id ========== *)
(* Read i32 little-endian from bytes 16-19 of click/contextmenu payload.
 * Layout: [f64:clientX(0-7)][f64:clientY(8-15)][i32:target(16-19)] *)
implement read_payload_target_id(arr) = let
  val b16 = byte2int0(ward_arr_get<byte>(arr, 16))
  val b17 = byte2int0(ward_arr_get<byte>(arr, 17))
  val b18 = byte2int0(ward_arr_get<byte>(arr, 18))
  val b19 = byte2int0(ward_arr_get<byte>(arr, 19))
in
  bor_int_int(bor_int_int(b16, bsl_int_int(b17, 8)),
              bor_int_int(bsl_int_int(b18, 16), bsl_int_int(b19, 24)))
end

(* ========== IEEE 754 f64 → int extraction ========== *)

implement read_payload_click_x(arr) = let
  val b5 = byte2int0(ward_arr_get<byte>(arr, 5))
  val b6 = byte2int0(ward_arr_get<byte>(arr, 6))
  val b7 = byte2int0(ward_arr_get<byte>(arr, 7))
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
