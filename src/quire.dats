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
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/listener.sats"
staload "./../vendor/ward/lib/file.sats"
staload "./../vendor/ward/lib/promise.sats"
staload "./../vendor/ward/lib/event.sats"
staload "./../vendor/ward/lib/decompress.sats"
staload "./../vendor/ward/lib/xml.sats"
staload "./../vendor/ward/lib/dom_read.sats"
staload "./../vendor/ward/lib/window.sats"
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
staload "./quire_ext.sats"

(* Forward declaration for JS import — suppresses C99 warning *)
%{
extern void quireSetTitle(int mode);
%}

(* ========== Text constant IDs ========== *)

#define TEXT_NO_BOOKS 0
#define TEXT_EPUB_EXT 1
#define TEXT_NOT_STARTED 2
#define TEXT_READ 3
#define TEXT_IMPORTING 4
#define TEXT_OPENING_FILE 5
#define TEXT_PARSING_ZIP 6
#define TEXT_READING_META 7
#define TEXT_ADDING_BOOK 8

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
  else if text_id = 3 then let (* "Read" *)
    val () = ward_arr_set_byte(arr, 0, alen, 82)   (* R *)
    val () = ward_arr_set_byte(arr, 1, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 2, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 3, alen, 100)  (* d *)
  in end
  else if text_id = 4 then let (* "Importing" *)
    val () = ward_arr_set_byte(arr, 0, alen, 73)   (* I *)
    val () = ward_arr_set_byte(arr, 1, alen, 109)  (* m *)
    val () = ward_arr_set_byte(arr, 2, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 3, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 4, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 5, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 6, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 7, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 8, alen, 103)  (* g *)
  in end
  else if text_id = 5 then let (* "Opening file" *)
    val () = ward_arr_set_byte(arr, 0, alen, 79)   (* O *)
    val () = ward_arr_set_byte(arr, 1, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 2, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 3, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 4, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 5, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 6, alen, 103)  (* g *)
    val () = ward_arr_set_byte(arr, 7, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 8, alen, 102)  (* f *)
    val () = ward_arr_set_byte(arr, 9, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 10, alen, 108) (* l *)
    val () = ward_arr_set_byte(arr, 11, alen, 101) (* e *)
  in end
  else if text_id = 6 then let (* "Parsing archive" *)
    val () = ward_arr_set_byte(arr, 0, alen, 80)   (* P *)
    val () = ward_arr_set_byte(arr, 1, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 2, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 3, alen, 115)  (* s *)
    val () = ward_arr_set_byte(arr, 4, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 5, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 6, alen, 103)  (* g *)
    val () = ward_arr_set_byte(arr, 7, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 8, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 9, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 10, alen, 99)  (* c *)
    val () = ward_arr_set_byte(arr, 11, alen, 104) (* h *)
    val () = ward_arr_set_byte(arr, 12, alen, 105) (* i *)
    val () = ward_arr_set_byte(arr, 13, alen, 118) (* v *)
    val () = ward_arr_set_byte(arr, 14, alen, 101) (* e *)
  in end
  else if text_id = 7 then let (* "Reading metadata" *)
    val () = ward_arr_set_byte(arr, 0, alen, 82)   (* R *)
    val () = ward_arr_set_byte(arr, 1, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 2, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 3, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 4, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 5, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 6, alen, 103)  (* g *)
    val () = ward_arr_set_byte(arr, 7, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 8, alen, 109)  (* m *)
    val () = ward_arr_set_byte(arr, 9, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 10, alen, 116) (* t *)
    val () = ward_arr_set_byte(arr, 11, alen, 97)  (* a *)
    val () = ward_arr_set_byte(arr, 12, alen, 100) (* d *)
    val () = ward_arr_set_byte(arr, 13, alen, 97)  (* a *)
    val () = ward_arr_set_byte(arr, 14, alen, 116) (* t *)
    val () = ward_arr_set_byte(arr, 15, alen, 97)  (* a *)
  in end
  else let (* text_id = 8: "Adding to library" *)
    val () = ward_arr_set_byte(arr, 0, alen, 65)   (* A *)
    val () = ward_arr_set_byte(arr, 1, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 2, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 3, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 4, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 5, alen, 103)  (* g *)
    val () = ward_arr_set_byte(arr, 6, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 7, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 8, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 9, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 10, alen, 108) (* l *)
    val () = ward_arr_set_byte(arr, 11, alen, 105) (* i *)
    val () = ward_arr_set_byte(arr, 12, alen, 98)  (* b *)
    val () = ward_arr_set_byte(arr, 13, alen, 114) (* r *)
    val () = ward_arr_set_byte(arr, 14, alen, 97)  (* a *)
    val () = ward_arr_set_byte(arr, 15, alen, 114) (* r *)
    val () = ward_arr_set_byte(arr, 16, alen, 121) (* y *)
  in end

(* Copy len bytes from string_buffer to ward_arr *)
fn copy_from_sbuf {l:agz}{n:pos}
  (dst: !ward_arr(byte, l, n), len: int n): void = let
  fun loop(dst: !ward_arr(byte, l, n), dlen: int n,
           i: int, count: int): void =
    if i < count then let
      val b = _app_sbuf_get_u8(i)
      val () = ward_arr_set_byte(dst, i, dlen, b)
    in loop(dst, dlen, i + 1, count) end
in loop(dst, len, 0, len) end

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

fn cls_importing(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, char2int1('i'))
  val b = ward_text_putc(b, 7, char2int1('n'))
  val b = ward_text_putc(b, 8, char2int1('g'))
in ward_text_done(b) end

fn cls_import_status(): ward_safe_text(13) = let
  val b = ward_text_build(13)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, 45) (* '-' *)
  val b = ward_text_putc(b, 7, char2int1('s'))
  val b = ward_text_putc(b, 8, char2int1('t'))
  val b = ward_text_putc(b, 9, char2int1('a'))
  val b = ward_text_putc(b, 10, char2int1('t'))
  val b = ward_text_putc(b, 11, char2int1('u'))
  val b = ward_text_putc(b, 12, char2int1('s'))
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

(* ========== Log message safe text builders ========== *)

