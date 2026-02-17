(* crash_repro.dats — Reproduce Chromium renderer crash (ward#18).
 *
 * Uses the EXACT 21138-byte HTML from conan-stories.epub chapter 0,
 * compressed as 9213 bytes of deflate-raw data. Runs 3 chapter
 * transition cycles to match real user navigation:
 *
 *   Phase 1: Create viewport + container + 15 cover elements
 *   Cycle 1-3 (each):
 *     a. REMOVE_CHILDREN (DOM flush — clears container)
 *     b. ward_decompress (async — event loop turn)
 *     c. Callback: blob_read → parse HTML → SAX render → DOM flush
 *     d. Deferred image: <img> + blob URL (18KB)
 *     e. Measure: scrollWidth + width (synchronous reflow x2)
 *     f. CSS transform: translateX(0px)
 *
 * ~70KB static padding brings WASM binary to ~90KB, matching
 * quire.wasm. V8 uses different JIT strategies by module size.
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

fn mk_img (): ward_safe_text(3) = let
  val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('g'))
in ward_text_done(b) end

fn mk_h1 (): ward_safe_text(2) = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('1'))
in ward_text_done(b) end

fn mk_h2 (): ward_safe_text(2) = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('2'))
in ward_text_done(b) end

fn mk_h3 (): ward_safe_text(2) = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('3'))
in ward_text_done(b) end

fn mk_hr (): ward_safe_text(2) = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('r'))
in ward_text_done(b) end

fn mk_i (): ward_safe_text(1) = let
  val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('i'))
in ward_text_done(b) end

fn mk_a (): ward_safe_text(1) = let
  val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('a'))
in ward_text_done(b) end

fn mk_em (): ward_safe_text(2) = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('m'))
in ward_text_done(b) end

fn mk_b (): ward_safe_text(1) = let
  val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, char2int1('b'))
in ward_text_done(b) end

fn mk_br (): ward_safe_text(2) = let
  val b = ward_text_build(2)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('r'))
in ward_text_done(b) end

(* "blockquote" - 10 chars *)
fn mk_blockquote (): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('l'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('c'))
  val b = ward_text_putc(b, 4, char2int1('k'))
  val b = ward_text_putc(b, 5, char2int1('q'))
  val b = ward_text_putc(b, 6, char2int1('u'))
  val b = ward_text_putc(b, 7, char2int1('o'))
  val b = ward_text_putc(b, 8, char2int1('t'))
  val b = ward_text_putc(b, 9, char2int1('e'))
in ward_text_done(b) end

(* "strong" - 6 chars *)
fn mk_strong (): ward_safe_text(6) = let
  val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('t'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('n'))
  val b = ward_text_putc(b, 5, char2int1('g'))
in ward_text_done(b) end

(* "section" - 7 chars *)
fn mk_section (): ward_safe_text(7) = let
  val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('c'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, char2int1('i'))
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('n'))
in ward_text_done(b) end

(* Attribute name safe_text — "class" is the most common attribute
 * in the conan EPUB HTML. Emitting class attributes triggers CSS
 * style resolution in Chromium, increasing layout work. *)
fn mk_class (): ward_safe_text(5) = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('l'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('s'))
  val b = ward_text_putc(b, 4, char2int1('s'))
in ward_text_done(b) end

(* "image/jpeg" — 10 chars, for ward_dom_stream_set_image_src MIME type *)
fn mk_mime_jpeg (): [l:agz] ward_safe_content_text(l, 10) = let
  val b = ward_content_text_build(10)
  val b = ward_content_text_putc(b, 0, char2int1('i'))
  val b = ward_content_text_putc(b, 1, char2int1('m'))
  val b = ward_content_text_putc(b, 2, char2int1('a'))
  val b = ward_content_text_putc(b, 3, char2int1('g'))
  val b = ward_content_text_putc(b, 4, char2int1('e'))
  val b = ward_content_text_putc(b, 5, 47) (* '/' *)
  val b = ward_content_text_putc(b, 6, char2int1('j'))
  val b = ward_content_text_putc(b, 7, char2int1('p'))
  val b = ward_content_text_putc(b, 8, char2int1('e'))
  val b = ward_content_text_putc(b, 9, char2int1('g'))
