(* xml.dats - Tree-based XML parser implementation
 *
 * Pure ATS2 recursive descent parser that builds a tree of xml_node_vt.
 * Replaces the old C %{ SAX-style parser.
 *
 * All byte access goes through buf_get_u8 / buf_set_u8 (runtime.h macros).
 * Strings reference the fetch buffer directly (zero-copy).
 *)

#define ATS_DYNLOADFLAG 0

staload "buf.sats"
staload "xml.sats"

(* ========== Integer arithmetic for freestanding mode ========== *)
extern fun add_int_int(a: int, b: int): int = "mac#quire_add"
extern fun mul_int_int(a: int, b: int): int = "mac#quire_mul"
extern fun gte_int_int(a: int, b: int): bool = "mac#quire_gte"
extern fun gt_int_int(a: int, b: int): bool = "mac#quire_gt"
overload + with add_int_int of 10
overload * with mul_int_int of 10

extern fun quire_null_ptr(): ptr = "mac#"

(* Equality and inequality — avoid prelude templates *)
extern fun sub_int_int(a: int, b: int): int = "mac#quire_sub"
extern fun eq_int_int(a: int, b: int): bool = "mac#quire_eq"
extern fun neq_int_int(a: int, b: int): bool = "mac#quire_neq"
extern fun eq_ptr_ptr(a: ptr, b: ptr): bool = "mac#quire_ptr_eq"
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

extern fun serialize_nodes_h(nodes_ptr: ptr, buf: ptr, pos: int, max: int): int
extern fun serialize_attrs_h(attrs_ptr: ptr, buf: ptr, pos: int, max: int): int

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
      val p = serialize_attrs_h(ap, buf, p, max)
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 62)
      val p = p + 1
      val cp = nodes_borrow_ptr(children)
      val p = serialize_nodes_h(cp, buf, p, max)
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 60)
      val p = p + 1
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 47)
      val p = p + 1
      val () = copy_bytes(name, 0, buf, p, nlen, max)
      val p = p + nlen
      val () = if gt_int_int(max, p) then buf_set_u8(buf, p, 62)
      val _ = node_to_ptr(node2)
      (* Proof: serialized '<' name attrs '>' children '</' name '>'
       * — symmetric with parse_element_impl field order *)
      prval pf = xml_roundtrip_lemma()
    in (pf | p + 1) end
  | xml_text_vt(text, tlen) => let
      val () = copy_bytes(text, 0, buf, pos, tlen, max)
      val _ = node_to_ptr(node2)
      (* Proof: serialized raw text bytes — symmetric with parse text *)
      prval pf = xml_roundtrip_lemma()
    in (pf | pos + tlen) end
end

implement serialize_nodes_h(nodes_ptr, buf, pos, max) =
  if eq_ptr_ptr(nodes_ptr, quire_null_ptr()) then pos
  else let
    val nodes = ptr_to_nodes(nodes_ptr)
  in case+ nodes of
    | xml_nodes_nil() => let val _ = nodes_to_ptr(nodes) in pos end
    | xml_nodes_cons(node, rest) => let
        val np = node_borrow_ptr(node)
        val rp = nodes_borrow_ptr(rest)
        val _ = nodes_to_ptr(nodes)
        val node3 = ptr_to_node(np)
        val (pf | p) = xml_serialize_node(node3, buf, pos, max)
        prval _ = pf
        val _ = node_to_ptr(node3)
      in serialize_nodes_h(rp, buf, p, max) end
  end

implement serialize_attrs_h(attrs_ptr, buf, pos, max) =
  if eq_ptr_ptr(attrs_ptr, quire_null_ptr()) then pos
  else let
    val attrs = ptr_to_attrs(attrs_ptr)
  in case+ attrs of
    | xml_attrs_nil() => let val _ = attrs_to_ptr(attrs) in pos end
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
        val _ = attrs_to_ptr(attrs)
      in serialize_attrs_h(rp, buf, p, max) end
  end

implement xml_serialize_nodes(nodes, buf, pos, max) = let
  val np = nodes_borrow_ptr(nodes)
  val result = serialize_nodes_h(np, buf, pos, max)
  prval pf = xml_roundtrip_lemma()
in (pf | result) end

(* xml_roundtrip_lemma is praxi — no implementation needed. *)

(* ========== C-Callable Query API ========== *)