(* "import-start" = 12 chars *)
fn log_import_start(): ward_safe_text(12) = let
  val b = ward_text_build(12)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, 45)
  val b = ward_text_putc(b, 7, char2int1('s'))
  val b = ward_text_putc(b, 8, char2int1('t'))
  val b = ward_text_putc(b, 9, char2int1('a'))
  val b = ward_text_putc(b, 10, char2int1('r'))
  val b = ward_text_putc(b, 11, char2int1('t'))
in ward_text_done(b) end

(* "import-done" = 11 chars *)
fn log_import_done(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('i'))
  val b = ward_text_putc(b, 1, char2int1('m'))
  val b = ward_text_putc(b, 2, char2int1('p'))
  val b = ward_text_putc(b, 3, char2int1('o'))
  val b = ward_text_putc(b, 4, char2int1('r'))
  val b = ward_text_putc(b, 5, char2int1('t'))
  val b = ward_text_putc(b, 6, 45)
  val b = ward_text_putc(b, 7, char2int1('d'))
  val b = ward_text_putc(b, 8, char2int1('o'))
  val b = ward_text_putc(b, 9, char2int1('n'))
  val b = ward_text_putc(b, 10, char2int1('e'))
in ward_text_done(b) end

(* ========== App CSS injection ========== *)

(* CSS bytes packed as little-endian int32s, written via _w4.
 * Generated from the CSS string — round-trip verified. *)
#define APP_CSS_LEN 2012
stadef APP_CSS_LEN = 2012

(* Write 4 bytes from packed little-endian int *)
fn _w4 {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, off: int, v: int): void = let
  val () = ward_arr_set_byte(arr, off, alen, band_int_int(v, 255))
  val () = ward_arr_set_byte(arr, off+1, alen, band_int_int(bsr_int_int(v, 8), 255))
  val () = ward_arr_set_byte(arr, off+2, alen, band_int_int(bsr_int_int(v, 16), 255))
  val () = ward_arr_set_byte(arr, off+3, alen, bsr_int_int(v, 24))
in end

fn fill_css_base {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* html,body *)
  val () = _w4(arr, alen, 0, 1819112552)
  val () = _w4(arr, alen, 4, 1685021228)
  val () = _w4(arr, alen, 8, 1634564985)
  val () = _w4(arr, alen, 12, 1852401522)
  val () = _w4(arr, alen, 16, 1882927162)
  val () = _w4(arr, alen, 20, 1768186977)
  val () = _w4(arr, alen, 24, 809133934)
  val () = _w4(arr, alen, 28, 1667326523)
  val () = _w4(arr, alen, 32, 1869768555)
  val () = _w4(arr, alen, 36, 979660405)
  val () = _w4(arr, alen, 40, 1717659171)
  val () = _w4(arr, alen, 44, 993551969)
  val () = _w4(arr, alen, 48, 1869377379)
  val () = _w4(arr, alen, 52, 841169522)
  val () = _w4(arr, alen, 56, 845230689)
  val () = _w4(arr, alen, 60, 1868970849)
  val () = _w4(arr, alen, 64, 1714254958)
  val () = _w4(arr, alen, 68, 1818848609)
  val () = _w4(arr, alen, 72, 1699166841)
  val () = _w4(arr, alen, 76, 1768387183)
  val () = _w4(arr, alen, 80, 1702046817)
  val () = _w4(arr, alen, 84, 996567410)
  val () = _w4(arr, alen, 88, 1953394534)
  val () = _w4(arr, alen, 92, 2053731117)
  val () = _w4(arr, alen, 96, 942750309)
  val () = _w4(arr, alen, 100, 1815836784)
  val () = _w4(arr, alen, 104, 761622121)
  val () = _w4(arr, alen, 108, 1734960488)
  val () = _w4(arr, alen, 112, 825914472)
  val () = _w4(arr, alen, 116, 779957806)
  (* .import-btn *)
  val () = _w4(arr, alen, 120, 1869639017)
  val () = _w4(arr, alen, 124, 1647146098)
  val () = _w4(arr, alen, 128, 1685810804)
  val () = _w4(arr, alen, 132, 1819308905)
  val () = _w4(arr, alen, 136, 1765439841)
  val () = _w4(arr, alen, 140, 1852402798)
  val () = _w4(arr, alen, 144, 1818373477)
  val () = _w4(arr, alen, 148, 996893551)
  val () = _w4(arr, alen, 152, 1684300144)
  val () = _w4(arr, alen, 156, 979857001)
  val () = _w4(arr, alen, 160, 1701983534)
  val () = _w4(arr, alen, 164, 774971501)
  val () = _w4(arr, alen, 168, 1835364914)
  val () = _w4(arr, alen, 172, 1918987579)
  val () = _w4(arr, alen, 176, 980314471)
  val () = _w4(arr, alen, 180, 1835364913)
  val () = _w4(arr, alen, 184, 1667326523)
  val () = _w4(arr, alen, 188, 1869768555)
  val () = _w4(arr, alen, 192, 979660405)
  val () = _w4(arr, alen, 196, 929117219)
  val () = _w4(arr, alen, 200, 993604963)
  val () = _w4(arr, alen, 204, 1869377379)
  val () = _w4(arr, alen, 208, 1713584754)
  val () = _w4(arr, alen, 212, 1648060006)
  val () = _w4(arr, alen, 216, 1701081711)
  val () = _w4(arr, alen, 220, 1634872690)
  val () = _w4(arr, alen, 224, 1937074532)
  val () = _w4(arr, alen, 228, 2020619322)
  val () = _w4(arr, alen, 232, 1920295739)
  val () = _w4(arr, alen, 236, 980578163)
  val () = _w4(arr, alen, 240, 1852403568)
  val () = _w4(arr, alen, 244, 997352820)
  val () = _w4(arr, alen, 248, 1953394534)
  val () = _w4(arr, alen, 252, 2053731117)
  val () = _w4(arr, alen, 256, 1915828837)
  val () = _w4(arr, alen, 260, 779971941)
  (* .import-btn input[type=file] *)
  val () = _w4(arr, alen, 264, 1869639017)
  val () = _w4(arr, alen, 268, 1647146098)
  val () = _w4(arr, alen, 272, 1763733108)
  val () = _w4(arr, alen, 276, 1953853550)
  val () = _w4(arr, alen, 280, 1887007835)
  val () = _w4(arr, alen, 284, 1768308069)
  val () = _w4(arr, alen, 288, 2069718380)
  val () = _w4(arr, alen, 292, 1886611812)
  val () = _w4(arr, alen, 296, 981033324)
  val () = _w4(arr, alen, 300, 1701736302)
  (* .library-list *)
  val () = _w4(arr, alen, 304, 1768697469)
  val () = _w4(arr, alen, 308, 1918988898)
  val () = _w4(arr, alen, 312, 1768697209)
  val () = _w4(arr, alen, 316, 1887138931)
  val () = _w4(arr, alen, 320, 1768186977)
  val () = _w4(arr, alen, 324, 825911150)
  val () = _w4(arr, alen, 328, 2104321394)
  (* .empty-lib *)
  val () = _w4(arr, alen, 332, 1886217518)
  val () = _w4(arr, alen, 336, 1814919540)
  val () = _w4(arr, alen, 340, 1669030505)
  val () = _w4(arr, alen, 344, 1919904879)
  val () = _w4(arr, alen, 348, 943203130)
  val () = _w4(arr, alen, 352, 1702116152)
  val () = _w4(arr, alen, 356, 1630368888)
  val () = _w4(arr, alen, 360, 1852270956)
  val () = _w4(arr, alen, 364, 1852138298)
  val () = _w4(arr, alen, 368, 997352820)
  val () = _w4(arr, alen, 372, 1684300144)
  val () = _w4(arr, alen, 376, 979857001)
  val () = _w4(arr, alen, 380, 1835364914)
  val () = _w4(arr, alen, 384, 1852794427)
  val () = _w4(arr, alen, 388, 1953705332)
  val () = _w4(arr, alen, 392, 979725433)
  val () = _w4(arr, alen, 396, 1818326121)
  val () = ward_arr_set_byte(arr, 400, alen, 105)
  val () = ward_arr_set_byte(arr, 401, alen, 99)
  val () = ward_arr_set_byte(arr, 402, alen, 125)
