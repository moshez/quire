(* crash_repro.dats — Reproduce Chromium renderer crash (ward#18).
 *
 * The crash occurs when quire loads a 21KB deflate-compressed HTML chapter
 * from the conan EPUB. The previous exerciser (500 flat elements) did NOT
 * crash because it skipped the critical operation: wardJsParseHtml.
 *
 * This exerciser replicates the exact crash path:
 *   1. Build ~21KB HTML string in WASM memory (matching conan chapter size)
 *   2. Call ward_xml_parse_html (DOMParser in JS → binary SAX)
 *   3. Walk SAX and render DOM via ward_dom_stream
 *   4. ward_dom_stream_end flushes ~21KB of DOM diffs → CRASH
 *
 * Build: make crash-repro   (in vendor/ward/)
 * Run:   open exerciser/crash_repro.html in Chromium *)

#include "share/atspre_staload.hats"
staload "./../lib/memory.sats"
staload "./../lib/dom.sats"
staload "./../lib/promise.sats"
staload "./../lib/event.sats"
staload "./../lib/idb.sats"
staload "./../lib/window.sats"
staload "./../lib/nav.sats"
staload "./../lib/dom_read.sats"
staload "./../lib/listener.sats"
staload "./../lib/fetch.sats"
staload "./../lib/clipboard.sats"
staload "./../lib/file.sats"
staload "./../lib/decompress.sats"
staload "./../lib/notify.sats"
staload "./../lib/callback.sats"
staload "./../lib/xml.sats"
dynload "./../lib/memory.dats"
dynload "./../lib/dom.dats"
dynload "./../lib/promise.dats"
dynload "./../lib/event.dats"
dynload "./../lib/idb.dats"
dynload "./../lib/window.dats"
dynload "./../lib/nav.dats"
dynload "./../lib/dom_read.dats"
dynload "./../lib/listener.dats"
dynload "./../lib/fetch.dats"
dynload "./../lib/clipboard.dats"
dynload "./../lib/file.dats"
dynload "./../lib/decompress.dats"
dynload "./../lib/notify.dats"
dynload "./../lib/callback.dats"
dynload "./../lib/xml.dats"
staload _ = "./../lib/memory.dats"
staload _ = "./../lib/dom.dats"
staload _ = "./../lib/promise.dats"
staload _ = "./../lib/event.dats"
staload _ = "./../lib/idb.dats"
staload _ = "./../lib/window.dats"
staload _ = "./../lib/nav.dats"
staload _ = "./../lib/dom_read.dats"
staload _ = "./../lib/listener.dats"
staload _ = "./../lib/fetch.dats"
staload _ = "./../lib/clipboard.dats"
staload _ = "./../lib/file.dats"
staload _ = "./../lib/decompress.dats"
staload _ = "./../lib/notify.dats"
staload _ = "./../lib/callback.dats"
staload _ = "./../lib/xml.dats"

(* --- Freestanding arithmetic (no prelude templates) --- *)

extern fun add_int_int(a: int, b: int): int = "mac#atspre_g0int_add_int"
extern fun sub_int_int(a: int, b: int): int = "mac#atspre_g0int_sub_int"
extern fun mul_int_int(a: int, b: int): int = "mac#atspre_g0int_mul_int"
extern fun mod_int_int(a: int, b: int): int = "mac#atspre_g0int_mod_int"
extern fun eq_int_int(a: int, b: int): bool = "mac#atspre_g0int_eq_int"
extern fun lt_int_int(a: int, b: int): bool = "mac#atspre_g0int_lt_int"
extern fun gt_int_int(a: int, b: int): bool = "mac#atspre_g0int_gt_int"
extern fun gte_int_int(a: int, b: int): bool = "mac#atspre_g0int_gte_int"
extern fun lte_int_int(a: int, b: int): bool = "mac#atspre_g0int_lte_int"

(* Dependent comparisons for ward_arr_set bounds *)
extern fun lt1_int_int {a,b:int}
  (a: int a, b: int b): bool(a < b) = "mac#atspre_g0int_lt_int"
extern fun gte1_int_int {a,b:int}
  (a: int a, b: int b): bool(a >= b) = "mac#atspre_g0int_gte_int"

(* --- Safe text tag helpers --- *)

fn mk_div (): ward_safe_text(3) = let
  val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('v'))
