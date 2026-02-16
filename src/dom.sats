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

(* ========== Skippable tag indices ========== *)

(* Dataprop enum: only whitelisted tag indices can be skipped.
 * MUST match _tag_names table indices in dom.dats.
 * Single source of truth — if the tag table is reordered,
 * update these constants. Adding a new constructor is the ONLY
 * way to make a tag index skippable. *)
dataprop SKIPPABLE_TAG(idx: int) =
  | SKIP_IMG(13)

#define TAG_IDX_IMG 13

(* Attribute index for src — matches _attr_names table *)
#define ATTR_IDX_SRC 6

(* ========== Tag/Attribute lookup from raw bytes ========== *)

(* Look up a tag name from raw bytes. Returns safe_text index or -1.
 * Uses static C data tables + ATS2 loop (compact WASM).
 * Used by the tree renderer to match parsed HTML tag bytes to
 * pre-built ward_safe_text constants. *)
fun lookup_tag {lb:agz}{n:pos}
  (tree: !ward_arr(byte, lb, n), tlen: int n, offset: int, name_len: int): int

(* Look up an attribute name from raw bytes. Returns index or -1. *)
fun lookup_attr {lb:agz}{n:pos}
  (tree: !ward_arr(byte, lb, n), tlen: int n, offset: int, name_len: int): int

(* Get a tag safe_text by index (returned by lookup_tag).
 * All tags are <= 10 chars, so n + 10 <= 4096 holds. *)
fun get_tag_by_index(idx: int): [n:pos | n <= 10] @(ward_safe_text(n), int n)

(* Get an attr safe_text by index (returned by lookup_attr).
 * All attrs are <= 11 chars, so n <= 11 holds. *)
fun get_attr_by_index(idx: int): [n:pos | n <= 11] @(ward_safe_text(n), int n)

(* ========== Render limits ========== *)

(* Maximum DOM elements created per render_tree / render_tree_with_images call.
 * Prevents unbounded DOM node creation from malformed or adversarial EPUB content.
 * 10000 is generous — real EPUB chapters rarely exceed a few hundred elements.
 * When the limit is reached, remaining SAX events are skipped silently. *)
#define MAX_RENDER_ELEMENTS 10000

(* ========== Windowed rendering proofs ========== *)

(* RENDER_BOUNDED: element count never exceeds hard budget.
 * Constructed after render_tree returns ecnt. *)
dataprop RENDER_BOUNDED(ecnt: int, budget: int) =
  | {e,b:nat | e <= b} UNDER_BUDGET(e, b)

(* WINDOW_OPTIMAL: window size is the largest that fits the budget.
 * Each constructor encodes WHY that size was chosen.
 * epp = elements per page, budget = MAX_RENDER_ELEMENTS. *)
dataprop WINDOW_OPTIMAL(window: int, epp: int, budget: int) =
  | {e,b:nat | 5*e <= b} WINDOW_5(5, e, b)
  | {e,b:nat | 3*e <= b; 5*e > b} WINDOW_3(3, e, b)
  | {e,b:nat | e <= b; 3*e > b} WINDOW_1(1, e, b)

(* ADVERSARIAL_PAGE: single page exceeds budget — content too dense.
 * Triggers visible error + log details. *)
dataprop ADVERSARIAL_PAGE(epp: int, budget: int) =
  | {e,b:nat | e > b} TOO_DENSE(e, b)

(* ========== Tree renderer ========== *)

(* TEXT_RENDER_SAFE invariant (prevents set_text from destroying existing children):
 *
 * ward_dom_stream_set_text sets textContent, REPLACING all existing children
 * with a single text node. render_tree tracks has_child (0 or 1) per scope:
 *
 *   has_child=0: parent has no DOM children yet.
 *     set_text(parent) is safe — nothing to destroy.
 *   has_child=1: parent has at least one DOM child (text or element).
 *     TEXT must be wrapped in <span>; set_text called on span, not parent.
 *
 * Transitions: has_child goes 0→1 after any TEXT or ELEMENT_OPEN creates
 * a DOM child. Entering a child scope resets to 0. Skipping whitespace-only
 * text or unknown elements does NOT change has_child (no DOM node created).
 *
 * Bug classes prevented:
 * - Whitespace text between <h1> and <p> wiping <h1> via set_text
 * - Non-whitespace text after element children wiping siblings
 * - Split large text fragments where second set_text wipes first
 * - Mixed inline content (text + elements) losing text or elements
 *)
dataprop TEXT_RENDER_SAFE(has_child: int) =
  | TEXT_ON_EMPTY(0)  (* no children yet — set_text on parent is safe *)

(* SIBLING_CONTINUATION invariant (prevents render_tree first-element-only bug):
 *
 * The render_tree loop must process ALL sibling elements under a parent.
 * Every branch in the loop must either:
 * (a) call loop() recursively to continue processing the next sibling, OR
 * (b) return @(st, pos) ONLY when opc = ELEMENT_CLOSE (returning to parent)
 *     or pos >= len (buffer exhausted)
 *
 * Bug class prevented: returning after processing one known element causes
 * all subsequent siblings to be silently dropped (e.g., <h1> renders but
 * sibling <p> elements are never visited).
 *
 * This is documented rather than encoded as dataprop because the invariant
 * is structural (about recursion shape) rather than about data values.
 * The correct pattern for each SAX opcode:
 *   ELEMENT_OPEN (known):   create element, process children, then loop()
 *   ELEMENT_OPEN (unknown): skip_element, then loop()
 *   TEXT:                    render text, then loop()
 *   ELEMENT_CLOSE:           return @(st, pos) — only valid exit
 *)

(* Walk parsed HTML tree binary and emit DOM nodes via ward stream.
 * parent_id: parent DOM node for emitted elements
 * tree: pointer to parsed tree binary (from wardJsParseHtml)
 * tree_len: length of binary data
 * Returns the stream after all emissions. Caller manages begin/end. *)
fun render_tree
  {l:agz}{lb:agz}{n:pos}
  (stream: ward_dom_stream(l), parent_id: int,
   tree: !ward_arr(byte, lb, n), tree_len: int n)
  : ward_dom_stream(l)

(* Walk parsed HTML tree with inline image loading from EPUB ZIP.
 * Like render_tree but handles <img> tags: resolves src relative to
 * chapter_dir, reads stored image data from ZIP, sets image via
 * ward_dom_stream_set_image_src with detected MIME type.
 * Deflated or missing images degrade gracefully (element without src). *)
fun render_tree_with_images
  {l:agz}{lb:agz}{n:pos}{ld:agz}{nd:pos}
  (stream: ward_dom_stream(l), parent_id: int,
   tree: !ward_arr(byte, lb, n), tree_len: int n,
   file_handle: int,
   chapter_dir: !ward_arr(byte, ld, nd), chapter_dir_len: int nd)
  : ward_dom_stream(l)

(* Get element count from the last render_tree / render_tree_with_images call.
 * Stored in a C static variable — avoids struct return across compilation
 * units which causes ABI mismatch with WASM LTO. *)
fun dom_get_render_ecnt(): int

(* Standalone crash reproduction: exercises render_tree_with_images
 * with a minimal SAX tree containing <img src="x">.
 * try_set_image calls malloc(4097) which crashes Chromium's renderer
 * when called from inside the render loop.
 * Returns 0 on success (no crash). *)
fun crash_repro_render(): int = "mac#"