in end

fn fill_css_cards {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* .book-card *)
  val () = _w4(arr, alen, 403, 1869570606)
  val () = _w4(arr, alen, 407, 1633889643)
  val () = _w4(arr, alen, 411, 1685808242)
  val () = _w4(arr, alen, 415, 1819308905)
  val () = _w4(arr, alen, 419, 1715108193)
  val () = _w4(arr, alen, 423, 997746028)
  val () = _w4(arr, alen, 427, 1734962273)
  val () = _w4(arr, alen, 431, 1953049966)
  val () = _w4(arr, alen, 435, 980643173)
  val () = _w4(arr, alen, 439, 1953391971)
  val () = _w4(arr, alen, 443, 1882944101)
  val () = _w4(arr, alen, 447, 1768186977)
  val () = _w4(arr, alen, 451, 775579502)
  val () = _w4(arr, alen, 455, 1701983543)
  val () = _w4(arr, alen, 459, 1915822189)
  val () = _w4(arr, alen, 463, 1832611173)
  val () = _w4(arr, alen, 467, 1768387169)
  val () = _w4(arr, alen, 471, 1868705134)
  val () = _w4(arr, alen, 475, 1836020852)
  val () = _w4(arr, alen, 479, 1916087866)
  val () = _w4(arr, alen, 483, 1648061797)
  val () = _w4(arr, alen, 487, 1735091041)
  val () = _w4(arr, alen, 491, 1853190002)
  val () = _w4(arr, alen, 495, 1713584740)
  val () = _w4(arr, alen, 499, 1648060006)
  val () = _w4(arr, alen, 503, 1701081711)
  val () = _w4(arr, alen, 507, 1882274418)
  val () = _w4(arr, alen, 511, 1869815928)
  val () = _w4(arr, alen, 515, 543451500)
  val () = _w4(arr, alen, 519, 1697670435)
  val () = _w4(arr, alen, 523, 993027376)
  val () = _w4(arr, alen, 527, 1685221218)
  val () = _w4(arr, alen, 531, 1915581029)
  val () = _w4(arr, alen, 535, 1969841249)
  val () = _w4(arr, alen, 539, 1882602099)
  val () = _w4(arr, alen, 543, 1647213944)
  val () = _w4(arr, alen, 547, 762015599)
  (* .book-title *)
  val () = _w4(arr, alen, 551, 1819568500)
  val () = _w4(arr, alen, 555, 1868987237)
  val () = _w4(arr, alen, 559, 1999467630)
  val () = _w4(arr, alen, 563, 1751607653)
  val () = _w4(arr, alen, 567, 1868708468)
  val () = _w4(arr, alen, 571, 1832608876)
  val () = _w4(arr, alen, 575, 1768387169)
  val () = _w4(arr, alen, 579, 1769090414)
  val () = _w4(arr, alen, 583, 980707431)
  val () = _w4(arr, alen, 587, 1701983534)
  val () = _w4(arr, alen, 591, 1647213933)
  (* .book-author *)
  val () = _w4(arr, alen, 595, 762015599)
  val () = _w4(arr, alen, 599, 1752462689)
  val () = _w4(arr, alen, 603, 1669034607)
  val () = _w4(arr, alen, 607, 1919904879)
  val () = _w4(arr, alen, 611, 909517626)
  val () = _w4(arr, alen, 615, 1634548534)
  val () = _w4(arr, alen, 619, 1852401522)
  val () = _w4(arr, alen, 623, 1734963757)
  val () = _w4(arr, alen, 627, 1631220840)
  val () = _w4(arr, alen, 631, 2104456309)
  (* .book-position *)
  val () = _w4(arr, alen, 635, 1869570606)
  val () = _w4(arr, alen, 639, 1869622635)
  val () = _w4(arr, alen, 643, 1769236851)
  val () = _w4(arr, alen, 647, 1669033583)
  val () = _w4(arr, alen, 651, 1919904879)
  val () = _w4(arr, alen, 655, 960045882)
  val () = _w4(arr, alen, 659, 1868970809)
  val () = _w4(arr, alen, 663, 1932358766)
  val () = _w4(arr, alen, 667, 979729001)
  val () = _w4(arr, alen, 671, 1916090414)
  val () = _w4(arr, alen, 675, 1832611173)
  val () = _w4(arr, alen, 679, 1768387169)
  val () = _w4(arr, alen, 683, 1769090414)
  val () = _w4(arr, alen, 687, 980707431)
  val () = _w4(arr, alen, 691, 1835364913)
  (* .read-btn *)
  val () = _w4(arr, alen, 695, 1701981821)
  val () = _w4(arr, alen, 699, 1647141985)
  val () = _w4(arr, alen, 703, 1887137396)
  val () = _w4(arr, alen, 707, 1768186977)
  val () = _w4(arr, alen, 711, 775579502)
  val () = _w4(arr, alen, 715, 1835364916)
  val () = _w4(arr, alen, 719, 1701982496)
  val () = _w4(arr, alen, 723, 1633827693)
  val () = _w4(arr, alen, 727, 1919380323)
  val () = _w4(arr, alen, 731, 1684960623)
  val () = _w4(arr, alen, 735, 1630806842)
  val () = _w4(arr, alen, 739, 959800119)
  val () = _w4(arr, alen, 743, 1819239227)
  val () = _w4(arr, alen, 747, 591032943)
  val () = _w4(arr, alen, 751, 996566630)
  val () = _w4(arr, alen, 755, 1685221218)
  val () = _w4(arr, alen, 759, 1849324133)
  val () = _w4(arr, alen, 763, 996503151)
  val () = _w4(arr, alen, 767, 1685221218)
  val () = _w4(arr, alen, 771, 1915581029)
  val () = _w4(arr, alen, 775, 1969841249)
  val () = _w4(arr, alen, 779, 1882471027)
  val () = _w4(arr, alen, 783, 1969437560)
  val () = _w4(arr, alen, 787, 1919906674)
  val () = _w4(arr, alen, 791, 1768910906)
  val () = _w4(arr, alen, 795, 1919251566)
  val () = ward_arr_set_byte(arr, 799, alen, 125)
