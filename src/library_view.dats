(* library_view.dats — Library view rendering implementation
 *
 * Extracted from quire.dats: render_library, render_library_with_books,
 * register_card_btns, register_ctx_listeners, load_library_covers,
 * count_visible_books, and supporting helpers.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./quire.sats"
staload "./quire_ui.sats"
staload "./library_view.sats"
staload "./quire_text.sats"
staload "./ui_classes.sats"
staload "./quire_css.sats"
staload "./import_ui.sats"
staload "./modals.sats"
staload "./context_menu.sats"
staload "./book_info.sats"
staload "./app_state.sats"
staload "./dom.sats"
staload "./arith.sats"
staload "./library.sats"
staload "./epub.sats"
staload "./reader.sats"
staload "./sha256.sats"
staload "./zip.sats"
staload "./quire_ext.sats"
staload "./buf.sats"
staload "./settings.sats"
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

%{
extern void quireSetTitle(int mode);
extern int quire_time_now(void);
%}

(* ========== Local castfn declarations ========== *)

extern castfn _idx48(x: int): [i:nat | i < 48] int i
extern castfn _byte {c:int | 0 <= c; c <= 255} (c: int c): byte
extern castfn _mk_book_access(x: int): [i:nat | i < 32] (BOOK_ACCESS_SAFE(i) | int(i))
extern castfn _checked_spine_count(x: int): [n:nat | n <= 256] int n

(* ========== itoa_to_arr — integer to ASCII in ward_arr ========== *)

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

(* ========== Render book cards into library list ========== *)

(* Set inline style "width:XX%" on a node via ward_dom_stream_set_style.
 * pct must be 1-100. Builds "width:X%" (7-10 bytes) in a 48-byte arr. *)
fn _set_width_pct {l:agz}
  (s: ward_dom_stream(l), nid: int, pct: int)
  : ward_dom_stream(l) = let
  val arr = ward_arr_alloc<byte>(48)
  (* "width:" = 6 bytes *)
  val () = ward_arr_set<byte>(arr, 0, _byte(char2int1('w')))
  val () = ward_arr_set<byte>(arr, 1, _byte(char2int1('i')))
  val () = ward_arr_set<byte>(arr, 2, _byte(char2int1('d')))
  val () = ward_arr_set<byte>(arr, 3, _byte(char2int1('t')))
  val () = ward_arr_set<byte>(arr, 4, _byte(char2int1('h')))
  val () = ward_arr_set<byte>(arr, 5, _byte(58)) (* ':' *)
  val ndigits = itoa_to_arr(arr, pct, 6)
  val pct_off = 6 + ndigits
  val () = ward_arr_set<byte>(arr, _idx48(pct_off), _byte(37)) (* '%' *)
  val total_len = pct_off + 1
  val tl = g1ofg0(total_len)
in
  if tl > 0 then
    if tl < 48 then let
      val @(used, rest) = ward_arr_split<byte>(arr, tl)
      val () = ward_arr_free<byte>(rest)
      val @(frozen, borrow) = ward_arr_freeze<byte>(used)
      val s = ward_dom_stream_set_style(s, nid, borrow, tl)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val used = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(used)
    in s end
    else let val () = ward_arr_free<byte>(arr) in s end
  else let val () = ward_arr_free<byte>(arr) in s end
end

(* Build "XX%" text in a ward_arr(48) and set as text on node. *)
fn _set_pct_text {l:agz}
  (s: ward_dom_stream(l), nid: int, pct: int)
  : ward_dom_stream(l) = let
  val arr = ward_arr_alloc<byte>(48)
  val ndigits = itoa_to_arr(arr, pct, 0)
  val () = ward_arr_set<byte>(arr, _idx48(ndigits), _byte(37)) (* '%' *)
  val total_len = ndigits + 1
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

(* Render progress bar with fill + percentage text as children of parent.
 * Creates: <div class="pbar"><div class="pfill" style="width:X%"></div></div>
 * and then a TEXT_RENDER_SAFE span with "X%" text. *)
fn _render_progress_elements {l:agz}
  (s: ward_dom_stream(l), parent_id: int, pct: int)
  : ward_dom_stream(l) = let
  val track_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, track_id, parent_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, track_id, attr_class(), 5, cls_pbar(), 4)
  val fill_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, fill_id, track_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, fill_id, attr_class(), 5, cls_pfill(), 5)
  val s = _set_width_pct(s, fill_id, pct)
  (* Percentage text in a span — TEXT_RENDER_SAFE: parent has children *)
  val pct_span_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, pct_span_id, parent_id, tag_span(), 4)
  val s = _set_pct_text(s, pct_span_id, pct)
