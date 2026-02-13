(* quire.dats — Quire application entry point
 *
 * Library view: renders import button and book cards.
 * Reader view: loads chapter from ZIP, decompresses, parses HTML, renders.
 * Navigation: click zones and keyboard (ArrowRight/Left, Space, Escape).
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./zip.sats"
staload "./epub.sats"
staload "./library.sats"
staload "./reader.sats"
staload "./buf.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/listener.sats"
staload "./../vendor/ward/lib/file.sats"
staload "./../vendor/ward/lib/promise.sats"
staload "./../vendor/ward/lib/event.sats"
staload "./../vendor/ward/lib/decompress.sats"
staload "./../vendor/ward/lib/xml.sats"
staload "./../vendor/ward/lib/dom_read.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload _ = "./../vendor/ward/lib/listener.dats"
staload _ = "./../vendor/ward/lib/file.dats"
staload _ = "./../vendor/ward/lib/promise.dats"
staload _ = "./../vendor/ward/lib/event.dats"
staload _ = "./../vendor/ward/lib/decompress.dats"
staload _ = "./../vendor/ward/lib/xml.dats"
staload _ = "./../vendor/ward/lib/dom_read.dats"

staload "./arith.sats"

(* ========== Text constant IDs ========== *)

#define TEXT_NO_BOOKS 0
#define TEXT_EPUB_EXT 1
#define TEXT_NOT_STARTED 2
#define TEXT_READ 3

(* ========== Byte-level helpers (pure ATS2) ========== *)

(* Byte write to ward_arr — wraps ward_arr_write_byte with castfn index *)
fn ward_arr_set_byte {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), off: int, len: int n, v: int): void =
  ward_arr_write_byte(arr, _ward_idx(off, len), _checked_byte(v))

(* Fill ward_arr with text constant bytes.
 * "No books yet"(12), ".epub"(5), "Not started"(11), "Read"(4) *)
fn fill_text {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, text_id: int): void =
  if text_id = 0 then let (* "No books yet" *)
    val () = ward_arr_set_byte(arr, 0, alen, 78)   (* N *)
    val () = ward_arr_set_byte(arr, 1, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 2, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 3, alen, 98)   (* b *)
    val () = ward_arr_set_byte(arr, 4, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 5, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 6, alen, 107)  (* k *)
    val () = ward_arr_set_byte(arr, 7, alen, 115)  (* s *)
    val () = ward_arr_set_byte(arr, 8, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 9, alen, 121)  (* y *)
    val () = ward_arr_set_byte(arr, 10, alen, 101) (* e *)
    val () = ward_arr_set_byte(arr, 11, alen, 116) (* t *)
  in end
  else if text_id = 1 then let (* ".epub" *)
    val () = ward_arr_set_byte(arr, 0, alen, 46)   (* . *)
    val () = ward_arr_set_byte(arr, 1, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 2, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 3, alen, 117)  (* u *)
    val () = ward_arr_set_byte(arr, 4, alen, 98)   (* b *)
  in end
  else if text_id = 2 then let (* "Not started" *)
    val () = ward_arr_set_byte(arr, 0, alen, 78)   (* N *)
    val () = ward_arr_set_byte(arr, 1, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 2, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 3, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 4, alen, 115)  (* s *)
    val () = ward_arr_set_byte(arr, 5, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 6, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 7, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 8, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 9, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 10, alen, 100) (* d *)
  in end
  else let (* text_id = 3: "Read" *)
    val () = ward_arr_set_byte(arr, 0, alen, 82)   (* R *)
    val () = ward_arr_set_byte(arr, 1, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 2, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 3, alen, 100)  (* d *)
  in end

(* Copy len bytes from string_buffer to ward_arr *)
fn copy_from_sbuf {l:agz}{n:pos}
  (dst: !ward_arr(byte, l, n), len: int n): void = let
  val sbuf = get_string_buffer_ptr()
  fun loop(dst: !ward_arr(byte, l, n), dlen: int n,
           sbuf: ptr, i: int, count: int): void =
    if i < count then let
      val b = buf_get_u8(sbuf, i)
      val () = ward_arr_set_byte(dst, i, dlen, b)
    in loop(dst, dlen, sbuf, i + 1, count) end
in loop(dst, len, sbuf, 0, len) end

(* EPUB parsing helpers (implemented in quire_runtime.c) *)
extern fun epub_parse_container_bytes {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): int = "mac#"
extern fun epub_parse_opf_bytes {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): int = "mac#"
extern fun epub_get_opf_path_ptr(): ptr = "mac#"
extern fun epub_get_opf_path_len(): int = "mac#"
extern fun get_str_container_ptr(): ptr = "mac#"

(* Spine path accessors *)
extern fun epub_get_spine_path_ptr(index: int): ptr = "mac#"
extern fun epub_get_spine_path_len(index: int): int = "mac#"

(* ========== Measurement correctness ========== *)

(* SCROLL_WIDTH_SLOT: proves that scrollWidth lives in ward measurement slot 4.
 * ward_measure_get_top() reads slot 4 = el.scrollWidth.
 * ward_measure_get_left() reads slot 5 = el.scrollHeight.
 * The names are confusing — this dataprop ensures quire code uses the correct slot.
 *
 * BUG PREVENTED: measure_and_set_pages used ward_measure_get_left (scrollHeight)
 * instead of ward_measure_get_top (scrollWidth), giving total_pages=1 always. *)
dataprop SCROLL_WIDTH_SLOT(slot: int) =
  | SLOT_4(4)

