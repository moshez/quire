(* dom.dats - Implementation of type-level DOM operations
 *
 * Pure ATS2 implementation. All low-level byte access goes through
 * extern primitives declared in dom.sats (macros in runtime.h).
 * The abstract node_proof type erases to ptr at runtime.
 * Type checking happens at compile time, runtime is just diff emission.
 *)

#define ATS_DYNLOADFLAG 0

staload "dom.sats"

(* ========== Integer arithmetic for freestanding mode ========== *)
(* ATS2's built-in + / * / >= generate template dispatch calls
 * (g0int_add, g0int_mul, gte_g0int_int) that require the prelude.
 * These explicit overloads generate direct C macro calls instead. *)
extern fun add_int_int(a: int, b: int): int = "mac#quire_add"
extern fun mul_int_int(a: int, b: int): int = "mac#quire_mul"
extern fun gte_int_int(a: int, b: int): bool = "mac#quire_gte"
extern fun gt_int_int(a: int, b: int): bool = "mac#quire_gt"
overload + with add_int_int of 10
overload * with mul_int_int of 10

(* ========== Internal helpers (module-local) ========== *)

(* Write a 32-bit unsigned integer in little-endian format.
 * buf: pointer to buffer, offset: byte offset within buffer, v: value *)
fn dom_write_u32
  (buf: ptr, offset: int, v: int): void = let
  val () = buf_set_u8(buf, offset, quire_band(v, 255))
  val () = buf_set_u8(buf, offset + 1, quire_band(quire_bsr(v, 8), 255))
  val () = buf_set_u8(buf, offset + 2, quire_band(quire_bsr(v, 16), 255))
  val () = buf_set_u8(buf, offset + 3, quire_band(quire_bsr(v, 24), 255))
in
end

(* Add a diff entry to the buffer.
 * Requires VALID_OPCODE proof — only protocol-defined opcodes accepted.
 * Diff buffer layout (16-byte aligned entries, quire-design.md §2.2):
 *   Byte 0: entry count (uint8)
 *   Bytes 1-3: padding
 *   Byte 4+: entries, each 16 bytes:
 *     +0: op (uint32)  +4: nodeId (uint32)  +8: value1 (uint32)  +12: value2 (uint32) *)
fn dom_emit_diff
  {opc:int}
  (pf_op: VALID_OPCODE(opc)
  , opcode: int opc, node_id: int, value1: int, value2: int): void = let
  prval _ = pf_op
  val diff = get_diff_buffer_ptr()
  val count = buf_get_u8(diff, 0)
in
  (* Max 255 entries per frame (fits in byte 0).
   * count: [c:nat | c <= 255] from buf_get_u8.
   * When c < 255: entry at 4 + c*16, max = 4 + 254*16 + 16 = 4084 <= 4096. *)
  if gte_int_int(count, 255) then ()
  else let
    val entry_off = 4 + count * 16
    val () = dom_write_u32(diff, entry_off, opcode)
    val () = dom_write_u32(diff, entry_off + 4, node_id)
    val () = dom_write_u32(diff, entry_off + 8, value1)
    val () = dom_write_u32(diff, entry_off + 12, value2)
    val () = buf_set_u8(diff, 0, count + 1)
  in
  end
end

(* Extern declaration for memcpy (implemented in runtime.c) *)
extern fun quire_memcpy(dst: ptr, src: ptr, n: int): ptr = "mac#memcpy"

