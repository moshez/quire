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

(* --- Create small chapter (cover page, ~15 elements) --- *)
fun create_small_chapter {l:agz}
  (s: ward_dom_stream(l), parent: int, base: int,
   i: int, n: int): ward_dom_stream(l) =
  if i >= n then s
  else let
    val nid = base + i
    val s = ward_dom_stream_create_element(s, nid, parent, mk_p(), 1)
    val s = ward_dom_stream_set_safe_text(s, nid, mk_text(), 5)
  in create_small_chapter(s, parent, base, i + 1, n) end

(* --- Create large chapter with long text + attributes ---
 * Each element: create_element("p") + set_attr("class","demo") + set_text(100 bytes)
 * Per element: 11 + 17 + 107 = 135 bytes in diff buffer.
 * 160 elements → ~21,600 bytes (matches conan's 21,452-byte flush).
 * Text borrow is reused across all elements (frozen once). *)
fun create_large_chapter {l:agz}{lb:agz}
  (s: ward_dom_stream(l), parent: int, base: int,
   text_borrow: !ward_arr_borrow(byte, lb, 100),
   i: int, n: int): ward_dom_stream(l) =
  if i >= n then s
  else let
    val nid = base + i
    val s = ward_dom_stream_create_element(s, nid, parent, mk_p(), 1)
    val s = ward_dom_stream_set_attr_safe(s, nid, mk_class(), 5, mk_demo(), 4)
    val s = ward_dom_stream_set_text(s, nid, text_borrow, 100)
  in create_large_chapter(s, parent, base, text_borrow, i + 1, n) end

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
  val s3 = create_small_chapter(s3, 1, 10, 0, 15)
  val dom3 = ward_dom_stream_end(s3)
  val () = ward_dom_fini(dom3)

  val () = ward_arr_free<byte>(sax_buf)

  (* ============================================================
   * Phase 5: Navigate next — REMOVE_CHILDREN + large chapter
   * Matches: decompress 9213→21138, SAX 20684, flush 21452
   *
   * Target: single flush of ~21KB to match the conan crash point.
   * 160 elements × 135 bytes/element = 21,600 bytes + 5 bytes
   * for REMOVE_CHILDREN = ~21,605 total.
   * ============================================================ *)
  val () = alloc_and_free(9213)
  val () = alloc_and_free(21138)

  (* SAX buffer for large chapter stays alive during render *)
  val sax_buf2 = ward_arr_alloc<byte>(20684)
  val () = ward_arr_set<byte>(sax_buf2, 0, ward_int2byte(1))

  (* Allocate reusable 100-byte text buffer — frozen once, borrow reused *)
  val text_buf = ward_arr_alloc<byte>(100)
  (* Fill with repeating ASCII: "The gods of the north were wild and..." *)
  val () = ward_arr_set<byte>(text_buf, 0, ward_int2byte(84))  (* T *)
  val () = ward_arr_set<byte>(text_buf, 1, ward_int2byte(104)) (* h *)
  val () = ward_arr_set<byte>(text_buf, 2, ward_int2byte(101)) (* e *)
  val () = ward_arr_set<byte>(text_buf, 3, ward_int2byte(32))  (*   *)
  val () = ward_arr_set<byte>(text_buf, 4, ward_int2byte(103)) (* g *)
  val () = ward_arr_set<byte>(text_buf, 5, ward_int2byte(111)) (* o *)
  val () = ward_arr_set<byte>(text_buf, 6, ward_int2byte(100)) (* d *)
  val () = ward_arr_set<byte>(text_buf, 7, ward_int2byte(115)) (* s *)
  val () = ward_arr_set<byte>(text_buf, 8, ward_int2byte(32))  (*   *)
  val () = ward_arr_set<byte>(text_buf, 9, ward_int2byte(111)) (* o *)
  (* Fill rest with repeating space + lowercase pattern *)
  val () = ward_arr_set<byte>(text_buf, 10, ward_int2byte(102))
  val () = ward_arr_set<byte>(text_buf, 11, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 12, ward_int2byte(116))
  val () = ward_arr_set<byte>(text_buf, 13, ward_int2byte(104))
  val () = ward_arr_set<byte>(text_buf, 14, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 15, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 16, ward_int2byte(110))
  val () = ward_arr_set<byte>(text_buf, 17, ward_int2byte(111))
  val () = ward_arr_set<byte>(text_buf, 18, ward_int2byte(114))
  val () = ward_arr_set<byte>(text_buf, 19, ward_int2byte(116))
  (* positions 20-99: fill with space-separated word pattern *)
  val () = ward_arr_set<byte>(text_buf, 20, ward_int2byte(104))
  val () = ward_arr_set<byte>(text_buf, 21, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 22, ward_int2byte(119))
  val () = ward_arr_set<byte>(text_buf, 23, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 24, ward_int2byte(114))
  val () = ward_arr_set<byte>(text_buf, 25, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 26, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 27, ward_int2byte(119))
  val () = ward_arr_set<byte>(text_buf, 28, ward_int2byte(105))
  val () = ward_arr_set<byte>(text_buf, 29, ward_int2byte(108))
  val () = ward_arr_set<byte>(text_buf, 30, ward_int2byte(100))
  val () = ward_arr_set<byte>(text_buf, 31, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 32, ward_int2byte(97))
  val () = ward_arr_set<byte>(text_buf, 33, ward_int2byte(110))
  val () = ward_arr_set<byte>(text_buf, 34, ward_int2byte(100))
  val () = ward_arr_set<byte>(text_buf, 35, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 36, ward_int2byte(115))
  val () = ward_arr_set<byte>(text_buf, 37, ward_int2byte(116))
  val () = ward_arr_set<byte>(text_buf, 38, ward_int2byte(114))
  val () = ward_arr_set<byte>(text_buf, 39, ward_int2byte(97))
  (* bytes 40-99: repeat "nge and fierce " pattern *)
  val () = ward_arr_set<byte>(text_buf, 40, ward_int2byte(110))
  val () = ward_arr_set<byte>(text_buf, 41, ward_int2byte(103))
  val () = ward_arr_set<byte>(text_buf, 42, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 43, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 44, ward_int2byte(97))
  val () = ward_arr_set<byte>(text_buf, 45, ward_int2byte(110))
  val () = ward_arr_set<byte>(text_buf, 46, ward_int2byte(100))
  val () = ward_arr_set<byte>(text_buf, 47, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 48, ward_int2byte(102))
  val () = ward_arr_set<byte>(text_buf, 49, ward_int2byte(105))
  val () = ward_arr_set<byte>(text_buf, 50, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 51, ward_int2byte(114))
  val () = ward_arr_set<byte>(text_buf, 52, ward_int2byte(99))
  val () = ward_arr_set<byte>(text_buf, 53, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 54, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 55, ward_int2byte(98))
  val () = ward_arr_set<byte>(text_buf, 56, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 57, ward_int2byte(121))
  val () = ward_arr_set<byte>(text_buf, 58, ward_int2byte(111))
  val () = ward_arr_set<byte>(text_buf, 59, ward_int2byte(110))
  val () = ward_arr_set<byte>(text_buf, 60, ward_int2byte(100))
  val () = ward_arr_set<byte>(text_buf, 61, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 62, ward_int2byte(116))
  val () = ward_arr_set<byte>(text_buf, 63, ward_int2byte(104))
  val () = ward_arr_set<byte>(text_buf, 64, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 65, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 66, ward_int2byte(105))
  val () = ward_arr_set<byte>(text_buf, 67, ward_int2byte(99))
  val () = ward_arr_set<byte>(text_buf, 68, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 69, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 70, ward_int2byte(98))
  val () = ward_arr_set<byte>(text_buf, 71, ward_int2byte(111))
  val () = ward_arr_set<byte>(text_buf, 72, ward_int2byte(117))
  val () = ward_arr_set<byte>(text_buf, 73, ward_int2byte(110))
  val () = ward_arr_set<byte>(text_buf, 74, ward_int2byte(100))
  val () = ward_arr_set<byte>(text_buf, 75, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 76, ward_int2byte(119))
  val () = ward_arr_set<byte>(text_buf, 77, ward_int2byte(97))
  val () = ward_arr_set<byte>(text_buf, 78, ward_int2byte(115))
  val () = ward_arr_set<byte>(text_buf, 79, ward_int2byte(116))
  val () = ward_arr_set<byte>(text_buf, 80, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 81, ward_int2byte(115))
  val () = ward_arr_set<byte>(text_buf, 82, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 83, ward_int2byte(119))
  val () = ward_arr_set<byte>(text_buf, 84, ward_int2byte(104))
  val () = ward_arr_set<byte>(text_buf, 85, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 86, ward_int2byte(114))
  val () = ward_arr_set<byte>(text_buf, 87, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 88, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 89, ward_int2byte(116))
  val () = ward_arr_set<byte>(text_buf, 90, ward_int2byte(104))
  val () = ward_arr_set<byte>(text_buf, 91, ward_int2byte(101))
  val () = ward_arr_set<byte>(text_buf, 92, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 93, ward_int2byte(119))
  val () = ward_arr_set<byte>(text_buf, 94, ward_int2byte(105))
  val () = ward_arr_set<byte>(text_buf, 95, ward_int2byte(110))
  val () = ward_arr_set<byte>(text_buf, 96, ward_int2byte(100))
  val () = ward_arr_set<byte>(text_buf, 97, ward_int2byte(32))
  val () = ward_arr_set<byte>(text_buf, 98, ward_int2byte(104))
  val () = ward_arr_set<byte>(text_buf, 99, ward_int2byte(111))
  val @(text_frozen, text_borrow) = ward_arr_freeze<byte>(text_buf)

  val dom4 = ward_dom_init()
  val s4 = ward_dom_stream_begin(dom4)
  val s4 = ward_dom_stream_remove_children(s4, 1)
  (* Create 160 elements with text + class attr.
   * 160 × 135 bytes/element + 5 REMOVE_CHILDREN = ~21,605 bytes.
   * Single flush matches conan's ward_dom_flush(ptr, 21452). *)
  val s4 = create_large_chapter(s4, 1, 100, text_borrow, 0, 160)
  val dom4 = ward_dom_stream_end(s4)
  val () = ward_dom_fini(dom4)

  val () = ward_arr_drop<byte>(text_frozen, text_borrow)
  val text_thaw = ward_arr_thaw<byte>(text_frozen)
  val () = ward_arr_free<byte>(text_thaw)

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