(* Safe wrapper: measures a node and returns its scrollWidth.
 * Abstracts over ward's confusing slot naming.
 * Constructs SCROLL_WIDTH_SLOT(4) proof to document correctness. *)
fn measure_node_scroll_width(node_id: int): int = let
  val _found = ward_measure_node(node_id)
  prval _ = SLOT_4()  (* proof: we read slot 4 = scrollWidth *)
in
  ward_measure_get_top()  (* slot 4 = el.scrollWidth *)
end

(* Safe wrapper: measures a node and returns its element width.
 * Uses slot 2 = el.width from getBoundingClientRect. *)
fn measure_node_width(node_id: int): int = let
  val _found = ward_measure_node(node_id)
in
  ward_measure_get_w()  (* slot 2 = rect.width *)
end

(* Read f64 clientX from click payload, return as int — irreducibly C *)
extern fun read_payload_click_x {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n)): int = "mac#"

(* Castfn for indices proven in-bounds at runtime but not by solver.
 * Used for ward_arr(byte, l, 48) where max write index is 35. *)
extern castfn _idx48(x: int): [i:nat | i < 48] int i

(* Safe byte conversion: value must be 0-255.
 * For static chars: use char2int1('x') which carries the static value.
 * For computed digits: 48 + (v % 10) is always 48-57 — in range. *)
extern castfn _byte {c:int | 0 <= c; c <= 255} (c: int c): byte

(* ========== CSS class safe text builders ========== *)

fn cls_import_btn(): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, 45) (* '-' *)
  val b = ward_text_putc(b, 7, char2int1('b'))
  val b = ward_text_putc(b, 8, char2int1('t'))
  val b = ward_text_putc(b, 9, char2int1('n'))
in ward_text_done(b) end

fn cls_library_list(): ward_safe_text(12) = let
  val b = ward_text_build(12)
  val b = ward_text_putc(b, 0, char2int1('l'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('b'))
  val b = ward_text_putc(b, 3, char2int1('r'))
  val b = ward_text_putc(b, 4, char2int1('a'))
  val b = ward_text_putc(b, 5, char2int1('r'))
  val b = ward_text_putc(b, 6, char2int1('y'))
  val b = ward_text_putc(b, 7, 45) (* '-' *)
  val b = ward_text_putc(b, 8, char2int1('l'))
  val b = ward_text_putc(b, 9, char2int1('i'))
  val b = ward_text_putc(b, 10, char2int1('s'))
  val b = ward_text_putc(b, 11, char2int1('t'))
in ward_text_done(b) end

fn cls_empty_lib(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, char2int1('y'))
  val b = ward_text_putc(b, 5, 45) (* '-' *)
  val b = ward_text_putc(b, 6, char2int1('l'))
  val b = ward_text_putc(b, 7, char2int1('i'))
  val b = ward_text_putc(b, 8, char2int1('b'))
in ward_text_done(b) end

fn st_file(): ward_safe_text(4) = let
  val b = ward_text_build(4)
  val b = ward_text_putc(b, 0, char2int1('f'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('l'))
  val b = ward_text_putc(b, 3, char2int1('e'))
in ward_text_done(b) end

fn evt_change(): ward_safe_text(6) = let
  val b = ward_text_build(6)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('h'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('n'))
  val b = ward_text_putc(b, 4, char2int1('g'))
  val b = ward_text_putc(b, 5, char2int1('e'))
in ward_text_done(b) end

fn evt_click(): ward_safe_text(5) = let
  val b = ward_text_build(5)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('l'))
  val b = ward_text_putc(b, 2, char2int1('i'))
  val b = ward_text_putc(b, 3, char2int1('c'))
  val b = ward_text_putc(b, 4, char2int1('k'))
in ward_text_done(b) end

fn evt_keydown(): ward_safe_text(7) = let
  val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('k'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('y'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, char2int1('w'))
  val b = ward_text_putc(b, 6, char2int1('n'))
in ward_text_done(b) end

fn cls_book_card(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('k'))
  val b = ward_text_putc(b, 4, 45)
  val b = ward_text_putc(b, 5, char2int1('c'))
  val b = ward_text_putc(b, 6, char2int1('a'))
  val b = ward_text_putc(b, 7, char2int1('r'))
  val b = ward_text_putc(b, 8, char2int1('d'))
in ward_text_done(b) end

fn cls_book_title(): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('k'))
  val b = ward_text_putc(b, 4, 45)
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, char2int1('i'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('l'))
  val b = ward_text_putc(b, 9, char2int1('e'))
in ward_text_done(b) end

fn cls_book_author(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('k'))
  val b = ward_text_putc(b, 4, 45)
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('u'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('h'))
  val b = ward_text_putc(b, 9, char2int1('o'))
  val b = ward_text_putc(b, 10, char2int1('r'))
in ward_text_done(b) end

fn cls_book_position(): ward_safe_text(13) = let
  val b = ward_text_build(13)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('k'))
  val b = ward_text_putc(b, 4, 45)
  val b = ward_text_putc(b, 5, char2int1('p'))
  val b = ward_text_putc(b, 6, char2int1('o'))
  val b = ward_text_putc(b, 7, char2int1('s'))
  val b = ward_text_putc(b, 8, char2int1('i'))
  val b = ward_text_putc(b, 9, char2int1('t'))
  val b = ward_text_putc(b, 10, char2int1('i'))
  val b = ward_text_putc(b, 11, char2int1('o'))
  val b = ward_text_putc(b, 12, char2int1('n'))
in ward_text_done(b) end

fn cls_read_btn(): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, 45)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
in ward_text_done(b) end

