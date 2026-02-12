(* xml.dats — Cursor-based XML/HTML reader implementation *)
(* All cursor reads are bounds-checked via ward_arr_read<byte>.
   No $<M>UNSAFE in cursor functions — byte2int0 is in runtime.h. *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./xml.sats"
staload _ = "./memory.dats"

(*
 * $<M>UNSAFE justification:
 * [U1] castvwtp1{ptr}(html) — borrows borrow as raw ptr for JS import call.
 *   Same pattern as memory.dats [U1]. Single-use, not for data reads.
 *)

(* JS import *)
extern fun _ward_js_parse_html
  (html: ptr, len: int): int = "mac#ward_js_parse_html"

(* Bridge int stash — stash_id in slot 1 *)
extern fun _ward_bridge_stash_get_int
  (slot: int): int = "mac#ward_bridge_stash_get_int"

(* Bounds-checked byte read. Returns byte as int, or -1 if OOB. *)
fn _peek{l:agz}{n:pos}
  (buf: !ward_arr_borrow(byte, l, n), off: int, len: int n): int = let
  val off1 = g1ofg0(off)
in
  if off1 >= 0 then
    if off1 < len then
      byte2int0(ward_arr_read<byte>(buf, off1))
    else ~1
  else ~1
end

implement
ward_xml_parse_html{lb}{n}(html, len) =
  _ward_js_parse_html($UNSAFE.castvwtp1{ptr}(html), len) (* [U1] *)

implement
ward_xml_get_result{n}(len) =
  ward_bridge_recv(_ward_bridge_stash_get_int(1), len)

implement
ward_xml_opcode{l}{n}{p}(buf, pos) =
  byte2int0(ward_arr_read<byte>(buf, pos))

implement
ward_xml_element_open{l}{n}{p}(buf, pos, len) = let
  val p0 : int = g0ofg1(pos)
  (* pos points to opcode byte (0x01); skip it *)
  val tag_len = _peek(buf, p0 + 1, len)
in
  if tag_len >= 0 then let
    val tag_off = p0 + 2
    val after_tag = tag_off + tag_len
    val attr_count = _peek(buf, after_tag, len)
  in
    if attr_count >= 0 then
      @(tag_off, tag_len, attr_count, after_tag + 1)
    else @(0, 0, 0, ~1)
  end
  else @(0, 0, 0, ~1)
end

implement
ward_xml_read_attr{l}{n}{p}(buf, pos, len) = let
  val p0 : int = g0ofg1(pos)
  val name_len = _peek(buf, p0, len)
in
  if name_len >= 0 then let
    val name_off = p0 + 1
    val after_name = name_off + name_len
    val val_lo = _peek(buf, after_name, len)
    val val_hi = _peek(buf, after_name + 1, len)
  in
    if val_lo >= 0 then
      if val_hi >= 0 then let
        val val_len = val_lo + val_hi * 256
        val val_off = after_name + 2
      in @(name_off, name_len, val_off, val_len, val_off + val_len) end
      else @(0, 0, 0, 0, ~1)
    else @(0, 0, 0, 0, ~1)
  end
  else @(0, 0, 0, 0, ~1)
end

implement
ward_xml_read_text{l}{n}{p}(buf, pos, len) = let
  val p0 : int = g0ofg1(pos)
  (* pos points to opcode byte (0x03); skip it *)
  val lo = _peek(buf, p0 + 1, len)
  val hi = _peek(buf, p0 + 2, len)
in
  if lo >= 0 then
    if hi >= 0 then let
      val text_len = lo + hi * 256
      val text_off = p0 + 3
    in @(text_off, text_len, text_off + text_len) end
    else @(0, 0, ~1)
  else @(0, 0, ~1)
end