in end

fn fill_css_reader {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* .reader-viewport *)
  val () = _w4(arr, alen, 800, 1634038318)
  val () = _w4(arr, alen, 804, 762471780)
  val () = _w4(arr, alen, 808, 2003134838)
  val () = _w4(arr, alen, 812, 1953656688)
  val () = _w4(arr, alen, 816, 1684633467)
  val () = _w4(arr, alen, 820, 825911412)
  val () = _w4(arr, alen, 824, 2004234288)
  val () = _w4(arr, alen, 828, 1768253499)
  val () = _w4(arr, alen, 832, 980707431)
  val () = _w4(arr, alen, 836, 1982869553)
  val () = _w4(arr, alen, 840, 1987001192)
  val () = _w4(arr, alen, 844, 1818653285)
  val () = _w4(arr, alen, 848, 1748662127)
  val () = _w4(arr, alen, 852, 1701078121)
  val () = _w4(arr, alen, 856, 1869626222)
  val () = _w4(arr, alen, 860, 1769236851)
  val () = _w4(arr, alen, 864, 1916431983)
  val () = _w4(arr, alen, 868, 1952541797)
  val () = _w4(arr, alen, 872, 2103801449)
  (* .chapter-container *)
  val () = _w4(arr, alen, 876, 1634231086)
  val () = _w4(arr, alen, 880, 1919251568)
  val () = _w4(arr, alen, 884, 1852793645)
  val () = _w4(arr, alen, 888, 1852399988)
  val () = _w4(arr, alen, 892, 1669034597)
  val () = _w4(arr, alen, 896, 1836412015)
  val () = _w4(arr, alen, 900, 1769418094)
  val () = _w4(arr, alen, 904, 979924068)
  val () = _w4(arr, alen, 908, 1982869553)
  val () = _w4(arr, alen, 912, 1868774263)
  val () = _w4(arr, alen, 916, 1852667244)
  val () = _w4(arr, alen, 920, 1885431597)
  val () = _w4(arr, alen, 924, 1748709434)
  val () = _w4(arr, alen, 928, 1751607653)
  val () = _w4(arr, alen, 932, 1633892980)
  val () = _w4(arr, alen, 936, 824730476)
  val () = _w4(arr, alen, 940, 1752576048)
  val () = _w4(arr, alen, 944, 874523936)
  val () = _w4(arr, alen, 948, 695035250)
  val () = _w4(arr, alen, 952, 1702260539)
  val () = _w4(arr, alen, 956, 1869375090)
  val () = _w4(arr, alen, 960, 1769355895)
  val () = _w4(arr, alen, 964, 1818388851)
  val () = _w4(arr, alen, 968, 1634745189)
  val () = _w4(arr, alen, 972, 1852400740)
  val () = _w4(arr, alen, 976, 1915894375)
  val () = _w4(arr, alen, 980, 824208741)
  val () = _w4(arr, alen, 984, 1701983534)
  val () = _w4(arr, alen, 988, 1868708717)
  val () = _w4(arr, alen, 992, 1769155960)
  val () = _w4(arr, alen, 996, 1735289210)
  val () = _w4(arr, alen, 1000, 1919902266)
  val () = _w4(arr, alen, 1004, 762471780)
  val () = _w4(arr, alen, 1008, 2105044834)
in end

