(* xml.sats — Cursor-based XML/HTML reader over binary SAX format *)
(* Reads the flat binary buffer produced by ward_js_parse_html.
   Returns offsets into the borrow buffer — no raw pointers exposed.
   Tag names can be validated via ward_text_from_bytes.
   All reads are bounds-checked; next_pos = -1 signals OOB error. *)

staload "./memory.sats"

(* Opcodes *)
#define WARD_XML_ELEMENT_OPEN  1
#define WARD_XML_ELEMENT_CLOSE 2
#define WARD_XML_TEXT          3

(* Parse untrusted HTML via JS host. Returns byte length of SAX buffer
   (0 on failure). Buffer is stashed; retrieve with ward_xml_get_result. *)
fun ward_xml_parse_html
  {lb:agz}{n:pos}
  (html: !ward_arr_borrow(byte, lb, n), len: int n): int

(* Retrieve the parsed SAX buffer. Caller must free. *)
fun ward_xml_get_result
  {n:pos}
  (len: int n): [l:agz] ward_arr(byte, l, n)

(* Read opcode byte at position. Statically bounded by {p < n}. *)
fun ward_xml_opcode
  {l:agz}{n:pos}{p:nat | p < n}
  (buf: !ward_arr_borrow(byte, l, n), pos: int p): int

(* After ELEMENT_OPEN opcode byte: read tag_len, skip tag bytes, read attr_count.
   Returns (tag_offset, tag_len, attr_count, next_pos).
   next_pos = -1 on OOB. *)
fun ward_xml_element_open
  {l:agz}{n:pos}{p:nat | p < n}
  (buf: !ward_arr_borrow(byte, l, n), pos: int p, len: int n)
  : @(int(*tag_off*), int(*tag_len*), int(*attr_count*), int(*next_pos*))

(* Read one attribute: name_off, name_len, value_off, value_len, next_pos.
   next_pos = -1 on OOB. *)
fun ward_xml_read_attr
  {l:agz}{n:pos}{p:nat | p < n}
  (buf: !ward_arr_borrow(byte, l, n), pos: int p, len: int n)
  : @(int(*name_off*), int(*name_len*), int(*val_off*), int(*val_len*), int(*next_pos*))

(* Read TEXT node: text_off, text_len, next_pos.
   next_pos = -1 on OOB. *)
fun ward_xml_read_text
  {l:agz}{n:pos}{p:nat | p < n}
  (buf: !ward_arr_borrow(byte, l, n), pos: int p, len: int n)
  : @(int(*text_off*), int(*text_len*), int(*next_pos*))