in ward_text_done(b) end

fn mk_p (): ward_safe_text(1) = let
  val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('p'))
in ward_text_done(b) end

fn mk_span (): ward_safe_text(4) = let
  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('p'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('n'))
in ward_text_done(b) end

fn mk_dummy_text (): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('b'))
  val b = ward_text_putc(b, 2, char2int1('c'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, char2int1('e'))
  val b = ward_text_putc(b, 5, char2int1('f'))
  val b = ward_text_putc(b, 6, char2int1('g'))
  val b = ward_text_putc(b, 7, char2int1('h'))
  val b = ward_text_putc(b, 8, char2int1('i'))
  val b = ward_text_putc(b, 9, char2int1('j'))
in ward_text_done(b) end

(* --- Bounds-checked byte write ---
 * pos is g0int (plain), uses g1ofg0 + dependent lt1 for ward_arr_set *)

fn wb {l:agz}{n:pos}{b:nat | b < 256}
  (buf: !ward_arr(byte, l, n), pos: int, b: int b, sz: int n): void = let
  val p = g1ofg0(pos)
in
  if gte1_int_int(p, 0) then
    if lt1_int_int(p, sz) then
      ward_arr_set<byte>(buf, p, ward_int2byte(b))
    else ()
  else ()
end

(* --- Fill buffer range with 'A' (65) --- *)

fun fill_text {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), pos: int, count: int, sz: int n): void =
  if lte_int_int(count, 0) then ()
  else let
    val () = wb(buf, pos, 65, sz)
  in fill_text(buf, add_int_int(pos, 1), sub_int_int(count, 1), sz) end

(* --- Write HTML paragraphs into buffer ---
 * Each paragraph: <p>TEXT</p>\n = 3 + 190 + 5 = 198 bytes
 * 108 paragraphs = 21384 bytes + header/footer *)

fun write_paras {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), pos: int, count: int, sz: int n): int =
  if lte_int_int(count, 0) then pos
  else let
    val () = wb(buf, pos, 60, sz)                    (* < *)
    val () = wb(buf, add_int_int(pos, 1), 112, sz)   (* p *)
    val () = wb(buf, add_int_int(pos, 2), 62, sz)    (* > *)
    val () = fill_text(buf, add_int_int(pos, 3), 190, sz)
    val ep = add_int_int(pos, 193)
    val () = wb(buf, ep, 60, sz)                     (* < *)
    val () = wb(buf, add_int_int(ep, 1), 47, sz)     (* / *)
    val () = wb(buf, add_int_int(ep, 2), 112, sz)    (* p *)
    val () = wb(buf, add_int_int(ep, 3), 62, sz)     (* > *)
    val () = wb(buf, add_int_int(ep, 4), 10, sz)     (* \n *)
  in write_paras(buf, add_int_int(ep, 5), sub_int_int(count, 1), sz) end

(* --- Build ~21KB HTML string in a ward_arr ---
 * Structure: <html><body>\n + 108 paragraphs + </body></html>
 * Returns frozen array + borrow for passing to ward_xml_parse_html *)

#define HTML_SIZE 110000

