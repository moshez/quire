(* dom.dats — Ward DOM implementation with streaming *)
(* Trusted core: writes diff protocol bytes to owned buffer, flushes to bridge.
   Stream API batches multiple ops into 256KB buffer, auto-flushes when full.
   Stream is a datavtype carrying {buf: ward_arr(byte), cursor: int}. *)

#include "share/atspre_staload.hats"
staload "./memory.sats"
staload "./dom.sats"
staload _ = "./memory.dats"

(* Bridge flush — host-provided *)
extern fun _ward_dom_flush
  (buf: ptr, len: int): void = "mac#ward_dom_flush"

local

datavtype stream_vt(l:addr) =
  | {l:agz} stream_mk(l) of (ward_arr(byte, l, WARD_DOM_BUF_CAP), int(*cursor*))

assume ward_dom_state(l) = ptr l
assume ward_dom_stream(l) = stream_vt(l)

in

(*
 * $<M>UNSAFE justifications — each use is marked with its pattern tag.
 *
 * [RT1] castvwtp1{ptr}(buf) in _flush_arr:
 *   Extracts raw pointer from ward_arr(byte) to pass to ward_dom_flush.
 *   This crosses the WASM/JS runtime boundary — ward_dom_flush is a host
 *   import that requires a raw pointer. No ATS2-level alternative exists
 *   because the host API is defined in terms of raw memory addresses.
 *
 * No other $<M>UNSAFE uses. All buffer writes go through ward_arr_write_byte,
 * ward_arr_write_i32, ward_arr_write_borrow, and ward_arr_write_safe_text
 * which are bounds-checked in memory.sats and implemented in memory.dats.
 *)

(* --- Runtime boundary helper --- *)

fn _flush_arr{l:agz}
  (buf: !ward_arr(byte, l, WARD_DOM_BUF_CAP), len: int): void =
  _ward_dom_flush($UNSAFE.castvwtp1{ptr}(buf), len) (* [RT1] *)

(* --- Lifecycle --- *)

extern fun _ward_malloc_bytes
  (n: int): [l:agz] ptr l = "mac#malloc"

implement
ward_dom_init() = _ward_malloc_bytes(4)  (* lightweight token *)

implement
ward_dom_fini{l}(state) = $extfcall(void, "free", state)

(* --- Stream lifecycle --- *)

implement
ward_dom_stream_begin{l}(state) = let
  val () = $extfcall(void, "free", state)  (* free state token *)
  val buf = ward_arr_alloc<byte>(WARD_DOM_BUF_CAP_DYN)
in stream_mk(buf, 0) end

implement
ward_dom_stream_end{l}(stream) = let
  val+ ~stream_mk(buf, c) = stream
  val () = if c > 0 then _flush_arr(buf, c)
  val () = ward_arr_free<byte>(buf)
in _ward_malloc_bytes(4) end

(* --- Auto-flush helper ---
   Returns a dependent cursor guaranteed to have room for 'needed' bytes.
   Flushes and resets to 0 if current cursor + needed exceeds capacity. *)

fn _ward_stream_auto_flush
  {l:agz}{needed:pos | needed <= WARD_DOM_BUF_CAP}
  (stream: !stream_vt(l), needed: int needed)
  : [c:nat | c + needed <= WARD_DOM_BUF_CAP] int(c) = let
  val+ @stream_mk(buf, cursor) = stream
  val c0 = cursor
  val c1 = g1ofg0(c0)
in
  if c1 + needed > WARD_DOM_BUF_CAP_DYN then let
    val () = _flush_arr(buf, c0)
    val () = cursor := 0
    prval () = fold@(stream)
  in 0 end
  else if c1 >= 0 then let
    prval () = fold@(stream)
  in c1 end
  else let
    (* unreachable: cursor is always >= 0 *)
    val () = _flush_arr(buf, c0)
    val () = cursor := 0
    prval () = fold@(stream)
  in 0 end
end

(*
 * Diff protocol (little-endian):
 *   CREATE_ELEMENT: [1:op=4] [4:node_id] [4:parent_id] [1:tag_len] [tag_data]
 *   SET_TEXT:       [1:op=1] [4:node_id] [1:lo] [1:hi]  [text_data]
 *   SET_ATTR:       [1:op=2] [4:node_id] [1:name_len]   [name_data]
 *                                         [1:lo] [1:hi]  [value_data]
 *   REMOVE_CHILDREN:[1:op=3] [4:node_id]
 *   REMOVE_CHILD:   [1:op=5] [4:node_id]
 *)

(* --- Stream ops --- *)

implement
ward_dom_stream_create_element{l}{tl}
  (stream, node_id, parent_id, tag, tag_len) = let
  val op_size = 10 + tag_len
  val c = _ward_stream_auto_flush(stream, op_size)
  val+ @stream_mk(buf, cursor) = stream
  val () = ward_arr_write_byte(buf, c, 4)
  val () = ward_arr_write_i32(buf, c + 1, node_id)
  val () = ward_arr_write_i32(buf, c + 5, parent_id)
  val () = ward_arr_write_byte(buf, c + 9, tag_len)
  val () = ward_arr_write_safe_text(buf, c + 10, tag, tag_len)
  val () = cursor := g0ofg1(c + op_size)
  prval () = fold@(stream)