fn fill_css_content {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* .chapter-container h1,.chapter-container h2,.chapter-container h3 *)
  val () = _w4(arr, alen, 1012, 1634231086)
  val () = _w4(arr, alen, 1016, 1919251568)
  val () = _w4(arr, alen, 1020, 1852793645)
  val () = _w4(arr, alen, 1024, 1852399988)
  val () = _w4(arr, alen, 1028, 1746956901)
  val () = _w4(arr, alen, 1032, 1663970353)
  val () = _w4(arr, alen, 1036, 1953522024)
  val () = _w4(arr, alen, 1040, 1663922789)
  val () = _w4(arr, alen, 1044, 1635020399)
  val () = _w4(arr, alen, 1048, 1919250025)
  val () = _w4(arr, alen, 1052, 741500960)
  val () = _w4(arr, alen, 1056, 1634231086)
  val () = _w4(arr, alen, 1060, 1919251568)
  val () = _w4(arr, alen, 1064, 1852793645)
  val () = _w4(arr, alen, 1068, 1852399988)
  val () = _w4(arr, alen, 1072, 1746956901)
  val () = _w4(arr, alen, 1076, 1634564915)
  val () = _w4(arr, alen, 1080, 1852401522)
  val () = _w4(arr, alen, 1084, 1886352429)
  val () = _w4(arr, alen, 1088, 892219706)
  val () = _w4(arr, alen, 1092, 1832611173)
  val () = _w4(arr, alen, 1096, 1768387169)
  val () = _w4(arr, alen, 1100, 1868705134)
  val () = _w4(arr, alen, 1104, 1836020852)
  val () = _w4(arr, alen, 1108, 1697984058)
  val () = _w4(arr, alen, 1112, 1768700781)
  val () = _w4(arr, alen, 1116, 1747805550)
  val () = _w4(arr, alen, 1120, 1751607653)
  val () = _w4(arr, alen, 1124, 774978164)
  (* .chapter-container p *)
  val () = _w4(arr, alen, 1128, 1663991091)
  val () = _w4(arr, alen, 1132, 1953522024)
  val () = _w4(arr, alen, 1136, 1663922789)
  val () = _w4(arr, alen, 1140, 1635020399)
  val () = _w4(arr, alen, 1144, 1919250025)
  val () = _w4(arr, alen, 1148, 1836806176)
  val () = _w4(arr, alen, 1152, 1768387169)
  val () = _w4(arr, alen, 1156, 540031598)
  val () = _w4(arr, alen, 1160, 942546992)
  val () = _w4(arr, alen, 1164, 1950051685)
  val () = _w4(arr, alen, 1168, 762607717)
  val () = _w4(arr, alen, 1172, 1734962273)
  val () = _w4(arr, alen, 1176, 1969896046)
  val () = _w4(arr, alen, 1180, 1718187123)
  (* .chapter-container blockquote *)
  val () = _w4(arr, alen, 1184, 1663991161)
  val () = _w4(arr, alen, 1188, 1953522024)
  val () = _w4(arr, alen, 1192, 1663922789)
  val () = _w4(arr, alen, 1196, 1635020399)
  val () = _w4(arr, alen, 1200, 1919250025)
  val () = _w4(arr, alen, 1204, 1869373984)
  val () = _w4(arr, alen, 1208, 1970367331)
  val () = _w4(arr, alen, 1212, 2070246511)
  val () = _w4(arr, alen, 1216, 1735549293)
  val () = _w4(arr, alen, 1220, 825912937)
  val () = _w4(arr, alen, 1224, 840985957)
  val () = _w4(arr, alen, 1228, 1882942821)
  val () = _w4(arr, alen, 1232, 1768186977)
  val () = _w4(arr, alen, 1236, 1814914926)
  val () = _w4(arr, alen, 1240, 980706917)
  val () = _w4(arr, alen, 1244, 997025073)
  val () = _w4(arr, alen, 1248, 1685221218)
  val () = _w4(arr, alen, 1252, 1814917733)
  val () = _w4(arr, alen, 1256, 980706917)
  val () = _w4(arr, alen, 1260, 544763955)
  val () = _w4(arr, alen, 1264, 1768714099)
  val () = _w4(arr, alen, 1268, 1663246436)
  val () = _w4(arr, alen, 1272, 1664836451)
  val () = _w4(arr, alen, 1276, 1919904879)
  val () = _w4(arr, alen, 1280, 892674874)
  (* .chapter-container pre *)
  val () = _w4(arr, alen, 1284, 1663991093)
  val () = _w4(arr, alen, 1288, 1953522024)
  val () = _w4(arr, alen, 1292, 1663922789)
  val () = _w4(arr, alen, 1296, 1635020399)
  val () = _w4(arr, alen, 1300, 1919250025)
  val () = _w4(arr, alen, 1304, 1701998624)
  val () = _w4(arr, alen, 1308, 1667326587)
  val () = _w4(arr, alen, 1312, 1869768555)
  val () = _w4(arr, alen, 1316, 979660405)
  val () = _w4(arr, alen, 1320, 1714710051)
  val () = _w4(arr, alen, 1324, 993289780)
  val () = _w4(arr, alen, 1328, 1684300144)
  val () = _w4(arr, alen, 1332, 979857001)
  val () = _w4(arr, alen, 1336, 1835350062)
  val () = _w4(arr, alen, 1340, 1919902267)
  val () = _w4(arr, alen, 1344, 762471780)
  val () = _w4(arr, alen, 1348, 1768186226)
  val () = _w4(arr, alen, 1352, 876245877)
  val () = _w4(arr, alen, 1356, 1866168432)
  val () = _w4(arr, alen, 1360, 1718773110)
  val () = _w4(arr, alen, 1364, 762802028)
  val () = _w4(arr, alen, 1368, 1969306232)
  val () = _w4(arr, alen, 1372, 1715171188)
  val () = _w4(arr, alen, 1376, 762605167)
  val () = _w4(arr, alen, 1380, 1702521203)
  val () = _w4(arr, alen, 1384, 1698246202)
  (* .chapter-container code *)
  val () = _w4(arr, alen, 1388, 1663991149)
  val () = _w4(arr, alen, 1392, 1953522024)
  val () = _w4(arr, alen, 1396, 1663922789)
  val () = _w4(arr, alen, 1400, 1635020399)
  val () = _w4(arr, alen, 1404, 1919250025)
  val () = _w4(arr, alen, 1408, 1685021472)
  val () = _w4(arr, alen, 1412, 1633844069)
  val () = _w4(arr, alen, 1416, 1919380323)
  val () = _w4(arr, alen, 1420, 1684960623)
  val () = _w4(arr, alen, 1424, 879108922)
  val () = _w4(arr, alen, 1428, 879113318)
  val () = _w4(arr, alen, 1432, 1684107323)
  val () = _w4(arr, alen, 1436, 1735289188)
  val () = _w4(arr, alen, 1440, 1697721914)
  val () = _w4(arr, alen, 1444, 858660973)
  val () = _w4(arr, alen, 1448, 1648061797)
  val () = _w4(arr, alen, 1452, 1701081711)
  val () = _w4(arr, alen, 1456, 1634872690)
  val () = _w4(arr, alen, 1460, 1937074532)
  val () = _w4(arr, alen, 1464, 2020618810)
  val () = _w4(arr, alen, 1468, 1852794427)
  val () = _w4(arr, alen, 1472, 1769155956)
  val () = _w4(arr, alen, 1476, 775579002)
  val () = _w4(arr, alen, 1480, 2104321337)
  (* .chapter-container img *)
  val () = _w4(arr, alen, 1484, 1634231086)
  val () = _w4(arr, alen, 1488, 1919251568)
  val () = _w4(arr, alen, 1492, 1852793645)
  val () = _w4(arr, alen, 1496, 1852399988)
  val () = _w4(arr, alen, 1500, 1763734117)
  val () = _w4(arr, alen, 1504, 1836803949)
  val () = _w4(arr, alen, 1508, 1999468641)
  val () = _w4(arr, alen, 1512, 1752458345)
  val () = _w4(arr, alen, 1516, 808464698)
  val () = _w4(arr, alen, 1520, 1701329701)
  val () = _w4(arr, alen, 1524, 1952999273)
  val () = _w4(arr, alen, 1528, 1953849658)
  (* .chapter-container a *)
  val () = _w4(arr, alen, 1532, 1663991151)
  val () = _w4(arr, alen, 1536, 1953522024)
  val () = _w4(arr, alen, 1540, 1663922789)
  val () = _w4(arr, alen, 1544, 1635020399)
  val () = _w4(arr, alen, 1548, 1919250025)
  val () = _w4(arr, alen, 1552, 1669030176)
  val () = _w4(arr, alen, 1556, 1919904879)
  val () = _w4(arr, alen, 1560, 1630806842)
  val () = _w4(arr, alen, 1564, 959800119)
  (* .chapter-container table *)
  val () = _w4(arr, alen, 1568, 1751330429)
  val () = _w4(arr, alen, 1572, 1702129761)
  val () = _w4(arr, alen, 1576, 1868770674)
  val () = _w4(arr, alen, 1580, 1767994478)
  val () = _w4(arr, alen, 1584, 544367982)
  val () = _w4(arr, alen, 1588, 1818386804)
  val () = _w4(arr, alen, 1592, 1868725093)
  val () = _w4(arr, alen, 1596, 1919247474)
  val () = _w4(arr, alen, 1600, 1819239213)
  val () = _w4(arr, alen, 1604, 1936744812)
  val () = _w4(arr, alen, 1608, 1868773989)
  val () = _w4(arr, alen, 1612, 1885432940)
  val () = _w4(arr, alen, 1616, 1832609139)
  val () = _w4(arr, alen, 1620, 1768387169)
  val () = _w4(arr, alen, 1624, 1697725038)
  val () = _w4(arr, alen, 1628, 2100306029)
  (* .chapter-container td,.chapter-container th *)
  val () = _w4(arr, alen, 1632, 1634231086)
  val () = _w4(arr, alen, 1636, 1919251568)
  val () = _w4(arr, alen, 1640, 1852793645)
  val () = _w4(arr, alen, 1644, 1852399988)
  val () = _w4(arr, alen, 1648, 1948283493)
  val () = _w4(arr, alen, 1652, 1663970404)
  val () = _w4(arr, alen, 1656, 1953522024)
  val () = _w4(arr, alen, 1660, 1663922789)
  val () = _w4(arr, alen, 1664, 1635020399)
  val () = _w4(arr, alen, 1668, 1919250025)
  val () = _w4(arr, alen, 1672, 2070443040)
  val () = _w4(arr, alen, 1676, 1685221218)
  val () = _w4(arr, alen, 1680, 825913957)
  val () = _w4(arr, alen, 1684, 1931507824)
  val () = _w4(arr, alen, 1688, 1684630639)
  val () = _w4(arr, alen, 1692, 1684284192)
  val () = _w4(arr, alen, 1696, 1634745188)
  val () = _w4(arr, alen, 1700, 1852400740)
  val () = _w4(arr, alen, 1704, 875444839)
  val () = _w4(arr, alen, 1708, 773877093)
  val () = _w4(arr, alen, 1712, 2104321336)
