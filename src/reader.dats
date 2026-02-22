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
  val () = app_state_store(st)
in end

implement reader_enter(root_id, container_hide_id) = let
  val st = app_state_load()
  val () = app_set_rdr_active(st, 1)
  val () = app_set_rdr_root_id(st, root_id)
  val () = app_state_store(st)
in end

implement reader_exit(pf) = let
  prval SAVED() = pf
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
implement reader_remeasure_all() = ()
implement reader_show_toc() = ()
implement reader_hide_toc() = ()
implement reader_toggle_toc() = ()
implement reader_is_toc_visible() = gt_int_int(reader_get_toc_view_mode(), 0)
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

implement reader_set_toc_view_mode(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_view_mode(st, v)
  val () = app_state_store(st)
in end

implement reader_get_toc_view_mode() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_view_mode(st)
  val () = app_state_store(st)
in v end

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