in ward_content_text_done(b) end

(* --- Compressed conan chapter (9213 bytes deflate-raw → 21138 bytes) ---
 * Uses the exact compressed data from conan-stories.epub chapter 0. *)

%{
#include "../exerciser/conan_compressed.h"

/* "transform:translateX(0px)" — 25 bytes, applied after measurement
 * to match quire's apply_page_transform (page 0). */
static unsigned char transform_zero[25] = {
  't','r','a','n','s','f','o','r','m',':',
  't','r','a','n','s','l','a','t','e','X',
  '(','0','p','x',')'
};
static void copy_transform_zero(void *dst) {
  unsigned char *d = (unsigned char *)dst;
  int i;
  for (i = 0; i < 25; i++) d[i] = transform_zero[i];
}

/* Dummy JPEG data — 18538 bytes (matches conan illustration size).
 * Just zeros — bridge creates Blob regardless of content. */
#define DUMMY_IMG_SIZE 18538
static void fill_dummy_jpeg(void *dst) {
  unsigned char *d = (unsigned char *)dst;
  /* JPEG SOI marker so Chromium treats it as image data */
  d[0] = 0xFF; d[1] = 0xD8;
  int i;
  for (i = 2; i < DUMMY_IMG_SIZE; i++) d[i] = 0;
}

/* Padding to match quire.wasm binary size (~91KB).
 * V8 may use different WASM compilation strategies (Liftoff vs TurboFan)
 * based on module size. __attribute__((used)) prevents DCE even at -O2.
 * GCC/Clang range initializer fills entire array with 0xAA (non-zero
 * forces inclusion in WASM data section, not BSS). */
#define WASM_PAD_SIZE 71680
__attribute__((used))
static const unsigned char _wasm_padding[WASM_PAD_SIZE] = {
  [0 ... 71679] = 0xAA
};
static int wasm_padding_touch(int x) {
  return x + (int)((volatile const unsigned char *)_wasm_padding)[0];
}
%}

extern fun copy_conan_compressed {l:agz}
  (dst: !ward_arr(byte, l, 9213)): void = "mac#"

extern fun copy_transform_zero {l:agz}
  (dst: !ward_arr(byte, l, 25)): void = "mac#"

extern fun fill_dummy_jpeg {l:agz}
  (dst: !ward_arr(byte, l, 18538)): void = "mac#"

extern fun wasm_padding_touch(x: int): int = "mac#"