in s end

(* Render "Done" with full progress bar as children of parent.
 * Creates: <div class="pbar"><div class="pfill" style="width:100%"></div></div>
 * and then a TEXT_RENDER_SAFE span with "Done" text. *)
fn _render_done_elements {l:agz}
  (s: ward_dom_stream(l), parent_id: int)
  : ward_dom_stream(l) = let
  val track_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, track_id, parent_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, track_id, attr_class(), 5, cls_pbar(), 4)
  val fill_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, fill_id, track_id, tag_div(), 3)
  val s = ward_dom_stream_set_attr_safe(s, fill_id, attr_class(), 5, cls_pfill(), 5)
  val s = _set_width_pct(s, fill_id, 100)
  (* "Done" text in a span — TEXT_RENDER_SAFE: parent has children *)
  val done_span_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, done_span_id, parent_id, tag_span(), 4)
  val s = set_text_cstr(VT_39() | s, done_span_id, 39, 4)
in s end

(* Render book reading progress into the .book-position element.
 * PROGRESS_DISPLAY dataprop ensures correct state classification:
 * - New (ch=0, pg=0): text "New", no bar
 * - Done (ch >= sc, sc > 0): full bar + "Done" text
 * - In progress: partial bar + "X%" text *)
fn render_book_progress {l:agz}{ch:nat}{pg:nat}{sc:nat}
  (s: ward_dom_stream(l), nid: int, ch: int(ch), pg: int(pg), sc: int(sc))
  : ward_dom_stream(l) =
  if eq_g1(ch, 0) then
    if eq_g1(pg, 0) then let
      prval _ = PROGRESS_NEW() : PROGRESS_DISPLAY(0, 0, sc, 0)
    in set_text_cstr(VT_38() | s, nid, 38, 3) end (* "New" *)
    else let
      prval _ = PROGRESS_READING() : PROGRESS_DISPLAY(0, pg, sc, 2)
      (* ch=0, pg>0: very early in the book — show 1% *)
    in _render_progress_elements(s, nid, 1) end
  else if gt_g1(sc, 0) then
    if gte_g1(ch, sc) then let
      prval _ = PROGRESS_DONE() : PROGRESS_DISPLAY(ch, pg, sc, 1)
    in _render_done_elements(s, nid) end
    else let
      prval _ = PROGRESS_READING() : PROGRESS_DISPLAY(ch, pg, sc, 2)
      (* Calculate percentage: ch * 100 / sc, clamped to [1, 99] *)
      val raw_pct = div_int_int(mul_int_int(ch, 100), sc)
      val pct = if gt_int_int(raw_pct, 99) then 99
                else if gt_int_int(1, raw_pct) then 1
                else raw_pct
    in _render_progress_elements(s, nid, pct) end
  else let
    (* sc=0 but ch>0 — defensive fallback, show as in-progress at 1% *)
    prval _ = PROGRESS_READING() : PROGRESS_DISPLAY(ch, pg, 0, 2)
  in _render_progress_elements(s, nid, 1) end

(* ========== Book visibility filter ========== *)

implement filter_book_visible(vm, book_idx) = let
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

(* Cover queue: stored in fetch buffer during library render.
 * Layout: fbuf[0..3] = count, fbuf[4..131] = nids (32 i32),
 *         fbuf[132..259] = bidxs (32 i32).
 * Safe: fbuf is unused between import and next serialize. *)