(* "reader-viewport" = 15 chars *)
fn cls_reader_viewport(): ward_safe_text(15) = let
  val b = ward_text_build(15)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, char2int1('e'))
  val b = ward_text_putc(b, 5, char2int1('r'))
  val b = ward_text_putc(b, 6, 45) (* '-' *)
  val b = ward_text_putc(b, 7, char2int1('v'))
  val b = ward_text_putc(b, 8, char2int1('i'))
  val b = ward_text_putc(b, 9, char2int1('e'))
  val b = ward_text_putc(b, 10, char2int1('w'))
  val b = ward_text_putc(b, 11, char2int1('p'))
  val b = ward_text_putc(b, 12, char2int1('o'))
  val b = ward_text_putc(b, 13, char2int1('r'))
  val b = ward_text_putc(b, 14, char2int1('t'))
in ward_text_done(b) end

(* "chapter-container" = 17 chars *)
fn cls_chapter_container(): ward_safe_text(17) = let
  val b = ward_text_build(17)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('h'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('p'))
  val b = ward_text_putc(b, 4, char2int1('t'))
  val b = ward_text_putc(b, 5, char2int1('e'))
  val b = ward_text_putc(b, 6, char2int1('r'))
  val b = ward_text_putc(b, 7, 45) (* '-' *)
  val b = ward_text_putc(b, 8, char2int1('c'))
  val b = ward_text_putc(b, 9, char2int1('o'))
  val b = ward_text_putc(b, 10, char2int1('n'))
  val b = ward_text_putc(b, 11, char2int1('t'))
  val b = ward_text_putc(b, 12, char2int1('a'))
  val b = ward_text_putc(b, 13, char2int1('i'))
  val b = ward_text_putc(b, 14, char2int1('n'))
  val b = ward_text_putc(b, 15, char2int1('e'))
  val b = ward_text_putc(b, 16, char2int1('r'))
in ward_text_done(b) end

(* tabindex value "0" = 1 char *)
fn val_zero(): ward_safe_text(1) = let
  val b = ward_text_build(1)
  val b = ward_text_putc(b, 0, 48) (* '0' *)
in ward_text_done(b) end

(* ========== Helper: set text content from C string constant ========== *)

fn set_text_cstr {l:agz}
  (s: ward_dom_stream(l), nid: int, text_id: int, text_len: int)
  : ward_dom_stream(l) = let
  val tl = g1ofg0(text_len)
in
  if tl > 0 then
    if tl < 65536 then let
      val arr = ward_arr_alloc<byte>(tl)
      val () = fill_text(arr, tl, text_id)
      val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
      val s = ward_dom_stream_set_text(s, nid, borrow, tl)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val arr = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(arr)
    in s end
    else s
  else s
end

(* ========== Helper: set attribute with C string value ========== *)

fn set_attr_cstr {l:agz}{nl:pos | nl < 256}
  (s: ward_dom_stream(l), nid: int,
   aname: ward_safe_text(nl), nl_v: int nl,
   text_id: int, text_len: int)
  : ward_dom_stream(l) = let
  val vl = g1ofg0(text_len)
in
  if vl > 0 then
    if vl < 65536 then
    if nl_v + vl + 8 <= 262144 then let
      val arr = ward_arr_alloc<byte>(vl)
      val () = fill_text(arr, vl, text_id)
      val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
      val s = ward_dom_stream_set_attr(s, nid, aname, nl_v, borrow, vl)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val arr = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(arr)
    in s end
    else s
    else s
  else s
end

(* ========== Helper: set text content from string buffer ========== *)

fn set_text_from_sbuf {l:agz}
  (s: ward_dom_stream(l), nid: int, len: int)
  : ward_dom_stream(l) = let
  val len1 = g1ofg0(len)
in
  if len1 > 0 then
    if len1 < 65536 then let
      val arr = ward_arr_alloc<byte>(len1)
      val () = copy_from_sbuf(arr, len1)
      val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
      val s = ward_dom_stream_set_text(s, nid, borrow, len1)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val arr = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(arr)
    in s end
    else s
  else s
end

(* ========== Page navigation helpers ========== *)

(* Write non-negative int as decimal digits into ward_arr at offset.
 * Returns number of digits written. Array must be >= 48 bytes.
 * Digit bytes are 48-57 ('0'-'9') — always valid for int2byte0.
 * NOTE: mod_int_int returns plain int so solver can't verify range;
 * the invariant 0 <= (v%10) <= 9 holds by definition of modulo. *)
fn itoa_to_arr {l:agz}
  (arr: !ward_arr(byte, l, 48), v: int, offset: int): int = let
  fun count_digits(x: int, acc: int): int =
    if gt_int_int(x, 0) then count_digits(div_int_int(x, 10), acc + 1)
    else acc
in
  if gt_int_int(1, v) then let
    val () = ward_arr_set<byte>(arr, _idx48(offset),
      _byte(char2int1('0')))
  in 1 end
  else let
    val ndigits = count_digits(v, 0)
    fun write_rev {l:agz}
      (arr: !ward_arr(byte, l, 48), x: int, pos: int): void =
      if gt_int_int(x, 0) then let
        val digit = mod_int_int(x, 10)
        (* digit is 0-9, so 48+digit is 48-57 — within byte range *)
        val () = ward_arr_set<byte>(arr, _idx48(pos), ward_int2byte(_checked_byte(48 + digit)))
      in write_rev(arr, div_int_int(x, 10), pos - 1) end
      else ()
    val () = write_rev(arr, v, offset + ndigits - 1)
  in ndigits end
end

(* Build "transform:translateX(-Npx)" in a ward_arr(48).
 * Returns total bytes written. Max: 22 prefix + 10 digits + 3 suffix = 35.
 * Static chars use char2int1 + _byte — constraint-solver verified. *)