#define COMP_SIZE 9213
#define TRANSFORM_SIZE 25
#define IMG_SIZE 18538

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
        (* Emit attributes as class="value" — matches quire's emit_attrs
         * which calls ward_dom_stream_set_attr for each attribute.
         * This increases diff buffer size and triggers CSS style resolution. *)
        fun emit_attrs {l2:agz}{lb2:agz}{n2:pos}
          (s2: ward_dom_stream(l2), nid2: int,
           sax2: !ward_arr_borrow(byte, lb2, n2),
           sl: int n2, ap: int, ac: int): @(ward_dom_stream(l2), int) =
          if lte_int_int(ac, 0) then @(s2, ap)
          else if lt_int_int(ap, 0) then @(s2, ap)
          else let
            val ap1 = g1ofg0(ap)
          in
            if lt1_int_int(ap1, 0) then @(s2, sub_int_int(0, 1))
            else if lt1_int_int(ap1, sl) then let
              val @(_, _, val_off, val_len, next) =
                ward_xml_read_attr(sax2, ap1, sl)
              val vl = g1ofg0(val_len)
            in
              if lt1_int_int(0, vl) then
                if lt1_int_int(vl, 65536) then let
                  val val_arr = ward_arr_alloc<byte>(vl)
                  val () = copy_borrow_bytes(val_arr, vl, sax2, sl, val_off, 0, val_len)
                  val @(frozen, borrow) = ward_arr_freeze<byte>(val_arr)
                  val s2 = ward_dom_stream_set_attr(s2, nid2, mk_class(), 5, borrow, vl)
                  val () = ward_arr_drop<byte>(frozen, borrow)
                  val val_arr2 = ward_arr_thaw<byte>(frozen)
                  val () = ward_arr_free<byte>(val_arr2)
                in emit_attrs(s2, nid2, sax2, sl, next, sub_int_int(ac, 1)) end
                else emit_attrs(s2, nid2, sax2, sl, next, sub_int_int(ac, 1))
              else emit_attrs(s2, nid2, sax2, sl, next, sub_int_int(ac, 1))
            end
            else @(s2, sub_int_int(0, 1))
          end
        val nid = next_id
        (* Read up to 2 tag bytes for dispatch. Must match the real
         * HTML element types to preserve DOM nesting: <strong> inside
         * <p> must be inline (span), not block (div), or the browser
         * auto-closes the <p> and changes the entire tree structure. *)
        val t0g1 = g1ofg0(tag_off)
        val t1g1 = g1ofg0(add_int_int(tag_off, 1))
        val ch0 = (
          if gte1_int_int(t0g1, 0) then
            if lt1_int_int(t0g1, sax_len) then
              byte2int0(ward_arr_read<byte>(sax, t0g1))
            else 0
          else 0
        ): int
        val ch1 = (
          if gte1_int_int(t1g1, 0) then
            if lt1_int_int(t1g1, sax_len) then
              byte2int0(ward_arr_read<byte>(sax, t1g1))
            else 0
          else 0
        ): int
        (* Tag classification:
         * void(skip): br(98,114), hr(104,114)
         * inline:     i(105), b(98), a(97), u(117), s(115), q(113) [1-byte]
         *             em(101,109) [2-byte]
         *             span(115,112,4), code(99,111,4) [4-byte]
         *             strong(115,116,6) [6-byte]
         * heading:    h1(104,49), h2(104,50), h3(104,51) [2-byte]
         * paragraph:  p(112) [1-byte]
         * block:      everything else → div *)
        val is_void = (
          if eq_int_int(tag_len, 2) then
            (* br: 98,114  hr: 104,114 *)
            if eq_int_int(ch1, 114) then
              if eq_int_int(ch0, 98) then true   (* br *)
              else if eq_int_int(ch0, 104) then true  (* hr *)
              else false
            else false
          else if eq_int_int(tag_len, 3) then
            (* img: 105,109,103 *)
            if eq_int_int(ch0, 105) then
              if eq_int_int(ch1, 109) then true  (* img *)
              else false
            else false
          else false
        ): bool
      in
        if is_void then let
          (* Void elements: create the element but skip children.
           * hr gets CSS styling; br creates line break; img is replaced. *)
          val s = (
            if eq_int_int(ch0, 104) then
              ward_dom_stream_create_element(s, nid, parent, mk_hr(), 2)
            else if eq_int_int(tag_len, 3) then
              ward_dom_stream_create_element(s, nid, parent, mk_img(), 3)
            else
              ward_dom_stream_create_element(s, nid, parent, mk_div(), 3)
          ): ward_dom_stream(l)
          val @(s, child_pos) = emit_attrs(s, nid, sax, sax_len, after_tag, attr_count)
          (* Skip children (void elements shouldn't have any) *)
          val @(s, after_children, nid2) =
            render_sax(s, sax, sax_len, nid, child_pos, add_int_int(next_id, 1), 0)
        in render_sax(s, sax, sax_len, parent, after_children, nid2, 1) end
        else let
        val is_inline = (
          if eq_int_int(tag_len, 1) then
            (* 1-byte inline: i, b, a, u, s, q *)
            if eq_int_int(ch0, 105) then true  (* i *)
            else if eq_int_int(ch0, 98) then true  (* b *)
            else if eq_int_int(ch0, 97) then true  (* a *)
            else if eq_int_int(ch0, 117) then true  (* u *)
            else if eq_int_int(ch0, 115) then true  (* s *)
            else if eq_int_int(ch0, 113) then true  (* q *)
            else false
          else if eq_int_int(tag_len, 2) then
            (* 2-byte inline: em *)
            if eq_int_int(ch0, 101) then
              if eq_int_int(ch1, 109) then true else false  (* em *)
            else false
          else if eq_int_int(tag_len, 4) then
            (* 4-byte: span(s,p), code(c,o) *)
            if eq_int_int(ch0, 115) then
              if eq_int_int(ch1, 112) then true else false  (* span *)
            else if eq_int_int(ch0, 99) then
              if eq_int_int(ch1, 111) then true else false  (* code *)
            else false
          else if eq_int_int(tag_len, 6) then
            (* 6-byte: strong(s,t) *)
            if eq_int_int(ch0, 115) then
              if eq_int_int(ch1, 116) then true else false  (* strong *)
            else false
          else false
        ): bool
        val is_p = (
          if eq_int_int(tag_len, 1) then
            eq_int_int(ch0, 112)  (* p=112 *)
          else false
        ): bool
        (* heading: tag_len=2, ch0='h'(104), ch1 in '1'-'6' (49-54) *)
        val heading_level = (
          if eq_int_int(tag_len, 2) then
            if eq_int_int(ch0, 104) then
              if gte_int_int(ch1, 49) then
                if lte_int_int(ch1, 54) then ch1
                else 0
              else 0
            else 0
          else 0
        ): int
        val is_blockquote = (
          if eq_int_int(tag_len, 10) then
            if eq_int_int(ch0, 98) then
              if eq_int_int(ch1, 108) then true else false  (* bl *)
            else false
          else false
        ): bool
        val is_section = (
          if eq_int_int(tag_len, 7) then
            if eq_int_int(ch0, 115) then
              if eq_int_int(ch1, 101) then true else false  (* se *)
            else false
          else false
        ): bool
        val s = (
          if is_inline then
            if eq_int_int(tag_len, 6) then
              ward_dom_stream_create_element(s, nid, parent, mk_strong(), 6)
            else if eq_int_int(tag_len, 2) then
              ward_dom_stream_create_element(s, nid, parent, mk_em(), 2)
            else if eq_int_int(ch0, 97) then
              ward_dom_stream_create_element(s, nid, parent, mk_a(), 1)
            else if eq_int_int(ch0, 98) then
              ward_dom_stream_create_element(s, nid, parent, mk_b(), 1)
            else if eq_int_int(ch0, 105) then
              ward_dom_stream_create_element(s, nid, parent, mk_i(), 1)
            else
              ward_dom_stream_create_element(s, nid, parent, mk_span(), 4)
          else if is_p then
            ward_dom_stream_create_element(s, nid, parent, mk_p(), 1)
          else if gt_int_int(heading_level, 0) then
            if eq_int_int(heading_level, 49) then
              ward_dom_stream_create_element(s, nid, parent, mk_h1(), 2)
            else if eq_int_int(heading_level, 51) then
              ward_dom_stream_create_element(s, nid, parent, mk_h3(), 2)
            else
              ward_dom_stream_create_element(s, nid, parent, mk_h2(), 2)
          else if is_blockquote then
            ward_dom_stream_create_element(s, nid, parent, mk_blockquote(), 10)
          else if is_section then
            ward_dom_stream_create_element(s, nid, parent, mk_section(), 7)
          else
            ward_dom_stream_create_element(s, nid, parent, mk_div(), 3)
        ): ward_dom_stream(l)
        val @(s, child_pos) = emit_attrs(s, nid, sax, sax_len, after_tag, attr_count)
        (* Recurse into children with has_child=0 for the new scope *)
        val @(s, after_children, nid2) =
          render_sax(s, sax, sax_len, nid, child_pos, add_int_int(next_id, 1), 0)
        (* Continue with siblings — has_child=1 since we just created an element *)
      in render_sax(s, sax, sax_len, parent, after_children, nid2, 1) end
      end

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

(* --- Helper: render chapter from decompressed blob ---
 * Does the full render cycle: blob_read → parse → render → image → measure → transform.
 * Called from each chapter transition callback. *)
fn render_chapter_from_blob(blob_handle: int): void = let
  val decomp_len = ward_decompress_get_len()
  val dl = g1ofg0(decomp_len)
in
  if lt1_int_int(0, dl) then let
    val html_buf = ward_arr_alloc<byte>(dl)
    val _bytes = ward_blob_read(blob_handle, 0, html_buf, dl)
    val () = ward_blob_free(blob_handle)
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
        val sax = ward_xml_get_result(sax_g1)
        val @(sax_frozen, sax_borrow) = ward_arr_freeze<byte>(sax)
        (* Render from SAX into container (node 2) *)
        val dom4 = ward_dom_init()
        val s4 = ward_dom_stream_begin(dom4)
        val @(s4, _, _) = render_sax(s4, sax_borrow, sax_g1, 2, 0, 100, 0)
        val dom4 = ward_dom_stream_end(s4)
        (* Deferred image — matches quire's load_deferred_images *)
        val s4b = ward_dom_stream_begin(dom4)
        val s4b = ward_dom_stream_create_element(s4b, 50, 2, mk_img(), 3)
        val img_arr = ward_arr_alloc<byte>(IMG_SIZE)
        val () = fill_dummy_jpeg(img_arr)
        val @(img_frozen, img_borrow) = ward_arr_freeze<byte>(img_arr)
        val mime = mk_mime_jpeg()
        val s4b = ward_dom_stream_set_image_src(s4b, 50, img_borrow, IMG_SIZE, mime, 10)
        val () = ward_safe_content_text_free(mime)
        val () = ward_arr_drop<byte>(img_frozen, img_borrow)
        val img_arr2 = ward_arr_thaw<byte>(img_frozen)
        val () = ward_arr_free<byte>(img_arr2)
        val dom4 = ward_dom_stream_end(s4b)
        val () = ward_dom_fini(dom4)
        (* Measure — forces synchronous layout reflow *)
        val _found1 = ward_measure_node(2)
        val _found2 = ward_measure_node(1)
        (* Apply CSS transform — triggers another layout *)
        val style_arr = ward_arr_alloc<byte>(TRANSFORM_SIZE)
        val () = copy_transform_zero(style_arr)
        val @(sf, sb) = ward_arr_freeze<byte>(style_arr)
        val dom5 = ward_dom_init()
        val s5 = ward_dom_stream_begin(dom5)
        val s5 = ward_dom_stream_set_style(s5, 2, sb, TRANSFORM_SIZE)
        val dom5 = ward_dom_stream_end(s5)
        val () = ward_dom_fini(dom5)
        val () = ward_arr_drop<byte>(sf, sb)
        val style_arr2 = ward_arr_thaw<byte>(sf)
        val () = ward_arr_free<byte>(style_arr2)
        val () = ward_arr_drop<byte>(sax_frozen, sax_borrow)
        val sax2 = ward_arr_thaw<byte>(sax_frozen)
        val () = ward_arr_free<byte>(sax2)
      in () end
      else ()
    end
    else ()
  end
  else let
    val () = ward_blob_free(blob_handle)
  in () end
end

(* --- Helper: start a chapter transition ---
 * REMOVE_CHILDREN + stale ops + decompress. Returns decompress promise.
 * Each call simulates navigate_next crossing a chapter boundary.
 *
 * CRITICAL: Includes the premature apply_page_transform + measure that
 * was present in quire's navigate_next BEFORE the async race fix
 * (commit 5059454). These calls ran on the EMPTY container right after
 * REMOVE_CHILDREN and before load_chapter started the async decompress.
 * This is the exact pattern that caused the Chromium renderer crash:
 *   1. REMOVE_CHILDREN → flush → browser removes all DOM children
 *   2. measure_node(container) → forces reflow on EMPTY container
 *   3. set_style(transform:translateX) → apply CSS transform on empty container
 *   4. decompress (async) → event loop turn → browser processes empty layout
 *   5. Callback: render 21KB DOM → measure → transform on POPULATED container
 * The rapid empty→populated transition with intermediate forced reflows
 * triggers the Chromium renderer crash. *)
fn start_chapter_transition(): ward_promise_pending(int) = let
  (* Step 1: REMOVE_CHILDREN — clears container *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, 2)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Step 2: Premature measure on empty container — the bug.
   * navigate_next called apply_page_transform which measured viewport
   * width and set CSS transform, all on the empty container. This forced
   * Chromium's renderer to reflow the emptied CSS columns layout. *)
  val _found1 = ward_measure_node(2)
  val _found2 = ward_measure_node(1)

  (* Step 3: Premature CSS transform on empty container — the bug.
   * apply_page_transform set transform:translateX(0px) on the empty
   * container, causing another forced layout on the emptied columns. *)
  val style_arr = ward_arr_alloc<byte>(TRANSFORM_SIZE)
  val () = copy_transform_zero(style_arr)
  val @(sf, sb) = ward_arr_freeze<byte>(style_arr)
  val dom2 = ward_dom_init()
  val s2 = ward_dom_stream_begin(dom2)
  val s2 = ward_dom_stream_set_style(s2, 2, sb, TRANSFORM_SIZE)
  val dom2 = ward_dom_stream_end(s2)
  val () = ward_dom_fini(dom2)
  val () = ward_arr_drop<byte>(sf, sb)
  val style_arr2 = ward_arr_thaw<byte>(sf)
  val () = ward_arr_free<byte>(style_arr2)

  (* Step 4: Start async decompress — the event loop turn between
   * the empty layout and the heavy render is where the crash occurs. *)
  val comp_buf = ward_arr_alloc<byte>(COMP_SIZE)
  val () = copy_conan_compressed(comp_buf)
  val @(c_frozen, c_borrow) = ward_arr_freeze<byte>(comp_buf)
  val decomp_p = ward_decompress(c_borrow, COMP_SIZE, 2)
  val () = ward_arr_drop<byte>(c_frozen, c_borrow)
  val comp_buf2 = ward_arr_thaw<byte>(c_frozen)
  val () = ward_arr_free<byte>(comp_buf2)
in decomp_p end

(* WASM export: entry point *)
extern fun ward_node_init (root_id: int): void = "ext#ward_node_init"

implement ward_node_init (root_id) = let
  (* Reference padding array to prevent dead-code elimination.
   * This brings WASM binary from ~20KB to ~90KB, matching quire.wasm.
   * V8 may use different compilation strategies based on module size. *)
  val _pad = wasm_padding_touch(0)

  (* ============================================================
   * Phase 1: Create viewport (node 1) + container (node 2).
   * Matches quire's reader structure:
   *   root → .reader-viewport → .chapter-container
   * ============================================================ *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_create_element(s, 1, root_id, mk_div(), 3)
  val s = ward_dom_stream_create_element(s, 2, 1, mk_div(), 3)
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
      val s = ward_dom_stream_create_element(s, nid, 2, mk_p(), 1)
    in create_cover(s, add_int_int(i, 1)) end
  val s2 = create_cover(s2, 0)
  val dom2 = ward_dom_stream_end(s2)
  val () = ward_dom_fini(dom2)

  (* ============================================================
   * 3 chapter transition cycles — simulates a user navigating
   * through chapters. Each cycle:
   *   1. REMOVE_CHILDREN (DOM flush — clears container)
   *   2. ward_decompress (async — event loop turn)
   *   3. Callback: blob_read → parse HTML → render SAX → DOM flush
   *   4. Deferred image: create <img> + set blob URL
   *   5. Measure: scrollWidth + width (synchronous reflow x2)
   *   6. CSS transform: translateX(0px) (another layout)
   *
   * The crash happens in Chromium's renderer during step 3 or 5.
   * Multiple rapid transitions increase the likelihood of hitting
   * the race condition between WASM→JS calls and renderer layout.
   * ============================================================ *)

  (* Cycle 1: cover → chapter *)
  val decomp1 = start_chapter_transition()
  val cycle1 = ward_promise_then<int><int>(decomp1,
    llam (blob1: int) => let
      val () = render_chapter_from_blob(blob1)
    in ward_promise_vow(start_chapter_transition()) end)

  (* Cycle 2: chapter → chapter *)
  val cycle2 = ward_promise_then<int><int>(cycle1,
    llam (blob2: int) => let
      val () = render_chapter_from_blob(blob2)
    in ward_promise_vow(start_chapter_transition()) end)

  (* Cycle 3: chapter → chapter *)
  val cycle3 = ward_promise_then<int><int>(cycle2,
    llam (blob3: int) => let
      val () = render_chapter_from_blob(blob3)
    in ward_promise_return<int>(0) end)

  val exit_p = ward_promise_then<int><int>(cycle3,
    llam (_x: int) => let
      val () = ward_exit()
    in ward_promise_return<int>(0) end)
  val () = ward_promise_discard(exit_p)
in end