fn _cover_queue_reset(): void =
  _app_fbuf_set_u8(0, 0)

fn _cover_queue_record(nid: int, bidx: int): void = let
  val cnt = _app_fbuf_get_u8(0)
in
  if gte_int_int(cnt, 32) then ()
  else let
    val nid_off = 4 + cnt * 4
    val bidx_off = 132 + cnt * 4
    val () = _app_fbuf_set_u8(nid_off, band_int_int(nid, 255))
    val () = _app_fbuf_set_u8(nid_off + 1, band_int_int(bsr_int_int(nid, 8), 255))
    val () = _app_fbuf_set_u8(nid_off + 2, band_int_int(bsr_int_int(nid, 16), 255))
    val () = _app_fbuf_set_u8(nid_off + 3, band_int_int(bsr_int_int(nid, 24), 255))
    val () = _app_fbuf_set_u8(bidx_off, band_int_int(bidx, 255))
    val () = _app_fbuf_set_u8(bidx_off + 1, band_int_int(bsr_int_int(bidx, 8), 255))
    val () = _app_fbuf_set_u8(bidx_off + 2, band_int_int(bsr_int_int(bidx, 16), 255))
    val () = _app_fbuf_set_u8(bidx_off + 3, band_int_int(bsr_int_int(bidx, 24), 255))
    val () = _app_fbuf_set_u8(0, cnt + 1)
  in end
end

fn _cover_queue_count(): int = _app_fbuf_get_u8(0)

fn _cover_queue_get_nid(idx: int): int = let
  val off = 4 + idx * 4
  val b0 = _app_fbuf_get_u8(off)
  val b1 = _app_fbuf_get_u8(off + 1)
  val b2 = _app_fbuf_get_u8(off + 2)
  val b3 = _app_fbuf_get_u8(off + 3)
in bor_int_int(bor_int_int(b0, bsl_int_int(b1, 8)),
               bor_int_int(bsl_int_int(b2, 16), bsl_int_int(b3, 24))) end

fn _cover_queue_get_bidx(idx: int): int = let
  val off = 132 + idx * 4
  val b0 = _app_fbuf_get_u8(off)
  val b1 = _app_fbuf_get_u8(off + 1)
  val b2 = _app_fbuf_get_u8(off + 2)
  val b3 = _app_fbuf_get_u8(off + 3)
in bor_int_int(bor_int_int(b0, bsl_int_int(b1, 8)),
               bor_int_int(bsl_int_int(b2, 16), bsl_int_int(b3, 24))) end

fn _maybe_add_cover {l:agz}
  (s: ward_dom_stream(l), has_cover: int, parent_id: int, book_idx: int)
  : ward_dom_stream(l) =
  if gt_int_int(has_cover, 0) then let
    val img_id = dom_next_id()
    val s = ward_dom_stream_create_element(s, img_id, parent_id, tag_img(), 3)
    val s = ward_dom_stream_set_attr_safe(s, img_id, attr_class(), 5, cls_book_cover(), 10)
    val () = _cover_queue_record(img_id, book_idx)
  in s end
  else s

(* ========== render_library_with_books ========== *)