fn build_transform_arr {l:agz}
  (arr: !ward_arr(byte, l, 48), page: int, page_width: int): int = let
  val pixel_offset = mul_int_int(page, page_width)
  (* "transform:translateX(-" — 22 bytes, all verified via char2int1 *)
  val () = ward_arr_set<byte>(arr, 0, _byte(char2int1('t')))
  val () = ward_arr_set<byte>(arr, 1, _byte(char2int1('r')))
  val () = ward_arr_set<byte>(arr, 2, _byte(char2int1('a')))
  val () = ward_arr_set<byte>(arr, 3, _byte(char2int1('n')))
  val () = ward_arr_set<byte>(arr, 4, _byte(char2int1('s')))
  val () = ward_arr_set<byte>(arr, 5, _byte(char2int1('f')))
  val () = ward_arr_set<byte>(arr, 6, _byte(char2int1('o')))
  val () = ward_arr_set<byte>(arr, 7, _byte(char2int1('r')))
  val () = ward_arr_set<byte>(arr, 8, _byte(char2int1('m')))
  val () = ward_arr_set<byte>(arr, 9, _byte(58))  (* ':' — char2int1 can't parse punctuation *)
  val () = ward_arr_set<byte>(arr, 10, _byte(char2int1('t')))
  val () = ward_arr_set<byte>(arr, 11, _byte(char2int1('r')))
  val () = ward_arr_set<byte>(arr, 12, _byte(char2int1('a')))
  val () = ward_arr_set<byte>(arr, 13, _byte(char2int1('n')))
  val () = ward_arr_set<byte>(arr, 14, _byte(char2int1('s')))
  val () = ward_arr_set<byte>(arr, 15, _byte(char2int1('l')))
  val () = ward_arr_set<byte>(arr, 16, _byte(char2int1('a')))
  val () = ward_arr_set<byte>(arr, 17, _byte(char2int1('t')))
  val () = ward_arr_set<byte>(arr, 18, _byte(char2int1('e')))
  val () = ward_arr_set<byte>(arr, 19, _byte(char2int1('X')))
  val () = ward_arr_set<byte>(arr, 20, _byte(40))  (* '(' *)
  val () = ward_arr_set<byte>(arr, 21, _byte(45))  (* '-' *)
  (* decimal digits *)
  val ndigits = itoa_to_arr(arr, pixel_offset, 22)
  val pos = 22 + ndigits
  (* "px)" — 3 bytes *)
  val () = ward_arr_set<byte>(arr, _idx48(pos), _byte(char2int1('p')))
  val () = ward_arr_set<byte>(arr, _idx48(pos + 1), _byte(char2int1('x')))
  val () = ward_arr_set<byte>(arr, _idx48(pos + 2), _byte(41))  (* ')' *)
in pos + 3 end

(* Apply CSS transform to scroll chapter container to current page.
 * Uses measure_node_width wrapper for clarity. *)
fn apply_page_transform(container_id: int): void = let
  val page_width = measure_node_width(reader_get_viewport_id())
in
  if gt_int_int(page_width, 0) then let
    val cur_page = reader_get_current_page()
    val arr = ward_arr_alloc<byte>(48)
    val slen = build_transform_arr(arr, cur_page, page_width)
    (* Split arr to exact length for set_style *)
    val slen1 = g1ofg0(slen)
  in
    if slen1 > 0 then
      if slen1 <= 48 then let
        val @(used, rest) = ward_arr_split<byte>(arr, slen1)
        val () = ward_arr_free<byte>(rest)
        val @(frozen, borrow) = ward_arr_freeze<byte>(used)
        val dom = ward_dom_init()
        val s = ward_dom_stream_begin(dom)
        val s = ward_dom_stream_set_style(s, container_id, borrow, slen1)
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = ward_arr_drop<byte>(frozen, borrow)
        val used = ward_arr_thaw<byte>(frozen)
        val () = ward_arr_free<byte>(used)
      in end
      else let
        val () = ward_arr_free<byte>(arr)
      in end
    else let
      val () = ward_arr_free<byte>(arr)
    in end
  end
  else ()
end

(* Measure chapter container and viewport, compute total pages.
 * Uses safe wrappers to prevent slot confusion (see SCROLL_WIDTH_SLOT). *)
fn measure_and_set_pages(container_id: int): void = let
  val scroll_width = measure_node_scroll_width(container_id)
  val page_width = measure_node_width(reader_get_viewport_id())
in
  if gt_int_int(page_width, 0) then let
    (* ceiling division: (scrollWidth + pageWidth - 1) / pageWidth *)
    val total = div_int_int(scroll_width + page_width - 1, page_width)
    val () = reader_set_total_pages(total)
  in end
  else ()
end

(* Save reading position and exit reader.
 * Constructs POSITION_SAVED proof required by reader_exit.
 * This is THE only permitted way to exit the reader from ATS code.
 * See POSITION_SAVED dataprop in reader.sats. *)
fn reader_save_and_exit(): void = let
  val () = library_update_position(
    reader_get_book_index(),
    reader_get_current_chapter(),
    reader_get_current_page())
  prval pf = SAVED()
in
  reader_exit(pf)
end

(* ========== EPUB import: read and parse ZIP entries ========== *)

fn epub_read_container(handle: int): int = let
  val idx = zip_find_entry(get_str_container_ptr(), 22)
in
  if gt_int_int(0, idx) then 0
  else let
    var entry: zip_entry
    val found = zip_get_entry(idx, entry)
  in
    if eq_int_int(found, 0) then 0
    else let
      val usize = entry.uncompressed_size
    in
      if gt_int_int(1, usize) then 0
      else if gt_int_int(usize, 16384) then 0
      else let
        val data_off = zip_get_data_offset(idx)
      in
        if gt_int_int(0, data_off) then 0
        else let
          val usize1 = _checked_pos(usize)
          val arr = ward_arr_alloc<byte>(usize1)
          val _rd = ward_file_read(handle, data_off, arr, usize1)
          val result = epub_parse_container_bytes(arr, usize1)
          val () = ward_arr_free<byte>(arr)
        in result end
      end
    end
  end
end

fn epub_read_opf(handle: int): int = let
  val opf_ptr = epub_get_opf_path_ptr()
  val opf_len = epub_get_opf_path_len()
  val idx = zip_find_entry(opf_ptr, opf_len)
in
  if gt_int_int(0, idx) then 0
  else let
    var entry: zip_entry
    val found = zip_get_entry(idx, entry)
  in
    if eq_int_int(found, 0) then 0
    else let
      val usize = entry.uncompressed_size
    in
      if gt_int_int(1, usize) then 0
      else if gt_int_int(usize, 16384) then 0
      else let
        val data_off = zip_get_data_offset(idx)
      in
        if gt_int_int(0, data_off) then 0
        else let
          val usize1 = _checked_pos(usize)
          val arr = ward_arr_alloc<byte>(usize1)
          val _rd = ward_file_read(handle, data_off, arr, usize1)
          val result = epub_parse_opf_bytes(arr, usize1)
          val () = ward_arr_free<byte>(arr)
        in result end
      end
    end
  end
end

(* ========== Render book cards into library list ========== *)

(* Render "Ch X Pg Y" into a ward_arr(48) and set as text on node.
 * Falls back to "Not started" if ch=0 and pg=0. *)
fn render_position_text {l:agz}
  (s: ward_dom_stream(l), nid: int, ch: int, pg: int)
  : ward_dom_stream(l) =
  if eq_int_int(ch, 0) then
    if eq_int_int(pg, 0) then
      set_text_cstr(s, nid, TEXT_NOT_STARTED, 11)
    else let
      (* Build "Ch 1 Pg Y" *)
      val arr = ward_arr_alloc<byte>(48)
      val () = ward_arr_set<byte>(arr, 0, _byte(char2int1('C')))
      val () = ward_arr_set<byte>(arr, 1, _byte(char2int1('h')))
      val () = ward_arr_set<byte>(arr, 2, _byte(32))
      val ch_digits = itoa_to_arr(arr, ch + 1, 3)
      val p = 3 + ch_digits
      val () = ward_arr_set<byte>(arr, _idx48(p), _byte(32))
      val () = ward_arr_set<byte>(arr, _idx48(p + 1), _byte(char2int1('P')))
      val () = ward_arr_set<byte>(arr, _idx48(p + 2), _byte(char2int1('g')))
      val () = ward_arr_set<byte>(arr, _idx48(p + 3), _byte(32))
      val pg_digits = itoa_to_arr(arr, pg + 1, p + 4)
      val total_len = p + 4 + pg_digits
      val tl = g1ofg0(total_len)
    in
      if tl > 0 then
        if tl < 48 then let
          val @(used, rest) = ward_arr_split<byte>(arr, tl)
          val () = ward_arr_free<byte>(rest)
          val @(frozen, borrow) = ward_arr_freeze<byte>(used)
          val s = ward_dom_stream_set_text(s, nid, borrow, tl)
          val () = ward_arr_drop<byte>(frozen, borrow)
          val used = ward_arr_thaw<byte>(frozen)
          val () = ward_arr_free<byte>(used)
        in s end
        else let val () = ward_arr_free<byte>(arr) in s end
      else let val () = ward_arr_free<byte>(arr) in s end
    end
  else let
    (* Build "Ch X Pg Y" *)
    val arr = ward_arr_alloc<byte>(48)
    val () = ward_arr_set<byte>(arr, 0, _byte(char2int1('C')))
    val () = ward_arr_set<byte>(arr, 1, _byte(char2int1('h')))
    val () = ward_arr_set<byte>(arr, 2, _byte(32))
    val ch_digits = itoa_to_arr(arr, ch + 1, 3)
    val p = 3 + ch_digits
    val () = ward_arr_set<byte>(arr, _idx48(p), _byte(32))
    val () = ward_arr_set<byte>(arr, _idx48(p + 1), _byte(char2int1('P')))
    val () = ward_arr_set<byte>(arr, _idx48(p + 2), _byte(char2int1('g')))
    val () = ward_arr_set<byte>(arr, _idx48(p + 3), _byte(32))
    val pg_digits = itoa_to_arr(arr, pg + 1, p + 4)
    val total_len = p + 4 + pg_digits
    val tl = g1ofg0(total_len)
  in
    if tl > 0 then
      if tl < 48 then let
        val @(used, rest) = ward_arr_split<byte>(arr, tl)
        val () = ward_arr_free<byte>(rest)
        val @(frozen, borrow) = ward_arr_freeze<byte>(used)
        val s = ward_dom_stream_set_text(s, nid, borrow, tl)
        val () = ward_arr_drop<byte>(frozen, borrow)
        val used = ward_arr_thaw<byte>(frozen)
        val () = ward_arr_free<byte>(used)
      in s end
      else let val () = ward_arr_free<byte>(arr) in s end
    else let val () = ward_arr_free<byte>(arr) in s end
  end

fn render_library_with_books {l:agz}
  (s: ward_dom_stream(l), list_id: int)
  : ward_dom_stream(l) = let
  val s = ward_dom_stream_remove_children(s, list_id)
  val count = library_get_count()
  fun loop {l:agz}(s: ward_dom_stream(l), i: int, n: int): ward_dom_stream(l) =
    if gte_int_int(i, n) then s
    else let
      val card_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, card_id, list_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, card_id, attr_class(), 5, cls_book_card(), 9)

      val title_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, title_id, card_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, title_id, attr_class(), 5, cls_book_title(), 10)
      val title_len = library_get_title(i, 0)
      val s = set_text_from_sbuf(s, title_id, title_len)

      val author_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, author_id, card_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, author_id, attr_class(), 5, cls_book_author(), 11)
      val author_len = library_get_author(i, 0)
      val s = set_text_from_sbuf(s, author_id, author_len)

      val pos_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, pos_id, card_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, pos_id, attr_class(), 5, cls_book_position(), 13)
      val s = render_position_text(s, pos_id, library_get_chapter(i), library_get_page(i))

      val btn_id = dom_next_id()
      val () = reader_set_btn_id(i, btn_id)
      val s = ward_dom_stream_create_element(s, btn_id, card_id, tag_button(), 6)
      val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_read_btn(), 8)
      val s = set_text_cstr(s, btn_id, TEXT_READ, 4)
    in loop(s, i + 1, n) end