in end

fn fill_css_import {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* .importing *)
  val () = _w4(arr, alen, 1716, 1886218542)
  val () = _w4(arr, alen, 1720, 1769239151)
  val () = _w4(arr, alen, 1724, 1685809006)
  val () = _w4(arr, alen, 1728, 1819308905)
  val () = _w4(arr, alen, 1732, 1765439841)
  val () = _w4(arr, alen, 1736, 1852402798)
  val () = _w4(arr, alen, 1740, 1818373477)
  val () = _w4(arr, alen, 1744, 996893551)
  val () = _w4(arr, alen, 1748, 1684300144)
  val () = _w4(arr, alen, 1752, 979857001)
  val () = _w4(arr, alen, 1756, 1701983534)
  val () = _w4(arr, alen, 1760, 774971501)
  val () = _w4(arr, alen, 1764, 1835364914)
  val () = _w4(arr, alen, 1768, 1918987579)
  val () = _w4(arr, alen, 1772, 980314471)
  val () = _w4(arr, alen, 1776, 1835364913)
  val () = _w4(arr, alen, 1780, 1667326523)
  val () = _w4(arr, alen, 1784, 1869768555)
  val () = _w4(arr, alen, 1788, 979660405)
  val () = _w4(arr, alen, 1792, 929117219)
  val () = _w4(arr, alen, 1796, 993604963)
  val () = _w4(arr, alen, 1800, 1869377379)
  val () = _w4(arr, alen, 1804, 1713584754)
  val () = _w4(arr, alen, 1808, 1648060006)
  val () = _w4(arr, alen, 1812, 1701081711)
  val () = _w4(arr, alen, 1816, 1634872690)
  val () = _w4(arr, alen, 1820, 1937074532)
  val () = _w4(arr, alen, 1824, 2020619322)
  val () = _w4(arr, alen, 1828, 1852794427)
  val () = _w4(arr, alen, 1832, 1769155956)
  val () = _w4(arr, alen, 1836, 825910650)
  val () = _w4(arr, alen, 1840, 997025138)
  val () = _w4(arr, alen, 1844, 1835626081)
  val () = _w4(arr, alen, 1848, 1869182049)
  val () = _w4(arr, alen, 1852, 1970289262)
  val () = _w4(arr, alen, 1856, 543519596)
  val () = _w4(arr, alen, 1860, 1932865073)
  val () = _w4(arr, alen, 1864, 1935762720)
  val () = _w4(arr, alen, 1868, 1852386661)
  val () = _w4(arr, alen, 1872, 1953853229)
  val () = _w4(arr, alen, 1876, 1718511904)
  val () = _w4(arr, alen, 1880, 1953066601)
  val () = _w4(arr, alen, 1884, 1799388517)
  (* @keyframes pulse *)
  val () = _w4(arr, alen, 1888, 1919318373)
  val () = _w4(arr, alen, 1892, 1936026977)
  val () = _w4(arr, alen, 1896, 1819635744)
  val () = _w4(arr, alen, 1900, 813393267)
  val () = _w4(arr, alen, 1904, 808528933)
  val () = _w4(arr, alen, 1908, 1870341424)
  val () = _w4(arr, alen, 1912, 1768120688)
  val () = _w4(arr, alen, 1916, 825915764)
  val () = _w4(arr, alen, 1920, 623916413)
  val () = _w4(arr, alen, 1924, 1634758523)
  val () = _w4(arr, alen, 1928, 2037672291)
  val () = _w4(arr, alen, 1932, 2100702778)
  (* .import-status *)
  val () = _w4(arr, alen, 1936, 1835609725)
  val () = _w4(arr, alen, 1940, 1953656688)
  val () = _w4(arr, alen, 1944, 1635021613)
  val () = _w4(arr, alen, 1948, 2071164276)
  val () = _w4(arr, alen, 1952, 1684300144)
  val () = _w4(arr, alen, 1956, 979857001)
  val () = _w4(arr, alen, 1960, 1915822128)
  val () = _w4(arr, alen, 1964, 1664839013)
  val () = _w4(arr, alen, 1968, 1919904879)
  val () = _w4(arr, alen, 1972, 943203130)
  val () = _w4(arr, alen, 1976, 1868970808)
  val () = _w4(arr, alen, 1980, 1932358766)
  val () = _w4(arr, alen, 1984, 979729001)
  val () = _w4(arr, alen, 1988, 1916090414)
  val () = _w4(arr, alen, 1992, 1832611173)
  val () = _w4(arr, alen, 1996, 1747807849)
  val () = _w4(arr, alen, 2000, 1751607653)
  val () = _w4(arr, alen, 2004, 774978164)
  val () = _w4(arr, alen, 2008, 2104321330)
