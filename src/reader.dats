(* reader.dats - Reader module implementation
 *
 * All reader state is in app_state (linear datavtype).
 * Each function does app_state_load → use → app_state_store.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./reader.sats"
staload "./app_state.sats"
staload "./dom.sats"

staload "./arith.sats"
staload "./drag_state.sats"
staload "./settings.sats"
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"

extern castfn _rdr_byte {c:int | 0 <= c; c <= 255} (c: int c): byte
extern castfn _idx64(x: int): [i:nat | i < 64] int i

implement reader_init() = let
  val st = app_state_load()
  val () = app_set_rdr_active(st, 0)
  val () = app_set_rdr_book_index(st, 0 - 1)
  val () = app_set_rdr_current_chapter(st, 0)
  val () = app_set_rdr_current_page(st, 0)
  val () = app_set_rdr_total_pages(st, 1)
  val () = app_set_rdr_chrome_visible(st, 0)
  val () = app_set_rdr_chrome_timer_gen(st, 0)
  val () = app_set_rdr_chapter_title_id(st, 0)
  val () = app_set_rdr_bm_count(st, 0)
  val () = app_set_rdr_bm_btn_id(st, 0)
  val () = app_set_rdr_bm_save_pending(st, 0)
  val () = app_set_rdr_scrub_bar_id(st, 0)
  val () = app_set_rdr_scrub_track_id(st, 0)
  val () = app_set_rdr_scrub_fill_id(st, 0)
  val () = app_set_rdr_scrub_handle_id(st, 0)
  val () = app_set_rdr_scrub_tooltip_id(st, 0)
  val () = app_set_rdr_scrub_text_id(st, 0)
  val () = app_set_rdr_scrub_dragging(DRAG_IDLE() | st, 0)
  val () = app_set_rdr_scrub_drag_ch(st, 0)
  val () = app_set_rdr_toc_panel_id(st, 0)
  val () = app_set_rdr_toc_list_id(st, 0)
  val () = app_set_rdr_toc_close_btn_id(st, 0)
  val () = app_set_rdr_toc_bm_count_btn_id(st, 0)
  val () = app_set_rdr_toc_switch_btn_id(st, 0)
  val () = app_set_rdr_toc_view_mode(st, 0)
  val () = app_set_rdr_toc_first_entry_id(st, 0)
  val () = app_set_rdr_toc_entry_count(st, 0)
  val () = app_set_rdr_bm_first_entry_id(st, 0)
  val () = app_set_rdr_page_turn_counter(st, 0)
  val () = app_set_rdr_char_offset(st, 0 - 1)
  val () = app_state_store(st)
in end

implement reader_enter(root_id, container_hide_id) = let
  val st = app_state_load()
  val () = app_set_rdr_active(st, 1)
  val () = app_set_rdr_root_id(st, root_id)
  val () = app_state_store(st)
in end

implement reader_exit(pf) = let
  prval _ = pf
  val st = app_state_load()
  val () = app_set_rdr_active(st, 0)
  val () = app_set_rdr_book_index(st, 0 - 1)
  val () = app_set_rdr_current_chapter(st, 0)
  val () = app_set_rdr_current_page(st, 0)
  val () = app_set_rdr_total_pages(st, 1)
  val () = app_set_rdr_chrome_visible(st, 0)
  val () = app_set_rdr_chrome_timer_gen(st, 0)
  val () = app_set_rdr_chapter_title_id(st, 0)
  val () = app_set_rdr_bm_count(st, 0)
  val () = app_set_rdr_bm_btn_id(st, 0)
  val () = app_set_rdr_bm_save_pending(st, 0)
  val () = app_set_rdr_scrub_bar_id(st, 0)
  val () = app_set_rdr_scrub_track_id(st, 0)
  val () = app_set_rdr_scrub_fill_id(st, 0)
  val () = app_set_rdr_scrub_handle_id(st, 0)
  val () = app_set_rdr_scrub_tooltip_id(st, 0)
  val () = app_set_rdr_scrub_text_id(st, 0)
  val () = app_set_rdr_scrub_dragging(DRAG_IDLE() | st, 0)
  val () = app_set_rdr_scrub_drag_ch(st, 0)
  val () = app_set_rdr_toc_panel_id(st, 0)
  val () = app_set_rdr_toc_list_id(st, 0)
  val () = app_set_rdr_toc_close_btn_id(st, 0)
  val () = app_set_rdr_toc_bm_count_btn_id(st, 0)
  val () = app_set_rdr_toc_switch_btn_id(st, 0)
  val () = app_set_rdr_toc_view_mode(st, 0)
  val () = app_set_rdr_toc_first_entry_id(st, 0)
  val () = app_set_rdr_toc_entry_count(st, 0)
  val () = app_set_rdr_bm_first_entry_id(st, 0)
  val () = app_set_rdr_nav_back_btn_id(st, 0)
  val () = app_set_rdr_pos_stack_count(st, 0)
  val () = app_state_store(st)
in end

implement reader_is_active() = let
  val st = app_state_load()
  val v = app_get_rdr_active(st)
  val () = app_state_store(st)
in v end

implement reader_get_current_chapter() = let
  val st = app_state_load()
  val v = app_get_rdr_current_chapter(st)
  val () = app_state_store(st)
in v end

implement reader_get_current_page() = let
  val st = app_state_load()
  val v = app_get_rdr_current_page(st)
  val () = app_state_store(st)
in
  if v >= 0 then _checked_nat(v)
  else _checked_nat(0)
end

implement reader_get_total_pages() = let
  val st = app_state_load()
  val v = app_get_rdr_total_pages(st)
  val () = app_state_store(st)
in
  if v > 0 then _checked_pos(v)
  else _checked_pos(1)
end

implement reader_get_chapter_count() = let
  val st = app_state_load()
  val v = app_get_epub_spine_count(st)
  val () = app_state_store(st)
in
  if v >= 0 then _checked_nat(v)
  else _checked_nat(0)
end

implement reader_next_page() = let
  val st = app_state_load()
  val pg = app_get_rdr_current_page(st)
  val total = app_get_rdr_total_pages(st)
in
  if lt_int_int(pg, total - 1) then let
    val () = app_set_rdr_current_page(st, pg + 1)
    val () = app_state_store(st)
  in end
  else let
    val () = app_state_store(st)
  in end
end

implement reader_prev_page() = let
  val st = app_state_load()
  val pg = app_get_rdr_current_page(st)
in
  if gt_int_int(pg, 0) then let
    val () = app_set_rdr_current_page(st, pg - 1)
    val () = app_state_store(st)
  in end
  else let
    val () = app_state_store(st)
  in end
end

implement reader_go_to_page(page) = let
  val st = app_state_load()
  val total = app_get_rdr_total_pages(st)
in
  if gte_int_int(page, 0) then
    if lt_int_int(page, total) then let
      val () = app_set_rdr_current_page(st, page)
      val () = app_state_store(st)
    in end
    else let val () = app_state_store(st) in end
  else let val () = app_state_store(st) in end
end

implement reader_go_to_chapter{ch,t}(chapter_index, total_chapters) = let
  val st = app_state_load()
  val spine = app_get_epub_spine_count(st)
  val ci = g0ofg1(chapter_index)
in
  if gte_int_int(ci, 0) then
    if lt_int_int(ci, spine) then let
      val () = app_set_rdr_current_chapter(st, ci)
      val () = app_set_rdr_current_page(st, 0)
      val () = app_state_store(st)
    in end
    else let val () = app_state_store(st) in end
  else let val () = app_state_store(st) in end
end

(* Stub implementations — not yet fully wired *)
implement reader_on_chapter_loaded(len) = ()
implement reader_on_chapter_blob_loaded(handle, size) = ()
implement reader_get_viewport_width() = 0
implement reader_update_page_display() = ()
implement reader_is_loading() = 0
(* reader_remeasure_all: apply font-size and line-height as inline style on
 * the reader viewport. Font properties cascade to chapter-container content.
 * Uses the viewport (not the container) to avoid conflicts with transform. *)
implement reader_remeasure_all() = let
  val vp_id = reader_get_viewport_id()
in
  if gt_int_int(vp_id, 0) then let
    val fs = settings_get_font_size()  (* 14-32 *)
    val lh = settings_get_line_height_tenths()  (* 14-24, i.e. 1.4-2.4 *)
    (* Build: "font-size:NNpx;line-height:N.N" = 15 + 15 = 30 bytes max *)
    val arr = ward_arr_alloc<byte>(48)
    (* "font-size:" = 10 bytes *)
    val () = ward_arr_set<byte>(arr, 0, _rdr_byte(102))   (* f *)
    val () = ward_arr_set<byte>(arr, 1, _rdr_byte(111))   (* o *)
    val () = ward_arr_set<byte>(arr, 2, _rdr_byte(110))   (* n *)
    val () = ward_arr_set<byte>(arr, 3, _rdr_byte(116))   (* t *)
    val () = ward_arr_set<byte>(arr, 4, _rdr_byte(45))    (* - *)
    val () = ward_arr_set<byte>(arr, 5, _rdr_byte(115))   (* s *)
    val () = ward_arr_set<byte>(arr, 6, _rdr_byte(105))   (* i *)
    val () = ward_arr_set<byte>(arr, 7, _rdr_byte(122))   (* z *)
    val () = ward_arr_set<byte>(arr, 8, _rdr_byte(101))   (* e *)
    val () = ward_arr_set<byte>(arr, 9, _rdr_byte(58))    (* : *)
    (* font size: 14-32, always 2 digits *)
    val fs_d1 = div_int_int(fs, 10)
    val fs_d0 = mod_int_int(fs, 10)
    val () = ward_arr_set<byte>(arr, 10, ward_int2byte(_checked_byte(48 + fs_d1)))
    val () = ward_arr_set<byte>(arr, 11, ward_int2byte(_checked_byte(48 + fs_d0)))
    (* "px;" *)
    val () = ward_arr_set<byte>(arr, 12, _rdr_byte(112))  (* p *)
    val () = ward_arr_set<byte>(arr, 13, _rdr_byte(120))  (* x *)
    val () = ward_arr_set<byte>(arr, 14, _rdr_byte(59))   (* ; *)
    (* "line-height:" = 12 bytes *)
    val () = ward_arr_set<byte>(arr, 15, _rdr_byte(108))  (* l *)
    val () = ward_arr_set<byte>(arr, 16, _rdr_byte(105))  (* i *)
    val () = ward_arr_set<byte>(arr, 17, _rdr_byte(110))  (* n *)
    val () = ward_arr_set<byte>(arr, 18, _rdr_byte(101))  (* e *)
    val () = ward_arr_set<byte>(arr, 19, _rdr_byte(45))   (* - *)
    val () = ward_arr_set<byte>(arr, 20, _rdr_byte(104))  (* h *)
    val () = ward_arr_set<byte>(arr, 21, _rdr_byte(101))  (* e *)
    val () = ward_arr_set<byte>(arr, 22, _rdr_byte(105))  (* i *)
    val () = ward_arr_set<byte>(arr, 23, _rdr_byte(103))  (* g *)
    val () = ward_arr_set<byte>(arr, 24, _rdr_byte(104))  (* h *)
    val () = ward_arr_set<byte>(arr, 25, _rdr_byte(116))  (* t *)
    val () = ward_arr_set<byte>(arr, 26, _rdr_byte(58))   (* : *)
    (* N.N from tenths *)
    val lh_whole = div_int_int(lh, 10)
    val lh_frac = mod_int_int(lh, 10)
    val () = ward_arr_set<byte>(arr, 27, ward_int2byte(_checked_byte(48 + lh_whole)))
    val () = ward_arr_set<byte>(arr, 28, _rdr_byte(46))   (* . *)
    val () = ward_arr_set<byte>(arr, 29, ward_int2byte(_checked_byte(48 + lh_frac)))
    (* total = 30 bytes *)
    val @(used, rest) = ward_arr_split<byte>(arr, 30)
    val () = ward_arr_free<byte>(rest)
    val @(frozen, borrow) = ward_arr_freeze<byte>(used)
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_set_style(s, vp_id, borrow, 30)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = ward_arr_drop<byte>(frozen, borrow)
    val used = ward_arr_thaw<byte>(frozen)
    val () = ward_arr_free<byte>(used)
  in end
  else ()
end
implement reader_show_toc() = ()
implement reader_hide_toc() = ()
implement reader_toggle_toc() = ()
implement reader_is_toc_visible() = let
  val (pf_mode | mode) = reader_get_toc_view_mode()
  prval _ = pf_mode
in gt_int_int(mode, 0) end
implement reader_get_toc_id() = 0
implement reader_get_progress_bar_id() = 0
implement reader_get_toc_index_for_node(node_id) = 0 - 1
implement reader_on_toc_click(node_id) = ()
implement reader_enter_at(root_id, container_hide_id, chapter, page) = let
  val () = reader_enter(root_id, container_hide_id)
  val st = app_state_load()
  val () = app_set_rdr_current_chapter(st, chapter)
  val () = app_set_rdr_current_page(st, page)
  val () = app_state_store(st)
in end

implement reader_get_viewport_id() = let
  val st = app_state_load()
  val v = app_get_rdr_viewport_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_viewport_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_viewport_id(st, id)
  val () = app_state_store(st)
in end

implement reader_set_container_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_container_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_container_id() = let
  val st = app_state_load()
  val v = app_get_rdr_container_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_book_index(idx) = let
  val st = app_state_load()
  val () = app_set_rdr_book_index(st, idx)
  val () = app_state_store(st)
in end

implement reader_get_book_index() = let
  val st = app_state_load()
  val v = app_get_rdr_book_index(st)
  val () = app_state_store(st)
in v end

implement reader_set_file_handle(h) = let
  val st = app_state_load()
  val () = app_set_rdr_file_handle(st, h)
  val () = app_state_store(st)
in end

implement reader_get_file_handle() = let
  val st = app_state_load()
  val v = app_get_rdr_file_handle(st)
  val () = app_state_store(st)
in v end

implement reader_set_btn_id(book_index, node_id) = let
  val st = app_state_load()
  val () = app_set_rdr_btn_id(st, book_index, node_id)
  val () = app_state_store(st)
in end

implement reader_get_btn_id(book_index) = let
  val st = app_state_load()
  val v = app_get_rdr_btn_id(st, book_index)
  val () = app_state_store(st)
in v end

implement reader_set_total_pages(n) = let
  val st = app_state_load()
  val v = if gt_int_int(n, 0) then n else 1
  val () = app_set_rdr_total_pages(st, v)
  val () = app_state_store(st)
in end

implement reader_set_page_info_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_page_info_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_page_indicator_id() = let
  val st = app_state_load()
  val v = app_get_rdr_page_info_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_nav_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_nav_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_nav_id() = let
  val st = app_state_load()
  val v = app_get_rdr_nav_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_resume_page(page) = let
  val st = app_state_load()
  val () = app_set_rdr_resume_page(st, page)
  val () = app_state_store(st)
in end

implement reader_get_resume_page() = let
  val st = app_state_load()
  val v = app_get_rdr_resume_page(st)
  val () = app_state_store(st)
in v end

implement reader_get_chrome_visible() = let
  val st = app_state_load()
  val v = app_get_rdr_chrome_visible(st)
  val () = app_state_store(st)
in v end

implement reader_set_chrome_visible(v) = let
  val st = app_state_load()
  val () = app_set_rdr_chrome_visible(st, v)
  val () = app_state_store(st)
in end

implement reader_get_chrome_timer_gen() = let
  val st = app_state_load()
  val v = app_get_rdr_chrome_timer_gen(st)
  val () = app_state_store(st)
in v end

implement reader_set_chrome_timer_gen(v) = let
  val st = app_state_load()
  val () = app_set_rdr_chrome_timer_gen(st, v)
  val () = app_state_store(st)
in end

implement reader_incr_chrome_timer_gen() = let
  val st = app_state_load()
  val v = app_get_rdr_chrome_timer_gen(st)
  val nv = v + 1
  val () = app_set_rdr_chrome_timer_gen(st, nv)
  val () = app_state_store(st)
in nv end

implement reader_set_chapter_title_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_chapter_title_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_chapter_title_id() = let
  val st = app_state_load()
  val v = app_get_rdr_chapter_title_id(st)
  val () = app_state_store(st)
in v end

implement reader_get_bm_count() = let
  val st = app_state_load()
  val v = app_get_rdr_bm_count(st)
  val () = app_state_store(st)
in v end

implement reader_set_bm_count(v) = let
  val st = app_state_load()
  val () = app_set_rdr_bm_count(st, v)
  val () = app_state_store(st)
in end

implement reader_get_bm_btn_id() = let
  val st = app_state_load()
  val v = app_get_rdr_bm_btn_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_bm_btn_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_bm_btn_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_bm_save_pending() = let
  val st = app_state_load()
  val v = app_get_rdr_bm_save_pending(st)
  val () = app_state_store(st)
in v end

implement reader_set_bm_save_pending(v) = let
  val st = app_state_load()
  val () = app_set_rdr_bm_save_pending(st, v)
  val () = app_state_store(st)
in end

(* ========== Scrubber state ========== *)

implement reader_set_scrub_bar_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_bar_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_scrub_bar_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_bar_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_scrub_track_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_track_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_scrub_track_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_track_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_scrub_fill_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_fill_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_scrub_fill_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_fill_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_scrub_handle_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_handle_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_scrub_handle_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_handle_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_scrub_tooltip_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_tooltip_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_scrub_tooltip_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_tooltip_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_scrub_text_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_text_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_scrub_text_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_text_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_scrub_dragging{d}(pf | v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_dragging(pf | st, v)
  val () = app_state_store(st)
in end

implement reader_get_scrub_dragging() = let
  val st = app_state_load()
  val d = app_get_rdr_scrub_dragging(st)
  val () = app_state_store(st)
in
  if d = 1 then 1 else 0
end

implement reader_set_scrub_drag_ch(v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_drag_ch(st, v)
  val () = app_state_store(st)
in end

implement reader_get_scrub_drag_ch() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_drag_ch(st)
  val () = app_state_store(st)
in v end

(* ========== TOC panel state ========== *)

implement reader_set_toc_panel_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_panel_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_toc_panel_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_panel_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_toc_list_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_list_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_toc_list_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_list_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_toc_close_btn_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_close_btn_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_toc_close_btn_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_close_btn_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_toc_bm_count_btn_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_bm_count_btn_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_toc_bm_count_btn_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_bm_count_btn_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_toc_switch_btn_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_switch_btn_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_toc_switch_btn_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_switch_btn_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_toc_view_mode{m}(pf | v) = let
  prval _ = pf
  val st = app_state_load()
  val () = app_set_rdr_toc_view_mode(st, v)
  val () = app_state_store(st)
in end

implement reader_get_toc_view_mode() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_view_mode(st)
  val () = app_state_store(st)
in
  if eq_int_int(v, 1) then (TOC_MODE_CONTENTS() | 1)
  else if eq_int_int(v, 2) then (TOC_MODE_BOOKMARKS() | 2)
  else (TOC_MODE_HIDDEN() | 0)
end

implement reader_set_toc_first_entry_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_first_entry_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_toc_first_entry_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_first_entry_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_toc_entry_count(n) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_entry_count(st, n)
  val () = app_state_store(st)
in end

implement reader_get_toc_entry_count() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_entry_count(st)
  val () = app_state_store(st)
in v end

implement reader_set_bm_first_entry_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_bm_first_entry_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_bm_first_entry_id() = let
  val st = app_state_load()
  val v = app_get_rdr_bm_first_entry_id(st)
  val () = app_state_store(st)
in v end

(* ========== Position stack state ========== *)

implement reader_get_nav_back_btn_id() = let
  val st = app_state_load()
  val v = app_get_rdr_nav_back_btn_id(st)
  val () = app_state_store(st)
in v end

implement reader_set_nav_back_btn_id(id) = let
  val st = app_state_load()
  val () = app_set_rdr_nav_back_btn_id(st, id)
  val () = app_state_store(st)
in end

implement reader_get_pos_stack_count() = let
  val v = _app_rdr_pos_stack_count()
in
  if v >= 0 then _checked_nat(v)
  else _checked_nat(0)
end

implement reader_set_pos_stack_count(v) = let
  val st = app_state_load()
  val () = app_set_rdr_pos_stack_count(st, v)
  val () = app_state_store(st)
in end

implement reader_get_pos_stack_ch(i) =
  _app_rdr_pos_stack_get_i32(i * 2)

implement reader_get_pos_stack_pg(i) =
  _app_rdr_pos_stack_get_i32(i * 2 + 1)

implement reader_set_pos_stack_entry(i, ch, pg) = let
  val () = _app_rdr_pos_stack_set_i32(i * 2, ch)
  val () = _app_rdr_pos_stack_set_i32(i * 2 + 1, pg)
in end

extern castfn _clamp_turn_counter(x: int): [n:nat | n < 5] int n

implement reader_get_page_turn_counter() = let
  val st = app_state_load()
  val v = app_get_rdr_page_turn_counter(st)
  val () = app_state_store(st)
in
  if v >= 0 then
    if lt_int_int(v, 5) then _clamp_turn_counter(v)
    else _clamp_turn_counter(0)
  else _clamp_turn_counter(0)
end

implement reader_set_page_turn_counter{n}(v) = let
  val st = app_state_load()
  val () = app_set_rdr_page_turn_counter(st, v)
  val () = app_state_store(st)
in end

implement reader_get_char_offset() = let
  val st = app_state_load()
  val v = app_get_rdr_char_offset(st)
  val () = app_state_store(st)
in v end

implement reader_set_char_offset{n}(pf | v) = let
  prval CARET_AT() = pf
  val st = app_state_load()
  val () = app_set_rdr_char_offset(st, v)
  val () = app_state_store(st)
in end

implement reader_clear_char_offset() = let
  val st = app_state_load()
  val () = app_set_rdr_char_offset(st, 0 - 1)
  val () = app_state_store(st)
in end
