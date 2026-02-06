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
 * Diff buffer layout (16-byte aligned entries, quire-design.md §2.2):
 *   Byte 0: entry count (uint8)
 *   Bytes 1-3: padding
 *   Byte 4+: entries, each 16 bytes:
 *     +0: op (uint32)  +4: nodeId (uint32)  +8: value1 (uint32)  +12: value2 (uint32) *)
fn dom_emit_diff
  (opcode: int, node_id: int, value1: int, value2: int): void = let
  val diff = get_diff_buffer_ptr()
  val count = buf_get_u8(diff, 0)
in
  (* Max 255 entries per frame (fits in byte 0) *)
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
 * Uses memcpy via pointer arithmetic on the shared string buffer. *)
fn dom_copy_to_string_buf
  (src: ptr, len: int, offset: int): void = let
  val sbuf = get_string_buffer_ptr()
  val dst = ptr_add_int(sbuf, offset)
  val _ = quire_memcpy(dst, src, len)
in
end

(* Copy bytes to fetch buffer at given offset. *)
fn dom_copy_to_fetch_buf
  (src: ptr, len: int, offset: int): void = let
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
  {parent} {grandparent} {child}
  (parent_pf, parent_id, child_id, tag_ptr, tag_len) = let
  (* Flush pending diffs before overwriting shared buffers *)
  val () = js_apply_diffs()
  (* Copy tag name to string buffer at offset 0 *)
  val () = dom_copy_to_string_buf(tag_ptr, tag_len, 0)
  (* CREATE_ELEMENT: nodeId=child, value1=parent, value2=tag_len *)
  val () = dom_emit_diff(4, child_id, parent_id, tag_len)
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
  val () = dom_emit_diff(5, id, 0, 0)
  val _ = pf
in
end

implement dom_set_text
  {id} {parent}
  (pf, id, text_ptr, text_len) = let
  val () = js_apply_diffs()
  (* Copy text to fetch buffer at offset 0 *)
  val () = dom_copy_to_fetch_buf(text_ptr, text_len, 0)
  (* SET_TEXT: nodeId=id, value1=offset(0), value2=len *)
  val () = dom_emit_diff(1, id, 0, text_len)
  val _ = pf
in
  __make_proof{id}{parent}(quire_null_ptr())
end

implement dom_set_text_offset
  {id} {parent}
  (pf, id, fetch_offset, fetch_len) = let
  val () = js_apply_diffs()
  (* SET_TEXT: nodeId=id, value1=offset, value2=len *)
  val () = dom_emit_diff(1, id, fetch_offset, fetch_len)
  val _ = pf
in
  __make_proof{id}{parent}(quire_null_ptr())
end

implement dom_set_attr
  {id} {parent}
  (pf, id, name_ptr, name_len, val_ptr, val_len) = let
  val () = js_apply_diffs()
  (* Copy name to string buffer at offset 0 *)
  val () = dom_copy_to_string_buf(name_ptr, name_len, 0)
  (* Copy value to string buffer at offset name_len *)
  val () = if gt_int_int(val_len, 0) then
    dom_copy_to_string_buf(val_ptr, val_len, name_len)
  (* SET_ATTR: nodeId=id, value1=name_len, value2=val_len *)
  val () = dom_emit_diff(2, id, name_len, val_len)
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
  val () = dom_emit_diff(3, id, quire_int2uint(x), quire_int2uint(y))
  val _ = pf
in
  __make_proof{id}{parent}(quire_null_ptr())
end

implement dom_set_inner_html
  {id} {parent}
  (pf, id, fetch_offset, fetch_len) = let
  val () = js_apply_diffs()
  (* SET_INNER_HTML: nodeId=id, value1=offset, value2=len *)
  val () = dom_emit_diff(6, id, fetch_offset, fetch_len)
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

(* dom_set_attr_checked: proof-checked attribute setter.
 * Consumes VALID_ATTR_NAME proof at compile time,
 * delegates to dom_set_attr at runtime.
 *
 * This function enforces at compile time that attribute names are
 * known HTML constants, preventing Bug #3 (invalid attribute names). *)
implement dom_set_attr_checked
  {id} {parent} {n}
  (pf_attr, pf, id, name_ptr, name_len, val_ptr, val_len) = let
    prval _ = pf_attr  (* Consume proof — name is valid *)
  in
    dom_set_attr(pf, id, name_ptr, name_len, val_ptr, val_len)
  end
