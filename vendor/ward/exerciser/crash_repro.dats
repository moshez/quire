(* crash_repro.dats — Reproduce Chromium renderer crash (ward#18).
 *
 * Evidence from WASM call recording in quire e2e tests:
 *   - Crash occurs at/after ward_dom_flush(bufPtr, 21452)
 *   - This flush creates ~500+ DOM elements for a large EPUB chapter
 *   - Pattern: small chapter render → REMOVE_CHILDREN → large chapter render
 *   - Viewport 2 trace: flush succeeds, then crashes during file_read
 *   - All 5 viewport sizes crash around the same point
 *
 * This exerciser reproduces the exact memory lifecycle:
 *   Phase 1: ZIP buffer alloc/free (65558 bytes oversized)
 *   Phase 2: Multiple DOM stream cycles (262144 bytes each)
 *   Phase 3: Decompress metadata (alloc/free cycles: 177, 252, 1028, 2725)
 *   Phase 4: Render small cover chapter (~15 elements)
 *   Phase 5: Navigate next — REMOVE_CHILDREN + render large chapter
 *            with allocations DURING the DOM stream (text wrapping)
 *   Phase 6: Post-render allocation (simulating deferred image loading)
 *
 * Build: make crash-repro   (in vendor/ward/)
 * Run:   node exerciser/crash_repro_runner.mjs *)

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

(* --- Tag/text helpers (non-linear, reusable) --- *)

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

fn mk_text (): ward_safe_text(5) = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('o'))
in ward_text_done(b) end

fn mk_class (): ward_safe_text(5) = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('l'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('s'))
  val b = ward_text_putc(b, 4, char2int1('s'))
in ward_text_done(b) end

fn mk_demo (): ward_safe_text(4) = let
  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('d'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('m'))
  val b = ward_text_putc(b, 3, char2int1('o'))
in ward_text_done(b) end

(* --- Alloc + free helper to simulate decompress/parse cycles --- *)
fn alloc_and_free (sz: int): void = let
  val pos = (if sz > 0 then sz else 1): int
  val g1 = g1ofg0(pos)
in
  if g1 > 0 then let
    val arr = ward_arr_alloc<byte>(g1)
    val () = ward_arr_set<byte>(arr, 0, ward_int2byte(42))
    val () = ward_arr_free<byte>(arr)
  in end
  else ()
end

(* --- Create elements with text wrapping (simulates render_tree) ---
 * For every 3rd element, simulate the text-wrapping pattern:
 *   1. Create a <span> child
 *   2. Allocate a buffer for the text content
 *   3. Freeze, set_text via borrow, drop, thaw, free
 * This exercises the allocator DURING an active DOM stream,
 * matching what render_tree does for text after child elements. *)
fun create_many_with_allocs {l:agz}
  (s: ward_dom_stream(l), parent: int, base: int,
   i: int, n: int): ward_dom_stream(l) =
  if i >= n then s
  else let
    val nid = base + i * 2
    val s = ward_dom_stream_create_element(s, nid, parent, mk_p(), 1)
  in
    if i mod 3 = 0 then let
      (* Text-wrapping path: create <span>, alloc text buffer, set_text *)
      val span_nid = nid + 1
      val s = ward_dom_stream_create_element(s, span_nid, nid, mk_span(), 4)
      (* Allocate text buffer — this exercises malloc during DOM stream *)
      val txt_buf = ward_arr_alloc<byte>(5)
      val () = ward_arr_set<byte>(txt_buf, 0, ward_int2byte(104)) (* h *)
      val () = ward_arr_set<byte>(txt_buf, 1, ward_int2byte(101)) (* e *)
      val () = ward_arr_set<byte>(txt_buf, 2, ward_int2byte(108)) (* l *)
      val () = ward_arr_set<byte>(txt_buf, 3, ward_int2byte(108)) (* l *)
      val () = ward_arr_set<byte>(txt_buf, 4, ward_int2byte(111)) (* o *)
      val @(frozen, borrow) = ward_arr_freeze<byte>(txt_buf)
      val s = ward_dom_stream_set_text(s, span_nid, borrow, 5)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val txt_buf2 = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(txt_buf2)
    in
      create_many_with_allocs(s, parent, base, i + 1, n)
    end
    else let
      (* Direct safe text path *)
      val s = ward_dom_stream_set_safe_text(s, nid, mk_text(), 5)
    in
      create_many_with_allocs(s, parent, base, i + 1, n)
    end
  end

