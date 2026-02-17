(* crash_repro.dats — Reproduce Chromium renderer crash (ward#18).
 *
 * Uses the EXACT 21138-byte HTML from conan-stories.epub chapter 0,
 * compressed as 9213 bytes of deflate-raw data. Matches the exact
 * quire crash path:
 *
 *   1. ward_node_init: create container + 15 cover elements
 *   2. ward_decompress: async DecompressionStream (deflate-raw)
 *   3. Callback: ward_blob_read → ward_xml_parse_html → SAX render
 *   4. ward_dom_stream_end flushes diffs → CRASH?
 *   5. ward_measure_node forces synchronous layout reflow
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

(* --- Compressed conan chapter (9213 bytes deflate-raw → 21138 bytes) ---
 * Uses the exact compressed data from conan-stories.epub chapter 0. *)

%{
#include "../exerciser/conan_compressed.h"
%}

extern fun copy_conan_compressed {l:agz}
  (dst: !ward_arr(byte, l, 9213)): void = "mac#"

#define COMP_SIZE 9213

(* --- Copy bytes from SAX borrow to a new mutable ward_arr ---
 * Since ward_arr_borrow and ward_arr are different types, we read byte-by-byte
 * from the borrow using ward_arr_read and write to the new array. *)

fun copy_borrow_bytes {lb:agz}{nb:pos}{la:agz}{na:pos}
  (dst: !ward_arr(byte, la, na), dlen: int na,
   src: !ward_arr_borrow(byte, lb, nb), slen: int nb,
   src_off: int, i: int, count: int): void =
  if gte_int_int(i, count) then ()
  else let
    val off_g1 = g1ofg0(add_int_int(src_off, i))
    val i_g1 = g1ofg0(i)
  in
    if gte1_int_int(off_g1, 0) then
      if lt1_int_int(off_g1, slen) then
        if gte1_int_int(i_g1, 0) then
          if lt1_int_int(i_g1, dlen) then let
            val b = ward_arr_read<byte>(src, off_g1)
            val () = ward_arr_set<byte>(dst, i_g1, b)
          in copy_borrow_bytes(dst, dlen, src, slen, src_off, add_int_int(i, 1), count) end
          else ()
        else ()
      else ()
    else ()
  end

(* --- Walk SAX binary and render DOM via ward_dom_stream ---
 * Matches quire's render_tree: creates elements, copies text from SAX
 * binary into new arrays, and calls ward_dom_stream_set_text.
 * This produces the full ~21KB DOM flush that triggers the crash. *)

fun render_sax {l:agz}{lb:agz}{n:pos}
  (s: ward_dom_stream(l),
   sax: !ward_arr_borrow(byte, lb, n), sax_len: int n,
   parent: int, pos: int, next_id: int,
   has_child: int): @(ward_dom_stream(l), int, int) =
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
        (* Recurse into children with has_child=0 for the new scope *)
        val @(s, after_children, nid2) =
          render_sax(s, sax, sax_len, nid, child_pos, add_int_int(next_id, 1), 0)
        (* Continue with siblings — has_child=1 since we just created an element *)
      in render_sax(s, sax, sax_len, parent, after_children, nid2, 1) end

      else if eq_int_int(opc, WARD_XML_ELEMENT_CLOSE) then
        (* Return to parent — pos+1 is the next sibling position *)
        @(s, add_int_int(pos, 1), next_id)

      else if eq_int_int(opc, WARD_XML_TEXT) then let
        val @(text_off, text_len, next_pos) =
          ward_xml_read_text(sax, p, sax_len)
        val tl = g1ofg0(text_len)
      in
        if lt1_int_int(0, tl) then
          if lt1_int_int(tl, 65536) then
            if gt_int_int(has_child, 0) then let
              (* TEXT_RENDER_SAFE: parent has children — wrap in <span> *)
              val nid = next_id
              val s = ward_dom_stream_create_element(s, nid, parent, mk_span(), 4)
              (* Copy text from SAX borrow to new array, set on span *)
              val text_arr = ward_arr_alloc<byte>(tl)
              val () = copy_borrow_bytes(text_arr, tl, sax, sax_len, text_off, 0, text_len)
              val @(frozen, borrow) = ward_arr_freeze<byte>(text_arr)
              val s = ward_dom_stream_set_text(s, nid, borrow, tl)
              val () = ward_arr_drop<byte>(frozen, borrow)
              val text_arr2 = ward_arr_thaw<byte>(frozen)
              val () = ward_arr_free<byte>(text_arr2)
            in render_sax(s, sax, sax_len, parent, next_pos, add_int_int(next_id, 1), 1) end
            else let
              (* TEXT_RENDER_SAFE: no children — set_text directly on parent *)
              val text_arr = ward_arr_alloc<byte>(tl)
              val () = copy_borrow_bytes(text_arr, tl, sax, sax_len, text_off, 0, text_len)
              val @(frozen, borrow) = ward_arr_freeze<byte>(text_arr)
              val s = ward_dom_stream_set_text(s, parent, borrow, tl)
              val () = ward_arr_drop<byte>(frozen, borrow)
              val text_arr2 = ward_arr_thaw<byte>(frozen)
              val () = ward_arr_free<byte>(text_arr2)
            in render_sax(s, sax, sax_len, parent, next_pos, next_id, 1) end
          else (* text too large — skip *)
            render_sax(s, sax, sax_len, parent, next_pos, next_id, has_child)
        else render_sax(s, sax, sax_len, parent, next_pos, next_id, has_child)
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
   * Phase 3: Decompress chapter via DecompressionStream.
   * This is the EXACT path quire takes: compressed ZIP entry →
   * ward_decompress(deflate-raw) → async callback → blob_read →
   * parse HTML → render DOM.
   * ============================================================ *)
  val comp_buf = ward_arr_alloc<byte>(COMP_SIZE)
  val () = copy_conan_compressed(comp_buf)
  val @(c_frozen, c_borrow) = ward_arr_freeze<byte>(comp_buf)
  val decomp_p = ward_decompress(c_borrow, COMP_SIZE, 2)
  (* JS pipes data synchronously into DecompressionStream — safe to free *)
  val () = ward_arr_drop<byte>(c_frozen, c_borrow)
  val comp_buf2 = ward_arr_thaw<byte>(c_frozen)
  val () = ward_arr_free<byte>(comp_buf2)

  (* ============================================================
   * Phase 4: Decompress callback — read blob, parse HTML, render
   * ============================================================ *)
  val render_p = ward_promise_then<int><int>(decomp_p,
    llam (blob_handle: int) => let
      val decomp_len = ward_decompress_get_len()
      val dl = g1ofg0(decomp_len)
    in
      if lt1_int_int(0, dl) then let
        (* Read decompressed HTML from blob into ward_arr *)
        val html_buf = ward_arr_alloc<byte>(dl)
        val _bytes = ward_blob_read(blob_handle, 0, html_buf, dl)
        val () = ward_blob_free(blob_handle)

        (* Parse HTML via ward_xml_parse_html (calls JS DOMParser) *)
        val @(h_frozen, h_borrow) = ward_arr_freeze<byte>(html_buf)
        val sax_len = ward_xml_parse_html(h_borrow, dl)
        val () = ward_arr_drop<byte>(h_frozen, h_borrow)
        val html_buf2 = ward_arr_thaw<byte>(h_frozen)
        val () = ward_arr_free<byte>(html_buf2)
      in
        if gt_int_int(sax_len, 0) then let
          val sax_g1 = g1ofg0(sax_len)
        in
          if lt1_int_int(0, sax_g1) then let
            (* Retrieve SAX binary result *)
            val sax = ward_xml_get_result(sax_g1)
            val @(sax_frozen, sax_borrow) = ward_arr_freeze<byte>(sax)

            (* REMOVE_CHILDREN + render from SAX with text content *)
            val dom3 = ward_dom_init()
            val s3 = ward_dom_stream_begin(dom3)
            val s3 = ward_dom_stream_remove_children(s3, 1)
            val @(s3, _, _) = render_sax(s3, sax_borrow, sax_g1, 1, 0, 100, 0)
            val dom3 = ward_dom_stream_end(s3)
            val () = ward_dom_fini(dom3)

            (* Measure container — forces synchronous layout reflow *)
            val _found = ward_measure_node(1)

            val () = ward_arr_drop<byte>(sax_frozen, sax_borrow)
            val sax2 = ward_arr_thaw<byte>(sax_frozen)
            val () = ward_arr_free<byte>(sax2)
          in ward_promise_return<int>(0) end
          else ward_promise_return<int>(0)
        end
        else ward_promise_return<int>(0)
      end
      else let
        val () = ward_blob_free(blob_handle)
      in ward_promise_return<int>(0) end
    end)
  val exit_p = ward_promise_then<int><int>(render_p,
    llam (_x: int) => let
      val () = ward_exit()
    in ward_promise_return<int>(0) end)
  val () = ward_promise_discard(exit_p)
in end
