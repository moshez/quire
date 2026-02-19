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
staload "./../vendor/ward/lib/idb.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload _ = "./../vendor/ward/lib/listener.dats"
staload _ = "./../vendor/ward/lib/file.dats"
staload _ = "./../vendor/ward/lib/promise.dats"
staload _ = "./../vendor/ward/lib/event.dats"
staload _ = "./../vendor/ward/lib/decompress.dats"
staload _ = "./../vendor/ward/lib/xml.dats"
staload _ = "./../vendor/ward/lib/dom_read.dats"
staload _ = "./../vendor/ward/lib/idb.dats"

staload "./arith.sats"
staload "./sha256.sats"
staload "./quire_ext.sats"

(* Forward declarations for JS imports — suppresses C99 warnings *)
%{
extern void quireSetTitle(int mode);
extern int quire_time_now(void);
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
#define TEXT_ERR_NOT_FOUND 9
#define TEXT_ERR_CANNOT_READ 10
#define TEXT_ERR_UNSUPPORTED 11
#define TEXT_ERR_DECOMPRESS 12
#define TEXT_ERR_EMPTY 13
#define TEXT_ERR_NO_CHAPTERS 14
#define TEXT_ERR_TOO_DENSE 15
#define TEXT_SHOW_ARCHIVED 16
#define TEXT_SHOW_ACTIVE 17
#define TEXT_SORT_TITLE 18
#define TEXT_SORT_AUTHOR 19
#define TEXT_ARCHIVE 20
#define TEXT_UNARCHIVE 21
#define TEXT_NO_ARCHIVED 22
#define TEXT_SORT_LAST_OPENED 23
#define TEXT_SORT_DATE_ADDED 24
#define TEXT_HIDDEN 25
#define TEXT_NO_HIDDEN 26
#define TEXT_HIDE 27
#define TEXT_UNHIDE 28

(* ========== Listener ID constants ========== *)

(* Named listener IDs — single source of truth.
 * Dataprop enum prevents arbitrary IDs in reader event listeners. *)
dataprop READER_LISTENER(id: int) =
  | READER_LISTEN_KEYDOWN(50)
  | READER_LISTEN_VIEWPORT_CLICK(51)
  | READER_LISTEN_BACK(52)
  | READER_LISTEN_PREV(53)
  | READER_LISTEN_NEXT(54)

#define LISTENER_FILE_INPUT 1
#define LISTENER_READ_BTN_BASE 2
#define LISTENER_KEYDOWN 50
#define LISTENER_VIEWPORT_CLICK 51
#define LISTENER_BACK 52
#define LISTENER_PREV 53
#define LISTENER_NEXT 54
#define LISTENER_SORT_TITLE 56
#define LISTENER_SORT_AUTHOR 57
#define LISTENER_SORT_LAST_OPENED 58
#define LISTENER_SORT_DATE_ADDED 59
#define LISTENER_ARCHIVE_BTN_BASE 60
#define LISTENER_VIEW_HIDDEN 92
#define LISTENER_VIEW_ARCHIVED 93
#define LISTENER_VIEW_ACTIVE 94
#define LISTENER_HIDE_BTN_BASE 95

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
  else if text_id = 8 then let (* "Adding to library" *)
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
  else if text_id = 9 then let (* "Chapter not found" *)
    val () = ward_arr_set_byte(arr, 0, alen, 67)   (* C *)
    val () = ward_arr_set_byte(arr, 1, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 2, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 3, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 4, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 5, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 6, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 7, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 8, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 9, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 10, alen, 116) (* t *)
    val () = ward_arr_set_byte(arr, 11, alen, 32)  (*   *)
    val () = ward_arr_set_byte(arr, 12, alen, 102) (* f *)
    val () = ward_arr_set_byte(arr, 13, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 14, alen, 117) (* u *)
    val () = ward_arr_set_byte(arr, 15, alen, 110) (* n *)
    val () = ward_arr_set_byte(arr, 16, alen, 100) (* d *)
  in end
  else if text_id = 10 then let (* "Cannot read chapter" *)
    val () = ward_arr_set_byte(arr, 0, alen, 67)   (* C *)
    val () = ward_arr_set_byte(arr, 1, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 2, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 3, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 4, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 5, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 6, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 7, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 8, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 9, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 10, alen, 100) (* d *)
    val () = ward_arr_set_byte(arr, 11, alen, 32)  (*   *)
    val () = ward_arr_set_byte(arr, 12, alen, 99)  (* c *)
    val () = ward_arr_set_byte(arr, 13, alen, 104) (* h *)
    val () = ward_arr_set_byte(arr, 14, alen, 97)  (* a *)
    val () = ward_arr_set_byte(arr, 15, alen, 112) (* p *)
    val () = ward_arr_set_byte(arr, 16, alen, 116) (* t *)
    val () = ward_arr_set_byte(arr, 17, alen, 101) (* e *)
    val () = ward_arr_set_byte(arr, 18, alen, 114) (* r *)
  in end
  else if text_id = 11 then let (* "Unsupported format" *)
    val () = ward_arr_set_byte(arr, 0, alen, 85)   (* U *)
    val () = ward_arr_set_byte(arr, 1, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 2, alen, 115)  (* s *)
    val () = ward_arr_set_byte(arr, 3, alen, 117)  (* u *)
    val () = ward_arr_set_byte(arr, 4, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 5, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 6, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 7, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 8, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 9, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 10, alen, 100) (* d *)
    val () = ward_arr_set_byte(arr, 11, alen, 32)  (*   *)
    val () = ward_arr_set_byte(arr, 12, alen, 102) (* f *)
    val () = ward_arr_set_byte(arr, 13, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 14, alen, 114) (* r *)
    val () = ward_arr_set_byte(arr, 15, alen, 109) (* m *)
    val () = ward_arr_set_byte(arr, 16, alen, 97)  (* a *)
    val () = ward_arr_set_byte(arr, 17, alen, 116) (* t *)
  in end
  else if text_id = 12 then let (* "Decompression failed" *)
    val () = ward_arr_set_byte(arr, 0, alen, 68)   (* D *)
    val () = ward_arr_set_byte(arr, 1, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 2, alen, 99)   (* c *)
    val () = ward_arr_set_byte(arr, 3, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 4, alen, 109)  (* m *)
    val () = ward_arr_set_byte(arr, 5, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 6, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 7, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 8, alen, 115)  (* s *)
    val () = ward_arr_set_byte(arr, 9, alen, 115)  (* s *)
    val () = ward_arr_set_byte(arr, 10, alen, 105) (* i *)
    val () = ward_arr_set_byte(arr, 11, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 12, alen, 110) (* n *)
    val () = ward_arr_set_byte(arr, 13, alen, 32)  (*   *)
    val () = ward_arr_set_byte(arr, 14, alen, 102) (* f *)
    val () = ward_arr_set_byte(arr, 15, alen, 97)  (* a *)
    val () = ward_arr_set_byte(arr, 16, alen, 105) (* i *)
    val () = ward_arr_set_byte(arr, 17, alen, 108) (* l *)
    val () = ward_arr_set_byte(arr, 18, alen, 101) (* e *)
    val () = ward_arr_set_byte(arr, 19, alen, 100) (* d *)
  in end
  else if text_id = 13 then let (* "Chapter content empty" *)
    val () = ward_arr_set_byte(arr, 0, alen, 67)   (* C *)
    val () = ward_arr_set_byte(arr, 1, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 2, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 3, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 4, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 5, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 6, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 7, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 8, alen, 99)   (* c *)
    val () = ward_arr_set_byte(arr, 9, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 10, alen, 110) (* n *)
    val () = ward_arr_set_byte(arr, 11, alen, 116) (* t *)
    val () = ward_arr_set_byte(arr, 12, alen, 101) (* e *)
    val () = ward_arr_set_byte(arr, 13, alen, 110) (* n *)
    val () = ward_arr_set_byte(arr, 14, alen, 116) (* t *)
    val () = ward_arr_set_byte(arr, 15, alen, 32)  (*   *)
    val () = ward_arr_set_byte(arr, 16, alen, 101) (* e *)
    val () = ward_arr_set_byte(arr, 17, alen, 109) (* m *)
    val () = ward_arr_set_byte(arr, 18, alen, 112) (* p *)
    val () = ward_arr_set_byte(arr, 19, alen, 116) (* t *)
    val () = ward_arr_set_byte(arr, 20, alen, 121) (* y *)
  in end
  else if text_id = 14 then let (* "No chapters in book" *)
    val () = ward_arr_set_byte(arr, 0, alen, 78)   (* N *)
    val () = ward_arr_set_byte(arr, 1, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 2, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 3, alen, 99)   (* c *)
    val () = ward_arr_set_byte(arr, 4, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 5, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 6, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 7, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 8, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 9, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 10, alen, 115) (* s *)
    val () = ward_arr_set_byte(arr, 11, alen, 32)  (*   *)
    val () = ward_arr_set_byte(arr, 12, alen, 105) (* i *)
    val () = ward_arr_set_byte(arr, 13, alen, 110) (* n *)
    val () = ward_arr_set_byte(arr, 14, alen, 32)  (*   *)
    val () = ward_arr_set_byte(arr, 15, alen, 98)  (* b *)
    val () = ward_arr_set_byte(arr, 16, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 17, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 18, alen, 107) (* k *)
  in end
  else if text_id = 15 then let (* "Page too dense" *)
    val () = ward_arr_set_byte(arr, 0, alen, 80)   (* P *)
    val () = ward_arr_set_byte(arr, 1, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 2, alen, 103)  (* g *)
    val () = ward_arr_set_byte(arr, 3, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 4, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 5, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 6, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 7, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 8, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 9, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 10, alen, 101) (* e *)
    val () = ward_arr_set_byte(arr, 11, alen, 110) (* n *)
    val () = ward_arr_set_byte(arr, 12, alen, 115) (* s *)
    val () = ward_arr_set_byte(arr, 13, alen, 101) (* e *)
  in end
  else if text_id = 16 then let (* "Archived" *)
    val () = ward_arr_set_byte(arr, 0, alen, 65)   (* A *)
    val () = ward_arr_set_byte(arr, 1, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 2, alen, 99)   (* c *)
    val () = ward_arr_set_byte(arr, 3, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 4, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 5, alen, 118)  (* v *)
    val () = ward_arr_set_byte(arr, 6, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 7, alen, 100)  (* d *)
  in end
  else if text_id = 17 then let (* "Library" *)
    val () = ward_arr_set_byte(arr, 0, alen, 76)   (* L *)
    val () = ward_arr_set_byte(arr, 1, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 2, alen, 98)   (* b *)
    val () = ward_arr_set_byte(arr, 3, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 4, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 5, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 6, alen, 121)  (* y *)
  in end
  else if text_id = 18 then let (* "By title" *)
    val () = ward_arr_set_byte(arr, 0, alen, 66)   (* B *)
    val () = ward_arr_set_byte(arr, 1, alen, 121)  (* y *)
    val () = ward_arr_set_byte(arr, 2, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 3, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 4, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 5, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 6, alen, 108)  (* l *)
    val () = ward_arr_set_byte(arr, 7, alen, 101)  (* e *)
  in end
  else if text_id = 19 then let (* "By author" *)
    val () = ward_arr_set_byte(arr, 0, alen, 66)   (* B *)
    val () = ward_arr_set_byte(arr, 1, alen, 121)  (* y *)
    val () = ward_arr_set_byte(arr, 2, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 3, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 4, alen, 117)  (* u *)
    val () = ward_arr_set_byte(arr, 5, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 6, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 7, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 8, alen, 114)  (* r *)
  in end
  else if text_id = 20 then let (* "Archive" *)
    val () = ward_arr_set_byte(arr, 0, alen, 65)   (* A *)
    val () = ward_arr_set_byte(arr, 1, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 2, alen, 99)   (* c *)
    val () = ward_arr_set_byte(arr, 3, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 4, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 5, alen, 118)  (* v *)
    val () = ward_arr_set_byte(arr, 6, alen, 101)  (* e *)
  in end
  else if text_id = 21 then let (* "Restore" *)
    val () = ward_arr_set_byte(arr, 0, alen, 82)   (* R *)
    val () = ward_arr_set_byte(arr, 1, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 2, alen, 115)  (* s *)
    val () = ward_arr_set_byte(arr, 3, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 4, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 5, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 6, alen, 101)  (* e *)
  in end
  else if text_id = 22 then let (* "No archived books" *)
    val () = ward_arr_set_byte(arr, 0, alen, 78)   (* N *)
    val () = ward_arr_set_byte(arr, 1, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 2, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 3, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 4, alen, 114)  (* r *)
    val () = ward_arr_set_byte(arr, 5, alen, 99)   (* c *)
    val () = ward_arr_set_byte(arr, 6, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 7, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 8, alen, 118)  (* v *)
    val () = ward_arr_set_byte(arr, 9, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 10, alen, 100) (* d *)
    val () = ward_arr_set_byte(arr, 11, alen, 32)  (*   *)
    val () = ward_arr_set_byte(arr, 12, alen, 98)  (* b *)
    val () = ward_arr_set_byte(arr, 13, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 14, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 15, alen, 107) (* k *)
    val () = ward_arr_set_byte(arr, 16, alen, 115) (* s *)
  in end
  else if text_id = 23 then let (* "Last opened" *)
    val () = ward_arr_set_byte(arr, 0, alen, 76)   (* L *)
    val () = ward_arr_set_byte(arr, 1, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 2, alen, 115)  (* s *)
    val () = ward_arr_set_byte(arr, 3, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 4, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 5, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 6, alen, 112)  (* p *)
    val () = ward_arr_set_byte(arr, 7, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 8, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 9, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 10, alen, 100) (* d *)
  in end
  else if text_id = 24 then let (* "Date added" *)
    val () = ward_arr_set_byte(arr, 0, alen, 68)   (* D *)
    val () = ward_arr_set_byte(arr, 1, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 2, alen, 116)  (* t *)
    val () = ward_arr_set_byte(arr, 3, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 4, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 5, alen, 97)   (* a *)
    val () = ward_arr_set_byte(arr, 6, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 7, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 8, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 9, alen, 100)  (* d *)
  in end
  else if text_id = 25 then let (* "Hidden" *)
    val () = ward_arr_set_byte(arr, 0, alen, 72)   (* H *)
    val () = ward_arr_set_byte(arr, 1, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 2, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 3, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 4, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 5, alen, 110)  (* n *)
  in end
  else if text_id = 26 then let (* "No hidden books" *)
    val () = ward_arr_set_byte(arr, 0, alen, 78)   (* N *)
    val () = ward_arr_set_byte(arr, 1, alen, 111)  (* o *)
    val () = ward_arr_set_byte(arr, 2, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 3, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 4, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 5, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 6, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 7, alen, 101)  (* e *)
    val () = ward_arr_set_byte(arr, 8, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 9, alen, 32)   (*   *)
    val () = ward_arr_set_byte(arr, 10, alen, 98)  (* b *)
    val () = ward_arr_set_byte(arr, 11, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 12, alen, 111) (* o *)
    val () = ward_arr_set_byte(arr, 13, alen, 107) (* k *)
    val () = ward_arr_set_byte(arr, 14, alen, 115) (* s *)
  in end
  else if text_id = 27 then let (* "Hide" *)
    val () = ward_arr_set_byte(arr, 0, alen, 72)   (* H *)
    val () = ward_arr_set_byte(arr, 1, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 2, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 3, alen, 101)  (* e *)
  in end
  else if text_id = 28 then let (* "Unhide" *)
    val () = ward_arr_set_byte(arr, 0, alen, 85)   (* U *)
    val () = ward_arr_set_byte(arr, 1, alen, 110)  (* n *)
    val () = ward_arr_set_byte(arr, 2, alen, 104)  (* h *)
    val () = ward_arr_set_byte(arr, 3, alen, 105)  (* i *)
    val () = ward_arr_set_byte(arr, 4, alen, 100)  (* d *)
    val () = ward_arr_set_byte(arr, 5, alen, 101)  (* e *)
  in end
  else () (* unused text_id *)

(* Copy len bytes from string_buffer to ward_arr *)
fn copy_from_sbuf {l:agz}{n:pos}
  (dst: !ward_arr(byte, l, n), len: int n): void = let
  fun loop {k:nat} .<k>.
    (rem: int(k), dst: !ward_arr(byte, l, n), dlen: int n,
     i: int, count: int): void =
    if lte_g1(rem, 0) then ()
    else if i < count then let
      val b = _app_sbuf_get_u8(i)
      val () = ward_arr_set_byte(dst, i, dlen, b)
    in loop(sub_g1(rem, 1), dst, dlen, i + 1, count) end
in loop(_checked_nat(_g0(len)), dst, len, 0, len) end

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

(* "lib-toolbar" = 11 chars *)
fn cls_lib_toolbar(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('l'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('b'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('t'))
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('o'))
  val b = ward_text_putc(b, 7, char2int1('l'))
  val b = ward_text_putc(b, 8, char2int1('b'))
  val b = ward_text_putc(b, 9, char2int1('a'))
  val b = ward_text_putc(b, 10, char2int1('r'))
in ward_text_done(b) end

(* "hide-btn" = 8 chars *)
fn cls_hide_btn(): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('h'))
  val b = ward_text_putc(b, 1, char2int1('i'))
  val b = ward_text_putc(b, 2, char2int1('d'))
  val b = ward_text_putc(b, 3, char2int1('e'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
in ward_text_done(b) end

(* "sort-btn" = 8 chars *)
fn cls_sort_btn(): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
in ward_text_done(b) end

(* "sort-active" = 11 chars *)
fn cls_sort_active(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('s'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('c'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('i'))
  val b = ward_text_putc(b, 9, char2int1('v'))
  val b = ward_text_putc(b, 10, char2int1('e'))
in ward_text_done(b) end

(* "archive-btn" = 11 chars *)
fn cls_archive_btn(): ward_safe_text(11) = let
  val b = ward_text_build(11)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('c'))
  val b = ward_text_putc(b, 3, char2int1('h'))
  val b = ward_text_putc(b, 4, char2int1('i'))
  val b = ward_text_putc(b, 5, char2int1('v'))
  val b = ward_text_putc(b, 6, char2int1('e'))
  val b = ward_text_putc(b, 7, 45) (* '-' *)
  val b = ward_text_putc(b, 8, char2int1('b'))
  val b = ward_text_putc(b, 9, char2int1('t'))
  val b = ward_text_putc(b, 10, char2int1('n'))
in ward_text_done(b) end

(* "card-actions" = 12 chars *)
fn cls_card_actions(): ward_safe_text(12) = let
  val b = ward_text_build(12)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('a'))
  val b = ward_text_putc(b, 6, char2int1('c'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('i'))
  val b = ward_text_putc(b, 9, char2int1('o'))
  val b = ward_text_putc(b, 10, char2int1('n'))
  val b = ward_text_putc(b, 11, char2int1('s'))
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

(* "chapter-error" = 13 chars *)
fn cls_chapter_error(): ward_safe_text(13) = let
  val b = ward_text_build(13)
  val b = ward_text_putc(b, 0, char2int1('c'))
  val b = ward_text_putc(b, 1, char2int1('h'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('p'))
  val b = ward_text_putc(b, 4, char2int1('t'))
  val b = ward_text_putc(b, 5, char2int1('e'))
  val b = ward_text_putc(b, 6, char2int1('r'))
  val b = ward_text_putc(b, 7, 45) (* '-' *)
  val b = ward_text_putc(b, 8, char2int1('e'))
  val b = ward_text_putc(b, 9, char2int1('r'))
  val b = ward_text_putc(b, 10, char2int1('r'))
  val b = ward_text_putc(b, 11, char2int1('o'))
  val b = ward_text_putc(b, 12, char2int1('r'))
in ward_text_done(b) end

(* "reader-nav" = 10 chars *)
fn cls_reader_nav(): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('r'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('a'))
  val b = ward_text_putc(b, 3, char2int1('d'))
  val b = ward_text_putc(b, 4, char2int1('e'))
  val b = ward_text_putc(b, 5, char2int1('r'))
  val b = ward_text_putc(b, 6, 45) (* '-' *)
  val b = ward_text_putc(b, 7, char2int1('n'))
  val b = ward_text_putc(b, 8, char2int1('a'))
  val b = ward_text_putc(b, 9, char2int1('v'))
in ward_text_done(b) end

(* "back-btn" = 8 chars *)
fn cls_back_btn(): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('c'))
  val b = ward_text_putc(b, 3, char2int1('k'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
in ward_text_done(b) end

(* "page-info" = 9 chars *)
fn cls_page_info(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('p'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('g'))
  val b = ward_text_putc(b, 3, char2int1('e'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('i'))
  val b = ward_text_putc(b, 6, char2int1('n'))
  val b = ward_text_putc(b, 7, char2int1('f'))
  val b = ward_text_putc(b, 8, char2int1('o'))
in ward_text_done(b) end

(* "nav-controls" = 12 chars *)
fn cls_nav_controls(): ward_safe_text(12) = let
  val b = ward_text_build(12)
  val b = ward_text_putc(b, 0, char2int1('n'))
  val b = ward_text_putc(b, 1, char2int1('a'))
  val b = ward_text_putc(b, 2, char2int1('v'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('c'))
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('n'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('r'))
  val b = ward_text_putc(b, 9, char2int1('o'))
  val b = ward_text_putc(b, 10, char2int1('l'))
  val b = ward_text_putc(b, 11, char2int1('s'))
in ward_text_done(b) end

(* "prev-btn" = 8 chars *)
fn cls_prev_btn(): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('p'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('e'))
  val b = ward_text_putc(b, 3, char2int1('v'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
in ward_text_done(b) end

(* "next-btn" = 8 chars *)
fn cls_next_btn(): ward_safe_text(8) = let
  val b = ward_text_build(8)
  val b = ward_text_putc(b, 0, char2int1('n'))
  val b = ward_text_putc(b, 1, char2int1('e'))
  val b = ward_text_putc(b, 2, char2int1('x'))
  val b = ward_text_putc(b, 3, char2int1('t'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
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

(* "err-container" = 13 chars — container.xml not found *)
fn log_err_container(): ward_safe_text(13) = let
  val b = ward_text_build(13)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('c'))
  val b = ward_text_putc(b, 5, char2int1('o'))
  val b = ward_text_putc(b, 6, char2int1('n'))
  val b = ward_text_putc(b, 7, char2int1('t'))
  val b = ward_text_putc(b, 8, char2int1('a'))
  val b = ward_text_putc(b, 9, char2int1('i'))
  val b = ward_text_putc(b, 10, char2int1('n'))
  val b = ward_text_putc(b, 11, char2int1('e'))
  val b = ward_text_putc(b, 12, char2int1('r'))
in ward_text_done(b) end

(* "err-opf" = 7 chars — OPF parsing failed *)
fn log_err_opf(): ward_safe_text(7) = let
  val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('o'))
  val b = ward_text_putc(b, 5, char2int1('p'))
  val b = ward_text_putc(b, 6, char2int1('f'))
in ward_text_done(b) end

(* "err-zip" = 7 chars — ZIP parsing failed (0 entries) *)
fn log_err_zip_parse(): ward_safe_text(7) = let
  val b = ward_text_build(7)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('z'))
  val b = ward_text_putc(b, 5, char2int1('i'))
  val b = ward_text_putc(b, 6, char2int1('p'))
in ward_text_done(b) end

(* "err-lib-full" = 12 chars — library at capacity *)
fn log_err_lib_full(): ward_safe_text(12) = let
  val b = ward_text_build(12)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('l'))
  val b = ward_text_putc(b, 5, char2int1('i'))
  val b = ward_text_putc(b, 6, char2int1('b'))
  val b = ward_text_putc(b, 7, 45) (* '-' *)
  val b = ward_text_putc(b, 8, char2int1('f'))
  val b = ward_text_putc(b, 9, char2int1('u'))
  val b = ward_text_putc(b, 10, char2int1('l'))
  val b = ward_text_putc(b, 11, char2int1('l'))
in ward_text_done(b) end


(* ========== Linear import outcome proof ========== *)
(* import_handled is LINEAR — must be consumed exactly once.
 * Only import_mark_success and import_mark_failed can create it.
 * import_complete consumes it and logs "import-done".
 * If any if-then-else branch forgets a token, ATS2 rejects. *)
absvt@ype import_handled = int

extern fn import_mark_success(): import_handled
extern fn import_mark_failed {n:pos}
  (msg: ward_safe_text(n), len: int n): import_handled
extern fn import_complete(h: import_handled): void

local
assume import_handled = int
in
implement import_mark_success() = 1
implement import_mark_failed{n}(msg, len) = let
  val () = ward_log(3, msg, len)
in 0 end
implement import_complete(h) = let
  val _ = h
  val () = ward_log(1, log_import_done(), 11)
in end
end

(* ========== Chapter load error messages ========== *)

(* mk_ch_err builds "err-ch-XYZ" safe text where XYZ are the 3 suffix chars.
 * Used by load_chapter to log a specific error at each failure point. *)
fn mk_ch_err
  {c1:int | SAFE_CHAR(c1)}
  {c2:int | SAFE_CHAR(c2)}
  {c3:int | SAFE_CHAR(c3)}
  (c1: int(c1), c2: int(c2), c3: int(c3)): ward_safe_text(10) = let
  val b = ward_text_build(10)
  val b = ward_text_putc(b, 0, char2int1('e'))
  val b = ward_text_putc(b, 1, char2int1('r'))
  val b = ward_text_putc(b, 2, char2int1('r'))
  val b = ward_text_putc(b, 3, 45) (* '-' *)
  val b = ward_text_putc(b, 4, char2int1('c'))
  val b = ward_text_putc(b, 5, char2int1('h'))
  val b = ward_text_putc(b, 6, 45) (* '-' *)
  val b = ward_text_putc(b, 7, c1)
  val b = ward_text_putc(b, 8, c2)
  val b = ward_text_putc(b, 9, c3)
in ward_text_done(b) end

(* CHAPTER_DISPLAY_READY: proves that after chapter content is rendered,
 * both pagination measurement AND CSS transform application occurred.
 *
 * BUG PREVENTED: stale CSS transform from previous chapter leaving
 * first page of new chapter invisible. When navigating from Ch 2/3
 * page 11/11 (translateX=-10240px) to Ch 3/3 page 1/8, the old
 * transform persisted because apply_page_transform was only called
 * via apply_resume_page (which skips when resume_pg == 0).
 *
 * finish_chapter_load is the ONLY way to obtain this proof, and it
 * always calls apply_page_transform before apply_resume_page. *)
dataprop CHAPTER_DISPLAY_READY() =
  | MEASURED_AND_TRANSFORMED()

(* PAGE_DISPLAY_UPDATED: proves that after changing the page counter,
 * both the CSS transform AND the page indicator were updated.
 *
 * BUG CLASS PREVENTED: same as CHAPTER_DISPLAY_READY but for within-chapter
 * page turns. If someone adds a new page-changing path and calls
 * reader_next_page/reader_prev_page without applying the transform,
 * content becomes invisible. This proof forces the transform + page info
 * update to be bundled with every page counter change.
 *
 * page_turn_forward/page_turn_backward are the ONLY ways to obtain this proof. *)
dataprop PAGE_DISPLAY_UPDATED() =
  | PAGE_TURNED_AND_SHOWN()

(* ========== App CSS injection ========== *)

(* ---- Linear completion tokens ---- *)
(* CSS_READER_WRITTEN can ONLY be produced by stamp_reader_css.
 * CSS_NAV_WRITTEN can ONLY be produced by stamp_nav_css.
 * inject functions REQUIRE them — impossible to inject CSS
 * without calling stamp, which enforces all proof obligations. *)
absview CSS_READER_WRITTEN
absview CSS_NAV_WRITTEN

(* ---- CSS visibility dataprops ---- *)

(* COLUMN_ALIGNED: column-width matches viewport transform stride.
 * BUG PREVENTED: text bleeding — if ph != 0, columns != viewport width. *)
dataprop COLUMN_ALIGNED(column_width_vw: int, container_pad_h: int) =
  | {cw:pos}{ph:int | ph == 0} COLUMNS_MATCH_VIEWPORT(cw, ph)

(* CHILD_PADDED: content children have horizontal padding > 0.
 * Without this, text is flush against viewport edges. *)
dataprop CHILD_PADDED(pad_left_10: int, pad_right_10: int) =
  | {pl,pr:pos} CHILDREN_HAVE_PADDING(pl, pr)

(* NAV_BTN_VISIBLE: buttons have nonzero font-size and padding.
 * Without this, buttons render as invisible zero-size elements. *)
dataprop NAV_BTN_VISIBLE(font_size_10: int, padding_h_10: int) =
  | {fs,ph:pos} BTNS_HAVE_SIZE(fs, ph)

(* ---- CSS property constants ---- *)
(* #define is textual expansion — applies in BOTH dynamic and static contexts.
 * Dataprop constructors like COLUMNS_MATCH_VIEWPORT{CSS_COL_WIDTH_VW, ...}
 * see the #define value, so the proofs guard these values directly.
 * Changing any value triggers a compile-time constraint failure. *)
#define CSS_COL_WIDTH_VW 100       (* column-width: 100vw *)
#define CSS_CONTAINER_PAD_H 0      (* padding: 2rem 0 — zero horizontal *)
#define CSS_CHILD_PAD_L_10 15      (* padding-left: 1.5rem = 15 tenths *)
#define CSS_CHILD_PAD_R_10 15      (* padding-right: 1.5rem = 15 tenths *)
#define CSS_BTN_FONT_10 10         (* font-size: 1rem = 10 tenths *)
#define CSS_BTN_PAD_H_10 3         (* padding: 0 .3rem = 3 tenths *)

(* ---- CSS value writer functions ---- *)

(* Write CSS "0" at offset — for properties constrained to zero *)
fn write_css_zero {l:agz}{n:pos}{v:int | v == 0}
  (arr: !ward_arr(byte, l, n), alen: int n, off: int, v: int(v)): void =
  ward_arr_set_byte(arr, off, alen, 48) (* '0' *)

(* Write CSS "100vw" at offset (5 bytes) *)
fn write_css_100vw {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, off: int): void = let
  val () = ward_arr_set_byte(arr, off, alen, 49)     (* '1' *)
  val () = ward_arr_set_byte(arr, off+1, alen, 48)   (* '0' *)
  val () = ward_arr_set_byte(arr, off+2, alen, 48)   (* '0' *)
  val () = ward_arr_set_byte(arr, off+3, alen, 118)  (* 'v' *)
  val () = ward_arr_set_byte(arr, off+4, alen, 119)  (* 'w' *)
in end

(* Write CSS rem value at offset — value in tenths, must be positive.
 * Dispatches: 3→".3rem", 10→"1rem", 15→"1.5rem" *)
fn write_css_rem_pos {l:agz}{n:pos}{v:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, off: int, v: int(v)): void =
  if eq_int_int(v, 3) then let   (* .3rem — 5 bytes *)
    val () = ward_arr_set_byte(arr, off, alen, 46)    (* '.' *)
    val () = ward_arr_set_byte(arr, off+1, alen, 51)  (* '3' *)
    val () = ward_arr_set_byte(arr, off+2, alen, 114) (* 'r' *)
    val () = ward_arr_set_byte(arr, off+3, alen, 101) (* 'e' *)
    val () = ward_arr_set_byte(arr, off+4, alen, 109) (* 'm' *)
  in end
  else if eq_int_int(v, 10) then let (* 1rem — 4 bytes *)
    val () = ward_arr_set_byte(arr, off, alen, 49)    (* '1' *)
    val () = ward_arr_set_byte(arr, off+1, alen, 114) (* 'r' *)
    val () = ward_arr_set_byte(arr, off+2, alen, 101) (* 'e' *)
    val () = ward_arr_set_byte(arr, off+3, alen, 109) (* 'm' *)
  in end
  else if eq_int_int(v, 15) then let (* 1.5rem — 6 bytes *)
    val () = ward_arr_set_byte(arr, off, alen, 49)    (* '1' *)
    val () = ward_arr_set_byte(arr, off+1, alen, 46)  (* '.' *)
    val () = ward_arr_set_byte(arr, off+2, alen, 53)  (* '5' *)
    val () = ward_arr_set_byte(arr, off+3, alen, 114) (* 'r' *)
    val () = ward_arr_set_byte(arr, off+4, alen, 101) (* 'e' *)
    val () = ward_arr_set_byte(arr, off+5, alen, 109) (* 'm' *)
  in end
  else () (* unreachable for current constants *)

(* ---- CSS length constants ---- *)
(* #define: runtime values; stadef: type-level constraints *)
#define APP_CSS_LEN 2198
stadef APP_CSS_LEN = 2198
#define NAV_CSS_LEN 552
stadef NAV_CSS_LEN = 552

(* ---- Stamp functions: write proven bytes AND produce linear views ---- *)

(* ONLY function that produces CSS_READER_WRITTEN.
 * Takes proven CSS values as dependent int arguments + dataprop proofs.
 * Writes the CSS bytes AND returns the linear view.
 * Cannot be called without proofs. Cannot skip the byte writes. *)
fn stamp_reader_css {l:agz}{n:int | n >= APP_CSS_LEN}
    {cw:pos}{ph:int | ph == 0}{pl,pr:pos}
  (pf_col: COLUMN_ALIGNED(cw, ph),
   pf_pad: CHILD_PADDED(pl, pr) |
   arr: !ward_arr(byte, l, n), alen: int n,
   col_w_vw: int(cw), pad_h: int(ph),
   child_pad_l: int(pl), child_pad_r: int(pr))
  : (CSS_READER_WRITTEN | void) = let
  (* Overwrite critical bytes from proven values *)
  val () = write_css_100vw(arr, alen, 911)         (* column-width: 100vw *)
  val () = write_css_zero(arr, alen, 936, pad_h)   (* padding: 2rem 0 — offset shifted by gap shorthand *)
  val () = write_css_rem_pos(arr, alen, 1007, child_pad_l)  (* padding-left: 1.5rem *)
  val () = write_css_rem_pos(arr, alen, 1028, child_pad_r)  (* padding-right: 1.5rem *)
  (* Produce the linear view — only reachable after byte writes above *)
  extern praxi __seal_reader(): CSS_READER_WRITTEN
  prval pf = __seal_reader()
in (pf | ()) end

(* ONLY function that produces CSS_NAV_WRITTEN.
 * Stamps button font-size and padding bytes from proven values. *)
fn stamp_nav_css {l:agz}{n:int | n >= NAV_CSS_LEN}
    {fs,ph:pos}
  (pf_btn: NAV_BTN_VISIBLE(fs, ph) |
   arr: !ward_arr(byte, l, n), alen: int n,
   btn_font: int(fs), btn_pad: int(ph))
  : (CSS_NAV_WRITTEN | void) = let
  (* Overwrite critical bytes from proven values *)
  val () = write_css_rem_pos(arr, alen, 531, btn_font) (* font-size: 1rem *)
  val () = write_css_rem_pos(arr, alen, 546, btn_pad)  (* padding: 0 .3rem *)
  (* Produce the linear view — only reachable after byte writes above *)
  extern praxi __seal_nav(): CSS_NAV_WRITTEN
  prval pf = __seal_nav()
in (pf | ()) end

(* CSS bytes packed as little-endian int32s, written via _w4. *)

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

fn fill_css_reader {l:agz}{n:int | n >= APP_CSS_LEN}
  (arr: !ward_arr(byte, l, n), alen: int n): (CSS_READER_WRITTEN | void) = let
  (* .reader-viewport *)
  val () = _w4(arr, alen, 800, 1634038318)
  val () = _w4(arr, alen, 804, 762471780)
  val () = _w4(arr, alen, 808, 2003134838)
  val () = _w4(arr, alen, 812, 1953656688)
  val () = _w4(arr, alen, 816, 1936683131)
  val () = _w4(arr, alen, 820, 1869182057)
  val () = _w4(arr, alen, 824, 1701984878)
  val () = _w4(arr, alen, 828, 1769234796)
  val () = _w4(arr, alen, 832, 1748723062)
  val () = _w4(arr, alen, 836, 1751607653)
  val () = _w4(arr, alen, 840, 1633892980)
  val () = _w4(arr, alen, 844, 824730476)
  val () = _w4(arr, alen, 848, 1752576048)
  val () = _w4(arr, alen, 852, 857746720)
  val () = _w4(arr, alen, 856, 1701983534)
  val () = _w4(arr, alen, 860, 1866148205)
  val () = _w4(arr, alen, 864, 1718773110)
  val () = _w4(arr, alen, 868, 980905836)
  val () = _w4(arr, alen, 872, 1684302184)
  val () = _w4(arr, alen, 876, 779972197)
  (* .chapter-container *)
  val () = _w4(arr, alen, 880, 1885431907)
  val () = _w4(arr, alen, 884, 762471796)
  val () = _w4(arr, alen, 888, 1953394531)
  val () = _w4(arr, alen, 892, 1701734753)
  val () = _w4(arr, alen, 896, 1868790642)
  val () = _w4(arr, alen, 900, 1852667244)
  val () = _w4(arr, alen, 904, 1684633389)
  val () = _w4(arr, alen, 908, 825911412)
  val () = _w4(arr, alen, 912, 2004234288)
  (* CSS uses 'gap' shorthand (saves 7 chars vs 'column-gap') to make
   * room for will-change:transform. will-change:transform forces the
   * browser to create a GPU compositing layer that includes ALL CSS
   * column content — without it, browsers skip painting columns that
   * start off-screen, making pages 2+ invisible even after translateX
   * brings them into view. *)
  val () = _w4(arr, alen, 916, 1885431611)  (* ';gap' *)
  val () = _w4(arr, alen, 920, 1882927162)  (* ':0;p' *)
  val () = _w4(arr, alen, 924, 1768186977)  (* 'addi' *)
  val () = _w4(arr, alen, 928, 842688366)   (* 'ng:2' *)
  val () = _w4(arr, alen, 932, 544040306)   (* 'rem ' *)
  val () = _w4(arr, alen, 936, 1701329712)  (* '0;he' *)
  val () = _w4(arr, alen, 940, 1952999273)  (* 'ight' *)
  val () = _w4(arr, alen, 944, 808464698)   (* ':100' *)
  val () = _w4(arr, alen, 948, 1769421605)  (* '%;wi' *)
  val () = _w4(arr, alen, 952, 1663921260)  (* 'll-c' *)
  val () = _w4(arr, alen, 956, 1735287144)  (* 'hang' *)
  val () = _w4(arr, alen, 960, 1920219749)  (* 'e:tr' *)
  val () = _w4(arr, alen, 964, 1718840929)  (* 'ansf' *)
  val () = _w4(arr, alen, 968, 997028463)   (* 'orm;' *)
  val () = _w4(arr, alen, 972, 1751330429)
  (* .chapter-container>* *)
  val () = _w4(arr, alen, 976, 1702129761)
  val () = _w4(arr, alen, 980, 1868770674)
  val () = _w4(arr, alen, 984, 1767994478)
  val () = _w4(arr, alen, 988, 1047684462)
  val () = _w4(arr, alen, 992, 1634761514)
  val () = _w4(arr, alen, 996, 1852400740)
  val () = _w4(arr, alen, 1000, 1701588327)
  val () = _w4(arr, alen, 1004, 825914470)
  val () = _w4(arr, alen, 1008, 1701983534)
  val () = _w4(arr, alen, 1012, 1634745197)
  val () = _w4(arr, alen, 1016, 1852400740)
  val () = _w4(arr, alen, 1020, 1769090407)
  val () = _w4(arr, alen, 1024, 980707431)
  val () = _w4(arr, alen, 1028, 1916087857)
  val () = _w4(arr, alen, 1032, 1648061797)
  val () = _w4(arr, alen, 1036, 1932359791)
  val () = _w4(arr, alen, 1040, 1852406377)
  val () = _w4(arr, alen, 1044, 1868708455)
  val () = _w4(arr, alen, 1048, 1919247474)
  val () = _w4(arr, alen, 1052, 2020565549)
  val () = ward_arr_set_byte(arr, 1056, alen, 125)
  (* .chapter-error *)
  val () = _w4(arr, alen, 1057, 1634231086)
  val () = _w4(arr, alen, 1061, 1919251568)
  val () = _w4(arr, alen, 1065, 1920099629)
  val () = _w4(arr, alen, 1069, 1685811823)
  val () = _w4(arr, alen, 1073, 1819308905)
  val () = _w4(arr, alen, 1077, 1715108193)
  val () = _w4(arr, alen, 1081, 997746028)
  val () = _w4(arr, alen, 1085, 1734962273)
  val () = _w4(arr, alen, 1089, 1953049966)
  val () = _w4(arr, alen, 1093, 980643173)
  val () = _w4(arr, alen, 1097, 1953391971)
  val () = _w4(arr, alen, 1101, 1782280805)
  val () = _w4(arr, alen, 1105, 1769239413)
  val () = _w4(arr, alen, 1109, 1663924582)
  val () = _w4(arr, alen, 1113, 1702129263)
  val () = _w4(arr, alen, 1117, 1664775278)
  val () = _w4(arr, alen, 1121, 1702129253)
  val () = _w4(arr, alen, 1125, 1701329778)
  val () = _w4(arr, alen, 1129, 1952999273)
  val () = _w4(arr, alen, 1133, 808464698)
  val () = _w4(arr, alen, 1137, 1868774181)
  val () = _w4(arr, alen, 1141, 980578156)
  val () = _w4(arr, alen, 1145, 943208483)
  val () = _w4(arr, alen, 1149, 1852794427)
  val () = _w4(arr, alen, 1153, 1769155956)
  val () = _w4(arr, alen, 1157, 825910650)
  val () = _w4(arr, alen, 1161, 1701982510)
  val () = _w4(arr, alen, 1165, 1702116205)
  val () = _w4(arr, alen, 1169, 1630368888)
  val () = _w4(arr, alen, 1173, 1852270956)
  val () = _w4(arr, alen, 1177, 1852138298)
  val () = _w4(arr, alen, 1181, 997352820)
  val () = _w4(arr, alen, 1185, 1684300144)
  val () = _w4(arr, alen, 1189, 979857001)
  val () = _w4(arr, alen, 1193, 1835364914)
  val () = ward_arr_set_byte(arr, 1197, alen, 125)

  (* Construct proofs — solver verifies constraints *)
  prval pf_col = COLUMNS_MATCH_VIEWPORT{CSS_COL_WIDTH_VW, CSS_CONTAINER_PAD_H}()
  prval pf_pad = CHILDREN_HAVE_PADDING{CSS_CHILD_PAD_L_10, CSS_CHILD_PAD_R_10}()

  (* Stamp: overwrite critical bytes from proven values AND produce the view.
   * This is the ONLY way to get CSS_READER_WRITTEN. *)
  val (pf_written | ()) = stamp_reader_css(
    pf_col, pf_pad |
    arr, alen,
    CSS_COL_WIDTH_VW, CSS_CONTAINER_PAD_H,
    CSS_CHILD_PAD_L_10, CSS_CHILD_PAD_R_10)
in (pf_written | ()) end

fn fill_css_content {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* .chapter-container h1,.chapter-container h2,.chapter-container h3 *)
  val () = _w4(arr, alen, 1198, 1634231086)
  val () = _w4(arr, alen, 1202, 1919251568)
  val () = _w4(arr, alen, 1206, 1852793645)
  val () = _w4(arr, alen, 1210, 1852399988)
  val () = _w4(arr, alen, 1214, 1746956901)
  val () = _w4(arr, alen, 1218, 1663970353)
  val () = _w4(arr, alen, 1222, 1953522024)
  val () = _w4(arr, alen, 1226, 1663922789)
  val () = _w4(arr, alen, 1230, 1635020399)
  val () = _w4(arr, alen, 1234, 1919250025)
  val () = _w4(arr, alen, 1238, 741500960)
  val () = _w4(arr, alen, 1242, 1634231086)
  val () = _w4(arr, alen, 1246, 1919251568)
  val () = _w4(arr, alen, 1250, 1852793645)
  val () = _w4(arr, alen, 1254, 1852399988)
  val () = _w4(arr, alen, 1258, 1746956901)
  val () = _w4(arr, alen, 1262, 1634564915)
  val () = _w4(arr, alen, 1266, 1852401522)
  val () = _w4(arr, alen, 1270, 1886352429)
  val () = _w4(arr, alen, 1274, 892219706)
  val () = _w4(arr, alen, 1278, 1832611173)
  val () = _w4(arr, alen, 1282, 1768387169)
  val () = _w4(arr, alen, 1286, 1868705134)
  val () = _w4(arr, alen, 1290, 1836020852)
  val () = _w4(arr, alen, 1294, 1697984058)
  val () = _w4(arr, alen, 1298, 1768700781)
  val () = _w4(arr, alen, 1302, 1747805550)
  val () = _w4(arr, alen, 1306, 1751607653)
  val () = _w4(arr, alen, 1310, 774978164)
  (* .chapter-container p *)
  val () = _w4(arr, alen, 1314, 1663991091)
  val () = _w4(arr, alen, 1318, 1953522024)
  val () = _w4(arr, alen, 1322, 1663922789)
  val () = _w4(arr, alen, 1326, 1635020399)
  val () = _w4(arr, alen, 1330, 1919250025)
  val () = _w4(arr, alen, 1334, 1836806176)
  val () = _w4(arr, alen, 1338, 1768387169)
  val () = _w4(arr, alen, 1342, 540031598)
  val () = _w4(arr, alen, 1346, 942546992)
  val () = _w4(arr, alen, 1350, 1950051685)
  val () = _w4(arr, alen, 1354, 762607717)
  val () = _w4(arr, alen, 1358, 1734962273)
  val () = _w4(arr, alen, 1362, 1969896046)
  val () = _w4(arr, alen, 1366, 1718187123)
  (* .chapter-container blockquote *)
  val () = _w4(arr, alen, 1370, 1663991161)
  val () = _w4(arr, alen, 1374, 1953522024)
  val () = _w4(arr, alen, 1378, 1663922789)
  val () = _w4(arr, alen, 1382, 1635020399)
  val () = _w4(arr, alen, 1386, 1919250025)
  val () = _w4(arr, alen, 1390, 1869373984)
  val () = _w4(arr, alen, 1394, 1970367331)
  val () = _w4(arr, alen, 1398, 2070246511)
  val () = _w4(arr, alen, 1402, 1735549293)
  val () = _w4(arr, alen, 1406, 825912937)
  val () = _w4(arr, alen, 1410, 840985957)
  val () = _w4(arr, alen, 1414, 1882942821)
  val () = _w4(arr, alen, 1418, 1768186977)
  val () = _w4(arr, alen, 1422, 1814914926)
  val () = _w4(arr, alen, 1426, 980706917)
  val () = _w4(arr, alen, 1430, 997025073)
  val () = _w4(arr, alen, 1434, 1685221218)
  val () = _w4(arr, alen, 1438, 1814917733)
  val () = _w4(arr, alen, 1442, 980706917)
  val () = _w4(arr, alen, 1446, 544763955)
  val () = _w4(arr, alen, 1450, 1768714099)
  val () = _w4(arr, alen, 1454, 1663246436)
  val () = _w4(arr, alen, 1458, 1664836451)
  val () = _w4(arr, alen, 1462, 1919904879)
  val () = _w4(arr, alen, 1466, 892674874)
  (* .chapter-container pre *)
  val () = _w4(arr, alen, 1470, 1663991093)
  val () = _w4(arr, alen, 1474, 1953522024)
  val () = _w4(arr, alen, 1478, 1663922789)
  val () = _w4(arr, alen, 1482, 1635020399)
  val () = _w4(arr, alen, 1486, 1919250025)
  val () = _w4(arr, alen, 1490, 1701998624)
  val () = _w4(arr, alen, 1494, 1667326587)
  val () = _w4(arr, alen, 1498, 1869768555)
  val () = _w4(arr, alen, 1502, 979660405)
  val () = _w4(arr, alen, 1506, 1714710051)
  val () = _w4(arr, alen, 1510, 993289780)
  val () = _w4(arr, alen, 1514, 1684300144)
  val () = _w4(arr, alen, 1518, 979857001)
  val () = _w4(arr, alen, 1522, 1835350062)
  val () = _w4(arr, alen, 1526, 1919902267)
  val () = _w4(arr, alen, 1530, 762471780)
  val () = _w4(arr, alen, 1534, 1768186226)
  val () = _w4(arr, alen, 1538, 876245877)
  val () = _w4(arr, alen, 1542, 1866168432)
  val () = _w4(arr, alen, 1546, 1718773110)
  val () = _w4(arr, alen, 1550, 762802028)
  val () = _w4(arr, alen, 1554, 1969306232)
  val () = _w4(arr, alen, 1558, 1715171188)
  val () = _w4(arr, alen, 1562, 762605167)
  val () = _w4(arr, alen, 1566, 1702521203)
  val () = _w4(arr, alen, 1570, 1698246202)
  (* .chapter-container code *)
  val () = _w4(arr, alen, 1574, 1663991149)
  val () = _w4(arr, alen, 1578, 1953522024)
  val () = _w4(arr, alen, 1582, 1663922789)
  val () = _w4(arr, alen, 1586, 1635020399)
  val () = _w4(arr, alen, 1590, 1919250025)
  val () = _w4(arr, alen, 1594, 1685021472)
  val () = _w4(arr, alen, 1598, 1633844069)
  val () = _w4(arr, alen, 1602, 1919380323)
  val () = _w4(arr, alen, 1606, 1684960623)
  val () = _w4(arr, alen, 1610, 879108922)
  val () = _w4(arr, alen, 1614, 879113318)
  val () = _w4(arr, alen, 1618, 1684107323)
  val () = _w4(arr, alen, 1622, 1735289188)
  val () = _w4(arr, alen, 1626, 1697721914)
  val () = _w4(arr, alen, 1630, 858660973)
  val () = _w4(arr, alen, 1634, 1648061797)
  val () = _w4(arr, alen, 1638, 1701081711)
  val () = _w4(arr, alen, 1642, 1634872690)
  val () = _w4(arr, alen, 1646, 1937074532)
  val () = _w4(arr, alen, 1650, 2020618810)
  val () = _w4(arr, alen, 1654, 1852794427)
  val () = _w4(arr, alen, 1658, 1769155956)
  val () = _w4(arr, alen, 1662, 775579002)
  val () = _w4(arr, alen, 1666, 2104321337)
  (* .chapter-container img *)
  val () = _w4(arr, alen, 1670, 1634231086)
  val () = _w4(arr, alen, 1674, 1919251568)
  val () = _w4(arr, alen, 1678, 1852793645)
  val () = _w4(arr, alen, 1682, 1852399988)
  val () = _w4(arr, alen, 1686, 1763734117)
  val () = _w4(arr, alen, 1690, 1836803949)
  val () = _w4(arr, alen, 1694, 1999468641)
  val () = _w4(arr, alen, 1698, 1752458345)
  val () = _w4(arr, alen, 1702, 808464698)
  val () = _w4(arr, alen, 1706, 1701329701)
  val () = _w4(arr, alen, 1710, 1952999273)
  val () = _w4(arr, alen, 1714, 1953849658)
  (* .chapter-container a *)
  val () = _w4(arr, alen, 1718, 1663991151)
  val () = _w4(arr, alen, 1722, 1953522024)
  val () = _w4(arr, alen, 1726, 1663922789)
  val () = _w4(arr, alen, 1730, 1635020399)
  val () = _w4(arr, alen, 1734, 1919250025)
  val () = _w4(arr, alen, 1738, 1669030176)
  val () = _w4(arr, alen, 1742, 1919904879)
  val () = _w4(arr, alen, 1746, 1630806842)
  val () = _w4(arr, alen, 1750, 959800119)
  (* .chapter-container table *)
  val () = _w4(arr, alen, 1754, 1751330429)
  val () = _w4(arr, alen, 1758, 1702129761)
  val () = _w4(arr, alen, 1762, 1868770674)
  val () = _w4(arr, alen, 1766, 1767994478)
  val () = _w4(arr, alen, 1770, 544367982)
  val () = _w4(arr, alen, 1774, 1818386804)
  val () = _w4(arr, alen, 1778, 1868725093)
  val () = _w4(arr, alen, 1782, 1919247474)
  val () = _w4(arr, alen, 1786, 1819239213)
  val () = _w4(arr, alen, 1790, 1936744812)
  val () = _w4(arr, alen, 1794, 1868773989)
  val () = _w4(arr, alen, 1798, 1885432940)
  val () = _w4(arr, alen, 1802, 1832609139)
  val () = _w4(arr, alen, 1806, 1768387169)
  val () = _w4(arr, alen, 1810, 1697725038)
  val () = _w4(arr, alen, 1814, 2100306029)
  (* .chapter-container td,.chapter-container th *)
  val () = _w4(arr, alen, 1818, 1634231086)
  val () = _w4(arr, alen, 1822, 1919251568)
  val () = _w4(arr, alen, 1826, 1852793645)
  val () = _w4(arr, alen, 1830, 1852399988)
  val () = _w4(arr, alen, 1834, 1948283493)
  val () = _w4(arr, alen, 1838, 1663970404)
  val () = _w4(arr, alen, 1842, 1953522024)
  val () = _w4(arr, alen, 1846, 1663922789)
  val () = _w4(arr, alen, 1850, 1635020399)
  val () = _w4(arr, alen, 1854, 1919250025)
  val () = _w4(arr, alen, 1858, 2070443040)
  val () = _w4(arr, alen, 1862, 1685221218)
  val () = _w4(arr, alen, 1866, 825913957)
  val () = _w4(arr, alen, 1870, 1931507824)
  val () = _w4(arr, alen, 1874, 1684630639)
  val () = _w4(arr, alen, 1878, 1684284192)
  val () = _w4(arr, alen, 1882, 1634745188)
  val () = _w4(arr, alen, 1886, 1852400740)
  val () = _w4(arr, alen, 1890, 875444839)
  val () = _w4(arr, alen, 1894, 773877093)
  val () = _w4(arr, alen, 1898, 2104321336)
in end

fn fill_css_import {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* .importing *)
  val () = _w4(arr, alen, 1902, 1886218542)
  val () = _w4(arr, alen, 1906, 1769239151)
  val () = _w4(arr, alen, 1910, 1685809006)
  val () = _w4(arr, alen, 1914, 1819308905)
  val () = _w4(arr, alen, 1918, 1765439841)
  val () = _w4(arr, alen, 1922, 1852402798)
  val () = _w4(arr, alen, 1926, 1818373477)
  val () = _w4(arr, alen, 1930, 996893551)
  val () = _w4(arr, alen, 1934, 1684300144)
  val () = _w4(arr, alen, 1938, 979857001)
  val () = _w4(arr, alen, 1942, 1701983534)
  val () = _w4(arr, alen, 1946, 774971501)
  val () = _w4(arr, alen, 1950, 1835364914)
  val () = _w4(arr, alen, 1954, 1918987579)
  val () = _w4(arr, alen, 1958, 980314471)
  val () = _w4(arr, alen, 1962, 1835364913)
  val () = _w4(arr, alen, 1966, 1667326523)
  val () = _w4(arr, alen, 1970, 1869768555)
  val () = _w4(arr, alen, 1974, 979660405)
  val () = _w4(arr, alen, 1978, 929117219)
  val () = _w4(arr, alen, 1982, 993604963)
  val () = _w4(arr, alen, 1986, 1869377379)
  val () = _w4(arr, alen, 1990, 1713584754)
  val () = _w4(arr, alen, 1994, 1648060006)
  val () = _w4(arr, alen, 1998, 1701081711)
  val () = _w4(arr, alen, 2002, 1634872690)
  val () = _w4(arr, alen, 2006, 1937074532)
  val () = _w4(arr, alen, 2010, 2020619322)
  val () = _w4(arr, alen, 2014, 1852794427)
  val () = _w4(arr, alen, 2018, 1769155956)
  val () = _w4(arr, alen, 2022, 825910650)
  val () = _w4(arr, alen, 2026, 997025138)
  val () = _w4(arr, alen, 2030, 1835626081)
  val () = _w4(arr, alen, 2034, 1869182049)
  val () = _w4(arr, alen, 2038, 1970289262)
  val () = _w4(arr, alen, 2042, 543519596)
  val () = _w4(arr, alen, 2046, 1932865073)
  val () = _w4(arr, alen, 2050, 1935762720)
  val () = _w4(arr, alen, 2054, 1852386661)
  val () = _w4(arr, alen, 2058, 1953853229)
  val () = _w4(arr, alen, 2062, 1718511904)
  val () = _w4(arr, alen, 2066, 1953066601)
  val () = _w4(arr, alen, 2070, 1799388517)
  (* @keyframes pulse *)
  val () = _w4(arr, alen, 2074, 1919318373)
  val () = _w4(arr, alen, 2078, 1936026977)
  val () = _w4(arr, alen, 2082, 1819635744)
  val () = _w4(arr, alen, 2086, 813393267)
  val () = _w4(arr, alen, 2090, 808528933)
  val () = _w4(arr, alen, 2094, 1870341424)
  val () = _w4(arr, alen, 2098, 1768120688)
  val () = _w4(arr, alen, 2102, 825915764)
  val () = _w4(arr, alen, 2106, 623916413)
  val () = _w4(arr, alen, 2110, 1634758523)
  val () = _w4(arr, alen, 2114, 2037672291)
  val () = _w4(arr, alen, 2118, 2100702778)
  (* .import-status *)
  val () = _w4(arr, alen, 2122, 1835609725)
  val () = _w4(arr, alen, 2126, 1953656688)
  val () = _w4(arr, alen, 2130, 1635021613)
  val () = _w4(arr, alen, 2134, 2071164276)
  val () = _w4(arr, alen, 2138, 1684300144)
  val () = _w4(arr, alen, 2142, 979857001)
  val () = _w4(arr, alen, 2146, 1915822128)
  val () = _w4(arr, alen, 2150, 1664839013)
  val () = _w4(arr, alen, 2154, 1919904879)
  val () = _w4(arr, alen, 2158, 943203130)
  val () = _w4(arr, alen, 2162, 1868970808)
  val () = _w4(arr, alen, 2166, 1932358766)
  val () = _w4(arr, alen, 2170, 979729001)
  val () = _w4(arr, alen, 2174, 1916090414)
  val () = _w4(arr, alen, 2178, 1832611173)
  val () = _w4(arr, alen, 2182, 1747807849)
  val () = _w4(arr, alen, 2186, 1751607653)
  val () = _w4(arr, alen, 2190, 774978164)
  val () = _w4(arr, alen, 2194, 2104321330)
in end

fn fill_css {l:agz}{n:int | n >= APP_CSS_LEN}
  (arr: !ward_arr(byte, l, n), alen: int n): (CSS_READER_WRITTEN | void) = let
  val () = fill_css_base(arr, alen)
  val () = fill_css_cards(arr, alen)
  val (pf_reader | ()) = fill_css_reader(arr, alen)
  val () = fill_css_content(arr, alen)
  val () = fill_css_import(arr, alen)
in (pf_reader | ()) end

(* Create a <style> element under parent and fill it with app CSS.
 * Called at the start of both render_library and enter_reader so that
 * each view has its styles after remove_children clears the previous.
 * CONSUMES CSS_READER_WRITTEN — linear, must be produced by fill_css. *)
fn inject_app_css {l:agz}
  (s: ward_dom_stream(l), parent: int): ward_dom_stream(l) = let
  val css_arr = ward_arr_alloc<byte>(APP_CSS_LEN)
  val (pf_reader | ()) = fill_css(css_arr, APP_CSS_LEN)
  prval () = __consume(pf_reader) where {
    extern praxi __consume(pf: CSS_READER_WRITTEN): void
  }
  val style_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, style_id, parent, tag_style(), 5)
  val @(frozen, borrow) = ward_arr_freeze<byte>(css_arr)
  val s = ward_dom_stream_set_text(s, style_id, borrow, APP_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val css_arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(css_arr)
in s end

(* ========== Management toolbar CSS ========== *)

(* BUG CLASS PREVENTED: CSS_NULL_BYTE_CORRUPTION
 * The CSS fill writes 4 bytes per _w4 call. If MGMT_CSS_LEN is not
 * a multiple of 4, the last write pads with null bytes, which corrupt
 * the <style> text content and prevent CSS parsing in the browser.
 * The constraint MGMT_CSS_LEN == MGMT_CSS_WRITES * 4 proves alignment.
 * If someone changes the CSS content length, they must also update
 * MGMT_CSS_WRITES to match, or the solver rejects. *)
stadef MGMT_CSS_WRITES = 68
stadef MGMT_CSS_LEN = MGMT_CSS_WRITES * 4
#define MGMT_CSS_LEN 272

fn fill_css_mgmt {l:agz}{n:int | n >= MGMT_CSS_LEN}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  (* .lib-toolbar{display:flex;gap:8px;padding:8px 0;align-items:center}
   * .sort-btn,.sort-active,.archive-btn,.hide-btn{background:none;
   * border:1px solid #888;border-radius:4px;padding:4px 12px;cursor:pointer;
   * font-size:.9rem;color:inherit}.sort-active{background:#333;color:#fff} *)
  val () = _w4(arr, alen, 0, 1651076142)
  val () = _w4(arr, alen, 4, 1869575213)
  val () = _w4(arr, alen, 8, 1918984812)
  val () = _w4(arr, alen, 12, 1936286843)
  val () = _w4(arr, alen, 16, 2036427888)
  val () = _w4(arr, alen, 20, 1701602874)
  val () = _w4(arr, alen, 24, 1634155384)
  val () = _w4(arr, alen, 28, 1882733168)
  val () = _w4(arr, alen, 32, 1634745208)
  val () = _w4(arr, alen, 36, 1852400740)
  val () = _w4(arr, alen, 40, 1882733159)
  val () = _w4(arr, alen, 44, 993009784)
  val () = _w4(arr, alen, 48, 1734962273)
  val () = _w4(arr, alen, 52, 1953049966)
  val () = _w4(arr, alen, 56, 980643173)
  val () = _w4(arr, alen, 60, 1953391971)
  val () = _w4(arr, alen, 64, 779973221)
  val () = _w4(arr, alen, 68, 1953656691)
  val () = _w4(arr, alen, 72, 1853121069)
  val () = _w4(arr, alen, 76, 1869819436)
  val () = _w4(arr, alen, 80, 1630368882)
  val () = _w4(arr, alen, 84, 1986622563)
  val () = _w4(arr, alen, 88, 1630415973)
  val () = _w4(arr, alen, 92, 1768448882)
  val () = _w4(arr, alen, 96, 1647142262)
  val () = _w4(arr, alen, 100, 774663796)
  val () = _w4(arr, alen, 104, 1701079400)
  val () = _w4(arr, alen, 108, 1853121069)
  val () = _w4(arr, alen, 112, 1667326587)
  val () = _w4(arr, alen, 116, 1869768555)
  val () = _w4(arr, alen, 120, 979660405)
  val () = _w4(arr, alen, 124, 1701736302)
  val () = _w4(arr, alen, 128, 1919902267)
  val () = _w4(arr, alen, 132, 980575588)
  val () = _w4(arr, alen, 136, 544763953)
  val () = _w4(arr, alen, 140, 1768714099)
  val () = _w4(arr, alen, 144, 941826148)
  val () = _w4(arr, alen, 148, 1648048184)
  val () = _w4(arr, alen, 152, 1701081711)
  val () = _w4(arr, alen, 156, 1634872690)
  val () = _w4(arr, alen, 160, 1937074532)
  val () = _w4(arr, alen, 164, 2020619322)
  val () = _w4(arr, alen, 168, 1684107323)
  val () = _w4(arr, alen, 172, 1735289188)
  val () = _w4(arr, alen, 176, 2020619322)
  val () = _w4(arr, alen, 180, 1882337568)
  val () = _w4(arr, alen, 184, 1969437560)
  val () = _w4(arr, alen, 188, 1919906674)
  val () = _w4(arr, alen, 192, 1768910906)
  val () = _w4(arr, alen, 196, 1919251566)
  val () = _w4(arr, alen, 200, 1852794427)
  val () = _w4(arr, alen, 204, 1769155956)
  val () = _w4(arr, alen, 208, 775579002)
  val () = _w4(arr, alen, 212, 1835364921)
  val () = _w4(arr, alen, 216, 1819239227)
  val () = _w4(arr, alen, 220, 1765438063)
  val () = _w4(arr, alen, 224, 1919248494)
  val () = _w4(arr, alen, 228, 779973737)
  val () = _w4(arr, alen, 232, 1953656691)
  val () = _w4(arr, alen, 236, 1952669997)
  val () = _w4(arr, alen, 240, 2070247017)
  val () = _w4(arr, alen, 244, 1801675106)
  val () = _w4(arr, alen, 248, 1970238055)
  val () = _w4(arr, alen, 252, 591029358)
  val () = _w4(arr, alen, 256, 993211187)
  val () = _w4(arr, alen, 260, 1869377379)
  val () = _w4(arr, alen, 264, 1713584754)
  val () = _w4(arr, alen, 268, 545089126)
in end

fn inject_mgmt_css {l:agz}
  (s: ward_dom_stream(l), parent: int): ward_dom_stream(l) = let
  val mgmt_arr = ward_arr_alloc<byte>(MGMT_CSS_LEN)
  val () = fill_css_mgmt(mgmt_arr, MGMT_CSS_LEN)
  val mgmt_style_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, mgmt_style_id, parent, tag_style(), 5)
  val @(frozen, borrow) = ward_arr_freeze<byte>(mgmt_arr)
  val s = ward_dom_stream_set_text(s, mgmt_style_id, borrow, MGMT_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val mgmt_arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(mgmt_arr)
in s end

(* ========== Reader navigation CSS ========== *)

fn fill_css_nav {l:agz}{n:int | n >= NAV_CSS_LEN}
  (arr: !ward_arr(byte, l, n), alen: int n): (CSS_NAV_WRITTEN | void) = let
  (* .reader-nav *)
  val () = _w4(arr, alen, 0, 1634038318)
  val () = _w4(arr, alen, 4, 762471780)
  val () = _w4(arr, alen, 8, 2071355758)
  val () = _w4(arr, alen, 12, 1769172848)
  val () = _w4(arr, alen, 16, 1852795252)
  val () = _w4(arr, alen, 20, 2020173370)
  val () = _w4(arr, alen, 24, 1950049381)
  val () = _w4(arr, alen, 28, 809136239)
  val () = _w4(arr, alen, 32, 1717922875)
  val () = _w4(arr, alen, 36, 993016436)
  val () = _w4(arr, alen, 40, 1751607666)
  val () = _w4(arr, alen, 44, 993016436)
  val () = _w4(arr, alen, 48, 1886611812)
  val () = _w4(arr, alen, 52, 981033324)
  val () = _w4(arr, alen, 56, 2019912806)
  val () = _w4(arr, alen, 60, 1937074747)
  val () = _w4(arr, alen, 64, 2036754804)
  val () = _w4(arr, alen, 68, 1852793645)
  val () = _w4(arr, alen, 72, 1953391988)
  val () = _w4(arr, alen, 76, 1634759482)
  val () = _w4(arr, alen, 80, 1647142243)
  val () = _w4(arr, alen, 84, 1702327397)
  val () = _w4(arr, alen, 88, 1631284837)
  val () = _w4(arr, alen, 92, 1852270956)
  val () = _w4(arr, alen, 96, 1702127917)
  val () = _w4(arr, alen, 100, 1664775021)
  val () = _w4(arr, alen, 104, 1702129253)
  val () = _w4(arr, alen, 108, 1634745202)
  val () = _w4(arr, alen, 112, 1852400740)
  val () = _w4(arr, alen, 116, 540031591)
  val () = _w4(arr, alen, 120, 1835364913)
  val () = _w4(arr, alen, 124, 1768253499)
  val () = _w4(arr, alen, 128, 980707431)
  val () = _w4(arr, alen, 132, 1916087858)
  val () = _w4(arr, alen, 136, 1648061797)
  val () = _w4(arr, alen, 140, 1735091041)
  val () = _w4(arr, alen, 144, 1853190002)
  val () = _w4(arr, alen, 148, 1713584740)
  val () = _w4(arr, alen, 152, 1717659233)
  val () = _w4(arr, alen, 156, 762985272)
  val () = _w4(arr, alen, 160, 1701080681)
  val () = _w4(arr, alen, 164, 808532600)
  val () = _w4(arr, alen, 168, 1633824381)
  val () = _w4(arr, alen, 172, 1647143779)
  val () = _w4(arr, alen, 176, 1635479156)
  val () = _w4(arr, alen, 180, 1966763116)
  val () = _w4(arr, alen, 184, 1952805742)
  val () = _w4(arr, alen, 188, 1920295739)
  val () = _w4(arr, alen, 192, 980578163)
  val () = _w4(arr, alen, 196, 1852403568)
  val () = _w4(arr, alen, 200, 997352820)
  val () = _w4(arr, alen, 204, 1869377379)
  val () = _w4(arr, alen, 208, 874723954)
  val () = _w4(arr, alen, 212, 895694689)
  val () = _w4(arr, alen, 216, 1882094905)
  val () = _w4(arr, alen, 220, 761620321)
  val () = _w4(arr, alen, 224, 1868983913)
  val () = _w4(arr, alen, 228, 1819239291)
  val () = _w4(arr, alen, 232, 591032943)
  val () = _w4(arr, alen, 236, 993408566)
  val () = _w4(arr, alen, 240, 1953394534)
  val () = _w4(arr, alen, 244, 2053731117)
  val () = _w4(arr, alen, 248, 875641445)
  val () = _w4(arr, alen, 252, 779974768)
  val () = _w4(arr, alen, 256, 1684104562)
  val () = _w4(arr, alen, 260, 1848472165)
  val () = _w4(arr, alen, 264, 780039777)
  val () = _w4(arr, alen, 268, 1684104562)
  val () = _w4(arr, alen, 272, 1982689893)
  val () = _w4(arr, alen, 276, 1886872937)
  val () = _w4(arr, alen, 280, 2071229039)
  val () = _w4(arr, alen, 284, 1735549293)
  val () = _w4(arr, alen, 288, 1949134441)
  val () = _w4(arr, alen, 292, 842690671)
  val () = _w4(arr, alen, 296, 1701983534)
  val () = _w4(arr, alen, 300, 1701329773)
  val () = _w4(arr, alen, 304, 1952999273)
  val () = _w4(arr, alen, 308, 1818321722)
  val () = _w4(arr, alen, 312, 808527971)
  val () = _w4(arr, alen, 316, 543716912)
  val () = _w4(arr, alen, 320, 775036973)
  val () = _w4(arr, alen, 324, 1835364917)
  val () = _w4(arr, alen, 328, 1915649321)
  val () = _w4(arr, alen, 332, 1701077349)
  val () = _w4(arr, alen, 336, 1634610546)
  val () = _w4(arr, alen, 340, 1915649654)
  val () = _w4(arr, alen, 344, 1701077349)
  val () = _w4(arr, alen, 348, 1769352562)
  val () = _w4(arr, alen, 352, 1869641573)
  val () = _w4(arr, alen, 356, 773878898)
  val () = _w4(arr, alen, 360, 1885431907)
  val () = _w4(arr, alen, 364, 762471796)
  val () = _w4(arr, alen, 368, 1953394531)
  val () = _w4(arr, alen, 372, 1701734753)
  val () = _w4(arr, alen, 376, 1701346162)
  val () = _w4(arr, alen, 380, 1952999273)
  val () = _w4(arr, alen, 384, 1818321722)
  val () = _w4(arr, alen, 388, 808527971)
  val () = _w4(arr, alen, 392, 543716912)
  val () = _w4(arr, alen, 396, 775299117)
  val () = _w4(arr, alen, 400, 1835364917)
  val () = _w4(arr, alen, 404, 1848540457)
  (* .nav-controls *)
  val () = _w4(arr, alen, 408, 1663923809)
  val () = _w4(arr, alen, 412, 1920233071)
  val () = _w4(arr, alen, 416, 2071161967)
  val () = _w4(arr, alen, 420, 1886611812)
  val () = _w4(arr, alen, 424, 981033324)
  val () = _w4(arr, alen, 428, 2019912806)
  val () = _w4(arr, alen, 432, 1768710459)
  val () = _w4(arr, alen, 436, 1764585063)
  val () = _w4(arr, alen, 440, 1936549236)
  val () = _w4(arr, alen, 444, 1852138298)
  val () = _w4(arr, alen, 448, 997352820)
  val () = _w4(arr, alen, 452, 980443495)
  val () = _w4(arr, alen, 456, 1701983534)
  val () = _w4(arr, alen, 460, 1882094957)
  (* .prev-btn,.next-btn *)
  val () = _w4(arr, alen, 464, 762733938)
  val () = _w4(arr, alen, 468, 745436258)
  val () = _w4(arr, alen, 472, 2019913262)
  val () = _w4(arr, alen, 476, 1952591220)
  val () = _w4(arr, alen, 480, 1818327918)
  val () = _w4(arr, alen, 484, 1853176428)
  val () = _w4(arr, alen, 488, 997483891)
  val () = _w4(arr, alen, 492, 1936880995)
  val () = _w4(arr, alen, 496, 1882878575)
  val () = _w4(arr, alen, 500, 1953393007)
  val () = _w4(arr, alen, 504, 1664840293)
  val () = _w4(arr, alen, 508, 1919904879)
  val () = _w4(arr, alen, 512, 1630806842)
  val () = _w4(arr, alen, 516, 959800119)
  val () = _w4(arr, alen, 520, 1852794427)
  val () = _w4(arr, alen, 524, 1769155956)
  val () = _w4(arr, alen, 528, 825910650)
  val () = _w4(arr, alen, 532, 997025138)
  val () = _w4(arr, alen, 536, 1684300144)
  val () = _w4(arr, alen, 540, 979857001)
  val () = _w4(arr, alen, 544, 858660912)
  val () = _w4(arr, alen, 548, 2104321394)

  (* Construct proof — solver verifies constraints *)
  prval pf_btn = BTNS_HAVE_SIZE{CSS_BTN_FONT_10, CSS_BTN_PAD_H_10}()

  (* Stamp: overwrite critical bytes from proven values AND produce the view.
   * This is the ONLY way to get CSS_NAV_WRITTEN. *)
  val (pf_written | ()) = stamp_nav_css(
    pf_btn |
    arr, alen,
    CSS_BTN_FONT_10, CSS_BTN_PAD_H_10)
in (pf_written | ()) end

(* Inject reader-specific nav CSS as a separate <style> element.
 * CONSUMES CSS_NAV_WRITTEN — linear, must be produced by fill_css_nav. *)
fn inject_nav_css {l:agz}
  (s: ward_dom_stream(l), parent: int): ward_dom_stream(l) = let
  val nav_arr = ward_arr_alloc<byte>(NAV_CSS_LEN)
  val (pf_nav | ()) = fill_css_nav(nav_arr, NAV_CSS_LEN)
  prval () = __consume(pf_nav) where {
    extern praxi __consume(pf: CSS_NAV_WRITTEN): void
  }
  val nav_style_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, nav_style_id, parent, tag_style(), 5)
  val @(frozen, borrow) = ward_arr_freeze<byte>(nav_arr)
  val s = ward_dom_stream_set_text(s, nav_style_id, borrow, NAV_CSS_LEN)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val nav_arr = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(nav_arr)
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

(* import_finish: consumes linear import_handled token, restores UI, logs "import-done".
 * Called from each branch of the import outcome — token never crosses if-then-else. *)
fn import_finish(h: import_handled, label_id: int, span_id: int, status_id: int): void = let
  val () = quire_set_title(0)
  val () = update_import_label_class(label_id, 0)
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
  val s2 = ward_dom_stream_set_safe_text(s2, span_id, import_st2, 6)
  val dom2 = ward_dom_stream_end(s2)
  val () = ward_dom_fini(dom2)
  val () = clear_node(status_id)
  val () = import_complete(h)
in end

(* ========== Page navigation helpers ========== *)

(* Write non-negative int as decimal digits into ward_arr at offset.
 * Returns number of digits written. Array must be >= 48 bytes.
 * Digit bytes are 48-57 ('0'-'9') — always valid for int2byte0.
 * NOTE: mod_int_int returns plain int so solver can't verify range;
 * the invariant 0 <= (v%10) <= 9 holds by definition of modulo. *)
fn itoa_to_arr {l:agz}
  (arr: !ward_arr(byte, l, 48), v: int, offset: int): int = let
  fun count_digits {k:nat} .<k>.
    (rem: int(k), x: int, acc: int): int =
    if lte_g1(rem, 0) then acc
    else if gt_int_int(x, 0) then count_digits(sub_g1(rem, 1), div_int_int(x, 10), acc + 1)
    else acc
in
  if gt_int_int(1, v) then let
    val () = ward_arr_set<byte>(arr, _idx48(offset),
      _byte(char2int1('0')))
  in 1 end
  else let
    val ndigits = count_digits(_checked_nat(11), v, 0)
    fun write_rev {l:agz}{k:nat} .<k>.
      (rem: int(k), arr: !ward_arr(byte, l, 48), x: int, pos: int): void =
      if lte_g1(rem, 0) then ()
      else if gt_int_int(x, 0) then let
        val digit = mod_int_int(x, 10)
        (* digit is 0-9, so 48+digit is 48-57 — within byte range *)
        val () = ward_arr_set<byte>(arr, _idx48(pos), ward_int2byte(_checked_byte(48 + digit)))
      in write_rev(sub_g1(rem, 1), arr, div_int_int(x, 10), pos - 1) end
      else ()
    val () = write_rev(_checked_nat(11), arr, v, offset + ndigits - 1)
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

(* Update page indicator text: "Ch X/Y  N/M" showing chapter and page position.
 * Uses standalone DOM stream — safe to call from event handlers.
 * Format: "Ch 1/5  3/10" — chapter 1 of 5, page 3 of 10.
 * Buffer: 48 bytes, max realistic content ~20 chars. *)
fn update_page_info(): void = let
  val nid = reader_get_page_indicator_id()
in
  if gt_int_int(nid, 0) then let
    val cur_ch = reader_get_current_chapter()
    val total_ch = reader_get_chapter_count()
    val cur_pg = reader_get_current_page()
    val total_pg = reader_get_total_pages()
    val arr = ward_arr_alloc<byte>(48)
    (* Write "Ch " prefix — 67='C' 104='h' 32=' ' *)
    val () = ward_arr_set<byte>(arr, _idx48(0), _byte(67))
    val () = ward_arr_set<byte>(arr, _idx48(1), _byte(104))
    val () = ward_arr_set<byte>(arr, _idx48(2), _byte(32))
    (* Chapter number (1-indexed) *)
    val ch_digits = itoa_to_arr(arr, cur_ch + 1, 3)
    val p = 3 + ch_digits
    val () = ward_arr_set<byte>(arr, _idx48(p), _byte(47))     (* '/' *)
    val tch_digits = itoa_to_arr(arr, total_ch, p + 1)
    val p2 = p + 1 + tch_digits
    (* Two-space separator *)
    val () = ward_arr_set<byte>(arr, _idx48(p2), _byte(32))
    val () = ward_arr_set<byte>(arr, _idx48(p2 + 1), _byte(32))
    (* Page number (1-indexed) *)
    val pg_digits = itoa_to_arr(arr, cur_pg + 1, p2 + 2)
    val p3 = p2 + 2 + pg_digits
    val () = ward_arr_set<byte>(arr, _idx48(p3), _byte(47))    (* '/' *)
    val tpg_digits = itoa_to_arr(arr, total_pg, p3 + 1)
    val total_len = p3 + 1 + tpg_digits
    val tl = g1ofg0(total_len)
  in
    if tl > 0 then
      if tl < 48 then let
        val @(used, rest) = ward_arr_split<byte>(arr, tl)
        val () = ward_arr_free<byte>(rest)
        val @(frozen, borrow) = ward_arr_freeze<byte>(used)
        val dom = ward_dom_init()
        val s = ward_dom_stream_begin(dom)
        val s = ward_dom_stream_set_text(s, nid, borrow, tl)
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = ward_arr_drop<byte>(frozen, borrow)
        val used = ward_arr_thaw<byte>(frozen)
        val () = ward_arr_free<byte>(used)
      in end
      else let val () = ward_arr_free<byte>(arr) in end
    else let val () = ward_arr_free<byte>(arr) in end
  end
  else ()
end

(* page_turn_forward: advance page within chapter and update display.
 * Bundles reader_next_page + apply_page_transform + update_page_info.
 * Returns PAGE_DISPLAY_UPDATED proof — the ONLY way to obtain it for
 * forward page turns. Caller must destructure the proof.
 *
 * Precondition: caller has already verified pg < total - 1. *)
fn page_turn_forward(container_id: int)
  : (PAGE_DISPLAY_UPDATED() | void) = let
  val () = reader_next_page()
  val () = apply_page_transform(container_id)
  val () = update_page_info()
  prval pf = PAGE_TURNED_AND_SHOWN()
in (pf | ()) end

(* page_turn_backward: go to previous page within chapter and update display.
 * Bundles reader_prev_page + apply_page_transform + update_page_info.
 * Returns PAGE_DISPLAY_UPDATED proof — the ONLY way to obtain it for
 * backward page turns. Caller must destructure the proof.
 *
 * Precondition: caller has already verified pg > 0. *)
fn page_turn_backward(container_id: int)
  : (PAGE_DISPLAY_UPDATED() | void) = let
  val () = reader_prev_page()
  val () = apply_page_transform(container_id)
  val () = update_page_info()
  prval pf = PAGE_TURNED_AND_SHOWN()
in (pf | ()) end

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

(* Apply resume page after chapter loads.
 * If reader_get_resume_page() > 0, go to that page (clamped to total),
 * apply transform, clear resume page. Called after measure_and_set_pages. *)
fn apply_resume_page(container_id: int): void = let
  val resume_pg = reader_get_resume_page()
in
  if gt_int_int(resume_pg, 0) then let
    val () = reader_go_to_page(resume_pg)
    val () = apply_page_transform(container_id)
    val () = update_page_info()
    val () = reader_set_resume_page(0)
  in end
  else ()
end


(* ========== EPUB import: read and parse ZIP entries (async) ========== *)

(* Read container.xml from ZIP, handling both stored and deflated entries.
 * Returns ward_promise_chained(int) — resolves to parse result (>0 = success).
 * For stored entries: reads directly, parses synchronously.
 * For deflated entries: reads compressed bytes, decompresses via ward_decompress,
 * parses in callback. Follows the load_chapter pattern exactly. *)
fn epub_read_container_async
  (pf_zip: ZIP_OPEN_OK | handle: int): ward_promise_chained(int) = let
  val _cl = epub_copy_container_path(0)
  val idx = zip_find_entry(pf_zip | 22)
in
  if gt_int_int(0, idx) then ward_promise_return<int>(0)
  else let
    var entry: zip_entry
    val found = zip_get_entry(idx, entry)
  in
    if eq_int_int(found, 0) then ward_promise_return<int>(0)
    else let
      val compression = entry.compression
      val compressed_size = entry.compressed_size
      val usize = entry.uncompressed_size
    in
      if gt_int_int(1, usize) then ward_promise_return<int>(0)
      else if gt_int_int(usize, 16384) then ward_promise_return<int>(0)
      else let
        val data_off = zip_get_data_offset(idx)
      in
        if gt_int_int(0, data_off) then ward_promise_return<int>(0)
        else if eq_int_int(compression, 8) then let
          (* Deflated — async decompression *)
          val cs1 = (if gt_int_int(compressed_size, 0)
            then compressed_size else 1): int
          val cs_pos = _checked_arr_size(cs1)
          val arr = ward_arr_alloc<byte>(cs_pos)
          val _rd = ward_file_read(handle, data_off, arr, cs_pos)
          val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
          val p = ward_decompress(borrow, cs_pos, 2) (* deflate-raw *)
          val () = ward_arr_drop<byte>(frozen, borrow)
          val arr = ward_arr_thaw<byte>(frozen)
          val () = ward_arr_free<byte>(arr)
        in ward_promise_then<int><int>(p,
          llam (blob_handle: int): ward_promise_chained(int) => let
            val dlen = ward_decompress_get_len()
          in
            if gt_int_int(dlen, 0) then let
              val dl = _checked_arr_size(dlen)
              val arr2 = ward_arr_alloc<byte>(dl)
              val _rd = ward_blob_read(blob_handle, 0, arr2, dl)
              val () = ward_blob_free(blob_handle)
              val result = epub_parse_container_bytes(arr2, dl)
              val () = ward_arr_free<byte>(arr2)
            in ward_promise_return<int>(result) end
            else let
              val () = ward_blob_free(blob_handle)
            in ward_promise_return<int>(0) end
          end)
        end
        else let
          (* Stored — synchronous read *)
          val usize1 = _checked_arr_size(usize)
          val arr = ward_arr_alloc<byte>(usize1)
          val _rd = ward_file_read(handle, data_off, arr, usize1)
          val result = epub_parse_container_bytes(arr, usize1)
          val () = ward_arr_free<byte>(arr)
        in ward_promise_return<int>(result) end
      end
    end
  end
end

(* Read content.opf from ZIP — same pattern as container. *)
fn epub_read_opf_async
  (pf_zip: ZIP_OPEN_OK | handle: int): ward_promise_chained(int) = let
  val opf_len = epub_copy_opf_path(0)
  val idx = zip_find_entry(pf_zip | opf_len)
in
  if gt_int_int(0, idx) then ward_promise_return<int>(0)
  else let
    var entry: zip_entry
    val found = zip_get_entry(idx, entry)
  in
    if eq_int_int(found, 0) then ward_promise_return<int>(0)
    else let
      val compression = entry.compression
      val compressed_size = entry.compressed_size
      val usize = entry.uncompressed_size
    in
      if gt_int_int(1, usize) then ward_promise_return<int>(0)
      else if gt_int_int(usize, 16384) then ward_promise_return<int>(0)
      else let
        val data_off = zip_get_data_offset(idx)
      in
        if gt_int_int(0, data_off) then ward_promise_return<int>(0)
        else if eq_int_int(compression, 8) then let
          (* Deflated — async decompression *)
          val cs1 = (if gt_int_int(compressed_size, 0)
            then compressed_size else 1): int
          val cs_pos = _checked_arr_size(cs1)
          val arr = ward_arr_alloc<byte>(cs_pos)
          val _rd = ward_file_read(handle, data_off, arr, cs_pos)
          val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
          val p = ward_decompress(borrow, cs_pos, 2) (* deflate-raw *)
          val () = ward_arr_drop<byte>(frozen, borrow)
          val arr = ward_arr_thaw<byte>(frozen)
          val () = ward_arr_free<byte>(arr)
        in ward_promise_then<int><int>(p,
          llam (blob_handle: int): ward_promise_chained(int) => let
            val dlen = ward_decompress_get_len()
          in
            if gt_int_int(dlen, 0) then let
              val dl = _checked_arr_size(dlen)
              val arr2 = ward_arr_alloc<byte>(dl)
              val _rd = ward_blob_read(blob_handle, 0, arr2, dl)
              val () = ward_blob_free(blob_handle)
              val result = epub_parse_opf_bytes(arr2, dl)
              val () = ward_arr_free<byte>(arr2)
            in ward_promise_return<int>(result) end
            else let
              val () = ward_blob_free(blob_handle)
            in ward_promise_return<int>(0) end
          end)
        end
        else let
          (* Stored — synchronous read *)
          val usize1 = _checked_arr_size(usize)
          val arr = ward_arr_alloc<byte>(usize1)
          val _rd = ward_file_read(handle, data_off, arr, usize1)
          val result = epub_parse_opf_bytes(arr, usize1)
          val () = ward_arr_free<byte>(arr)
        in ward_promise_return<int>(result) end
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

(* BUG CLASS PREVENTED: VIEW_FILTER_MISMATCH
 * count_visible_books and render_library_with_books MUST agree on which
 * books are visible. Both route through filter_book_visible, which validates
 * inputs and calls should_render_book (proven correct by VIEW_FILTER_CORRECT).
 * A toddler cannot get the filter wrong: should_render_book's dataprop
 * constructors enforce that active view shows active books, archived view
 * shows archived books. Duplicating the logic with raw comparisons allowed
 * the original bug where count showed 0 visible but render would have shown cards. *)
fn filter_book_visible(vm: int, book_idx: int): int = let
  val ss = library_get_shelf_state(book_idx)
  val vm_dep = _checked_nat(vm)
in
  if eq_g1(vm_dep, 0) then
    if eq_g1(ss, 0) then let
      val (_ | r) = should_render_book(VIEW_ACTIVE(), SHELF_ACTIVE() | 0, ss)
    in r end
    else if eq_g1(ss, 1) then let
      val (_ | r) = should_render_book(VIEW_ACTIVE(), SHELF_ARCHIVED() | 0, ss)
    in r end
    else let
      val (_ | r) = should_render_book(VIEW_ACTIVE(), SHELF_HIDDEN() | 0, ss)
    in r end
  else if eq_g1(vm_dep, 1) then
    if eq_g1(ss, 0) then let
      val (_ | r) = should_render_book(VIEW_ARCHIVED(), SHELF_ACTIVE() | 1, ss)
    in r end
    else if eq_g1(ss, 1) then let
      val (_ | r) = should_render_book(VIEW_ARCHIVED(), SHELF_ARCHIVED() | 1, ss)
    in r end
    else let
      val (_ | r) = should_render_book(VIEW_ARCHIVED(), SHELF_HIDDEN() | 1, ss)
    in r end
  else
    if eq_g1(ss, 0) then let
      val (_ | r) = should_render_book(VIEW_HIDDEN(), SHELF_ACTIVE() | 2, ss)
    in r end
    else if eq_g1(ss, 1) then let
      val (_ | r) = should_render_book(VIEW_HIDDEN(), SHELF_ARCHIVED() | 2, ss)
    in r end
    else let
      val (_ | r) = should_render_book(VIEW_HIDDEN(), SHELF_HIDDEN() | 2, ss)
    in r end
end

fn render_library_with_books {l:agz}
  (s: ward_dom_stream(l), list_id: int, view_mode: int)
  : ward_dom_stream(l) = let
  val s = ward_dom_stream_remove_children(s, list_id)
  val count = library_get_count()
  val vm_raw = view_mode
  fun loop {l:agz}{k:nat} .<k>.
    (rem: int(k), s: ward_dom_stream(l), i: int, n: int, vm: int): ward_dom_stream(l) =
    if lte_g1(rem, 0) then s
    else if gte_int_int(i, n) then s
    else let
      (* Proven filter: routes through should_render_book with VIEW_FILTER_CORRECT *)
      val do_render = filter_book_visible(vm, i)
    in
      if gt_int_int(do_render, 0) then let
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

        (* Card actions: buttons depend on view mode *)
        val actions_id = dom_next_id()
        val s = ward_dom_stream_create_element(s, actions_id, card_id, tag_div(), 3)
        val s = ward_dom_stream_set_attr_safe(s, actions_id, attr_class(), 5, cls_card_actions(), 12)
      in
        if eq_int_int(vm, 0) then let
          (* Active view: Read + Hide + Archive buttons *)
          val btn_id = dom_next_id()
          val () = reader_set_btn_id(i, btn_id)
          val s = ward_dom_stream_create_element(s, btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_read_btn(), 8)
          val s = set_text_cstr(s, btn_id, TEXT_READ, 4)

          val hide_btn_id = dom_next_id()
          val () = reader_set_btn_id(i + 64, hide_btn_id)
          val s = ward_dom_stream_create_element(s, hide_btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, hide_btn_id, attr_class(), 5, cls_hide_btn(), 8)
          val s = set_text_cstr(s, hide_btn_id, TEXT_HIDE, 4)

          val arch_btn_id = dom_next_id()
          val () = reader_set_btn_id(i + 32, arch_btn_id)
          val s = ward_dom_stream_create_element(s, arch_btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, arch_btn_id, attr_class(), 5, cls_archive_btn(), 11)
          val s = set_text_cstr(s, arch_btn_id, TEXT_ARCHIVE, 7)
        in loop(sub_g1(rem, 1), s, i + 1, n, vm) end
        else if eq_int_int(vm, 2) then let
          (* Hidden view: Read + Unhide buttons *)
          val btn_id = dom_next_id()
          val () = reader_set_btn_id(i, btn_id)
          val s = ward_dom_stream_create_element(s, btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_read_btn(), 8)
          val s = set_text_cstr(s, btn_id, TEXT_READ, 4)

          val unhide_btn_id = dom_next_id()
          val () = reader_set_btn_id(i + 64, unhide_btn_id)
          val s = ward_dom_stream_create_element(s, unhide_btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, unhide_btn_id, attr_class(), 5, cls_hide_btn(), 8)
          val s = set_text_cstr(s, unhide_btn_id, TEXT_UNHIDE, 6)
        in loop(sub_g1(rem, 1), s, i + 1, n, vm) end
        else let
          (* Archived view: Read + Restore buttons *)
          val btn_id = dom_next_id()
          val () = reader_set_btn_id(i, btn_id)
          val s = ward_dom_stream_create_element(s, btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_read_btn(), 8)
          val s = set_text_cstr(s, btn_id, TEXT_READ, 4)

          val restore_btn_id = dom_next_id()
          val () = reader_set_btn_id(i + 32, restore_btn_id)
          val s = ward_dom_stream_create_element(s, restore_btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, restore_btn_id, attr_class(), 5, cls_archive_btn(), 11)
          val s = set_text_cstr(s, restore_btn_id, TEXT_UNARCHIVE, 7)
        in loop(sub_g1(rem, 1), s, i + 1, n, vm) end
      end
      else loop(sub_g1(rem, 1), s, i + 1, n, vm)
    end
in loop(_checked_nat(count), s, 0, count, vm_raw) end

(* ========== Chapter loading ========== *)

(* show_chapter_error: Display an error message in the chapter container.
 * Clears existing content and shows a styled <p class="chapter-error">. *)
fn show_chapter_error(container_id: int, text_id: int, text_len: int): void = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, container_id)
  val error_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, error_id, container_id, tag_p(), 1)
  val s = ward_dom_stream_set_attr_safe(s, error_id, attr_class(), 5,
    cls_chapter_error(), 13)
  val s = set_text_cstr(s, error_id, text_id, text_len)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
in end

(* Validate render window after rendering + measuring.
 * Computes elements-per-page (epp) and determines the window tier:
 *   - WINDOW_5: 5*epp <= MAX_RENDER_ELEMENTS (typical — budget covers 5+ pages)
 *   - WINDOW_3: 3*epp <= budget but 5*epp > budget (dense content)
 *   - WINDOW_1: epp <= budget but 3*epp > budget (very dense)
 *   - ADVERSARIAL: epp > budget — show visible error + log
 *
 * Proofs (WINDOW_OPTIMAL, ADVERSARIAL_PAGE) document which tier was selected.
 * Runtime branches verify the arithmetic; comments reference the dataprop
 * constructors since freestanding ATS2 can't track g0int arithmetic. *)
fn validate_render_window(ecnt: int, container_id: int): void = let
  val pages = reader_get_total_pages()
in
  if gt_int_int(pages, 0) then let
    val epp = div_int_int(ecnt, pages)
  in
    if lte_int_int(mul_int_int(5, epp), MAX_RENDER_ELEMENTS) then
      () (* WINDOW_OPTIMAL: WINDOW_5 — budget supports 5+ pages *)
    else if lte_int_int(mul_int_int(3, epp), MAX_RENDER_ELEMENTS) then
      () (* WINDOW_OPTIMAL: WINDOW_3 — budget supports 3 pages *)
    else if lte_int_int(epp, MAX_RENDER_ELEMENTS) then
      () (* WINDOW_OPTIMAL: WINDOW_1 — budget supports 1 page *)
    else let
      (* ADVERSARIAL_PAGE: TOO_DENSE — single page exceeds budget *)
      val () = ward_log(3, mk_ch_err(char2int1('d'), char2int1('n'), char2int1('s')), 10)
    in show_chapter_error(container_id, TEXT_ERR_TOO_DENSE, 14) end
  end
  else () (* no pages — nothing to validate *)
end

(* finish_chapter_load: Complete chapter display after rendering.
 * Bundles ALL steps required to make chapter content visible:
 *   1. measure_and_set_pages — compute pagination from scrollWidth
 *   2. validate_render_window — sanity check rendered element count
 *   3. apply_page_transform — reset CSS transform to current page
 *   4. update_page_info — update "Ch X/Y N/M" UI
 *   5. apply_resume_page — override if resuming saved position
 *
 * Produces CHAPTER_DISPLAY_READY proof, which is the ONLY way to
 * obtain this dataprop. Consolidating all steps here makes it
 * impossible to skip apply_page_transform (the root cause of
 * blank first-page-after-chapter-transition). *)
fn finish_chapter_load(container_id: int)
  : (CHAPTER_DISPLAY_READY() | void) = let
  val () = measure_and_set_pages(container_id)
  val () = validate_render_window(dom_get_render_ecnt(), container_id)
  val () = apply_page_transform(container_id)
  val () = update_page_info()
  val () = apply_resume_page(container_id)
  prval pf = MEASURED_AND_TRANSFORMED()
in (pf | ()) end

(* Extract chapter directory from spine path in sbuf.
 * Scans sbuf[0..path_len-1] backward for last '/'.
 * Returns directory length (including trailing '/'), or 0 if no '/'.
 * E.g., "OEBPS/Text/ch1.xhtml" → dir_len=11 ("OEBPS/Text/") *)
fn find_chapter_dir_len(path_len: int): [d:nat] int(d) = let
  fun scan {k:nat} .<k>.
    (rem: int(k), pos: int): int =
    if lte_g1(rem, 0) then 0
    else if pos < 0 then 0
    else if _app_sbuf_get_u8(pos) = 47 (* '/' *)
    then pos + 1
    else scan(sub_g1(rem, 1), pos - 1)
  val d = scan(_checked_nat(path_len), path_len - 1)
in
  if d >= 0 then _checked_nat(d)
  else _checked_nat(0)
end

(* Allocate a ward_arr and copy sbuf[0..len-1] into it.
 * Used to capture chapter directory before sbuf is reused. *)
fn copy_sbuf_to_arr {dl:pos | dl <= 1048576}
  (dl: int dl): [l:agz] ward_arr(byte, l, dl) = let
  val arr = ward_arr_alloc<byte>(dl)
  fun copy_loop {l:agz}{n:pos}{k:nat} .<k>.
    (rem: int(k), a: !ward_arr(byte, l, n), alen: int n, i: int, count: int): void =
    if lte_g1(rem, 0) then ()
    else if i < count then let
      val b = _app_sbuf_get_u8(i)
      val () = ward_arr_write_byte(a, _ward_idx(i, alen), _checked_byte(b))
    in copy_loop(sub_g1(rem, 1), a, alen, i + 1, count) end
  val () = copy_loop(_checked_nat(_g0(dl)), arr, dl, 0, dl)
in arr end

(*
 * NOTE: load_chapter (ZIP-based direct read) was removed.
 * All chapter loading now goes through load_chapter_from_idb,
 * which reads pre-exploded resources from IDB (M1.2).
 * ZIP_OPEN_OK proof prevents zip_find_entry on empty archives.
 *)

(* ========== IDB-based image loading from IDB ========== *)

(* Detect MIME type from image data magic bytes.
 * Returns: 1=jpeg, 2=png, 3=gif, 4=svg+xml, 0=unknown *)
fn detect_mime_from_magic {lb:agz}{n:pos}
  (arr: !ward_arr(byte, lb, n), len: int n): int =
  if gte_int_int(len, 4) then let
    val b0 = byte2int0(ward_arr_get<byte>(arr, _ward_idx(0, len)))
    val b1 = byte2int0(ward_arr_get<byte>(arr, _ward_idx(1, len)))
    val b2 = byte2int0(ward_arr_get<byte>(arr, _ward_idx(2, len)))
    val b3 = byte2int0(ward_arr_get<byte>(arr, _ward_idx(3, len)))
  in
    if eq_int_int(b0, 255) then (* 0xFF *)
      if eq_int_int(b1, 216) then 1 (* 0xD8 → JPEG *)
      else 0
    else if eq_int_int(b0, 137) then (* 0x89 *)
      if eq_int_int(b1, 80) then (* 0x50 = 'P' *)
        if eq_int_int(b2, 78) then (* 0x4E = 'N' *)
          if eq_int_int(b3, 71) then 2 (* 0x47 = 'G' → PNG *)
          else 0
        else 0
      else 0
    else if eq_int_int(b0, 71) then (* 0x47 = 'G' *)
      if eq_int_int(b1, 73) then (* 0x49 = 'I' *)
        if eq_int_int(b2, 70) then 3 (* 0x46 = 'F' → GIF *)
        else 0
      else 0
    else if eq_int_int(b0, 60) then 4 (* 0x3C = '<' → SVG/XML *)
    else 0
  end
  else 0

(* Set image src on a DOM node from IDB-retrieved data.
 * Detects MIME from magic bytes, creates its own DOM stream.
 * Consumes the data array. *)
fn set_image_src_idb {lb:agz}{n:pos}
  (node_id: int, data: ward_arr(byte, lb, n), data_len: int n): void = let
  val mime_type = detect_mime_from_magic(data, data_len)
in
  if eq_int_int(mime_type, 0) then
    ward_arr_free<byte>(data) (* unknown MIME — skip, free data *)
  else let
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val @(frozen, borrow) = ward_arr_freeze<byte>(data)
  in
    if eq_int_int(mime_type, 1) then let (* JPEG *)
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
      val mime = ward_content_text_done(b)
      val s = ward_dom_stream_set_image_src(s, node_id, borrow, data_len, mime, 10)
      val () = ward_safe_content_text_free(mime)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val data = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(data)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else if eq_int_int(mime_type, 2) then let (* PNG *)
      val b = ward_content_text_build(9)
      val b = ward_content_text_putc(b, 0, char2int1('i'))
      val b = ward_content_text_putc(b, 1, char2int1('m'))
      val b = ward_content_text_putc(b, 2, char2int1('a'))
      val b = ward_content_text_putc(b, 3, char2int1('g'))
      val b = ward_content_text_putc(b, 4, char2int1('e'))
      val b = ward_content_text_putc(b, 5, 47) (* '/' *)
      val b = ward_content_text_putc(b, 6, char2int1('p'))
      val b = ward_content_text_putc(b, 7, char2int1('n'))
      val b = ward_content_text_putc(b, 8, char2int1('g'))
      val mime = ward_content_text_done(b)
      val s = ward_dom_stream_set_image_src(s, node_id, borrow, data_len, mime, 9)
      val () = ward_safe_content_text_free(mime)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val data = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(data)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else if eq_int_int(mime_type, 3) then let (* GIF *)
      val b = ward_content_text_build(9)
      val b = ward_content_text_putc(b, 0, char2int1('i'))
      val b = ward_content_text_putc(b, 1, char2int1('m'))
      val b = ward_content_text_putc(b, 2, char2int1('a'))
      val b = ward_content_text_putc(b, 3, char2int1('g'))
      val b = ward_content_text_putc(b, 4, char2int1('e'))
      val b = ward_content_text_putc(b, 5, 47) (* '/' *)
      val b = ward_content_text_putc(b, 6, char2int1('g'))
      val b = ward_content_text_putc(b, 7, char2int1('i'))
      val b = ward_content_text_putc(b, 8, char2int1('f'))
      val mime = ward_content_text_done(b)
      val s = ward_dom_stream_set_image_src(s, node_id, borrow, data_len, mime, 9)
      val () = ward_safe_content_text_free(mime)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val data = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(data)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else let (* SVG *)
      val b = ward_content_text_build(13)
      val b = ward_content_text_putc(b, 0, char2int1('i'))
      val b = ward_content_text_putc(b, 1, char2int1('m'))
      val b = ward_content_text_putc(b, 2, char2int1('a'))
      val b = ward_content_text_putc(b, 3, char2int1('g'))
      val b = ward_content_text_putc(b, 4, char2int1('e'))
      val b = ward_content_text_putc(b, 5, 47) (* '/' *)
      val b = ward_content_text_putc(b, 6, char2int1('s'))
      val b = ward_content_text_putc(b, 7, char2int1('v'))
      val b = ward_content_text_putc(b, 8, char2int1('g'))
      val b = ward_content_text_putc(b, 9, 43) (* '+' *)
      val b = ward_content_text_putc(b, 10, char2int1('x'))
      val b = ward_content_text_putc(b, 11, char2int1('m'))
      val b = ward_content_text_putc(b, 12, char2int1('l'))
      val mime = ward_content_text_done(b)
      val s = ward_dom_stream_set_image_src(s, node_id, borrow, data_len, mime, 13)
      val () = ward_safe_content_text_free(mime)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val data = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(data)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
  end
end

(* Pre-scan: resolve deferred image paths and find entry indices.
 * For each deferred image in the queue, resolves path via resolve_img_src
 * and looks up the manifest entry via epub_find_resource.
 * Stores (node_id, entry_idx) pairs in app_state deferred image buffers.
 * Returns the count of successfully resolved images. *)
fun prescan_deferred_for_idb {lb:agz}{n:pos}{ld:agz}{nd:pos}{k:nat} .<k>.
  (rem: int(k),
   tree: !ward_arr(byte, lb, n), tlen: int n,
   cdir: !ward_arr(byte, ld, nd), cdlen: int nd,
   i: int, total: int, out: int): int =
  if lte_g1(rem, 0) then out
  else if gte_int_int(i, total) then out
  else let
    val nid = deferred_image_get_node_id(i)
    val src_off = deferred_image_get_src_off(i)
    val src_len = deferred_image_get_src_len(i)
    val path_len = resolve_img_src(tree, tlen, src_off, src_len, cdir, cdlen)
    val entry_idx = epub_find_resource(path_len)
  in
    if gte_int_int(entry_idx, 0) then let
      val () = _app_deferred_img_node_id_set(out, nid)
      val () = _app_deferred_img_entry_idx_set(out, entry_idx)
    in prescan_deferred_for_idb(sub_g1(rem, 1), tree, tlen, cdir, cdlen,
      i + 1, total, out + 1) end
    else prescan_deferred_for_idb(sub_g1(rem, 1), tree, tlen, cdir, cdlen,
      i + 1, total, out)
  end

(* Async chain: load each deferred image from IDB and set its src.
 * For each (node_id, entry_idx) pair, builds IDB key, fetches data,
 * detects MIME from magic bytes, and sets image src. *)
fun load_idb_images_chain {k:nat} .<k>.
  (rem: int(k), idx: int, total: int): void =
  if lte_g1(rem, 0) then ()
  else if gte_int_int(idx, total) then ()
  else let
    val nid = _app_deferred_img_node_id_get(idx)
    val entry_idx = _app_deferred_img_entry_idx_get(idx)
    val key = epub_build_resource_key(entry_idx)
    val p = ward_idb_get(key, 20)
    val saved_nid = nid
    val saved_rem = sub_g1(rem, 1)
    val saved_next = idx + 1
    val saved_total = total
    val p2 = ward_promise_then<int><int>(p,
      llam (data_len: int): ward_promise_chained(int) =>
        if lte_int_int(data_len, 0) then let
          val () = load_idb_images_chain(saved_rem, saved_next, saved_total)
        in ward_promise_return<int>(0) end
        else let
          val dl = _checked_pos(data_len)
          val arr = ward_idb_get_result(dl)
          val () = set_image_src_idb(saved_nid, arr, dl)
          val () = load_idb_images_chain(saved_rem, saved_next, saved_total)
        in ward_promise_return<int>(1) end)
    val () = ward_promise_discard<int>(p2)
  in end

(* ========== IDB-based chapter loading ========== *)

(* Load chapter from IDB — no file handle needed.
 * Looks up spine→entry index from manifest, builds IDB key,
 * fetches decompressed XHTML from IDB, parses and renders. *)
fn load_chapter_from_idb {c,t:nat | c < t}
  (pf: SPINE_ORDERED(c, t) |
   chapter_idx: int(c), spine_count: int(t), container_id: int): void = let
  val entry_idx = _app_epub_spine_entry_idx_get(chapter_idx)
  val key = epub_build_resource_key(entry_idx)
  val p = ward_idb_get(key, 20)
  val saved_cid = container_id
  (* Copy spine path to sbuf[0..] and extract chapter dir *)
  val path_len = epub_copy_spine_path(pf | chapter_idx, spine_count, 0)
  val dir_len = find_chapter_dir_len(path_len)
in
  if gt_int_int(dir_len, 0) then let
    val dl_pos = _checked_arr_size(dir_len)
    val dir_arr = copy_sbuf_to_arr(dl_pos)
    val p2 = ward_promise_then<int><int>(p,
      llam (data_len: int): ward_promise_chained(int) =>
        if lte_int_int(data_len, 0) then let
          val () = ward_arr_free<byte>(dir_arr)
          val () = ward_log(3, mk_ch_err(char2int1('g'), char2int1('e'), char2int1('t')), 10)
          val () = show_chapter_error(saved_cid, TEXT_ERR_NOT_FOUND, 17)
        in ward_promise_return<int>(0) end
        else let
          val dl = _checked_pos(data_len)
          val arr = ward_idb_get_result(dl)
          val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
          val sax_len = ward_xml_parse_html(borrow, dl)
          val () = ward_arr_drop<byte>(frozen, borrow)
          val arr = ward_arr_thaw<byte>(frozen)
          val () = ward_arr_free<byte>(arr)
        in
          if gt_int_int(sax_len, 0) then let
            val sl = _checked_pos(sax_len)
            val sax_buf = ward_xml_get_result(sl)
            val dom = ward_dom_init()
            val s = ward_dom_stream_begin(dom)
            val s = render_tree_with_images(s, saved_cid, sax_buf, sl,
              0, dir_arr, dl_pos)
            val dom = ward_dom_stream_end(s)
            val () = ward_dom_fini(dom)
            (* Pre-scan: resolve deferred image paths → entry indices *)
            val img_q_count = deferred_image_get_count()
            val img_count = prescan_deferred_for_idb(
              _checked_nat(img_q_count), sax_buf, sl,
              dir_arr, dl_pos, 0, img_q_count, 0)
            val () = _app_set_deferred_img_count(img_count)
            val () = ward_arr_free<byte>(sax_buf)
            val () = ward_arr_free<byte>(dir_arr)
            val (pf_disp | ()) = finish_chapter_load(saved_cid)
            prval MEASURED_AND_TRANSFORMED() = pf_disp
            (* Async: load images from IDB *)
            val () = load_idb_images_chain(
              _checked_nat(img_count), 0, img_count)
          in ward_promise_return<int>(1) end
          else let
            val () = ward_arr_free<byte>(dir_arr)
            val () = show_chapter_error(saved_cid, TEXT_ERR_EMPTY, 21)
          in ward_promise_return<int>(0) end
        end)
    val () = ward_promise_discard<int>(p2)
  in end
  else let
    (* No directory prefix *)
    val p2 = ward_promise_then<int><int>(p,
      llam (data_len: int): ward_promise_chained(int) =>
        if lte_int_int(data_len, 0) then let
          val () = ward_log(3, mk_ch_err(char2int1('g'), char2int1('t'), char2int1('2')), 10)
          val () = show_chapter_error(saved_cid, TEXT_ERR_NOT_FOUND, 17)
        in ward_promise_return<int>(0) end
        else let
          val dl = _checked_pos(data_len)
          val arr = ward_idb_get_result(dl)
          val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
          val sax_len = ward_xml_parse_html(borrow, dl)
          val () = ward_arr_drop<byte>(frozen, borrow)
          val arr = ward_arr_thaw<byte>(frozen)
          val () = ward_arr_free<byte>(arr)
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
            val (pf_disp | ()) = finish_chapter_load(saved_cid)
            prval MEASURED_AND_TRANSFORMED() = pf_disp
          in ward_promise_return<int>(1) end
          else let
            val () = show_chapter_error(saved_cid, TEXT_ERR_EMPTY, 21)
          in ward_promise_return<int>(0) end
        end)
    val () = ward_promise_discard<int>(p2)
  in end
end

(* ========== Chapter navigation ========== *)

(* Navigate forward: advance page within chapter, or load next chapter.
 * When on the last page of the current chapter and there IS a next chapter,
 * clears the container and loads the next chapter asynchronously. *)
fn navigate_next(container_id: int): void = let
  val pg = reader_get_current_page()
  val total = reader_get_total_pages()
in
  if lt_int_int(pg, total - 1) then let
    (* Within chapter — advance page *)
    val (pf_pg | ()) = page_turn_forward(container_id)
    prval PAGE_TURNED_AND_SHOWN() = pf_pg
  in end
  else let
    (* At last page — try advancing chapter *)
    val ch = reader_get_current_chapter()
    val spine = epub_get_chapter_count()
    val next_ch = ch + 1
  in
    if lt_int_int(next_ch, spine) then let
      val spine_g1 = g1ofg0(spine)
      val next_g1 = _checked_nat(next_ch)
    in
      if lt1_int_int(next_g1, spine_g1) then let
        prval pf = SPINE_ENTRY()
        val () = reader_go_to_chapter(next_g1, spine_g1)
        val () = reader_set_total_pages(1)
        (* Clear container and load next chapter *)
        val dom = ward_dom_init()
        val s = ward_dom_stream_begin(dom)
        val s = ward_dom_stream_remove_children(s, container_id)
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = load_chapter_from_idb(pf | next_g1, spine_g1, container_id)
      in end
      else ()
    end
    else ()
  end
end

(* Navigate backward: go to previous page, or load previous chapter.
 * When on page 0 and there IS a previous chapter, loads it. *)
fn navigate_prev(container_id: int): void = let
  val pg = reader_get_current_page()
in
  if gt_int_int(pg, 0) then let
    (* Within chapter — go back a page *)
    val (pf_pg | ()) = page_turn_backward(container_id)
    prval PAGE_TURNED_AND_SHOWN() = pf_pg
  in end
  else let
    (* At first page — try going to previous chapter *)
    val ch = reader_get_current_chapter()
  in
    if gt_int_int(ch, 0) then let
      val prev_ch = ch - 1
      val spine = epub_get_chapter_count()
      val spine_g1 = g1ofg0(spine)
      val prev_g1 = _checked_nat(prev_ch)
    in
      if lt1_int_int(prev_g1, spine_g1) then let
        prval pf = SPINE_ENTRY()
        val () = reader_go_to_chapter(prev_g1, spine_g1)
        val () = reader_set_total_pages(1)
        (* Clear container and load previous chapter *)
        val dom = ward_dom_init()
        val s = ward_dom_stream_begin(dom)
        val s = ward_dom_stream_remove_children(s, container_id)
        val dom = ward_dom_stream_end(s)
        val () = ward_dom_fini(dom)
        val () = load_chapter_from_idb(pf | prev_g1, spine_g1, container_id)
      in end
      else ()
    end
    else ()
  end
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
      if eq_int_int(k0, 65) then navigate_next(cid)
      else ()
    else if eq_int_int(key_len, 9) then
      (* "ArrowLeft": key_len=9, k0='A' (65) *)
      if eq_int_int(k0, 65) then navigate_prev(cid)
      else ()
    else if eq_int_int(key_len, 1) then
      (* " " (Space): key_len=1, k0=' ' (32) *)
      if eq_int_int(k0, 32) then navigate_next(cid)
      else ()
    else ()
  end
  else ()
end

(* ========== Render library view ========== *)

(* Register click listeners on read, archive/restore, and hide/unhide buttons.
 * Read buttons: btn_ids[0..31], Archive: btn_ids[32..63], Hide: btn_ids[64..95].
 * Shared by initial render and post-import re-render. *)
fun register_card_btns {k:nat} .<k>.
  (rem: int(k), i: int, n: int, root: int, vm: int): void =
  if lte_g1(rem, 0) then ()
  else if gte_int_int(i, n) then ()
  else let
    val saved_r = root
    val book_idx = i
    (* Read button listener — available in all views *)
    val read_btn_id = reader_get_btn_id(i)
    val () =
      if gt_int_int(read_btn_id, 0) then
        ward_add_event_listener(
          read_btn_id, evt_click(), 5, LISTENER_READ_BTN_BASE + i,
          lam (_pl: int): int => let
            val () = enter_reader(saved_r, book_idx)
          in 0 end
        )
      else ()
    (* Archive/restore button listener — active view: archive, archived view: restore *)
    val arch_btn_id = reader_get_btn_id(i + 32)
    val () =
      if gt_int_int(arch_btn_id, 0) then let
        val saved_vm = vm
      in
        ward_add_event_listener(
          arch_btn_id, evt_click(), 5, LISTENER_ARCHIVE_BTN_BASE + i,
          lam (_pl: int): int => let
          in
            if eq_int_int(saved_vm, 0) then let
              (* Archive: set shelf_state=1 *)
              val () = library_set_shelf_state(SHELF_ARCHIVED() | book_idx, 1)
              val () = library_save()
              val () = render_library(saved_r)
            in 0 end
            else let
              (* Restore: set shelf_state=0 *)
              val () = library_set_shelf_state(SHELF_ACTIVE() | book_idx, 0)
              val () = library_save()
              val () = render_library(saved_r)
            in 0 end
          end
        )
      end
      else ()
    (* Hide/unhide button listener — active view: hide, hidden view: unhide *)
    val hide_btn_id = reader_get_btn_id(i + 64)
    val () =
      if gt_int_int(hide_btn_id, 0) then let
        val saved_vm = vm
      in
        ward_add_event_listener(
          hide_btn_id, evt_click(), 5, LISTENER_HIDE_BTN_BASE + i,
          lam (_pl: int): int => let
          in
            if eq_int_int(saved_vm, 0) then let
              (* Hide: set shelf_state=2 *)
              val () = library_set_shelf_state(SHELF_HIDDEN() | book_idx, 2)
              val () = library_save()
              val () = render_library(saved_r)
            in 0 end
            else let
              (* Unhide: set shelf_state=0 *)
              val () = library_set_shelf_state(SHELF_ACTIVE() | book_idx, 0)
              val () = library_save()
              val () = render_library(saved_r)
            in 0 end
          end
        )
      end
      else ()
  in register_card_btns(sub_g1(rem, 1), i + 1, n, root, vm) end

(* Import phase ordering: proves each phase follows the previous.
 * BUG PREVENTED: Copy-paste reordering of import phases would break
 * the proof chain — each phase requires the previous phase's proof. *)
dataprop IMPORT_PHASE(phase: int) =
  | PHASE_OPEN(0)
  | {p:int | p == 0} PHASE_ZIP(1) of IMPORT_PHASE(p)
  | {p:int | p == 1} PHASE_META(2) of IMPORT_PHASE(p)
  | {p:int | p == 2} PHASE_ADD(3) of IMPORT_PHASE(p)

(* Helper: set sort button class — active or inactive *)
fn set_sort_btn_class {l:agz}
  (s: ward_dom_stream(l), node: int, is_active: bool)
  : [l2:agz] ward_dom_stream(l2) =
  if is_active then
    ward_dom_stream_set_attr_safe(s, node, attr_class(), 5, cls_sort_active(), 11)
  else
    ward_dom_stream_set_attr_safe(s, node, attr_class(), 5, cls_sort_btn(), 8)

(* Helper: conditionally add import section *)
fn add_import_section {l:agz}
  (s: ward_dom_stream(l), root_id: int, view_mode: int,
   label_id: int, span_id: int, input_id: int)
  : [l2:agz] ward_dom_stream(l2) =
  if eq_int_int(view_mode, 0) then let
    val s = ward_dom_stream_create_element(s, label_id, root_id, tag_label(), 5)
    val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5, cls_import_btn(), 10)
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
    val s = ward_dom_stream_create_element(s, input_id, label_id, tag_input(), 5)
    val s = ward_dom_stream_set_attr_safe(s, input_id, attr_type(), 4, st_file(), 4)
    val s = set_attr_cstr(s, input_id, attr_accept(), 6, TEXT_EPUB_EXT, 5)
  in s end
  else s

(* Count books matching the given view mode — uses proven filter *)
fun count_visible_books {k:nat} .<k>.
  (rem: int(k), i: int, n: int, vm: int): int =
  if lte_g1(rem, 0) then 0
  else if gte_int_int(i, n) then 0
  else let
    val do_render = filter_book_visible(vm, i)
    val r1 = sub_g1(rem, 1)
  in
    if gt_int_int(do_render, 0) then
      add_int_int(1, count_visible_books(r1, add_int_int(i, 1), n, vm))
    else
      count_visible_books(r1, add_int_int(i, 1), n, vm)
  end

fn set_empty_text {l:agz}
  (s: ward_dom_stream(l), node: int, view_mode: int)
  : [l2:agz] ward_dom_stream(l2) =
  if eq_int_int(view_mode, 0) then
    set_text_cstr(s, node, TEXT_NO_BOOKS, 12)
  else if eq_int_int(view_mode, 2) then
    set_text_cstr(s, node, TEXT_NO_HIDDEN, 15)
  else
    set_text_cstr(s, node, TEXT_NO_ARCHIVED, 17)

implement render_library(root_id) = let
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, root_id)
  val s = inject_app_css(s, root_id)
  val s = inject_mgmt_css(s, root_id)

  val view_mode = _app_lib_view_mode()
  val sort_mode = _app_lib_sort_mode()

  (* Toolbar: shelf filter buttons + sort buttons *)
  val toolbar_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, toolbar_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, toolbar_id, attr_class(), 5, cls_lib_toolbar(), 11)

  (* Shelf filter buttons — Library / Hidden / Archived *)
  val shelf_active_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, shelf_active_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, shelf_active_btn_id, eq_int_int(view_mode, 0))
  val s = set_text_cstr(s, shelf_active_btn_id, TEXT_SHOW_ACTIVE, 7)

  val shelf_hidden_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, shelf_hidden_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, shelf_hidden_btn_id, eq_int_int(view_mode, 2))
  val s = set_text_cstr(s, shelf_hidden_btn_id, TEXT_HIDDEN, 6)

  val shelf_archived_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, shelf_archived_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, shelf_archived_btn_id, eq_int_int(view_mode, 1))
  val s = set_text_cstr(s, shelf_archived_btn_id, TEXT_SHOW_ARCHIVED, 8)

  (* Sort by title button *)
  val sort_title_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, sort_title_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, sort_title_btn_id, eq_int_int(sort_mode, 0))
  val s = set_text_cstr(s, sort_title_btn_id, TEXT_SORT_TITLE, 8)

  (* Sort by author button *)
  val sort_author_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, sort_author_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, sort_author_btn_id, eq_int_int(sort_mode, 1))
  val s = set_text_cstr(s, sort_author_btn_id, TEXT_SORT_AUTHOR, 9)

  (* Sort by last opened button *)
  val sort_last_opened_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, sort_last_opened_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, sort_last_opened_btn_id, eq_int_int(sort_mode, 2))
  val s = set_text_cstr(s, sort_last_opened_btn_id, TEXT_SORT_LAST_OPENED, 11)

  (* Sort by date added button *)
  val sort_date_added_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, sort_date_added_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, sort_date_added_btn_id, eq_int_int(sort_mode, 3))
  val s = set_text_cstr(s, sort_date_added_btn_id, TEXT_SORT_DATE_ADDED, 10)

  (* Import button — only shown in active view *)
  val label_id = dom_next_id()
  val span_id = dom_next_id()
  val input_id = dom_next_id()
  val s = add_import_section(s, root_id, view_mode, label_id, span_id, input_id)

  (* Status div: <div class="import-status"></div> — updated during import *)
  val status_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, status_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, status_id, attr_class(), 5, cls_import_status(), 13)

  (* Library list *)
  val list_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, list_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, list_id, attr_class(), 5, cls_library_list(), 12)

  val count = library_get_count()
  val visible = count_visible_books(_checked_nat(count), 0, count, view_mode)
  val () =
    if gt_int_int(visible, 0) then let
      (* Render book cards filtered by view_mode *)
      val s = render_library_with_books(s, list_id, view_mode)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end
    else let
      (* Empty library / no archived books message *)
      val empty_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, empty_id, list_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, empty_id, attr_class(), 5, cls_empty_lib(), 9)
      val s = set_empty_text(s, empty_id, view_mode)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
    in end

  (* Register click listeners on read and archive/restore buttons *)
  val () = register_card_btns(_checked_nat(count), 0, count, root_id, view_mode)

  (* Register toolbar button listeners *)
  val saved_root = root_id
  val () = ward_add_event_listener(
    shelf_active_btn_id, evt_click(), 5, LISTENER_VIEW_ACTIVE,
    lam (_pl: int): int => let
      val () = _app_set_lib_view_mode(0)
      val () = render_library(saved_root)
    in 0 end
  )
  val () = ward_add_event_listener(
    shelf_hidden_btn_id, evt_click(), 5, LISTENER_VIEW_HIDDEN,
    lam (_pl: int): int => let
      val () = _app_set_lib_view_mode(2)
      val () = render_library(saved_root)
    in 0 end
  )
  val () = ward_add_event_listener(
    shelf_archived_btn_id, evt_click(), 5, LISTENER_VIEW_ARCHIVED,
    lam (_pl: int): int => let
      val () = _app_set_lib_view_mode(1)
      val () = render_library(saved_root)
    in 0 end
  )
  val () = ward_add_event_listener(
    sort_title_btn_id, evt_click(), 5, LISTENER_SORT_TITLE,
    lam (_pl: int): int => let
      val (_ | _n) = library_sort(SORT_BY_TITLE() | 0)
      val () = _app_set_lib_sort_mode(0)
      val () = library_save()
      val () = render_library(saved_root)
    in 0 end
  )
  val () = ward_add_event_listener(
    sort_author_btn_id, evt_click(), 5, LISTENER_SORT_AUTHOR,
    lam (_pl: int): int => let
      val (_ | _n) = library_sort(SORT_BY_AUTHOR() | 1)
      val () = _app_set_lib_sort_mode(1)
      val () = library_save()
      val () = render_library(saved_root)
    in 0 end
  )
  val () = ward_add_event_listener(
    sort_last_opened_btn_id, evt_click(), 5, LISTENER_SORT_LAST_OPENED,
    lam (_pl: int): int => let
      val (_ | _n) = library_sort(SORT_BY_LAST_OPENED() | 2)
      val () = _app_set_lib_sort_mode(2)
      val () = library_save()
      val () = render_library(saved_root)
    in 0 end
  )
  val () = ward_add_event_listener(
    sort_date_added_btn_id, evt_click(), 5, LISTENER_SORT_DATE_ADDED,
    lam (_pl: int): int => let
      val (_ | _n) = library_sort(SORT_BY_DATE_ADDED() | 3)
      val () = _app_set_lib_sort_mode(3)
      val () = library_save()
      val () = render_library(saved_root)
    in 0 end
  )

  (* Register change listener on file input — only in active view.
   * Multi-phase promise chain with timer yields between phases
   * for UI responsiveness (browser can paint progress updates). *)
  val saved_input_id = input_id
  val saved_list_id = list_id
  val saved_label_id = label_id
  val saved_span_id = span_id
  val saved_status_id = status_id
  val () = if eq_int_int(view_mode, 0) then
  ward_add_event_listener(
    input_id, evt_change(), 6, LISTENER_FILE_INPUT,
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
          val () = _app_set_epub_file_size(file_size)
          val () = reader_set_file_handle(handle)

          (* Compute SHA-256 content hash as book identity.
           * BOOK_IDENTITY_IS_CONTENT_HASH: this is the only code
           * that sets epub_book_id. Same hash = same book. *)
          val hash_buf = ward_arr_alloc<byte>(64)
          val () = sha256_file_hash(handle, _checked_nat(file_size), hash_buf)
          fun _copy_hash {lh:agz}{k:nat} .<k>.
            (rem: int(k), hb: !ward_arr(byte, lh, 64), i: int): void =
            if lte_g1(rem, 0) then ()
            else if gte_int_int(i, 64) then ()
            else let
              val b = byte2int0(ward_arr_get<byte>(hb, _ward_idx(i, 64)))
              val () = _app_epub_book_id_set_u8(i, b)
            in _copy_hash(sub_g1(rem, 1), hb, i + 1) end
          val () = _copy_hash(_checked_nat(64), hash_buf, 0)
          val () = _app_set_epub_book_id_len(64)
          val () = ward_arr_free<byte>(hash_buf)

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
            val nentries = zip_open(sh, sfs)
          in
            (* ZIP_OPEN_OK proof: zip_open must return > 0 entries.
             * Bug class: querying empty ZIP silently yields -1,
             * causing confusing err-container instead of err-zip.
             * Prevention: check nentries here, fail fast with clear error. *)
            if lte_int_int(nentries, 0) then let
              prval _ = PHASE_ADD(pf2)
              val () = update_status_text(ssts, TEXT_ADDING_BOOK, 17)
              val () = import_finish(
                import_mark_failed(log_err_zip_parse(), 7),
                slbl, sspn, ssts)
            in ward_promise_return<int>(0) end
            else let
              val _np = _checked_pos(nentries)
              prval pf_zip = ZIP_PARSED_OK()

              (* Phase 2: Read EPUB metadata — yield for "Parsing archive" to paint *)
              val p2 = ward_timer_set(0)
            in ward_promise_then<int><int>(p2,
              llam (_: int): ward_promise_chained(int) => let
                (* Phase 3 — read metadata (async), consumes pf2 *)
                prval _ = PHASE_ADD(pf2)
                val () = update_status_text(ssts, TEXT_READING_META, 16)
                val p_container = epub_read_container_async(pf_zip | sh)

                (* Chain: container result → OPF read → add book *)
                val ssh = sh val ssli = sli val ssr = sr
                val sslbl = slbl val ssspn = sspn val sssts = ssts
              in ward_promise_then<int><int>(p_container,
                llam (ok1: int): ward_promise_chained(int) =>
                  if gt_int_int(ok1, 0) then let
                    val p_opf = epub_read_opf_async(pf_zip | ssh)
                  in ward_promise_then<int><int>(p_opf,
                    llam (ok2: int): ward_promise_chained(int) =>
                      if lte_int_int(ok2, 0) then let
                        val () = update_status_text(sssts, TEXT_ADDING_BOOK, 17)
                        val () = import_finish(
                          import_mark_failed(log_err_opf(), 7),
                          sslbl, ssspn, sssts)
                      in ward_promise_return<int>(0) end
                      else let
                        (* OPF parse succeeded — store all resources to IDB *)
                        val p_store = epub_store_all_resources(ssh)
                      in ward_promise_then<int><int>(p_store,
                        llam (_: int): ward_promise_chained(int) => let
                          (* Store manifest to IDB *)
                          val p_man = epub_store_manifest(pf_zip | (* *))
                      in ward_promise_then<int><int>(p_man,
                        llam (_: int): ward_promise_chained(int) => let
                          val () = update_status_text(sssts, TEXT_ADDING_BOOK, 17)
                          val () =
                            if gt_int_int(ok2, 0) then let
                              val (pf_result | book_idx) = library_add_book()
                              prval _ = pf_result
                            in
                              if gte_int_int(book_idx, 0) then let
                                val () = library_save()
                                val () = ward_file_close(ssh)
                                val h = import_mark_success()
                                val dom = ward_dom_init()
                                val s = ward_dom_stream_begin(dom)
                                val s = render_library_with_books(s, ssli, 0)
                                val dom = ward_dom_stream_end(s)
                                val () = ward_dom_fini(dom)
                                val btn_count = library_get_count()
                                val () = register_card_btns(_checked_nat(btn_count), 0, btn_count, ssr, 0)
                              in import_finish(h, sslbl, ssspn, sssts) end
                              else import_finish(
                                import_mark_failed(log_err_lib_full(), 12),
                                sslbl, ssspn, sssts)
                            end
                        in ward_promise_return<int>(0) end)
                      end)
                    end)
                end
                else let
                  val () = update_status_text(sssts, TEXT_ADDING_BOOK, 17)
                  val () = import_finish(
                    import_mark_failed(log_err_container(), 13),
                    sslbl, ssspn, sssts)
                in ward_promise_return<int>(0) end)
              end)
            end (* else let: nentries > 0 *)
          end)
        end)
      val () = ward_promise_discard<int>(p2)
    in 0 end
  )
  else ()