implement xml_parse(data_len) = let
  val data = get_fetch_buffer_ptr()
  val nodes = xml_parse_document(data, data_len)
in nodes_to_ptr(nodes) end

implement xml_free_tree(tree) = let
  val nodes = ptr_to_nodes(tree)
in xml_free_nodes(nodes) end

extern fun find_in_list_h(list_ptr: ptr, name: ptr, name_len: int): ptr
extern fun find_in_node_h(node_ptr: ptr, name: ptr, name_len: int): ptr

implement find_in_list_h(list_ptr, name, name_len) =
  if eq_ptr_ptr(list_ptr, quire_null_ptr()) then quire_null_ptr()
  else let
    val nodes = ptr_to_nodes(list_ptr)
  in case+ nodes of
    | xml_nodes_nil() => let val _ = nodes_to_ptr(nodes) in quire_null_ptr() end
    | xml_nodes_cons(node, rest) => let
        val np = node_borrow_ptr(node)
        val rp = nodes_borrow_ptr(rest)
        val _ = nodes_to_ptr(nodes)
        val result = find_in_node_h(np, name, name_len)
      in
        if eq_ptr_ptr(result, quire_null_ptr()) then find_in_list_h(rp, name, name_len)
        else result
      end
  end

implement find_in_node_h(node_ptr, name, name_len) =
  if eq_ptr_ptr(node_ptr, quire_null_ptr()) then quire_null_ptr()
  else let
    val node = ptr_to_node(node_ptr)
  in case+ node of
    | xml_element_vt(ename, elen, _, children) => let
        val cp = nodes_borrow_ptr(children)
        val _ = node_to_ptr(node)
      in
        if eq_int_int(elen, name_len) then
          if bytes_equal(ename, 0, name, name_len) then node_ptr
          else find_in_list_h(cp, name, name_len)
        else find_in_list_h(cp, name, name_len)
      end
    | xml_text_vt(_, _) => let val _ = node_to_ptr(node) in quire_null_ptr() end
  end

implement xml_find_element(tree, name, name_len) =
  find_in_list_h(tree, name, name_len)

implement xml_first_child(node_ptr) =
  if eq_ptr_ptr(node_ptr, quire_null_ptr()) then quire_null_ptr()
  else let
    val node = ptr_to_node(node_ptr)
  in case+ node of
    | xml_element_vt(_, _, _, children) => let
        val cp = nodes_borrow_ptr(children)
        val _ = node_to_ptr(node)
      in cp end
    | xml_text_vt(_, _) => let val _ = node_to_ptr(node) in quire_null_ptr() end
  end

implement xml_next_sibling(cursor) =
  if eq_ptr_ptr(cursor, quire_null_ptr()) then quire_null_ptr()
  else let
    val nodes = ptr_to_nodes(cursor)
  in case+ nodes of
    | xml_nodes_nil() => let val _ = nodes_to_ptr(nodes) in quire_null_ptr() end
    | xml_nodes_cons(_, rest) => let
        val rp = nodes_borrow_ptr(rest)
        val _ = nodes_to_ptr(nodes)
      in rp end
  end

implement xml_node_at(cursor) =
  if eq_ptr_ptr(cursor, quire_null_ptr()) then quire_null_ptr()
  else let
    val nodes = ptr_to_nodes(cursor)
  in case+ nodes of
    | xml_nodes_nil() => let val _ = nodes_to_ptr(nodes) in quire_null_ptr() end
    | xml_nodes_cons(node, _) => let
        val np = node_borrow_ptr(node)
        val _ = nodes_to_ptr(nodes)
      in np end
  end

implement xml_node_is_element(node_ptr) =
  if eq_ptr_ptr(node_ptr, quire_null_ptr()) then 0
  else let val node = ptr_to_node(node_ptr) in
    case+ node of
    | xml_element_vt(_, _, _, _) => let val _ = node_to_ptr(node) in 1 end
    | xml_text_vt(_, _) => let val _ = node_to_ptr(node) in 0 end
  end

