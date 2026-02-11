(* quire.dats — Quire application entry point
 *
 * Renders library view on init using ward DOM stream API.
 * All UI built through ward's typed diff protocol.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"

(* ========== Text constant IDs (match _text_table in quire_runtime.c) ========== *)

#define TEXT_NO_BOOKS 0
#define TEXT_EPUB_EXT 1
#define TEXT_NOT_STARTED 2

(* C helper to fill ward_arr with text constant bytes *)
extern fun fill_text {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), text_id: int): int = "mac#_fill_text"

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

(* ========== Helper: set text content from C string constant ========== *)

fn set_text_cstr {l:agz}
  (s: ward_dom_stream(l), nid: int, text_id: int, text_len: int)
  : ward_dom_stream(l) = let
  val tl = g1ofg0(text_len)
in
  if tl > 0 then
    if tl + 7 <= 262144 then let
      val arr = ward_arr_alloc<byte>(tl)
      val _ = fill_text(arr, text_id)
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

fn set_attr_cstr {l:agz}{nl:pos}
  (s: ward_dom_stream(l), nid: int,
   aname: ward_safe_text(nl), nl_v: int nl,
   text_id: int, text_len: int)
  : ward_dom_stream(l) = let
  val vl = g1ofg0(text_len)
in
  if vl > 0 then
    if nl_v + vl + 8 <= 262144 then let
      val arr = ward_arr_alloc<byte>(vl)
      val _ = fill_text(arr, text_id)
      val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
      val s = ward_dom_stream_set_attr(s, nid, aname, nl_v, borrow, vl)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val arr = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(arr)
    in s end
    else s
  else s
end

(* ========== Library view rendering ========== *)

fn render_library_view {l:agz}
  (s: ward_dom_stream(l), root_id: int)
  : ward_dom_stream(l) = let

  (* Clear "Loading..." text from root *)
  val s = ward_dom_stream_remove_children(s, root_id)

  (* Import button: <label class="import-btn">Import<input ...></label> *)
  val label_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, label_id, root_id, tag_label(), 5)
  val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5, cls_import_btn(), 10)

  (* "Import" text — all safe chars (I=73, m,p,o,r,t = a-z) *)
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

  (* File input: <input type="file" accept=".epub"> *)
  val input_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, input_id, label_id, tag_input(), 5)
  val s = ward_dom_stream_set_attr_safe(s, input_id, attr_type(), 4, st_file(), 4)
  val s = set_attr_cstr(s, input_id, attr_accept(), 6, TEXT_EPUB_EXT, 5)

  (* Library list: <div class="library-list"> *)
  val list_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, list_id, root_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, list_id, attr_class(), 5, cls_library_list(), 12)

  (* Empty message: <div class="empty-lib">No books yet</div> *)
  val empty_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, empty_id, list_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, empty_id, attr_class(), 5, cls_empty_lib(), 9)
  val s = set_text_cstr(s, empty_id, TEXT_NO_BOOKS, 12)

in s end

(* ========== Entry point ========== *)

implement ward_node_init(root_id) = let
  (* Initialize app state and register in callback stash *)
  val st = app_state_init()
  val () = app_state_register(st)

  (* Initialize DOM and render library view *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = render_library_view(s, root_id)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
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