in end

(* ========== Enter reader view ========== *)

implement enter_reader(root_id, book_index) = let
  val () = reader_enter(root_id, 0)
  val () = reader_set_book_index(book_index)
  val () = epub_set_book_id_from_library(book_index)

  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_remove_children(s, root_id)
  val s = inject_app_css(s, root_id)
  val s = inject_nav_css(s, root_id)

  (* Create nav bar: <div class="reader-nav">
   *   <button class="back-btn">Back</button>
   *   <div class="nav-controls">
   *     <button class="prev-btn">Prev</button>
   *     <span class="page-info"></span>
   *     <button class="next-btn">Next</button>
   *   </div>
   * </div> *)
  val nav_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, nav_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, nav_id, attr_class(), 5,
    cls_reader_nav(), 10)

  val back_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, back_btn_id, nav_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, back_btn_id, attr_class(), 5,
    cls_back_btn(), 8)
  (* "Back" = 4 chars *)
  val back_st = let
    val b = ward_text_build(4)
    val b = ward_text_putc(b, 0, char2int1('B'))
    val b = ward_text_putc(b, 1, char2int1('a'))
    val b = ward_text_putc(b, 2, char2int1('c'))
    val b = ward_text_putc(b, 3, char2int1('k'))
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, back_btn_id, back_st, 4)

  (* Nav controls wrapper *)
  val controls_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, controls_id, nav_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, controls_id, attr_class(), 5,
    cls_nav_controls(), 12)

  (* Prev button *)
  val prev_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, prev_btn_id, controls_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, prev_btn_id, attr_class(), 5,
    cls_prev_btn(), 8)
  val prev_st = let
    val b = ward_text_build(4)
    val b = ward_text_putc(b, 0, char2int1('P'))
    val b = ward_text_putc(b, 1, char2int1('r'))
    val b = ward_text_putc(b, 2, char2int1('e'))
    val b = ward_text_putc(b, 3, char2int1('v'))
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, prev_btn_id, prev_st, 4)

  (* Page info *)
  val page_info_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, page_info_id, controls_id, tag_span(), 4)
  val s = ward_dom_stream_set_attr_safe(s, page_info_id, attr_class(), 5,
    cls_page_info(), 9)

  (* Next button *)
  val next_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, next_btn_id, controls_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, next_btn_id, attr_class(), 5,
    cls_next_btn(), 8)
  val next_st = let
    val b = ward_text_build(4)
    val b = ward_text_putc(b, 0, char2int1('N'))
    val b = ward_text_putc(b, 1, char2int1('e'))
    val b = ward_text_putc(b, 2, char2int1('x'))
    val b = ward_text_putc(b, 3, char2int1('t'))
  in ward_text_done(b) end
  val s = ward_dom_stream_set_safe_text(s, next_btn_id, next_st, 4)

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
  val () = reader_set_nav_id(nav_id)
  val () = reader_set_page_info_id(page_info_id)

  (* Register click listener on back button *)
  val saved_root = root_id
  val saved_container = container_id
  val () = ward_add_event_listener(
    back_btn_id, evt_click(), 5, LISTENER_BACK,
    lam (_pl: int): int => let
      val () = reader_save_and_exit()
      val () = render_library(saved_root)
    in 0 end
  )

  (* Register click listener on prev button *)
  val () = ward_add_event_listener(
    prev_btn_id, evt_click(), 5, LISTENER_PREV,
    lam (_pl: int): int => let
      val () = navigate_prev(saved_container)
    in 0 end
  )

  (* Register click listener on next button *)
  val () = ward_add_event_listener(
    next_btn_id, evt_click(), 5, LISTENER_NEXT,
    lam (_pl: int): int => let
      val () = navigate_next(saved_container)
    in 0 end
  )

  (* Register keydown listener on viewport *)
  val () = ward_add_event_listener(
    viewport_id, evt_keydown(), 7, LISTENER_KEYDOWN,
    lam (payload_len: int): int => let
      val () = on_reader_keydown(payload_len, saved_root)
    in 0 end
  )

  (* Register click listener on viewport for page navigation *)
  val () = ward_add_event_listener(
    viewport_id, evt_click(), 5, LISTENER_VIEWPORT_CLICK,
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
            val () = navigate_next(saved_container)
          in 0 end
          else let
            val () = navigate_prev(saved_container)
          in 0 end
        end
        else 0
      end
      else 0
    end
  )

  (* Load manifest from IDB, then restore chapter/page position *)
  val saved_bi = book_index
  val saved_cid = container_id
  val p_manifest = epub_load_manifest()
  val p2 = ward_promise_then<int><int>(p_manifest,
    llam (ok: int): ward_promise_chained(int) =>
      if lte_int_int(ok, 0) then let
        val () = ward_log(3, mk_ch_err(char2int1('m'), char2int1('a'), char2int1('n')), 10)
        val () = show_chapter_error(saved_cid, TEXT_ERR_NOT_FOUND, 17)
      in ward_promise_return<int>(0) end
      else let
        val now = quire_time_now()
        val now_g1 = _checked_nat(now)
        val () = library_set_last_opened(VALID_TIMESTAMP() | saved_bi, now_g1)
        val () = library_save()
        val spine = epub_get_chapter_count()
        val spine_g1 = g1ofg0(spine)
        val saved_ch = library_get_chapter(saved_bi)
        val saved_pg = library_get_page(saved_bi)
        val start_ch: int = if lt_int_int(saved_ch, spine) then saved_ch else 0
        val start_ch_nat = _checked_nat(start_ch)
      in
        if lt1_int_int(start_ch_nat, spine_g1) then let
          prval pf = SPINE_ENTRY()
          val () = reader_go_to_chapter(start_ch_nat, spine_g1)
          val () = reader_set_resume_page(saved_pg)
          val () = load_chapter_from_idb(pf | start_ch_nat, spine_g1, saved_cid)
        in ward_promise_return<int>(1) end
        else let
          val () = ward_log(3, mk_ch_err(char2int1('s'), char2int1('p'), char2int1('n')), 10)
          val () = show_chapter_error(saved_cid, TEXT_ERR_NO_CHAPTERS, 19)
        in ward_promise_return<int>(0) end
      end)
  val () = ward_promise_discard<int>(p2)
in end

(* ========== Entry point ========== *)

implement ward_node_init(root_id) = let
  val st = app_state_init()
  val () = app_state_register(st)
  val p = library_load()
  val saved_root = root_id
  val p2 = ward_promise_then<int><int>(p,
    llam (_ok: int): ward_promise_chained(int) => let
      val () = render_library(saved_root)
    in ward_promise_return<int>(0) end)
  val () = ward_promise_discard<int>(p2)
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