fn build_html (): [l:agz] ward_arr(byte, l, HTML_SIZE) = let
  val buf = ward_arr_alloc<byte>(HTML_SIZE)
  (* <html><body>\n = 13 bytes *)
  val () = wb(buf, 0, 60, HTML_SIZE)    (* < *)
  val () = wb(buf, 1, 104, HTML_SIZE)   (* h *)
  val () = wb(buf, 2, 116, HTML_SIZE)   (* t *)
  val () = wb(buf, 3, 109, HTML_SIZE)   (* m *)
  val () = wb(buf, 4, 108, HTML_SIZE)   (* l *)
  val () = wb(buf, 5, 62, HTML_SIZE)    (* > *)
  val () = wb(buf, 6, 60, HTML_SIZE)    (* < *)
  val () = wb(buf, 7, 98, HTML_SIZE)    (* b *)
  val () = wb(buf, 8, 111, HTML_SIZE)   (* o *)
  val () = wb(buf, 9, 100, HTML_SIZE)   (* d *)
  val () = wb(buf, 10, 121, HTML_SIZE)  (* y *)
  val () = wb(buf, 11, 62, HTML_SIZE)   (* > *)
  val () = wb(buf, 12, 10, HTML_SIZE)   (* \n *)
  (* 550 paragraphs — produces ~100KB HTML, enough DOM ops for ~21KB diff *)
  val end_pos = write_paras(buf, 13, 550, HTML_SIZE)
  (* </body></html> = 14 bytes *)
  val () = wb(buf, end_pos, 60, HTML_SIZE)                     (* < *)
  val () = wb(buf, add_int_int(end_pos, 1), 47, HTML_SIZE)    (* / *)
  val () = wb(buf, add_int_int(end_pos, 2), 98, HTML_SIZE)    (* b *)
  val () = wb(buf, add_int_int(end_pos, 3), 111, HTML_SIZE)   (* o *)
  val () = wb(buf, add_int_int(end_pos, 4), 100, HTML_SIZE)   (* d *)
  val () = wb(buf, add_int_int(end_pos, 5), 121, HTML_SIZE)   (* y *)
  val () = wb(buf, add_int_int(end_pos, 6), 62, HTML_SIZE)    (* > *)
  val () = wb(buf, add_int_int(end_pos, 7), 60, HTML_SIZE)    (* < *)
  val () = wb(buf, add_int_int(end_pos, 8), 47, HTML_SIZE)    (* / *)
  val () = wb(buf, add_int_int(end_pos, 9), 104, HTML_SIZE)   (* h *)
  val () = wb(buf, add_int_int(end_pos, 10), 116, HTML_SIZE)  (* t *)
  val () = wb(buf, add_int_int(end_pos, 11), 109, HTML_SIZE)  (* m *)
  val () = wb(buf, add_int_int(end_pos, 12), 108, HTML_SIZE)  (* l *)
  val () = wb(buf, add_int_int(end_pos, 13), 62, HTML_SIZE)   (* > *)
in buf end

(* --- Walk SAX binary and render DOM via ward_dom_stream ---
 * Simplified render_tree: all elements become <p>, text creates <span>.
 * Skips attributes (not needed to trigger flush-size crash). *)

fun render_sax {l:agz}{lb:agz}{n:pos}
  (s: ward_dom_stream(l),
   sax: !ward_arr_borrow(byte, lb, n), sax_len: int n,
   parent: int, pos: int, next_id: int,
   dtxt: ward_safe_text(10)): @(ward_dom_stream(l), int, int) =
  if lt_int_int(pos, 0) then @(s, pos, next_id)
  else let
    val p = g1ofg0(pos)
  in
    if lt1_int_int(p, 0) then @(s, pos, next_id)
    else if lt1_int_int(p, sax_len) then let
      val opc = ward_xml_opcode(sax, p)
    in
      if eq_int_int(opc, WARD_XML_ELEMENT_OPEN) then let
        val @(tag_off, tag_len, attr_count, after_tag) =
          ward_xml_element_open(sax, p, sax_len)
        (* Skip attributes *)
        fun skip_attrs {lb2:agz}{n2:pos}
          (sax2: !ward_arr_borrow(byte, lb2, n2),
           sl: int n2, ap: int, ac: int): int =
          if lte_int_int(ac, 0) then ap
          else if lt_int_int(ap, 0) then ap
          else let
            val ap1 = g1ofg0(ap)
          in
            if lt1_int_int(ap1, 0) then sub_int_int(0, 1)
            else if lt1_int_int(ap1, sl) then let
              val @(_, _, _, _, next) = ward_xml_read_attr(sax2, ap1, sl)
            in skip_attrs(sax2, sl, next, sub_int_int(ac, 1)) end
            else sub_int_int(0, 1)
          end
        val child_pos = skip_attrs(sax, sax_len, after_tag, attr_count)
        val nid = next_id
        val s = ward_dom_stream_create_element(s, nid, parent, mk_p(), 1)
        (* Recurse into children *)
        val @(s, after_children, nid2) =
          render_sax(s, sax, sax_len, nid, child_pos, add_int_int(next_id, 1), dtxt)
        (* Continue with siblings *)
      in render_sax(s, sax, sax_len, parent, after_children, nid2, dtxt) end

      else if eq_int_int(opc, WARD_XML_ELEMENT_CLOSE) then
        (* Return to parent — pos+1 is the next sibling position *)
        @(s, add_int_int(pos, 1), next_id)

      else if eq_int_int(opc, WARD_XML_TEXT) then let
        val @(text_off, text_len, next_pos) =
          ward_xml_read_text(sax, p, sax_len)
      in
        if gt_int_int(text_len, 0) then let
          (* Create a span for the text, then set text content *)
          val nid = next_id
          val s = ward_dom_stream_create_element(s, nid, parent, mk_span(), 4)
          val s = ward_dom_stream_set_safe_text(s, nid, dtxt, 10)
        in render_sax(s, sax, sax_len, parent, next_pos, add_int_int(next_id, 1), dtxt) end
        else render_sax(s, sax, sax_len, parent, next_pos, next_id, dtxt)
      end

      else (* unknown opcode — skip *)
        @(s, add_int_int(pos, 1), next_id)
    end
    else @(s, pos, next_id)
  end