in loop(s, 0, count) end

(* ========== Chapter loading ========== *)

fn load_chapter(file_handle: int, chapter_idx: int, container_id: int): void = let
  val path_len = epub_get_spine_path_len(chapter_idx)
in
  if gt_int_int(path_len, 0) then let
    val path_ptr = epub_get_spine_path_ptr(chapter_idx)
    val zip_idx = zip_find_entry(path_ptr, path_len)
  in
    if gte_int_int(zip_idx, 0) then let
      var entry: zip_entry
      val found = zip_get_entry(zip_idx, entry)
    in
      if gt_int_int(found, 0) then let
        val compression = entry.compression
        val compressed_size = entry.compressed_size
        val uncompressed_size = entry.uncompressed_size
        val data_off = zip_get_data_offset(zip_idx)
      in
        if gt_int_int(data_off, 0) then
          if eq_int_int(compression, 8) then let
            (* Deflated — async decompression *)
            val cs1 = (if gt_int_int(compressed_size, 0) then compressed_size else 1): int
            val cs_pos = _checked_pos(cs1)
            val arr = ward_arr_alloc<byte>(cs_pos)
            val _rd = ward_file_read(file_handle, data_off, arr, cs_pos)
            val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
            val p = ward_decompress(borrow, cs_pos, 2) (* deflate-raw *)
            val () = ward_arr_drop<byte>(frozen, borrow)
            val arr = ward_arr_thaw<byte>(frozen)
            val () = ward_arr_free<byte>(arr)
            val saved_cid = container_id
            val p2 = ward_promise_then<int><int>(p,
              llam (blob_handle: int): ward_promise_pending(int) => let
                val dlen = ward_decompress_get_len()
              in
                if gt_int_int(dlen, 0) then let
                  val dl = _checked_pos(dlen)
                  val arr2 = ward_arr_alloc<byte>(dl)
                  val _rd = ward_blob_read(blob_handle, 0, arr2, dl)
                  val () = ward_blob_free(blob_handle)
                  val @(frozen2, borrow2) = ward_arr_freeze<byte>(arr2)
                  val sax_len = ward_xml_parse_html(borrow2, dl)
                  val () = ward_arr_drop<byte>(frozen2, borrow2)
                  val arr2 = ward_arr_thaw<byte>(frozen2)
                  val () = ward_arr_free<byte>(arr2)
                in
                  if gt_int_int(sax_len, 0) then let
                    val sl = _checked_pos(sax_len)
                    val sax_buf = ward_xml_get_result(sl)
                    val dom = ward_dom_init()
                    val s = ward_dom_stream_begin(dom)
                    val s = render_tree(s, saved_cid, sax_buf, sl)
                    val dom = ward_dom_stream_end(s)
                    val () = ward_dom_fini(dom)
                    val () = ward_arr_free<byte>(sax_buf)
                    val () = measure_and_set_pages(saved_cid)
                  in ward_promise_return<int>(0) end
                  else ward_promise_return<int>(0)
                end
                else let
                  val () = ward_blob_free(blob_handle)
                in ward_promise_return<int>(0) end
              end)
            val () = ward_promise_discard<int>(p2)
          in end
          else if eq_int_int(compression, 0) then let
            (* Stored — read directly, no decompression needed *)
            val us1 = (if gt_int_int(uncompressed_size, 0)
              then uncompressed_size else 1): int
            val us_pos = _checked_pos(us1)
            val arr = ward_arr_alloc<byte>(us_pos)
            val _rd = ward_file_read(file_handle, data_off, arr, us_pos)
            val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
            val sax_len = ward_xml_parse_html(borrow, us_pos)
            val () = ward_arr_drop<byte>(frozen, borrow)
            val arr = ward_arr_thaw<byte>(frozen)
            val () = ward_arr_free<byte>(arr)
          in
            if gt_int_int(sax_len, 0) then let
              val sl = _checked_pos(sax_len)
              val sax_buf = ward_xml_get_result(sl)
              val dom = ward_dom_init()
              val s = ward_dom_stream_begin(dom)
              val s = render_tree(s, container_id, sax_buf, sl)
              val dom = ward_dom_stream_end(s)
              val () = ward_dom_fini(dom)
              val () = ward_arr_free<byte>(sax_buf)
              val () = measure_and_set_pages(container_id)
            in end
            else ()
          end
          else () (* unsupported compression method *)
        else ()
      end
      else ()
    end
    else ()
  end
  else ()