in stream end

implement
ward_dom_stream_set_text{l}{lb}{tl}
  (stream, node_id, text, text_len) = let
  val op_size = 7 + text_len
  val c = _ward_stream_auto_flush(stream, op_size)
  val+ @stream_mk(buf, cursor) = stream
  val () = ward_arr_write_byte(buf, c, 1)
  val () = ward_arr_write_i32(buf, c + 1, node_id)
  val () = ward_arr_write_u16le(buf, c + 5, text_len)
  val () = ward_arr_write_borrow(buf, c + 7, text, text_len)
  val () = cursor := g0ofg1(c + op_size)
  prval () = fold@(stream)
in stream end

implement
ward_dom_stream_set_attr{l}{lb}{nl}{vl}
  (stream, node_id, attr_name, name_len, value, value_len) = let
  val op_size = 6 + name_len + 2 + value_len
  val c = _ward_stream_auto_flush(stream, op_size)
  val+ @stream_mk(buf, cursor) = stream
  val () = ward_arr_write_byte(buf, c, 2)
  val () = ward_arr_write_i32(buf, c + 1, node_id)
  val () = ward_arr_write_byte(buf, c + 5, name_len)
  val () = ward_arr_write_safe_text(buf, c + 6, attr_name, name_len)
  val off = c + 6 + name_len
  val () = ward_arr_write_u16le(buf, off, value_len)
  val () = ward_arr_write_borrow(buf, off + 2, value, value_len)
  val () = cursor := g0ofg1(c + op_size)
  prval () = fold@(stream)
in stream end

implement
ward_dom_stream_set_style{l}{lb}{vl}
  (stream, node_id, value, value_len) = let
  val op_size = 13 + value_len
  val c = _ward_stream_auto_flush(stream, op_size)
  val+ @stream_mk(buf, cursor) = stream
  (* Hardcoded "style" = 115 116 121 108 101 *)
  val () = ward_arr_write_byte(buf, c, 2)
  val () = ward_arr_write_i32(buf, c + 1, node_id)
  val () = ward_arr_write_byte(buf, c + 5, 5)
  val () = ward_arr_write_byte(buf, c + 6, 115)
  val () = ward_arr_write_byte(buf, c + 7, 116)
  val () = ward_arr_write_byte(buf, c + 8, 121)
  val () = ward_arr_write_byte(buf, c + 9, 108)
  val () = ward_arr_write_byte(buf, c + 10, 101)
  val () = ward_arr_write_u16le(buf, c + 11, value_len)
  val () = ward_arr_write_borrow(buf, c + 13, value, value_len)
  val () = cursor := g0ofg1(c + op_size)
  prval () = fold@(stream)
in stream end

implement
ward_dom_stream_remove_children{l}(stream, node_id) = let
  val c = _ward_stream_auto_flush{l}{5}(stream, 5)
  val+ @stream_mk(buf, cursor) = stream
  val () = ward_arr_write_byte(buf, c, 3)
  val () = ward_arr_write_i32(buf, c + 1, node_id)
  val () = cursor := g0ofg1(c + 5)
  prval () = fold@(stream)
in stream end

implement
ward_dom_stream_remove_child{l}(stream, node_id) = let
  val c = _ward_stream_auto_flush{l}{5}(stream, 5)
  val+ @stream_mk(buf, cursor) = stream
  val () = ward_arr_write_byte(buf, c, 5)
  val () = ward_arr_write_i32(buf, c + 1, node_id)
  val () = cursor := g0ofg1(c + 5)
  prval () = fold@(stream)
in stream end

(* --- Safe text stream variants --- *)

implement
ward_dom_stream_set_safe_text{l}{tl}
  (stream, node_id, text, text_len) = let
  val op_size = 7 + text_len
  val c = _ward_stream_auto_flush(stream, op_size)
  val+ @stream_mk(buf, cursor) = stream
  val () = ward_arr_write_byte(buf, c, 1)
  val () = ward_arr_write_i32(buf, c + 1, node_id)
  val () = ward_arr_write_u16le(buf, c + 5, text_len)
  val () = ward_arr_write_safe_text(buf, c + 7, text, text_len)
  val () = cursor := g0ofg1(c + op_size)
  prval () = fold@(stream)
in stream end

implement
ward_dom_stream_set_attr_safe{l}{nl}{vl}
  (stream, node_id, attr_name, name_len, value, value_len) = let
  val op_size = 6 + name_len + 2 + value_len
  val c = _ward_stream_auto_flush(stream, op_size)
  val+ @stream_mk(buf, cursor) = stream
  val () = ward_arr_write_byte(buf, c, 2)
  val () = ward_arr_write_i32(buf, c + 1, node_id)
  val () = ward_arr_write_byte(buf, c + 5, name_len)
  val () = ward_arr_write_safe_text(buf, c + 6, attr_name, name_len)
  val off = c + 6 + name_len
  val () = ward_arr_write_u16le(buf, off, value_len)
  val () = ward_arr_write_safe_text(buf, off + 2, value, value_len)
  val () = cursor := g0ofg1(c + op_size)
  prval () = fold@(stream)
in stream end

end (* local *)