(* Copy bytes to string buffer at given offset.
 * Requires STRING_BUFFER_SAFE proof: offset + len <= 4096.
 *
 * TEST MADE PASS-BY-CONSTRUCTION:
 *   test_string_buffer_write_bounded — Callers must prove writes
 *   stay within STRING_BUFFER_SIZE. Without proof, code won't compile. *)
fn dom_copy_to_string_buf
  {o,l:nat | o + l <= 4096}
  (pf_safe: STRING_BUFFER_SAFE(o, l)
  , src: ptr, len: int l, offset: int o): void = let
  prval _ = pf_safe
  val sbuf = get_string_buffer_ptr()
  val dst = ptr_add_int(sbuf, offset)
  val _ = quire_memcpy(dst, src, len)
in
end

(* Copy bytes to fetch buffer at given offset.
 * Requires FETCH_BUFFER_SAFE proof: offset + len <= 16384. *)
fn dom_copy_to_fetch_buf
  {o,l:nat | o + l <= 16384}
  (pf_safe: FETCH_BUFFER_SAFE(o, l)
  , src: ptr, len: int l, offset: int o): void = let
  prval _ = pf_safe
  val fbuf = get_fetch_buffer_ptr()
  val dst = ptr_add_int(fbuf, offset)
  val _ = quire_memcpy(dst, src, len)
in
end

(* ========== DOM API implementations ========== *)

implement dom_init() = let
  val diff = get_diff_buffer_ptr()
  val () = buf_set_u8(diff, 0, 0)
in
end

implement dom_create_element
  {parent} {grandparent} {child} {tl}
  (parent_pf, parent_id, child_id, tag_ptr, tag_len) = let
  (* Flush pending diffs before overwriting shared buffers *)
  val () = js_apply_diffs()
  (* Copy tag name to string buffer at offset 0 *)
  prval pf_safe = SAFE_STRING_WRITE()
  val () = dom_copy_to_string_buf(pf_safe, tag_ptr, tag_len, 0)
  (* CREATE_ELEMENT: nodeId=child, value1=parent, value2=tag_len *)
  val () = dom_emit_diff(OPCODE_CREATE_ELEMENT(), OP_CREATE_ELEMENT, child_id, parent_id, tag_len)
  (* Flush immediately: string buffer data (tag name) must be consumed
   * before caller can overwrite shared buffers. *)
  val () = js_apply_diffs()
  val _ = parent_pf
in
  __make_proof{child}{parent}(quire_null_ptr())
end

implement dom_remove_child
  {id} {parent}
  (pf, id) = let
  val () = js_apply_diffs()
  (* REMOVE_CHILD: nodeId=id, value1/value2 unused *)
  val () = dom_emit_diff(OPCODE_REMOVE_CHILD(), OP_REMOVE_CHILD, id, 0, 0)
  val _ = pf
in
end

implement dom_set_text
  {id} {parent} {tl}
  (pf, id, text_ptr, text_len) = let
  val () = js_apply_diffs()
  (* Copy text to fetch buffer at offset 0 *)
  prval pf_safe = SAFE_FETCH_WRITE()
  val () = dom_copy_to_fetch_buf(pf_safe, text_ptr, text_len, 0)
  (* SET_TEXT: nodeId=id, value1=offset(0), value2=len *)
  val () = dom_emit_diff(OPCODE_SET_TEXT(), OP_SET_TEXT, id, 0, text_len)
  val _ = pf
in
  __make_proof{id}{parent}(quire_null_ptr())
end

implement dom_set_text_offset
  {id} {parent}
  (pf, id, fetch_offset, fetch_len) = let
  val () = js_apply_diffs()
  (* SET_TEXT: nodeId=id, value1=offset, value2=len *)
  val () = dom_emit_diff(OPCODE_SET_TEXT(), OP_SET_TEXT, id, fetch_offset, fetch_len)
  val _ = pf
in
  __make_proof{id}{parent}(quire_null_ptr())
end

implement dom_set_attr
  {id} {parent} {nl} {vl}
  (pf_attr, pf, id, name_ptr, name_len, val_ptr, val_len) = let
  prval _ = pf_attr  (* Consume proof — name is valid *)
  val () = js_apply_diffs()
  (* Copy name to string buffer at offset 0 *)
  prval pf_name_safe = SAFE_STRING_WRITE()
  val () = dom_copy_to_string_buf(pf_name_safe, name_ptr, name_len, 0)
  (* Copy value to string buffer at offset name_len *)
  val () = if gt_int_int(val_len, 0) then let
    prval pf_val_safe = SAFE_STRING_WRITE()
  in
    dom_copy_to_string_buf(pf_val_safe, val_ptr, val_len, name_len)
  end
  (* SET_ATTR: nodeId=id, value1=name_len, value2=val_len *)
  val () = dom_emit_diff(OPCODE_SET_ATTR(), OP_SET_ATTR, id, name_len, val_len)
  (* Flush immediately: string buffer data (attr name/value) must be
   * consumed before caller can overwrite shared buffers. *)
  val () = js_apply_diffs()
  val _ = pf
in
  __make_proof{id}{parent}(quire_null_ptr())
end

implement dom_set_transform
  {id} {parent}
  (pf, id, x, y) = let
  val () = js_apply_diffs()
  (* SET_TRANSFORM: nodeId=id, value1=x, value2=y
   * x and y are int32, interpreted as signed by bridge *)
  val () = dom_emit_diff(OPCODE_SET_TRANSFORM(), OP_SET_TRANSFORM, id, quire_int2uint(x), quire_int2uint(y))
  val _ = pf
in
  __make_proof{id}{parent}(quire_null_ptr())
end

implement dom_set_inner_html
  {id} {parent}
  (pf, id, fetch_offset, fetch_len) = let
  val () = js_apply_diffs()
  (* SET_INNER_HTML: nodeId=id, value1=offset, value2=len *)
  val () = dom_emit_diff(OPCODE_SET_INNER_HTML(), OP_SET_INNER_HTML, id, fetch_offset, fetch_len)
  val _ = pf
in
  __make_proof{id}{parent}(quire_null_ptr())
end

implement dom_next_id() = let
  val id = get_dom_next_node_id()
  val () = set_dom_next_node_id(id + 1)
  (* dom_next_node_id starts at 2 and only increments — always > 0 *)
  extern castfn to_pos(x: int): [n:int | n > 0] int n
in
  to_pos(id)
end

implement dom_root_proof() =
  __make_proof{1}{0}(quire_null_ptr())

implement dom_drop_proof
  {id} {parent} (pf) = let
  val _ = pf
in
end

(* dom_set_attr_checked: backward-compatible alias.
 * Now that dom_set_attr requires VALID_ATTR_NAME, this is a
 * pure passthrough. Kept for existing callers. *)
implement dom_set_attr_checked
  {id} {parent} {nl} {vl}
  (pf_attr, pf, id, name_ptr, name_len, val_ptr, val_len) =
    dom_set_attr(pf_attr, pf, id, name_ptr, name_len, val_ptr, val_len)