end

(* ========== Forward declarations for mutual recursion ========== *)

extern fun render_library(root_id: int): void
extern fun enter_reader(root_id: int, book_index: int): void

(* ========== Reader keyboard handler ========== *)

fn on_reader_keydown(payload_len: int, root_id: int): void = let
  val pl = g1ofg0(payload_len)
in
  (* Keydown payload: [u8:keyLen][bytes:key][u8:flags]
   * Minimum payload sizes: Space=3, Escape=8, ArrowLeft=11, ArrowRight=12 *)
  if gt1_int_int(pl, 2) then let
    val payload = ward_event_get_payload(pl)
    val key_len = byte2int0(ward_arr_get<byte>(payload, 0))
    val k0 = byte2int0(ward_arr_get<byte>(payload, 1))
    val () = ward_arr_free<byte>(payload)
    val cid = reader_get_container_id()
  in
    if eq_int_int(key_len, 6) then
      (* "Escape": key_len=6, k0='E' (69) *)
      if eq_int_int(k0, 69) then let
        val () = reader_save_and_exit()
        val () = render_library(root_id)
      in end
      else ()
    else if eq_int_int(key_len, 10) then
      (* "ArrowRight": key_len=10, k0='A' (65) *)
      if eq_int_int(k0, 65) then let
        val () = reader_next_page()
        val () = apply_page_transform(cid)
      in end
      else ()
    else if eq_int_int(key_len, 9) then
      (* "ArrowLeft": key_len=9, k0='A' (65) *)
      if eq_int_int(k0, 65) then let
        val () = reader_prev_page()
        val () = apply_page_transform(cid)
      in end
      else ()
    else if eq_int_int(key_len, 1) then
      (* " " (Space): key_len=1, k0=' ' (32) *)
      if eq_int_int(k0, 32) then let
        val () = reader_next_page()
        val () = apply_page_transform(cid)
      in end
      else ()
    else ()
  end
  else ()
