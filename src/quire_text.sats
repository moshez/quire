(* quire_text.sats — Text constant definitions and helper declarations *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"

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
#define TEXT_ERR_MANIFEST 29
#define TEXT_DUP_SKIP 30
#define TEXT_DUP_REPLACE 31
#define TEXT_DUP_MSG 32
#define TEXT_RESET 33
#define TEXT_RESET_MSG 34
#define TEXT_CANCEL 35
#define TEXT_NOT_VALID_EPUB 36
#define TEXT_DRM_MSG 37
#define TEXT_NEW 38
#define TEXT_DONE 39
#define TEXT_BOOK_INFO 40
#define TEXT_DELETE 41
#define TEXT_PROGRESS 42
#define TEXT_ADDED 43
#define TEXT_LAST_READ 44
#define TEXT_SIZE 45
#define TEXT_BACK 46
#define TEXT_OF 47

(* ========== Text constant type proof ========== *)
(* VALID_TEXT(id, len) proves text_id maps to the correct byte length.
 * Prevents: calling set_text_cstr with wrong length, or with an id
 * that has no fill_text arm. *)
dataprop VALID_TEXT(id: int, len: int) =
  | VT_0(0, 12)   (* "No books yet" *)
  | VT_1(1, 5)    (* ".epub" *)
  | VT_2(2, 11)   (* "Not started" *)
  | VT_3(3, 4)    (* "Read" *)
  | VT_4(4, 9)    (* "Importing" *)
  | VT_5(5, 12)   (* "Opening file" *)
  | VT_6(6, 15)   (* "Parsing archive" *)
  | VT_7(7, 16)   (* "Reading metadata" *)
  | VT_8(8, 17)   (* "Adding to library" *)
  | VT_9(9, 17)   (* "Chapter not found" *)
  | VT_10(10, 19) (* "Cannot read chapter" *)
  | VT_11(11, 18) (* "Unsupported format" *)
  | VT_12(12, 20) (* "Decompression failed" *)
  | VT_13(13, 21) (* "Chapter content empty" *)
  | VT_14(14, 19) (* "No chapters in book" *)
  | VT_15(15, 14) (* "Page too dense" *)
  | VT_16(16, 8)  (* "Archived" *)
  | VT_17(17, 7)  (* "Library" *)
  | VT_18(18, 8)  (* "By title" *)
  | VT_19(19, 9)  (* "By author" *)
  | VT_20(20, 7)  (* "Archive" *)
  | VT_21(21, 7)  (* "Restore" *)
  | VT_22(22, 17) (* "No archived books" *)
  | VT_23(23, 11) (* "Last opened" *)
  | VT_24(24, 10) (* "Date added" *)
  | VT_25(25, 6)  (* "Hidden" *)
  | VT_26(26, 15) (* "No hidden books" *)
  | VT_27(27, 4)  (* "Hide" *)
  | VT_28(28, 6)  (* "Unhide" *)
  | VT_29(29, 13) (* "Import failed" *)
  | VT_30(30, 4)  (* "Skip" *)
  | VT_31(31, 7)  (* "Replace" *)
  | VT_32(32, 18) (* "Already in library" *)
  | VT_33(33, 5)  (* "Reset" *)
  | VT_34(34, 16) (* "Delete all data?" *)
  | VT_35(35, 6)  (* "Cancel" *)
  | VT_36(36, 26) (* " is not a valid ePub file." *)
  | VT_37(37, 39) (* "Quire supports .epub files without DRM." *)
  | VT_38(38, 3)  (* "New" *)
  | VT_39(39, 4)  (* "Done" *)
  | VT_40(40, 9)  (* "Book info" *)
  | VT_41(41, 6)  (* "Delete" *)
  | VT_42(42, 8)  (* "Progress" *)
  | VT_43(43, 5)  (* "Added" *)
  | VT_44(44, 9)  (* "Last read" *)
  | VT_45(45, 4)  (* "Size" *)
  | VT_46(46, 4)  (* "Back" *)
  | VT_47(47, 4)  (* " of " *)

(* ========== Function declarations ========== *)

(* Byte write to ward_arr -- wraps ward_arr_write_byte with castfn index *)
fun ward_arr_set_byte {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), off: int, len: int n, v: int): void

(* Fill ward_arr with text constant bytes *)
fun fill_text {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, text_id: int): void

(* Copy len bytes from string_buffer to ward_arr *)
fun copy_from_sbuf {l:agz}{n:pos}
  (dst: !ward_arr(byte, l, n), len: int n): void

(* Set text content from C string constant *)
fun set_text_cstr {l:agz}{tid:nat}{tl:pos | tl < 65536}
  (pf: VALID_TEXT(tid, tl) |
   s: ward_dom_stream(l), nid: int, text_id: int(tid), text_len: int(tl))
  : ward_dom_stream(l)

(* Set text content from string buffer *)
fun set_text_from_sbuf {l:agz}
  (s: ward_dom_stream(l), nid: int, len: int)
  : ward_dom_stream(l)

(* Set attribute with C string value *)
fun set_attr_cstr {l:agz}{nl:pos | nl < 256}
  (s: ward_dom_stream(l), nid: int,
   aname: ward_safe_text(nl), nl_v: int nl,
   text_id: int, text_len: int)
  : ward_dom_stream(l)

(* Write 4-byte little-endian integer to ward_arr *)
fun _w4 {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), alen: int n, off: int, v: int): void
