(* xml.dats - Tree-based XML parser implementation
 *
 * Pure ATS2 recursive descent parser that builds a tree of xml_node_vt.
 * All byte access goes through buf_get_u8 / buf_set_u8 (runtime.h macros).
 * Strings reference the fetch buffer directly (zero-copy).
 *)

#define ATS_DYNLOADFLAG 0

staload "./buf.sats"
staload "./xml.sats"

staload "./arith.sats"

(* Module-private raw ptr buffer access — stays within xml.dats.
 * xml.dats operates on fetch buffer ptr from epub module. *)
extern fun buf_get_u8(p: ptr, off: int): int = "mac#buf_get_u8"
extern fun buf_set_u8(p: ptr, off: int, v: int): void = "mac#buf_set_u8"
extern fun ptr_add_int(p: ptr, n: int): ptr = "mac#atspre_add_ptr0_bsz"

(* Cast functions for linear type borrowing — all at top level *)
extern castfn ptr_to_nodes(p: ptr): xml_node_list_vt
extern castfn nodes_to_ptr(ns: xml_node_list_vt): ptr
extern castfn ptr_to_node(p: ptr): xml_node_vt
extern castfn node_to_ptr(n: xml_node_vt): ptr
extern castfn ptr_to_attrs(p: ptr): xml_attr_list_vt
extern castfn attrs_to_ptr(a: xml_attr_list_vt): ptr
extern castfn node_borrow_ptr(n: !xml_node_vt): ptr
extern castfn nodes_borrow_ptr(ns: !xml_node_list_vt): ptr
extern castfn attrs_borrow_ptr(a: !xml_attr_list_vt): ptr

(* ========== Internal helpers ========== *)

fn is_ws(c: int): int =
  if eq_int_int(c, 32) then 1
  else if eq_int_int(c, 9) then 1
  else if eq_int_int(c, 10) then 1
  else if eq_int_int(c, 13) then 1
  else 0

fn is_name_char(c: int): int =
  if gte_int_int(c, 97) then
    if gt_int_int(123, c) then 1 else 0
  else if gte_int_int(c, 65) then
    if gt_int_int(91, c) then 1 else 0
  else if gte_int_int(c, 48) then
    if gt_int_int(58, c) then 1 else 0
  else if eq_int_int(c, 95) then 1
  else if eq_int_int(c, 45) then 1
  else if eq_int_int(c, 46) then 1
  else if eq_int_int(c, 58) then 1
  else 0

fn skip_ws(data: ptr, pos: int, len: int): int = let
  fun loop(p: int): int =
    if gte_int_int(p, len) then p
    else if eq_int_int(is_ws(buf_get_u8(data, p)), 1) then loop(p + 1)
    else p
in loop(pos) end

fn skip_comment(data: ptr, pos: int, len: int): int = let
  fun loop(p: int): int =
    if gte_int_int(p + 2, len) then len
    else if eq_int_int(buf_get_u8(data, p), 45) then
      if eq_int_int(buf_get_u8(data, p + 1), 45) then
        if eq_int_int(buf_get_u8(data, p + 2), 62) then p + 3
        else loop(p + 1)
      else loop(p + 1)
    else loop(p + 1)
in loop(pos) end

fn skip_pi(data: ptr, pos: int, len: int): int = let
  fun loop(p: int): int =
    if gte_int_int(p + 1, len) then len
    else if eq_int_int(buf_get_u8(data, p), 63) then
      if eq_int_int(buf_get_u8(data, p + 1), 62) then p + 2
      else loop(p + 1)
    else loop(p + 1)
in loop(pos) end

fn skip_doctype(data: ptr, pos: int, len: int): int = let
  fun loop(p: int, depth: int): int =
    if gte_int_int(p, len) then len
    else let val c = buf_get_u8(data, p)
    in
      if eq_int_int(c, 60) then loop(p + 1, depth + 1)
      else if eq_int_int(c, 62) then
        (if eq_int_int(depth, 1) then p + 1 else loop(p + 1, sub_int_int(depth, 1)))
      else loop(p + 1, depth)
    end
in loop(pos, 1) end

fn bytes_equal(p1: ptr, off1: int, p2: ptr, len2: int): bool = let
  fun loop(i: int): bool =
    if gte_int_int(i, len2) then true
    else if eq_int_int(buf_get_u8(p1, off1 + i), buf_get_u8(p2, i)) then loop(i + 1)
    else false