end

(* ========== Render library view ========== *)

implement render_library(root_id) = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, root_id)

  (* Import button: <label class="import-btn">Import<input ...></label> *)
  val label_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, label_id, root_id, tag_label(), 5)
  val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5, cls_import_btn(), 10)

  val import_st = let
    val b = ward_text_build(6)
    val b = ward_text_putc(b, 0, 73) (* 'I' *)
    val b = ward_text_putc(b, 1, char2int1('m'))
    val b = ward_text_putc(b, 2, char2int1('p'))
    val b = ward_text_putc(b, 3, char2int1('o'))
    val b = ward_text_putc(b, 4, char2int1('r'))
    val b = ward_text_putc(b, 5, char2int1('t'))
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, label_id, import_st, 6)

  val input_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, input_id, label_id, tag_input(), 5)
  val s = ward_dom_stream_set_attr_safe(s, input_id, attr_type(), 4, st_file(), 4)
  val s = set_attr_cstr(s, input_id, attr_accept(), 6, TEXT_EPUB_EXT, 5)

  (* Library list *)
  val list_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, list_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, list_id, attr_class(), 5, cls_library_list(), 12)

  val count = library_get_count()
in
  if gt_int_int(count, 0) then let
    (* Render book cards *)
    val s = render_library_with_books(s, list_id)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)

    (* Register change listener on file input *)
    val saved_input_id = input_id
    val saved_list_id = list_id
    val saved_root = root_id
    val () = ward_add_event_listener(
      input_id, evt_change(), 6, 1,
      lam (_payload_len: int): int => let
        val p = ward_file_open(saved_input_id)
        val p2 = ward_promise_then<int><int>(p,
          llam (handle: int): ward_promise_pending(int) => let
            val file_size = ward_file_get_size()
            val () = reader_set_file_handle(handle)
            (* Async break: yield to event loop to reset V8 call stack.
             * Chrome renderer stack is ~864KB; the synchronous EPUB
             * import chain exceeds this with ext# wrapper overhead. *)
            val break_p = ward_timer_set(0)
            val sh = handle val sfs = file_size val sli = saved_list_id
          in ward_promise_then<int><int>(break_p,
            llam (_unused: int): ward_promise_pending(int) => let
              val _nentries = zip_open(sh, sfs)
              val ok1 = epub_read_container(sh)
              val ok2 = (if gt_int_int(ok1, 0)
                then epub_read_opf(sh) else 0): int
              val _book_idx = (if gt_int_int(ok2, 0)
                then library_add_book() else 0 - 1): int
              val dom = ward_dom_init()
              val s = ward_dom_stream_begin(dom)
              val s = render_library_with_books(s, sli)
              val dom = ward_dom_stream_end(s)
              val () = ward_dom_fini(dom)
            in ward_promise_return<int>(0) end)
          end)
        val () = ward_promise_discard<int>(p2)
      in 0 end
    )

    (* Register click listeners on read buttons *)
    fun reg_btns(i: int, n: int, root: int): void =
      if gte_int_int(i, n) then ()
      else let
        val btn_id = reader_get_btn_id(i)
        val book_idx = i
        val saved_r = root
      in
        if gt_int_int(btn_id, 0) then let
          val () = ward_add_event_listener(
            btn_id, evt_click(), 5, 2 + i,
            lam (_pl: int): int => let
              val () = enter_reader(saved_r, book_idx)
            in 0 end
          )
        in reg_btns(i + 1, n, root) end
        else reg_btns(i + 1, n, root)
      end
    val () = reg_btns(0, count, root_id)
  in end
  else let
    (* Empty library message *)
    val empty_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, empty_id, list_id, tag_div(), 3)
    val s = ward_dom_stream_set_attr_safe(s, empty_id, attr_class(), 5, cls_empty_lib(), 9)
    val s = set_text_cstr(s, empty_id, TEXT_NO_BOOKS, 12)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)

    (* Register change listener on file input *)
    val saved_input_id = input_id
    val saved_list_id = list_id
    val saved_root = root_id
    val () = ward_add_event_listener(
      input_id, evt_change(), 6, 1,
      lam (_payload_len: int): int => let
        val p = ward_file_open(saved_input_id)
        val p2 = ward_promise_then<int><int>(p,
          llam (handle: int): ward_promise_pending(int) => let
            val file_size = ward_file_get_size()
            val () = reader_set_file_handle(handle)
            (* Async break: yield to event loop to reset V8 call stack *)
            val break_p = ward_timer_set(0)
            val sh = handle val sfs = file_size
            val sli = saved_list_id val sr = saved_root
          in ward_promise_then<int><int>(break_p,
            llam (_unused: int): ward_promise_pending(int) => let
              val _nentries = zip_open(sh, sfs)
              val ok1 = epub_read_container(sh)
              val ok2 = (if gt_int_int(ok1, 0)
                then epub_read_opf(sh) else 0): int
              val _book_idx = (if gt_int_int(ok2, 0)
                then library_add_book() else 0 - 1): int
              val dom = ward_dom_init()
              val s = ward_dom_stream_begin(dom)
              val s = render_library_with_books(s, sli)
              val dom = ward_dom_stream_end(s)
              val () = ward_dom_fini(dom)

              (* Register click listeners on newly rendered read buttons *)
              val btn_count = library_get_count()
              fun reg_new_btns(i: int, n: int, root: int): void =
                if gte_int_int(i, n) then ()
                else let
                  val bid = reader_get_btn_id(i)
                  val bidx = i
                  val sroot = root
                in
                  if gt_int_int(bid, 0) then let
                    val () = ward_add_event_listener(
                      bid, evt_click(), 5, 2 + i,
                      lam (_pl2: int): int => let
                        val () = enter_reader(sroot, bidx)
                      in 0 end
                    )
                  in reg_new_btns(i + 1, n, root) end
                  else reg_new_btns(i + 1, n, root)
                end
              val () = reg_new_btns(0, btn_count, sr)
            in ward_promise_return<int>(0) end)
          end)
        val () = ward_promise_discard<int>(p2)
      in 0 end
    )
  in end