implement render_library_with_books(s, list_id, view_mode) = let
  val () = _cover_queue_reset()
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
        val () = reader_set_btn_id(i + 96, card_id)
        val s = ward_dom_stream_create_element(s, card_id, list_id, tag_div(), 3)
        val s = ward_dom_stream_set_attr_safe(s, card_id, attr_class(), 5, cls_book_card(), 9)

        val s = _maybe_add_cover(s, library_get_has_cover(i), card_id, i)

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
        val s = render_book_progress(s, pos_id, library_get_chapter(i), library_get_page(i), library_get_spine_count(i))

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
          val s = set_text_cstr(VT_3() | s, btn_id, 3, 4)

          val hide_btn_id = dom_next_id()
          val () = reader_set_btn_id(i + 64, hide_btn_id)
          val s = ward_dom_stream_create_element(s, hide_btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, hide_btn_id, attr_class(), 5, cls_hide_btn(), 8)
          val s = set_text_cstr(VT_27() | s, hide_btn_id, 27, 4)

          val arch_btn_id = dom_next_id()
          val () = reader_set_btn_id(i + 32, arch_btn_id)
          val s = ward_dom_stream_create_element(s, arch_btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, arch_btn_id, attr_class(), 5, cls_archive_btn(), 11)
          val s = set_text_cstr(VT_20() | s, arch_btn_id, 20, 7)
        in loop(sub_g1(rem, 1), s, i + 1, n, vm) end
        else if eq_int_int(vm, 2) then let
          (* Hidden view: Read + Unhide buttons *)
          val btn_id = dom_next_id()
          val () = reader_set_btn_id(i, btn_id)
          val s = ward_dom_stream_create_element(s, btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, btn_id, attr_class(), 5, cls_read_btn(), 8)
          val s = set_text_cstr(VT_3() | s, btn_id, 3, 4)

          val unhide_btn_id = dom_next_id()
          val () = reader_set_btn_id(i + 64, unhide_btn_id)
          val s = ward_dom_stream_create_element(s, unhide_btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, unhide_btn_id, attr_class(), 5, cls_hide_btn(), 8)
          val s = set_text_cstr(VT_28() | s, unhide_btn_id, 28, 6)
        in loop(sub_g1(rem, 1), s, i + 1, n, vm) end
        else let
          (* Archived view: Restore only (no Read — IDB content deleted) *)
          val () = reader_set_btn_id(i, 0)

          val restore_btn_id = dom_next_id()
          val () = reader_set_btn_id(i + 32, restore_btn_id)
          val s = ward_dom_stream_create_element(s, restore_btn_id, actions_id, tag_button(), 6)
          val s = ward_dom_stream_set_attr_safe(s, restore_btn_id, attr_class(), 5, cls_archive_btn(), 11)
          val s = set_text_cstr(VT_21() | s, restore_btn_id, 21, 7)
        in loop(sub_g1(rem, 1), s, i + 1, n, vm) end
      end
      else loop(sub_g1(rem, 1), s, i + 1, n, vm)
    end
in loop(_checked_nat(count), s, 0, count, vm_raw) end

(* ========== register_card_btns ========== *)

implement register_card_btns(rem, i, n, root, vm) =
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
              (* Archive: set shelf_state=1 and delete IDB content *)
              val () = library_set_shelf_state(SHELF_ARCHIVED() | book_idx, 1)
              (* Copy book_id from library to epub module for key building *)
              val bi0 = g1ofg0(book_idx)
              val cnt = library_get_count()
              val ok = check_book_index(bi0, cnt)
              val () = if eq_g1(ok, 1) then let
                val (pf_ba | biv) = _mk_book_access(book_idx)
                val _ = epub_set_book_id_from_library(pf_ba | biv)
                val sc0 = library_get_spine_count(book_idx)
                val sc = (if lte_g1(sc0, 256) then sc0 else 256): int
                val () = epub_delete_book_data(_checked_spine_count(sc))
              in end
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

(* ========== register_ctx_listeners ========== *)

implement register_ctx_listeners(rem, i, n, root, vm) =
  if lte_g1(rem, 0) then ()
  else if gte_int_int(i, n) then ()
  else let
    val card_id = reader_get_btn_id(i + 96)
    val saved_r = root
    val saved_bi = i
    val saved_vm = vm
    val () =
      if gt_int_int(card_id, 0) then
        ward_add_event_listener(
          card_id, evt_contextmenu(), 11, LISTENER_CTX_BASE + i,
          lam (_pl: int): int => let
            val () = ward_prevent_default()
          in
            if eq_int_int(saved_vm, 0) then let
              val () = show_context_menu(CTX_ACTIVE() | saved_bi, saved_r, 0, 1, 1)
            in 0 end
            else if eq_int_int(saved_vm, 1) then let
              val () = show_context_menu(CTX_ARCHIVED() | saved_bi, saved_r, 1, 0, 1)
            in 0 end
            else let
              val () = show_context_menu(CTX_HIDDEN() | saved_bi, saved_r, 2, 1, 0)
            in 0 end
          end
        )
      else ()
  in register_ctx_listeners(sub_g1(rem, 1), i + 1, n, root, vm) end