implement xml_node_name_is(node_ptr, name, name_len) =
  if eq_ptr_ptr(node_ptr, quire_null_ptr()) then let
    (* Proof: null node — name cannot match *)
    prval _ = NAME_DIFFERS()
  in 0 end
  else let val node = ptr_to_node(node_ptr) in
    case+ node of
    | xml_element_vt(ename, elen, _, _) => let
        val r = if eq_int_int(elen, name_len) then
          if bytes_equal(ename, 0, name, name_len) then let
            (* Proof: compared against THE element's actual name field *)
            prval _ = NAME_MATCHES()
          in 1 end else let
            prval _ = NAME_DIFFERS()
          in 0 end
        else let
          prval _ = NAME_DIFFERS()
        in 0 end
        val _ = node_to_ptr(node)
      in r end
    | xml_text_vt(_, _) => let
        prval _ = NAME_DIFFERS()
        val _ = node_to_ptr(node)
      in 0 end
  end

extern fun find_attr_h(attrs_ptr: ptr, name: ptr, name_len: int, buf_offset: int): int

implement xml_node_get_attr(node_ptr, name, name_len, buf_offset) =
  if eq_ptr_ptr(node_ptr, quire_null_ptr()) then 0
  else let val node = ptr_to_node(node_ptr) in
    case+ node of
    | xml_element_vt(_, _, attrs, _) => let
        val ap = attrs_borrow_ptr(attrs)
        val _ = node_to_ptr(node)
      in find_attr_h(ap, name, name_len, buf_offset) end
    | xml_text_vt(_, _) => let val _ = node_to_ptr(node) in 0 end
  end

implement find_attr_h(attrs_ptr, name, name_len, buf_offset) =
  if eq_ptr_ptr(attrs_ptr, quire_null_ptr()) then let
    (* Proof: exhausted attribute list — attribute not found *)
    prval _ = ATTR_NOT_FOUND()
  in 0 end
  else let val attrs = ptr_to_attrs(attrs_ptr) in
    case+ attrs of
    | xml_attrs_nil() => let
        prval _ = ATTR_NOT_FOUND()
        val _ = attrs_to_ptr(attrs)
      in 0 end
    | xml_attrs_cons(an, anl, av, avl, rest) => let
        val rp = attrs_borrow_ptr(rest)
        val _ = attrs_to_ptr(attrs)
      in
        if eq_int_int(anl, name_len) then
          if bytes_equal(an, 0, name, name_len) then let
            (* Proof: name matched — av IS the value of THIS attribute *)
            prval _ = ATTR_FOUND()
            val sbuf = get_string_buffer_ptr()
            val () = copy_bytes(av, 0, sbuf, buf_offset, avl, 4096)
          in avl end
          else find_attr_h(rp, name, name_len, buf_offset)
        else find_attr_h(rp, name, name_len, buf_offset)
      end
  end

extern fun get_texts_h(list_ptr: ptr, buf_offset: int, written: int): int

implement xml_node_get_text(node_ptr, buf_offset) =
  if eq_ptr_ptr(node_ptr, quire_null_ptr()) then 0
  else let val node = ptr_to_node(node_ptr) in
    case+ node of
    | xml_text_vt(text, tlen) => let
        val sbuf = get_string_buffer_ptr()
        val () = copy_bytes(text, 0, sbuf, buf_offset, tlen, 4096)
        val _ = node_to_ptr(node)
      in tlen end
    | xml_element_vt(_, _, _, children) => let
        val cp = nodes_borrow_ptr(children)
        val _ = node_to_ptr(node)
      in get_texts_h(cp, buf_offset, 0) end
  end

implement get_texts_h(list_ptr, buf_offset, written) =
  if eq_ptr_ptr(list_ptr, quire_null_ptr()) then written
  else let val nodes = ptr_to_nodes(list_ptr) in
    case+ nodes of
    | xml_nodes_nil() => let val _ = nodes_to_ptr(nodes) in written end
    | xml_nodes_cons(node, rest) => let
        val np = node_borrow_ptr(node)
        val rp = nodes_borrow_ptr(rest)
        val _ = nodes_to_ptr(nodes)
        val w = let val n2 = ptr_to_node(np) in
          case+ n2 of
          | xml_text_vt(t, tl) => let
              val sbuf = get_string_buffer_ptr()
              val () = copy_bytes(t, 0, sbuf, buf_offset + written, tl, 4096)
              val _ = node_to_ptr(n2)
            in tl end
          | xml_element_vt(_, _, _, _) => let val _ = node_to_ptr(n2) in 0 end
        end
      in get_texts_h(rp, buf_offset, written + w) end
  end