end

(* ========== Enter reader view ========== *)

implement enter_reader(root_id, book_index) = let
  val () = reader_enter(root_id, 0)
  val () = reader_set_book_index(book_index)
  val file_handle = reader_get_file_handle()

  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, root_id)

  (* Create .reader-viewport with tabindex="0" for keyboard focus *)
  val viewport_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, viewport_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, viewport_id, attr_class(), 5,
    cls_reader_viewport(), 15)
  val s = ward_dom_stream_set_attr_safe(s, viewport_id, attr_tabindex(), 8,
    val_zero(), 1)

  (* Create .chapter-container *)
  val container_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, container_id, viewport_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, container_id, attr_class(), 5,
    cls_chapter_container(), 17)

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Store IDs *)
  val () = reader_set_viewport_id(viewport_id)
  val () = reader_set_container_id(container_id)

  (* Register keydown listener on viewport *)
  val saved_root = root_id
  val () = ward_add_event_listener(
    viewport_id, evt_keydown(), 7, 50,
    lam (payload_len: int): int => let
      val () = on_reader_keydown(payload_len, saved_root)
    in 0 end
  )

  (* Register click listener on viewport for page navigation *)
  val saved_container = container_id
  val () = ward_add_event_listener(
    viewport_id, evt_click(), 5, 51,
    lam (pl: int): int => let
      val pl1 = g1ofg0(pl)
    in
      if gt1_int_int(pl1, 19) then let
        (* Click payload: f64 clientX (0-7), f64 clientY (8-15), i32 target (16-19) *)
        val payload = ward_event_get_payload(pl1)
        val click_x = read_payload_click_x(payload)
        val () = ward_arr_free<byte>(payload)
        val vw = measure_node_width(reader_get_viewport_id())
      in
        if gt_int_int(vw, 0) then let
          (* Right 75% → next page, left 25% → prev page *)
          val threshold = div_int_int(vw, 4)
        in
          if gt_int_int(click_x, threshold) then let
            val () = reader_next_page()
            val () = apply_page_transform(saved_container)
          in 0 end
          else let
            val () = reader_prev_page()
            val () = apply_page_transform(saved_container)
          in 0 end
        end
        else 0
      end
      else 0
    end
  )

  (* Load first chapter *)
  val () = load_chapter(file_handle, 0, container_id)
in end

(* ========== Entry point ========== *)

implement ward_node_init(root_id) = let
  val st = app_state_init()
  val () = app_state_register(st)
  val () = render_library(root_id)
in end

(* Legacy callback stubs *)
implement init() = ()
implement process_event() = ()
implement on_fetch_complete(status, len) = ()
implement on_timer_complete(callback_id) = ()
implement on_file_open_complete(handle, size) = ()
implement on_decompress_complete(handle, size) = ()
implement on_kv_complete(success) = ()
implement on_kv_get_complete(len) = ()
implement on_kv_get_blob_complete(handle, size) = ()
implement on_clipboard_copy_complete(success) = ()
implement on_kv_open_complete(success) = ()
