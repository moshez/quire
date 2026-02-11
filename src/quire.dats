(* quire.dats — Quire application entry point
 *
 * Renders library view on init using ward DOM stream API.
 * Registers "change" event listener on file input for EPUB import.
 * Import flow: file_open → zip_open → parse container → parse OPF
 *              → library_add_book → render book cards.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./zip.sats"
staload "./epub.sats"
staload "./library.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./../vendor/ward/lib/listener.sats"
staload "./../vendor/ward/lib/file.sats"
staload "./../vendor/ward/lib/promise.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"
staload _ = "./../vendor/ward/lib/listener.dats"
staload _ = "./../vendor/ward/lib/file.dats"
staload _ = "./../vendor/ward/lib/promise.dats"

(* ========== Freestanding arithmetic ========== *)

extern fun add_int_int(a: int, b: int): int = "mac#quire_add"
extern fun gte_int_int(a: int, b: int): bool = "mac#quire_gte"
extern fun gt_int_int(a: int, b: int): bool = "mac#quire_gt"
extern fun eq_int_int(a: int, b: int): bool = "mac#quire_eq"
overload + with add_int_int of 10

(* Runtime-checked positive: used after verifying x > 0 at runtime *)
extern castfn _checked_pos(x: int): [n:pos] int n

(* ========== Text constant IDs (match _text_table in quire_runtime.c) ========== *)

#define TEXT_NO_BOOKS 0
#define TEXT_EPUB_EXT 1
#define TEXT_NOT_STARTED 2
#define TEXT_READ 3

(* C helpers *)
extern fun fill_text {l:agz}{n:pos}
  (arr: !ward_arr(byte, l, n), text_id: int): int = "mac#_fill_text"
extern fun copy_from_sbuf {l:agz}{n:pos}
  (dst: !ward_arr(byte, l, n), len: int n): void = "mac#_copy_from_sbuf"

(* EPUB parsing helpers (implemented in quire_runtime.c) *)
extern fun epub_parse_container_bytes {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): int = "mac#"
extern fun epub_parse_opf_bytes {l:agz}{n:pos}
  (buf: !ward_arr(byte, l, n), len: int n): int = "mac#"
extern fun epub_get_opf_path_ptr(): ptr = "mac#"
extern fun epub_get_opf_path_len(): int = "mac#"
extern fun get_str_container_ptr(): ptr = "mac#"

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

fn cls_book_card(): ward_safe_text(9) = let
  val b = ward_text_build(9)
  val b = ward_text_putc(b, 0, char2int1('b'))
  val b = ward_text_putc(b, 1, char2int1('o'))
  val b = ward_text_putc(b, 2, char2int1('o'))
  val b = ward_text_putc(b, 3, char2int1('k'))
  val b = ward_text_putc(b, 4, 45) (* '-' *)
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
  val b = ward_text_putc(b, 4, 45) (* '-' *)
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
  val b = ward_text_putc(b, 4, 45) (* '-' *)
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
  val b = ward_text_putc(b, 4, 45) (* '-' *)
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
  val b = ward_text_putc(b, 4, 45) (* '-' *)
  val b = ward_text_putc(b, 5, char2int1('b'))
  val b = ward_text_putc(b, 6, char2int1('t'))
  val b = ward_text_putc(b, 7, char2int1('n'))
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

(* ========== Helper: set text content from string buffer ========== *)

fn set_text_from_sbuf {l:agz}
  (s: ward_dom_stream(l), nid: int, len: int)
  : ward_dom_stream(l) = let
  val len1 = g1ofg0(len)
in
  if len1 > 0 then
    if len1 + 7 <= 262144 then let
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

fn render_library_with_books {l:agz}
  (s: ward_dom_stream(l), list_id: int)
  : ward_dom_stream(l) = let
  val s = ward_dom_stream_remove_children(s, list_id)
  val count = library_get_count()
  fun loop {l:agz}(s: ward_dom_stream(l), i: int, n: int): ward_dom_stream(l) =
    if gte_int_int(i, n) then s
    else let
      (* div.book-card *)
      val card_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, card_id, list_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, card_id, attr_class(), 5, cls_book_card(), 9)

      (* div.book-title *)
      val title_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, title_id, card_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, title_id, attr_class(), 5, cls_book_title(), 10)
      val title_len = library_get_title(i, 0)
      val s = set_text_from_sbuf(s, title_id, title_len)

      (* div.book-author *)
      val author_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, author_id, card_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, author_id, attr_class(), 5, cls_book_author(), 11)
      val author_len = library_get_author(i, 0)
      val s = set_text_from_sbuf(s, author_id, author_len)

      (* div.book-position *)
      val pos_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, pos_id, card_id, tag_div(), 3)
      val s = ward_dom_stream_set_attr_safe(s, pos_id, attr_class(), 5, cls_book_position(), 13)
      val s = set_text_cstr(s, pos_id, TEXT_NOT_STARTED, 11)

      (* button.read-btn *)
      val btn_id = dom_next_id()
      val s = ward_dom_stream_create_element(s, btn_id, card_id, tag_button(), 6)
      val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_read_btn(), 8)
      val s = set_text_cstr(s, btn_id, TEXT_READ, 4)
    in loop(s, i + 1, n) end
in loop(s, 0, count) end

(* ========== Entry point ========== *)

implement ward_node_init(root_id) = let
  (* Initialize app state and register in callback stash *)
  val st = app_state_init()
  val () = app_state_register(st)

  (* Initialize DOM and render library view *)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)

  (* Clear "Loading..." text from root *)
  val s = ward_dom_stream_remove_children(s, root_id)

  (* Import button: <label class="import-btn">Import<input ...></label> *)
  val label_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, label_id, root_id, tag_label(), 5)
  val s = ward_dom_stream_set_attr_safe(s, label_id, attr_class(), 5, cls_import_btn(), 10)

  (* "Import" text *)
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

  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)

  (* Capture IDs for the event listener closure *)
  val saved_input_id = input_id
  val saved_list_id = list_id

  (* Register "change" event listener on file input *)
  val () = ward_add_event_listener(
    input_id, evt_change(), 6, 1,
    lam (_payload_len: int): int => let
      val p = ward_file_open(saved_input_id)
      val p2 = ward_promise_then<int><int>(p,
        llam (handle: int): ward_promise_pending(int) => let
          val file_size = ward_file_get_size()
          val _nentries = zip_open(handle, file_size)
          val ok1 = epub_read_container(handle)
          val ok2 = (if gt_int_int(ok1, 0)
            then epub_read_opf(handle) else 0): int
          val _book_idx = (if gt_int_int(ok2, 0)
            then library_add_book() else 0 - 1): int
          (* Re-render library list with book cards *)
          val dom = ward_dom_init()
          val s = ward_dom_stream_begin(dom)
          val s = render_library_with_books(s, saved_list_id)
          val dom = ward_dom_stream_end(s)
          val () = ward_dom_fini(dom)
        in ward_promise_return<int>(0) end)
      val () = ward_promise_discard<int>(p2)
    in 0 end
  )
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