in loop(0) end

fn copy_bytes(src: ptr, src_off: int, dst: ptr, dst_off: int, count: int, max: int): void = let
  fun loop(i: int): void =
    if gte_int_int(i, count) then ()
    else if gte_int_int(dst_off + i, max) then ()
    else let
      val () = buf_set_u8(dst, dst_off + i, buf_get_u8(src, src_off + i))
    in loop(i + 1) end
in loop(0) end

(* ========== Attribute parser ========== *)

fun parse_attrs(data: ptr, pos: int, end_pos: int): (xml_attr_list_vt, int) = let
  val p = skip_ws(data, pos, end_pos)
in
  if gte_int_int(p, end_pos) then (xml_attrs_nil(), p)
  else if eq_int_int(is_name_char(buf_get_u8(data, p)), 0) then (xml_attrs_nil(), p)
  else let
    val name_start = p
    fun scan_name(p2: int): int =
      if gte_int_int(p2, end_pos) then p2
      else if eq_int_int(is_name_char(buf_get_u8(data, p2)), 1) then scan_name(p2 + 1)
      else p2
    val name_end = scan_name(p)
    val name_len = sub_int_int(name_end, name_start)
    val name_ptr = ptr_add_int(data, name_start)
    val p2 = skip_ws(data, name_end, end_pos)
  in
    if gte_int_int(p2, end_pos) then (xml_attrs_nil(), p2)
    else if eq_int_int(buf_get_u8(data, p2), 61) then let
      val p3 = skip_ws(data, p2 + 1, end_pos)
    in
      if gte_int_int(p3, end_pos) then (xml_attrs_nil(), p3)
      else let val quote = buf_get_u8(data, p3) in
        if eq_int_int(quote, 34) then let
          val vs = p3 + 1
          fun scan_dq(p4: int): int =
            if gte_int_int(p4, end_pos) then p4
            else if eq_int_int(buf_get_u8(data, p4), 34) then p4
            else scan_dq(p4 + 1)
          val ve = scan_dq(vs)
          val vl = sub_int_int(ve, vs)
          val vp = ptr_add_int(data, vs)
          val np = if gt_int_int(end_pos, ve) then ve + 1 else ve
          val (rest, fp) = parse_attrs(data, np, end_pos)
        in (xml_attrs_cons(name_ptr, name_len, vp, vl, rest), fp) end
        else if eq_int_int(quote, 39) then let
          val vs = p3 + 1
          fun scan_sq(p4: int): int =
            if gte_int_int(p4, end_pos) then p4
            else if eq_int_int(buf_get_u8(data, p4), 39) then p4
            else scan_sq(p4 + 1)
          val ve = scan_sq(vs)
          val vl = sub_int_int(ve, vs)
          val vp = ptr_add_int(data, vs)
          val np = if gt_int_int(end_pos, ve) then ve + 1 else ve
          val (rest, fp) = parse_attrs(data, np, end_pos)
        in (xml_attrs_cons(name_ptr, name_len, vp, vl, rest), fp) end
        else (xml_attrs_nil(), p3)
      end
    end
    else (xml_attrs_nil(), p2)
  end
end

(* ========== Tree-building recursive descent parser ========== *)

extern fun parse_nodes_impl(data: ptr, pos: int, len: int): (xml_node_list_vt, int)
extern fun parse_element_impl(data: ptr, pos: int, len: int): (xml_node_vt, int)

implement parse_nodes_impl(data, pos, len) = let
  val p = skip_ws(data, pos, len)