(* ========== Helpers for render_library ========== *)

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
implement count_visible_books(rem, i, n, vm) =
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
    set_text_cstr(VT_0() | s, node, 0, 12)
  else if eq_int_int(view_mode, 2) then
    set_text_cstr(VT_26() | s, node, 26, 15)
  else
    set_text_cstr(VT_22() | s, node, 22, 17)

(* ========== load_library_covers ========== *)

implement load_library_covers(rem, idx, total) =
  if lte_g1(rem, 0) then ()
  else if gte_int_int(idx, total) then ()
  else let
    val nid = _cover_queue_get_nid(idx)
    val bidx0 = _cover_queue_get_bidx(idx)
    val bidx = g1ofg0(bidx0)
    val cnt = library_get_count()
    val ok = check_book_index(bidx, cnt)
  in
    if eq_g1(ok, 1) then let
      val (pf_ba | bi) = _mk_book_access(bidx0)
      val _ = epub_set_book_id_from_library(pf_ba | bi)
      val key = epub_build_cover_key()
      val p = ward_idb_get(key, 20)
      val saved_nid = nid
      val saved_rem = sub_g1(rem, 1)
      val saved_next = idx + 1
      val saved_total = total
      val p2 = ward_promise_then<int><int>(p,
        llam (data_len: int): ward_promise_chained(int) =>
          if lte_int_int(data_len, 0) then let
            val () = load_library_covers(saved_rem, saved_next, saved_total)
          in ward_promise_return<int>(0) end
          else let
            val dl = _checked_pos(data_len)
            val arr = ward_idb_get_result(dl)
            val () = set_image_src_idb(saved_nid, arr, dl)
            val () = load_library_covers(saved_rem, saved_next, saved_total)
          in ward_promise_return<int>(1) end)
      val () = ward_promise_discard<int>(p2)
    in end
    else load_library_covers(sub_g1(rem, 1), idx + 1, total)
  end

(* ========== IDB-based image loading from IDB ========== *)

(* Detect MIME type from image data magic bytes.
 * Returns: 1=jpeg, 2=png, 3=gif, 4=svg+xml, 0=unknown *)
implement detect_mime_from_magic {lb}{n}
  (arr, len) =
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
implement set_image_src_idb {lb}{n}
  (node_id, data, data_len) = let
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

(* ========== render_library ========== *)