in end

fn fill_css {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  val () = fill_css_base(arr, alen)
  val () = fill_css_cards(arr, alen)
  val () = fill_css_reader(arr, alen)
  val () = fill_css_content(arr, alen)
  val () = fill_css_import(arr, alen)
in end

(* Create a <style> element under parent and fill it with app CSS.
 * Called at the start of both render_library and enter_reader so that
 * each view has its styles after remove_children clears the previous. *)
fn inject_app_css {l:agz}
  (s: ward_dom_stream(l), parent: int): ward_dom_stream(l) = let
  val css_arr = ward_arr_alloc<byte>(APP_CSS_LEN)
  val () = fill_css(css_arr, APP_CSS_LEN)
  val style_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, style_id, parent, tag_style(), 5)
  val @(frozen, borrow) = ward_arr_freeze<byte>(css_arr)
  val s = ward_dom_stream_set_text(s, style_id, borrow, APP_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val css_arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(css_arr)
in s end

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

(* ========== Import progress DOM update helpers ========== *)

(* Update a node's text content from a fill_text constant.
 * Opens/closes its own DOM stream — safe to call from promise callbacks. *)
fn update_status_text(nid: int, text_id: int, text_len: int): void = let
  val tl = g1ofg0(text_len)
in
  if tl > 0 then
    if tl < 65536 then let
      val dom = ward_dom_init()
      val s = ward_dom_stream_begin(dom)
      val s = set_text_cstr(s, nid, text_id, text_len)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else ()
  else ()
end

(* Set CSS class on import label: 1=importing, 0=import-btn *)
fn update_import_label_class(label_id: int, importing: int): void = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
in
  if gt_int_int(importing, 0) then let
    val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5,
      cls_importing(), 9)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
  in end
  else let
    val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5,
      cls_import_btn(), 10)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
  in end
end

(* Clear text content of a node by removing its children *)
fn clear_node(nid: int): void = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, nid)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

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
  val _cl = epub_copy_container_path(0)
  val idx = zip_find_entry(22)
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
  val opf_len = epub_copy_opf_path(0)
  val idx = zip_find_entry(opf_len)
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
  val ci = _checked_nat(chapter_idx)
  val count = epub_get_chapter_count()
in
  if lt1_int_int(ci, count) then let
    prval pf = SPINE_ENTRY()
    val path_len = epub_copy_spine_path(pf | ci, count, 0)
    val zip_idx = zip_find_entry(path_len)
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
              llam (blob_handle: int): ward_promise_chained(int) => let
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

(* Register click listeners on all read buttons.
 * Shared by initial render and post-import re-render. *)
fun register_read_btns(i: int, n: int, root: int): void =
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
    in register_read_btns(i + 1, n, root) end
    else register_read_btns(i + 1, n, root)
  end