in
  if gte_int_int(p, len) then (xml_nodes_nil(), p)
  else let val c = buf_get_u8(data, p) in
    if eq_int_int(c, 60) then
      if gte_int_int(p + 1, len) then (xml_nodes_nil(), p)
      else let val c2 = buf_get_u8(data, p + 1) in
        if eq_int_int(c2, 33) then let
          val new_pos =
            if gte_int_int(p + 3, len) then skip_doctype(data, p + 2, len)
            else if eq_int_int(buf_get_u8(data, p + 2), 45) then
              if eq_int_int(buf_get_u8(data, p + 3), 45) then skip_comment(data, p + 4, len)
              else skip_doctype(data, p + 2, len)
            else skip_doctype(data, p + 2, len)
        in parse_nodes_impl(data, new_pos, len) end
        else if eq_int_int(c2, 63) then
          parse_nodes_impl(data, skip_pi(data, p + 2, len), len)
        else if eq_int_int(c2, 47) then
          (xml_nodes_nil(), p)
        else let
          val (node, new_pos) = parse_element_impl(data, p, len)
          val (rest, final_pos) = parse_nodes_impl(data, new_pos, len)
        in (xml_nodes_cons(node, rest), final_pos) end
      end
    else let
      val text_start = p
      fun scan_text(p2: int): int =
        if gte_int_int(p2, len) then p2
        else if eq_int_int(buf_get_u8(data, p2), 60) then p2
        else scan_text(p2 + 1)
      val text_end = scan_text(p)
      val text_len = sub_int_int(text_end, text_start)
      val text_ptr = ptr_add_int(data, text_start)
      val (rest, final_pos) = parse_nodes_impl(data, text_end, len)
    in (xml_nodes_cons(xml_text_vt(text_ptr, text_len), rest), final_pos) end
  end
end

implement parse_element_impl(data, pos, len) = let
  val p = pos + 1
  val p = skip_ws(data, p, len)
  val name_start = p
  fun scan_name(p2: int): int =
    if gte_int_int(p2, len) then p2
    else if eq_int_int(is_name_char(buf_get_u8(data, p2)), 1) then scan_name(p2 + 1)
    else p2
  val name_end = scan_name(p)
  val name_len = sub_int_int(name_end, name_start)
  val name_ptr = ptr_add_int(data, name_start)
  val p2 = skip_ws(data, name_end, len)
  val attrs_start = p2
  fun find_tag_end(p3: int): (int, int) =
    if gte_int_int(p3, len) then (p3, 0)
    else let val c = buf_get_u8(data, p3) in
      if eq_int_int(c, 62) then (p3, 0)
      else if eq_int_int(c, 47) then
        if gt_int_int(len, p3 + 1) then
          if eq_int_int(buf_get_u8(data, p3 + 1), 62) then (p3, 1)
          else find_tag_end(p3 + 1)
        else (p3, 0)
      else if eq_int_int(c, 34) then let
        fun skip_dq(p4: int): int =
          if gte_int_int(p4, len) then p4
          else if eq_int_int(buf_get_u8(data, p4), 34) then p4 + 1
          else skip_dq(p4 + 1)
      in find_tag_end(skip_dq(p3 + 1)) end
      else if eq_int_int(c, 39) then let
        fun skip_sq(p4: int): int =
          if gte_int_int(p4, len) then p4
          else if eq_int_int(buf_get_u8(data, p4), 39) then p4 + 1
          else skip_sq(p4 + 1)
      in find_tag_end(skip_sq(p3 + 1)) end
      else find_tag_end(p3 + 1)
    end
  val (tag_end_pos, is_self) = find_tag_end(p2)
  val (attrs, _) = parse_attrs(data, attrs_start, tag_end_pos)
  val after_tag =
    if eq_int_int(is_self, 1) then tag_end_pos + 2
    else tag_end_pos + 1
in
  if eq_int_int(is_self, 1) then
    (xml_element_vt(name_ptr, name_len, attrs, xml_nodes_nil()), after_tag)
  else let
    val (children, child_end_pos) = parse_nodes_impl(data, after_tag, len)
    fun skip_closing_tag(p3: int): int =
      if gte_int_int(p3, len) then p3
      else if eq_int_int(buf_get_u8(data, p3), 62) then p3 + 1
      else skip_closing_tag(p3 + 1)
    val final_pos =
      if gte_int_int(child_end_pos, len) then child_end_pos
      else if eq_int_int(buf_get_u8(data, child_end_pos), 60) then
        if gte_int_int(child_end_pos + 1, len) then child_end_pos
        else if eq_int_int(buf_get_u8(data, child_end_pos + 1), 47) then
          skip_closing_tag(child_end_pos + 2)
        else child_end_pos
      else child_end_pos
  in (xml_element_vt(name_ptr, name_len, attrs, children), final_pos) end
end

implement xml_parse_document(data, data_len) = let
  val (nodes, _) = parse_nodes_impl(data, 0, data_len)
in nodes end

(* ========== Tree cleanup ========== *)