implement render_library(root_id) = let
  val () = dismiss_book_info()
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
  val s = set_text_cstr(VT_17() | s, shelf_active_btn_id, 17, 7)

  val shelf_hidden_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, shelf_hidden_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, shelf_hidden_btn_id, eq_int_int(view_mode, 2))
  val s = set_text_cstr(VT_25() | s, shelf_hidden_btn_id, 25, 6)

  val shelf_archived_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, shelf_archived_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, shelf_archived_btn_id, eq_int_int(view_mode, 1))
  val s = set_text_cstr(VT_16() | s, shelf_archived_btn_id, 16, 8)

  (* Sort by title button *)
  val sort_title_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, sort_title_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, sort_title_btn_id, eq_int_int(sort_mode, 0))
  val s = set_text_cstr(VT_18() | s, sort_title_btn_id, 18, 8)

  (* Sort by author button *)
  val sort_author_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, sort_author_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, sort_author_btn_id, eq_int_int(sort_mode, 1))
  val s = set_text_cstr(VT_19() | s, sort_author_btn_id, 19, 9)

  (* Sort by last opened button *)
  val sort_last_opened_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, sort_last_opened_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, sort_last_opened_btn_id, eq_int_int(sort_mode, 2))
  val s = set_text_cstr(VT_23() | s, sort_last_opened_btn_id, 23, 11)

  (* Sort by date added button *)
  val sort_date_added_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, sort_date_added_btn_id, toolbar_id, tag_button(), 6)
  val s = set_sort_btn_class(s, sort_date_added_btn_id, eq_int_int(sort_mode, 3))
  val s = set_text_cstr(VT_24() | s, sort_date_added_btn_id, 24, 10)

  (* Reset button *)
  val reset_btn_id = dom_next_id()
  val s = ward_dom_stream_create_element(s, reset_btn_id, toolbar_id, tag_button(), 6)
  val s = ward_dom_stream_set_attr_safe(s, reset_btn_id, attr_class(), 5, cls_sort_btn(), 8)
  val s = set_text_cstr(VT_33() | s, reset_btn_id, 33, 5)

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
  val () = register_ctx_listeners(_checked_nat(count), 0, count, root_id, view_mode)

  (* Load cover images from IDB *)
  val cvr_count = _cover_queue_count()
  val () = if gt_int_int(cvr_count, 0) then
    load_library_covers(_checked_nat(cvr_count), 0, cvr_count)

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
  val () = ward_add_event_listener(
    reset_btn_id, evt_click(), 5, LISTENER_RESET_BTN,
    lam (_pl: int): int => let
      val () = render_reset_modal(saved_root)
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
      (* Phase 0 — visual setup + render import progress card *)
      val () = dismiss_error_banner()
      val () = ward_log(1, log_import_start(), 12)
      val () = quire_set_title(1)
      val () = update_import_label_class(saved_label_id, 1)
      val () = update_status_text(VT_4() | saved_span_id, 4, 9)
      val (pf0 | imp_card, imp_bar, imp_stat) =
        render_import_card(saved_list_id, saved_root)

      val p = ward_file_open(saved_input_id)
      val p2 = ward_promise_then<int><int>(p,
        llam (handle: int): ward_promise_chained(int) => let
          (* Phase 1 — file open complete, consumes pf0 *)
          prval pf1 = IDP_ZIP(pf0)
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
          val sbar = imp_bar val sstat = imp_stat val scard = imp_card
        in ward_promise_then<int><int>(p1,
          llam (_: int): ward_promise_chained(int) => let
            (* Phase 2 — parse ZIP, consumes pf1 *)
            prval pf2 = IDP_META(pf1)
            val () = update_import_bar(PHASE_ZIP_PARSE() | sbar, 30)
            val () = update_status_text(VT_6() | sstat, 6, 15)
            val nentries = zip_open(sh, sfs)
          in
            (* ZIP_OPEN_OK proof: zip_open must return > 0 entries.
             * Bug class: querying empty ZIP silently yields -1,
             * causing confusing err-container instead of err-zip.
             * Prevention: check nentries here, fail fast with clear error. *)
            if lte_int_int(nentries, 0) then let
              prval pf_term = PTERMINAL_ERR(pf2)
              val () = render_error_banner(sr)
              val () = import_finish_with_card(
                pf_term |
                import_mark_failed(log_err_zip_parse(), 7),
                scard, slbl, sspn, ssts)
            in ward_promise_return<int>(0) end
            else let
              val _np = _checked_pos(nentries)
              prval pf_zip = ZIP_PARSED_OK()

              (* Phase 2: Read EPUB metadata — yield for "Parsing archive" to paint *)
              val p2 = ward_timer_set(0)
            in ward_promise_then<int><int>(p2,
              llam (_: int): ward_promise_chained(int) => let
                (* Phase 3 — read metadata (async), consumes pf2 *)
                prval pf3 = IDP_ADD(pf2)
                val () = update_import_bar(PHASE_READ_META() | sbar, 60)
                val () = update_status_text(VT_7() | sstat, 7, 16)
                val p_container = epub_read_container_async(pf_zip | sh)

                (* Chain: container result → OPF read → add book *)
                val ssh = sh val ssli = sli val ssr = sr
                val sslbl = slbl val ssspn = sspn val sssts = ssts
                val ssbar = sbar val ssstat = sstat val sscard = scard
              in ward_promise_then<int><int>(p_container,
                llam (ok1: int): ward_promise_chained(int) =>
                  if gt_int_int(ok1, 0) then let
                    val p_opf = epub_read_opf_async(pf_zip | ssh)
                  in ward_promise_then<int><int>(p_opf,
                    llam (ok2: int): ward_promise_chained(int) =>
                      if lte_int_int(ok2, 0) then let
                        prval pf_term = PTERMINAL_ERR(pf3)
                        val () = render_error_banner(ssr)
                        val () = import_finish_with_card(
                          pf_term |
                          import_mark_failed(log_err_opf(), 7),
                          sscard, sslbl, ssspn, sssts)
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
                          (* Load manifest — ward_idb_put resolves with 0 on success,
                           * so we cannot check p_man result. Instead check load result:
                           * epub_load_manifest returns 1 on success, 0 on failure. *)
                          val p_load = epub_load_manifest()
                        in ward_promise_then<int><int>(p_load,
                          llam (load_ok: int): ward_promise_chained(int) =>
                            if lte_int_int(load_ok, 0) then let
                              prval pf_term = PTERMINAL_ERR(pf3)
                              val () = ward_file_close(ssh)
                              val () = render_error_banner(ssr)
                              val () = import_finish_with_card(
                                pf_term |
                                import_mark_failed(log_err_manifest(), 12),
                                sscard, sslbl, ssspn, sssts)
                            in ward_promise_return<int>(0) end
                            else let
                              val p_cvr = epub_store_cover()
                              in ward_promise_then<int><int>(p_cvr,
                                llam (_: int): ward_promise_chained(int) => let
                                  val p_si = epub_store_search_index()
                                in ward_promise_then<int><int>(p_si,
                                  llam (_: int): ward_promise_chained(int) => let
                                    val () = update_import_bar(PHASE_ADD_BOOK() | ssbar, 90)
                                    val () = update_status_text(VT_8() | ssstat, 8, 17)
                                  in
                                    if lte_int_int(ok2, 0) then
                                      ward_promise_return<int>(0)
                                    else let
                                      val dup_idx = library_find_book_by_id()
                                    in
                                      if gte_int_int(dup_idx, 0) then let
                                        val shelf = library_get_shelf_state(dup_idx)
                                      in
                                        if gt_int_int(shelf, 0) then let
                                          val () = library_replace_book(dup_idx)
                                          val () = library_save()
                                          val () = ward_file_close(ssh)
                                          val h = import_mark_success()
                                          prval pf_term = PTERMINAL_OK(pf3)
                                          val () = import_finish_with_card(pf_term | h, sscard, sslbl, ssspn, sssts)
                                          val dom = ward_dom_init()
                                          val s = ward_dom_stream_begin(dom)
                                          val s = render_library_with_books(s, ssli, 0)
                                          val dom = ward_dom_stream_end(s)
                                          val () = ward_dom_fini(dom)
                                          val btn_count = library_get_count()
                                          val () = register_card_btns(_checked_nat(btn_count), 0, btn_count, ssr, 0)
                                          val () = register_ctx_listeners(_checked_nat(btn_count), 0, btn_count, ssr, 0)
                                          val cvr_count = _cover_queue_count()
                                          val () = if gt_int_int(cvr_count, 0) then
                                            load_library_covers(_checked_nat(cvr_count), 0, cvr_count)
                                        in ward_promise_return<int>(0) end
                                        else let
                                          val () = _app_set_dup_choice(0)
                                          val () = render_dup_modal(dup_idx, ssr)
                                          val sdi = dup_idx
                                          fun poll_dup {k:nat} .<k>.
                                            (rem: int(k)): ward_promise_chained(int) = let
                                            val c = _app_dup_choice()
                                          in
                                            if lte_g1(rem, 0) then let
                                              val () = dismiss_dup_modal()
                                              val () = ward_file_close(ssh)
                                              val h = import_mark_success()
                                              prval pf_term = PTERMINAL_OK(pf3)
                                              val () = import_finish_with_card(pf_term | h, sscard, sslbl, ssspn, sssts)
                                            in ward_promise_return<int>(0) end
                                            else if eq_int_int(c, 0) then
                                              ward_promise_then<int><int>(ward_timer_set(50),
                                                llam (_: int) => poll_dup(sub_g1(rem, 1)))
                                            else if eq_int_int(c, 1) then let
                                              val () = dismiss_dup_modal()
                                              val () = ward_file_close(ssh)
                                              val h = import_mark_success()
                                              prval pf_term = PTERMINAL_OK(pf3)
                                              val () = import_finish_with_card(pf_term | h, sscard, sslbl, ssspn, sssts)
                                            in ward_promise_return<int>(0) end
                                            else let
                                              val () = dismiss_dup_modal()
                                              val () = library_replace_book(sdi)
                                              val () = library_save()
                                              val () = ward_file_close(ssh)
                                              val h = import_mark_success()
                                              prval pf_term = PTERMINAL_OK(pf3)
                                              val () = import_finish_with_card(pf_term | h, sscard, sslbl, ssspn, sssts)
                                              val dom = ward_dom_init()
                                              val s = ward_dom_stream_begin(dom)
                                              val s = render_library_with_books(s, ssli, 0)
                                              val dom = ward_dom_stream_end(s)
                                              val () = ward_dom_fini(dom)
                                              val btn_count = library_get_count()
                                              val () = register_card_btns(_checked_nat(btn_count), 0, btn_count, ssr, 0)
                                              val () = register_ctx_listeners(_checked_nat(btn_count), 0, btn_count, ssr, 0)
                                              val cvr_count = _cover_queue_count()
                                              val () = if gt_int_int(cvr_count, 0) then
                                                load_library_covers(_checked_nat(cvr_count), 0, cvr_count)
                                            in ward_promise_return<int>(0) end
                                          end
                                        in poll_dup(_checked_nat(60000)) end
                                      end
                                      else let
                                        val (pf_result | book_idx) = library_add_book()
                                        prval _ = pf_result
                                      in
                                        if gte_int_int(book_idx, 0) then let
                                          val () = library_save()
                                          val () = ward_file_close(ssh)
                                          val h = import_mark_success()
                                          prval pf_term = PTERMINAL_OK(pf3)
                                          val () = import_finish_with_card(pf_term | h, sscard, sslbl, ssspn, sssts)
                                          val dom = ward_dom_init()
                                          val s = ward_dom_stream_begin(dom)
                                          val s = render_library_with_books(s, ssli, 0)
                                          val dom = ward_dom_stream_end(s)
                                          val () = ward_dom_fini(dom)
                                          val btn_count = library_get_count()
                                          val () = register_card_btns(_checked_nat(btn_count), 0, btn_count, ssr, 0)
                                          val () = register_ctx_listeners(_checked_nat(btn_count), 0, btn_count, ssr, 0)
                                          val cvr_count = _cover_queue_count()
                                          val () = if gt_int_int(cvr_count, 0) then
                                            load_library_covers(_checked_nat(cvr_count), 0, cvr_count)
                                        in ward_promise_return<int>(0) end
                                        else let
                                          val () = render_error_banner(ssr)
                                          prval pf_term = PTERMINAL_ERR(pf3)
                                          val () = import_finish_with_card(
                                            pf_term |
                                            import_mark_failed(log_err_lib_full(), 12),
                                            sscard, sslbl, ssspn, sssts)
                                        in ward_promise_return<int>(0) end
                                      end
                                    end
                                  end)
                                end)
                              end)
                            end)
                          end)
                end)
                end
                else let
                  prval pf_term = PTERMINAL_ERR(pf3)
                  val () = render_error_banner(ssr)
                  val () = import_finish_with_card(
                    pf_term |
                    import_mark_failed(log_err_container(), 13),
                    sscard, sslbl, ssspn, sssts)
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