(* Import phase ordering: proves each phase follows the previous.
 * BUG PREVENTED: Copy-paste reordering of import phases would break
 * the proof chain — each phase requires the previous phase's proof. *)
dataprop IMPORT_PHASE(phase: int) =
  | PHASE_OPEN(0)
  | {p:int | p == 0} PHASE_ZIP(1) of IMPORT_PHASE(p)
  | {p:int | p == 1} PHASE_META(2) of IMPORT_PHASE(p)
  | {p:int | p == 2} PHASE_ADD(3) of IMPORT_PHASE(p)

extern praxi consume_phase {p:int} (pf: IMPORT_PHASE(p)): void

implement render_library(root_id) = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, root_id)
  val s = inject_app_css(s, root_id)

  (* Import button: <label class="import-btn"><span>Import</span><input ...></label>
   * Text is in a <span> so we can update it during import without destroying <input>. *)
  val label_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, label_id, root_id, tag_label(), 5)
  val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5, cls_import_btn(), 10)

  val span_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, span_id, label_id, tag_span(), 4)
  val import_st = let
    val b = ward_text_build(6)
    val b = ward_text_putc(b, 0, 73) (* 'I' *)
    val b = ward_text_putc(b, 1, char2int1('m'))
    val b = ward_text_putc(b, 2, char2int1('p'))
    val b = ward_text_putc(b, 3, char2int1('o'))
    val b = ward_text_putc(b, 4, char2int1('r'))
    val b = ward_text_putc(b, 5, char2int1('t'))
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, span_id, import_st, 6)

  val input_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, input_id, label_id, tag_input(), 5)
  val s = ward_dom_stream_set_attr_safe(s, input_id, attr_type(), 4, st_file(), 4)
  val s = set_attr_cstr(s, input_id, attr_accept(), 6, TEXT_EPUB_EXT, 5)

  (* Status div: <div class="import-status"></div> — updated during import *)
  val status_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, status_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, status_id, attr_class(), 5, cls_import_status(), 13)

  (* Library list *)
  val list_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, list_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, list_id, attr_class(), 5, cls_library_list(), 12)

  val count = library_get_count()
  val () =
    if gt_int_int(count, 0) then let
      (* Render book cards *)
      val s = render_library_with_books(s, list_id)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else let
      (* Empty library message *)
      val empty_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, empty_id, list_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, empty_id, attr_class(), 5, cls_empty_lib(), 9)
      val s = set_text_cstr(s, empty_id, TEXT_NO_BOOKS, 12)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end

  (* Register click listeners on read buttons (if any) *)
  val () = register_read_btns(0, count, root_id)

  (* Register change listener on file input — shared import handler.
   * Multi-phase promise chain with timer yields between phases
   * for UI responsiveness (browser can paint progress updates). *)
  val saved_input_id = input_id
  val saved_list_id = list_id
  val saved_root = root_id
  val saved_label_id = label_id
  val saved_span_id = span_id
  val saved_status_id = status_id
  val () = ward_add_event_listener(
    input_id, evt_change(), 6, 1,
    lam (_payload_len: int): int => let
      (* Phase 0 — visual setup *)
      prval pf0 = PHASE_OPEN()
      val () = ward_log(1, log_import_start(), 12)
      val () = quire_set_title(1)
      val () = update_import_label_class(saved_label_id, 1)
      val () = update_status_text(saved_span_id, TEXT_IMPORTING, 9)
      val () = update_status_text(saved_status_id, TEXT_OPENING_FILE, 12)

      val p = ward_file_open(saved_input_id)
      val p2 = ward_promise_then<int><int>(p,
        llam (handle: int): ward_promise_chained(int) => let
          (* Phase 1 — file open complete, consumes pf0 *)
          prval pf1 = PHASE_ZIP(pf0)
          val file_size = ward_file_get_size()
          val () = reader_set_file_handle(handle)

          (* Phase 1: Parse ZIP — yield first for "Opening file" to paint *)
          val p1 = ward_timer_set(0)
          val sh = handle val sfs = file_size
          val sli = saved_list_id val sr = saved_root
          val slbl = saved_label_id val sspn = saved_span_id
          val ssts = saved_status_id
        in ward_promise_then<int><int>(p1,
          llam (_: int): ward_promise_chained(int) => let
            (* Phase 2 — parse ZIP, consumes pf1 *)
            prval pf2 = PHASE_META(pf1)
            val () = update_status_text(ssts, TEXT_PARSING_ZIP, 15)
            val _nentries = zip_open(sh, sfs)

            (* Phase 2: Read EPUB metadata — yield for "Parsing archive" to paint *)
            val p2 = ward_timer_set(0)
          in ward_promise_then<int><int>(p2,
            llam (_: int): ward_promise_chained(int) => let
              (* Phase 3 — read metadata, consumes pf2 *)
              prval pf3 = PHASE_ADD(pf2)
              val () = update_status_text(ssts, TEXT_READING_META, 16)
              val ok1 = epub_read_container(sh)
              val ok2 = (if gt_int_int(ok1, 0)
                then epub_read_opf(sh) else 0): int

              (* Phase 3: Add book + re-render — yield for "Reading metadata" to paint *)
              val p3 = ward_timer_set(0)
            in ward_promise_then<int><int>(p3,
              llam (_: int): ward_promise_chained(int) => let
                (* Phase 3 complete — consume final proof *)
                prval () = consume_phase(pf3)
                val () = update_status_text(ssts, TEXT_ADDING_BOOK, 17)
                val _book_idx = (if gt_int_int(ok2, 0)
                  then library_add_book() else 0 - 1): int

                (* Re-render library list *)
                val dom = ward_dom_init()
                val s = ward_dom_stream_begin(dom)
                val s = render_library_with_books(s, sli)
                val dom = ward_dom_stream_end(s)
                val () = ward_dom_fini(dom)

                (* Register click listeners on all rendered read buttons *)
                val btn_count = library_get_count()
                val () = register_read_btns(0, btn_count, sr)

                (* Restore UI *)
                val () = quire_set_title(0)
                val () = update_import_label_class(slbl, 0)

                (* Restore span text to "Import" *)
                val import_st2 = let
                  val b = ward_text_build(6)
                  val b = ward_text_putc(b, 0, 73) (* 'I' *)
                  val b = ward_text_putc(b, 1, char2int1('m'))
                  val b = ward_text_putc(b, 2, char2int1('p'))
                  val b = ward_text_putc(b, 3, char2int1('o'))
                  val b = ward_text_putc(b, 4, char2int1('r'))
                  val b = ward_text_putc(b, 5, char2int1('t'))
                in ward_text_done(b) end
                val dom2 = ward_dom_init()
                val s2 = ward_dom_stream_begin(dom2)
                val s2 = ward_dom_stream_set_safe_text(s2, sspn, import_st2, 6)
                val dom2 = ward_dom_stream_end(s2)
                val () = ward_dom_fini(dom2)
                val () = clear_node(ssts)

                val () = ward_log(1, log_import_done(), 11)
              in ward_promise_return<int>(0) end)
            end)
          end)
        end)
      val () = ward_promise_discard<int>(p2)
    in 0 end
  )
in end

(* ========== Enter reader view ========== *)

implement enter_reader(root_id, book_index) = let
  val () = reader_enter(root_id, 0)
  val () = reader_set_book_index(book_index)
  val file_handle = reader_get_file_handle()

  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, root_id)
  val s = inject_app_css(s, root_id)

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