(* WASM export: entry point *)
extern fun ward_node_init (root_id: int): void = "ext#ward_node_init"

implement ward_node_init (root_id) = let
  (* ============================================================
   * Phase 1: Create container (matches quire reader setup)
   * ============================================================ *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_create_element(s, 1, root_id, mk_div(), 3)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* ============================================================
   * Phase 2: Small cover chapter (~15 elements)
   * ============================================================ *)
  val dom2 = ward_dom_init()
  val s2 = ward_dom_stream_begin(dom2)
  fun create_cover {l:agz}
    (s: ward_dom_stream(l), i: int): ward_dom_stream(l) =
    if gte_int_int(i, 15) then s
    else let
      val nid = add_int_int(10, i)
      val s = ward_dom_stream_create_element(s, nid, 1, mk_p(), 1)
    in create_cover(s, add_int_int(i, 1)) end
  val s2 = create_cover(s2, 0)
  val dom2 = ward_dom_stream_end(s2)
  val () = ward_dom_fini(dom2)

  (* ============================================================
   * Phase 3: Navigate next — REMOVE_CHILDREN + HTML parse + render
   * This is the crash path: build HTML, parse via DOMParser,
   * walk SAX, render DOM elements producing ~21KB flush.
   * ============================================================ *)

  (* Build ~21KB HTML in WASM memory *)
  val html_buf = build_html()

  (* Parse HTML via ward_xml_parse_html (calls JS DOMParser) *)
  val @(frozen, borrow) = ward_arr_freeze<byte>(html_buf)
  val sax_len = ward_xml_parse_html(borrow, HTML_SIZE)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val html_buf2 = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(html_buf2)

  val sax_g1 = g1ofg0(sax_len)
in
  if gt_int_int(sax_len, 0) then let
    val sax_g1 = g1ofg0(sax_len)
  in
    if lt1_int_int(0, sax_g1) then let
      (* Retrieve SAX binary *)
      val sax = ward_xml_get_result(sax_g1)
      val @(sax_frozen, sax_borrow) = ward_arr_freeze<byte>(sax)

      (* REMOVE_CHILDREN + render from SAX *)
      val dom3 = ward_dom_init()
      val s3 = ward_dom_stream_begin(dom3)
      val s3 = ward_dom_stream_remove_children(s3, 1)
      val dtxt = mk_dummy_text()
      val @(s3, _, _) = render_sax(s3, sax_borrow, sax_g1, 1, 0, 100, dtxt)
      val dom3 = ward_dom_stream_end(s3)
      val () = ward_dom_fini(dom3)

      val () = ward_arr_drop<byte>(sax_frozen, sax_borrow)
      val sax2 = ward_arr_thaw<byte>(sax_frozen)
      val () = ward_arr_free<byte>(sax2)

      val () = ward_exit()
    in end
    else let
      val () = ward_exit()
    in end
  end
  else let
    val () = ward_exit()
  in end
end
