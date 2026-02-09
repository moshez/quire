(* dom.sats — Quire DOM convenience layer over ward
 *
 * Provides pre-built ward_safe_text constants for UI tags and attributes,
 * a node ID allocator, and a tree renderer for parsed HTML binary.
 * All DOM operations go through ward's diff protocol.
 *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"

(* ========== Node ID allocator ========== *)

(* Get next available node ID and increment counter *)
fun dom_next_id(): [n:int | n > 0] int n

(* ========== Pre-built safe text: UI tags ========== *)

fun tag_div(): ward_safe_text(3)
fun tag_span(): ward_safe_text(4)
fun tag_button(): ward_safe_text(6)
fun tag_style(): ward_safe_text(5)
fun tag_h1(): ward_safe_text(2)
fun tag_h2(): ward_safe_text(2)
fun tag_h3(): ward_safe_text(2)
fun tag_p(): ward_safe_text(1)
fun tag_input(): ward_safe_text(5)
fun tag_label(): ward_safe_text(5)
fun tag_select(): ward_safe_text(6)
fun tag_option(): ward_safe_text(6)
fun tag_a(): ward_safe_text(1)
fun tag_img(): ward_safe_text(3)

(* ========== Pre-built safe text: EPUB content tags ========== *)

fun tag_b(): ward_safe_text(1)
fun tag_i(): ward_safe_text(1)
fun tag_u(): ward_safe_text(1)
fun tag_s(): ward_safe_text(1)
fun tag_q(): ward_safe_text(1)
fun tag_em(): ward_safe_text(2)
fun tag_br(): ward_safe_text(2)
fun tag_hr(): ward_safe_text(2)
fun tag_li(): ward_safe_text(2)
fun tag_dd(): ward_safe_text(2)
fun tag_dl(): ward_safe_text(2)
fun tag_dt(): ward_safe_text(2)
fun tag_ol(): ward_safe_text(2)
fun tag_ul(): ward_safe_text(2)
fun tag_td(): ward_safe_text(2)
fun tag_th(): ward_safe_text(2)
fun tag_tr(): ward_safe_text(2)
fun tag_h4(): ward_safe_text(2)
fun tag_h5(): ward_safe_text(2)
fun tag_h6(): ward_safe_text(2)
fun tag_pre(): ward_safe_text(3)
fun tag_sub(): ward_safe_text(3)
fun tag_sup(): ward_safe_text(3)
fun tag_var(): ward_safe_text(3)
fun tag_wbr(): ward_safe_text(3)
fun tag_nav(): ward_safe_text(3)
fun tag_kbd(): ward_safe_text(3)
fun tag_code(): ward_safe_text(4)
fun tag_mark(): ward_safe_text(4)
fun tag_cite(): ward_safe_text(4)
fun tag_abbr(): ward_safe_text(4)
fun tag_dfn(): ward_safe_text(3)
fun tag_main(): ward_safe_text(4)
fun tag_time(): ward_safe_text(4)
fun tag_ruby(): ward_safe_text(4)
fun tag_aside(): ward_safe_text(5)
fun tag_small(): ward_safe_text(5)
fun tag_table(): ward_safe_text(5)
fun tag_thead(): ward_safe_text(5)
fun tag_tbody(): ward_safe_text(5)
fun tag_tfoot(): ward_safe_text(5)
fun tag_strong(): ward_safe_text(6)
fun tag_figure(): ward_safe_text(6)
fun tag_footer(): ward_safe_text(6)
fun tag_header(): ward_safe_text(6)
fun tag_section(): ward_safe_text(7)
fun tag_article(): ward_safe_text(7)
fun tag_details(): ward_safe_text(7)
fun tag_summary(): ward_safe_text(7)
fun tag_caption(): ward_safe_text(7)
fun tag_blockquote(): ward_safe_text(10)
fun tag_figcaption(): ward_safe_text(10)

(* SVG *)
fun tag_svg(): ward_safe_text(3)
fun tag_g(): ward_safe_text(1)
fun tag_path(): ward_safe_text(4)
fun tag_circle(): ward_safe_text(6)
fun tag_rect(): ward_safe_text(4)
fun tag_line(): ward_safe_text(4)
fun tag_polyline(): ward_safe_text(8)
fun tag_polygon(): ward_safe_text(7)
fun tag_text(): ward_safe_text(4)
fun tag_tspan(): ward_safe_text(5)
fun tag_use(): ward_safe_text(3)
fun tag_defs(): ward_safe_text(4)
fun tag_image(): ward_safe_text(5)
fun tag_symbol(): ward_safe_text(6)
fun tag_title(): ward_safe_text(5)
fun tag_desc(): ward_safe_text(4)

(* MathML *)
fun tag_math(): ward_safe_text(4)
fun tag_mi(): ward_safe_text(2)
fun tag_mn(): ward_safe_text(2)
fun tag_mo(): ward_safe_text(2)
fun tag_mrow(): ward_safe_text(4)
fun tag_msup(): ward_safe_text(4)
fun tag_msub(): ward_safe_text(4)
fun tag_mfrac(): ward_safe_text(5)
fun tag_msqrt(): ward_safe_text(5)
fun tag_mroot(): ward_safe_text(5)
fun tag_mover(): ward_safe_text(5)
fun tag_munder(): ward_safe_text(6)
fun tag_mtable(): ward_safe_text(6)
fun tag_mtr(): ward_safe_text(3)
fun tag_mtd(): ward_safe_text(3)
fun tag_rp(): ward_safe_text(2)
fun tag_rt(): ward_safe_text(2)

(* ========== Pre-built safe text: attributes ========== *)

fun attr_class(): ward_safe_text(5)
fun attr_id(): ward_safe_text(2)
fun attr_type(): ward_safe_text(4)
fun attr_for(): ward_safe_text(3)
fun attr_accept(): ward_safe_text(6)
fun attr_href(): ward_safe_text(4)
fun attr_src(): ward_safe_text(3)
fun attr_alt(): ward_safe_text(3)
fun attr_title(): ward_safe_text(5)
fun attr_width(): ward_safe_text(5)
fun attr_height(): ward_safe_text(6)
fun attr_lang(): ward_safe_text(4)
fun attr_dir(): ward_safe_text(3)
fun attr_role(): ward_safe_text(4)
fun attr_tabindex(): ward_safe_text(8)
fun attr_colspan(): ward_safe_text(7)
fun attr_rowspan(): ward_safe_text(7)
fun attr_xmlns(): ward_safe_text(5)
fun attr_d(): ward_safe_text(1)
fun attr_fill(): ward_safe_text(4)
fun attr_stroke(): ward_safe_text(6)
fun attr_cx(): ward_safe_text(2)
fun attr_cy(): ward_safe_text(2)
fun attr_r(): ward_safe_text(1)
fun attr_x(): ward_safe_text(1)
fun attr_y(): ward_safe_text(1)
fun attr_transform(): ward_safe_text(9)
fun attr_viewBox(): ward_safe_text(7)
fun attr_aria_label(): ward_safe_text(10)
fun attr_aria_hidden(): ward_safe_text(11)
fun attr_name(): ward_safe_text(4)
fun attr_value(): ward_safe_text(5)

(* ========== Tag/Attribute lookup from raw bytes ========== *)

(* Look up a tag name from raw bytes. Returns safe_text index or -1.
 * Used by the tree renderer to match parsed HTML tag bytes to
 * pre-built ward_safe_text constants. *)
fun lookup_tag(bytes: ptr, len: int): int = "mac#"

(* Look up an attribute name from raw bytes. Returns index or -1. *)
fun lookup_attr(bytes: ptr, len: int): int = "mac#"

(* Get a tag safe_text by index (returned by lookup_tag).
 * All tags are <= 10 chars, so n + 10 <= 4096 holds. *)
fun get_tag_by_index(idx: int): [n:pos | n <= 10] @(ward_safe_text(n), int n)

(* Get an attr safe_text by index (returned by lookup_attr).
 * All attrs are <= 11 chars, so n <= 11 holds. *)
fun get_attr_by_index(idx: int): [n:pos | n <= 11] @(ward_safe_text(n), int n)

(* ========== Tree renderer ========== *)

(* Walk parsed HTML tree binary and emit DOM nodes via ward diffs.
 * parent_id: parent DOM node for emitted elements
 * tree: pointer to parsed tree binary (from wardJsParseHtml)
 * tree_len: length of binary data
 * Returns the dom state after all emissions. *)
fun render_tree
  {l:agz}
  (state: ward_dom_state(l), parent_id: int, tree: ptr, tree_len: int)
  : ward_dom_state(l)