fun free_attrs(attrs: xml_attr_list_vt): void =
  case+ attrs of
  | ~xml_attrs_nil() => ()
  | ~xml_attrs_cons(_, _, _, _, rest) => free_attrs(rest)

implement xml_free_node(node) =
  case+ node of
  | ~xml_element_vt(_, _, attrs, children) => let
      val () = free_attrs(attrs)
    in xml_free_nodes(children) end
  | ~xml_text_vt(_, _) => ()

implement xml_free_nodes(nodes) =
  case+ nodes of
  | ~xml_nodes_nil() => ()
  | ~xml_nodes_cons(node, rest) => let
      val () = xml_free_node(node)
    in xml_free_nodes(rest) end

(* ========== Serializer ========== *)
(* Uses algebraic pattern matching instead of null pointer checks.
 * Borrow-reborrow pattern: borrow → extract ptr → put back → create
 * new linear from ptr → recurse with ! borrow → put back. *)

extern fun serialize_attrs_b(attrs: !xml_attr_list_vt, buf: ptr, pos: int, max: int): int

implement xml_serialize_node(node, buf, pos, max) = let
  val np = node_borrow_ptr(node)
  val node2 = ptr_to_node(np)
in
  case+ node2 of
  | xml_element_vt(name, nlen, attrs, children) => let
      val () = if gt_int_int(max, pos) then buf_set_u8(buf, pos, 60)
      val p = pos + 1
      val () = copy_bytes(name, 0, buf, p, nlen, max)
      val p = p + nlen
      val ap = attrs_borrow_ptr(attrs)
      val a2 = ptr_to_attrs(ap)
      val p = serialize_attrs_b(a2, buf, p, max)
      val _ = attrs_to_ptr(a2)
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 62)
      val p = p + 1
      val cp = nodes_borrow_ptr(children)
      val c2 = ptr_to_nodes(cp)
      val p = xml_serialize_nodes(c2, buf, p, max)
      val _ = nodes_to_ptr(c2)
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 60)
      val p = p + 1
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 47)
      val p = p + 1
      val () = copy_bytes(name, 0, buf, p, nlen, max)
      val p = p + nlen
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 62)
      val _ = node_to_ptr(node2)
    in p + 1 end
  | xml_text_vt(text, tlen) => let
      val () = copy_bytes(text, 0, buf, pos, tlen, max)
      val _ = node_to_ptr(node2)
    in pos + tlen end
end

implement xml_serialize_nodes(nodes, buf, pos, max) = let
  val np = nodes_borrow_ptr(nodes)
  val nodes2 = ptr_to_nodes(np)
in
  case+ nodes2 of
  | xml_nodes_nil() => let
      val _ = nodes_to_ptr(nodes2)
    in pos end
  | xml_nodes_cons(node, rest) => let
      val np2 = node_borrow_ptr(node)
      val rp2 = nodes_borrow_ptr(rest)
      val _ = nodes_to_ptr(nodes2)
      val n3 = ptr_to_node(np2)
      val p = xml_serialize_node(n3, buf, pos, max)
      val _ = node_to_ptr(n3)
      val r3 = ptr_to_nodes(rp2)
      val p2 = xml_serialize_nodes(r3, buf, p, max)
      val _ = nodes_to_ptr(r3)
    in p2 end
end

implement serialize_attrs_b(attrs, buf, pos, max) = let
  val ap = attrs_borrow_ptr(attrs)
  val attrs2 = ptr_to_attrs(ap)
in
  case+ attrs2 of
  | xml_attrs_nil() => let
      val _ = attrs_to_ptr(attrs2)
    in pos end
  | xml_attrs_cons(name, nlen, vp, vlen, rest) => let
      val () = if gt_int_int(max, pos) then buf_set_u8(buf, pos, 32)
      val p = pos + 1
      val () = copy_bytes(name, 0, buf, p, nlen, max)
      val p = p + nlen
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 61)
      val p = p + 1
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 34)
      val p = p + 1
      val () = copy_bytes(vp, 0, buf, p, vlen, max)
      val p = p + vlen
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 34)
      val p = p + 1
      val rp = attrs_borrow_ptr(rest)
      val _ = attrs_to_ptr(attrs2)
      val r2 = ptr_to_attrs(rp)
      val p2 = serialize_attrs_b(r2, buf, p, max)
      val _ = attrs_to_ptr(r2)
    in p2 end
end