(* WASM export: entry point *)
extern fun ward_node_init (root_id: int): void = "ext#ward_node_init"

implement ward_node_init (root_id) = let
  (* ============================================================
   * Phase 1: ZIP buffer (65558 bytes — oversized alloc + free)
   * Matches: ward_js_file_read:[1,89244,65558,1386224]
   * ============================================================ *)
  val zip_buf = ward_arr_alloc<byte>(65558)
  val () = ward_arr_set<byte>(zip_buf, 0, ward_int2byte(80))
  val () = ward_arr_set<byte>(zip_buf, 65557, ward_int2byte(75))
  val () = ward_arr_free<byte>(zip_buf)

  (* ============================================================
   * Phase 2: Container + UI setup (multiple DOM cycles)
   * ============================================================ *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_create_element(s, 1, root_id, mk_div(), 3)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* ============================================================
   * Phase 3: Decompress metadata (alloc/free cycles matching trace)
   * Matches: decompress 177→252, decompress 1028→2725
   * ============================================================ *)
  val () = alloc_and_free(177)
  val () = alloc_and_free(252)
  val () = alloc_and_free(1028)
  val () = alloc_and_free(2725)

  (* Library rebuild DOM cycle *)
  val dom2 = ward_dom_init()
  val s2 = ward_dom_stream_begin(dom2)
  val s2 = ward_dom_stream_create_element(s2, 2, 1, mk_div(), 3)
  val s2 = ward_dom_stream_set_attr_safe(s2, 2, mk_class(), 5, mk_demo(), 4)
  val dom2 = ward_dom_stream_end(s2)
  val () = ward_dom_fini(dom2)

  (* ============================================================
   * Phase 4: Cover chapter (small — decompress 322→549, SAX 252)
   * ============================================================ *)
  val () = alloc_and_free(322)
  val () = alloc_and_free(549)

  (* SAX buffer stays alive during render *)
  val sax_buf = ward_arr_alloc<byte>(252)
  val () = ward_arr_set<byte>(sax_buf, 0, ward_int2byte(1))

  val dom3 = ward_dom_init()
  val s3 = ward_dom_stream_begin(dom3)
  val s3 = create_many_with_allocs(s3, 1, 10, 0, 15)
  val dom3 = ward_dom_stream_end(s3)
  val () = ward_dom_fini(dom3)

  val () = ward_arr_free<byte>(sax_buf)

  (* ============================================================
   * Phase 5: Navigate next — REMOVE_CHILDREN + large chapter
   * Matches: decompress 9213→21138, SAX 20684, flush 21452
   * ============================================================ *)
  val () = alloc_and_free(9213)
  val () = alloc_and_free(21138)

  (* SAX buffer for large chapter stays alive during render *)
  val sax_buf2 = ward_arr_alloc<byte>(20684)
  val () = ward_arr_set<byte>(sax_buf2, 0, ward_int2byte(1))

  val dom4 = ward_dom_init()
  val s4 = ward_dom_stream_begin(dom4)
  val s4 = ward_dom_stream_remove_children(s4, 1)
  (* Create 500 elements with allocs (matching render_tree's text wrapping).
   * Each element ~= 2 node IDs (p + span for wrapping).
   * Produces ~20000+ bytes of DOM diffs. *)
  val s4 = create_many_with_allocs(s4, 1, 100, 0, 500)
  val dom4 = ward_dom_stream_end(s4)
  val () = ward_dom_fini(dom4)

  val () = ward_arr_free<byte>(sax_buf2)

  (* ============================================================
   * Phase 6: Post-render image loading
   * Matches: ward_js_file_read:[1,114799,30,1486664] then crash
   * Allocate buffer for image data AFTER the big render flush.
   * ============================================================ *)
  val img_hdr = ward_arr_alloc<byte>(30)
  val () = ward_arr_set<byte>(img_hdr, 0, ward_int2byte(80))
  val () = ward_arr_free<byte>(img_hdr)

  (* Image data allocation (oversized: > 4096 bytes) *)
  val img_data = ward_arr_alloc<byte>(5000)
  val () = ward_arr_set<byte>(img_data, 0, ward_int2byte(137))
  val () = ward_arr_free<byte>(img_data)

  val () = ward_exit()
in end
