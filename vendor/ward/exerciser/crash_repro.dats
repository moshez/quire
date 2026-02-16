(* crash_repro.dats — Reproduce oversized allocator crash.
 *
 * Evidence from quire e2e tests:
 *   - Image data <= 4096 bytes: PASSES (bucketed malloc path)
 *   - Image data >= 4097 bytes: CRASHES (oversized malloc path)
 *   - Crash is inside ward_arr_alloc<byte>(N) where N > 4096
 *   - Crash happens during render_tree_with_images when DOM stream is active
 *   - The oversized free list contains a previously-freed block from zip_open
 *
 * This exerciser reproduces the exact allocation pattern:
 *   1. Alloc + free an oversized block (simulates zip search buffer)
 *   2. Multiple DOM stream begin/end cycles (256KB diff buffer alloc/free)
 *   3. During an active DOM stream, alloc 5000 bytes for image data
 *      → this triggers the oversized malloc path → CRASH
 *
 * Build: see Makefile target crash-repro
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

(* --- Tag/text helpers --- *)

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

fn mk_img (): ward_safe_text(3) = let
  val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('g'))
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

fn mk_text (): ward_safe_text(5) = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('l'))
  val b = ward_text_putc(b, 4, char2int1('o'))
in ward_text_done(b) end

(* --- Image with configurable size --- *)
(* Allocates N bytes for image data (oversized when N > 4096).
 * Calls ward_dom_stream_set_image_src which flushes the diff buffer
 * before making the direct bridge call. *)
fn set_image_sized {l:agz}{n:int | n >= 5}
  (s: ward_dom_stream(l), nid: int, sz: int n): ward_dom_stream(l) = let
  val d = ward_arr_alloc<byte>(sz)
  (* Write a fake PNG header at the start *)
  val () = ward_arr_set<byte>(d, 0, ward_int2byte(137))
  val () = ward_arr_set<byte>(d, 1, ward_int2byte(80))
  val () = ward_arr_set<byte>(d, 2, ward_int2byte(78))
  val () = ward_arr_set<byte>(d, 3, ward_int2byte(71))
  val @(fr, br) = ward_arr_freeze<byte>(d)
  val mb = ward_content_text_build(9)
  val mb = ward_content_text_putc(mb, 0, char2int1('i'))
  val mb = ward_content_text_putc(mb, 1, char2int1('m'))
  val mb = ward_content_text_putc(mb, 2, char2int1('a'))
  val mb = ward_content_text_putc(mb, 3, char2int1('g'))
  val mb = ward_content_text_putc(mb, 4, char2int1('e'))
  val mb = ward_content_text_putc(mb, 5, 47) (* / *)
  val mb = ward_content_text_putc(mb, 6, char2int1('p'))
  val mb = ward_content_text_putc(mb, 7, char2int1('n'))
  val mb = ward_content_text_putc(mb, 8, char2int1('g'))
  val mime = ward_content_text_done(mb)
  val s = ward_dom_stream_set_image_src(s, nid, br, sz, mime, 9)
  val () = ward_safe_content_text_free(mime)
  val () = ward_arr_drop<byte>(fr, br)
  val d2 = ward_arr_thaw<byte>(fr)
  val () = ward_arr_free<byte>(d2)
in s end

(* --- Render a chapter with one oversized image --- *)
fn render_chapter_large_image {l:agz}
  (s: ward_dom_stream(l), container: int, base: int): ward_dom_stream(l) = let
  (* Section wrapper *)
  val s = ward_dom_stream_create_element(s, base, container, mk_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, base, mk_class(), 5, mk_demo(), 4)

  (* A few paragraphs *)
  val s = ward_dom_stream_create_element(s, base + 1, base, mk_p(), 1)
  val s = ward_dom_stream_set_safe_text(s, base + 1, mk_text(), 5)
  val s = ward_dom_stream_create_element(s, base + 2, base, mk_p(), 1)
  val s = ward_dom_stream_set_safe_text(s, base + 2, mk_text(), 5)

  (* Image with 5000 bytes of data — OVERSIZED ALLOCATION.
   * In the app, this is where the crash occurs:
   *   ward_arr_alloc<byte>(5000) → malloc(5000) → oversized path *)
  val s = ward_dom_stream_create_element(s, base + 3, base, mk_img(), 3)
  val s = set_image_sized(s, base + 3, 5000)

  (* More paragraphs after the image *)
  val s = ward_dom_stream_create_element(s, base + 4, base, mk_p(), 1)
  val s = ward_dom_stream_set_safe_text(s, base + 4, mk_text(), 5)
in s end

(* WASM export: entry point — uses ward_node_init name for bridge compat *)
extern fun ward_node_init (root_id: int): void = "ext#ward_node_init"

implement ward_node_init (root_id) = let
  (* ============================================================
   * Test 1: Simulate zip search buffer (oversized alloc + free)
   *
   * In the app, zip_open allocates a search buffer of up to 65558
   * bytes, parses the ZIP central directory, then frees it.
   * For small EPUBs, the size is equal to file_size (~6000 bytes).
   * This puts a block on the oversized free list.
   * ============================================================ *)
  val zip_buf = ward_arr_alloc<byte>(6000)
  val () = ward_arr_set<byte>(zip_buf, 0, ward_int2byte(80))
  val () = ward_arr_set<byte>(zip_buf, 5999, ward_int2byte(75))
  val () = ward_arr_free<byte>(zip_buf)
  (* Oversized free list now: [zip_buf (6000)] *)

  (* ============================================================
   * Test 2: DOM stream cycle (262144-byte diff buffer alloc/free)
   *
   * In the app, multiple DOM stream begin/end cycles happen
   * before the chapter render. Each cycle allocates and frees
   * the 256KB diff buffer via the oversized path.
   * ============================================================ *)

  (* Cycle 1: library UI render *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_create_element(s, 1, root_id, mk_div(), 3)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
  (* Oversized free list: [diff_buf (262144) → zip_buf (6000)] *)

  (* Cycle 2: book reader UI setup *)
  val dom2 = ward_dom_init()
  val s2 = ward_dom_stream_begin(dom2)
  (* diff_buf reused from free list, zip_buf remains *)
  val s2 = ward_dom_stream_create_element(s2, 2, 1, mk_div(), 3)
  val s2 = ward_dom_stream_set_attr_safe(s2, 2, mk_class(), 5, mk_demo(), 4)
  val dom2 = ward_dom_stream_end(s2)
  val () = ward_dom_fini(dom2)
  (* Oversized free list: [diff_buf (262144) → zip_buf (6000)] *)

  (* ============================================================
   * Test 3: Chapter render with oversized image allocation
   *
   * The DOM stream is active (diff buffer is allocated, NOT in
   * the free list). Inside render_tree_with_images, try_set_image
   * calls ward_arr_alloc<byte>(N) where N > 4096.
   *
   * Free list at this point: [zip_buf (6000)]
   * malloc(5000) searches: 6000 >= 5000 && 6000 <= 10000 → match
   * → memset(zip_buf, 0, 6000) → THIS IS WHERE THE CRASH OCCURS
   * ============================================================ *)
  val dom3 = ward_dom_init()
  val s3 = ward_dom_stream_begin(dom3)
  (* diff_buf reused from free list, zip_buf remains in free list *)
  val s3 = ward_dom_stream_remove_children(s3, 1)
  val s3 = render_chapter_large_image(s3, 1, 100)
  val dom3 = ward_dom_stream_end(s3)
  val () = ward_dom_fini(dom3)

  val () = ward_exit()
in end
