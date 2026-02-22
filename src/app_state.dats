(* app_state.dats -- Linear application state implementation
 *
 * Pure ATS2 datavtype. Fields accessed via @-unfold pattern which
 * generates direct struct member access in C.
 *
 * Buffer fields are stored as ptr in the datavtype to avoid 14
 * existential address variables. The ONLY $UNSAFE usage in this file
 * is ptr<->ward_arr casts within _arr_borrow and un-borrow.
 * All buffer access goes through ward_arr_get/set (bounds-checked).
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./app_state.sats"
staload "./drag_state.sats"
staload "./buf.sats"
staload "./arith.sats"

staload UN = "prelude/SATS/unsafe.sats"
staload "./../vendor/ward/lib/memory.sats"
staload _ = "./../vendor/ward/lib/memory.dats"

(* Listener table slot for the app_state stash.
 * ward_listener_set/get in runtime.c stores/retrieves ptr.
 * app_state erases to atstype_ptrk at runtime -- same width. *)
#define APP_STATE_SLOT 127

datavtype app_state_impl =
  | APP_STATE of @{
      dom_next_node_id = int,
      zip_entry_count = int,
      zip_file_handle = int,
      zip_name_offset = int,
      zip_entries = ptr,
      zip_name_buf = ptr,
      library_count = int,
      lib_save_pending = int,
      lib_load_pending = int,
      lib_meta_save_pending = int,
      lib_meta_load_pending = int,
      lib_meta_load_index = int,
      lib_view_mode = int,
      lib_sort_mode = int,
      library_books = ptr,
      string_buffer = ptr,
      fetch_buffer = ptr,
      diff_buffer = ptr,
      stg_font_size = int,
      stg_font_family = int,
      stg_theme = int,
      stg_lh_tenths = int,
      stg_margin = int,
      stg_visible = int,
      stg_overlay_id = int,
      stg_close_id = int,
      stg_root_id = int,
      stg_btn_font_minus = int,
      stg_btn_font_plus = int,
      stg_btn_font_fam = int,
      stg_btn_theme_l = int,
      stg_btn_theme_d = int,
      stg_btn_theme_s = int,
      stg_btn_lh_minus = int,
      stg_btn_lh_plus = int,
      stg_btn_mg_minus = int,
      stg_btn_mg_plus = int,
      stg_disp_fs = int,
      stg_disp_ff = int,
      stg_disp_lh = int,
      stg_disp_mg = int,
      stg_save_pend = int,
      stg_load_pend = int,
      rdr_active = int,
      rdr_book_index = int,
      rdr_current_chapter = int,
      rdr_current_page = int,
      rdr_total_pages = int,
      rdr_viewport_id = int,
      rdr_container_id = int,
      rdr_root_id = int,
      rdr_file_handle = int,
      rdr_page_info_id = int,
      rdr_nav_id = int,
      rdr_resume_page = int,
      rdr_chrome_visible = int,
      rdr_chrome_timer_gen = int,
      rdr_chapter_title_id = int,
      rdr_bm_count = int,
      rdr_bm_btn_id = int,
      rdr_bm_save_pending = int,
      rdr_toc_panel_id = int,
      rdr_toc_list_id = int,
      rdr_toc_close_btn_id = int,
      rdr_toc_bm_count_btn_id = int,
      rdr_toc_switch_btn_id = int,
      rdr_toc_view_mode = int,
      rdr_toc_first_entry_id = int,
      rdr_toc_entry_count = int,
      rdr_bm_first_entry_id = int,
      rdr_scrub_bar_id = int,
      rdr_scrub_track_id = int,
      rdr_scrub_fill_id = int,
      rdr_scrub_handle_id = int,
      rdr_scrub_tooltip_id = int,
      rdr_scrub_text_id = int,
      rdr_scrub_dragging = int,
      rdr_scrub_drag_ch = int,
      rdr_bm_buf = ptr,
      rdr_btn_ids = ptr,
      epub_spine_count = int,
      epub_title = ptr,
      epub_title_len = int,
      epub_author = ptr,
      epub_author_len = int,
      epub_book_id = ptr,
      epub_book_id_len = int,
      epub_opf_path = ptr,
      epub_opf_path_len = int,
      epub_opf_dir_len = int,
      epub_state = int,
      epub_spine_path_buf = ptr,
      epub_spine_path_offsets = ptr,
      epub_spine_path_lens = ptr,
      epub_spine_path_count = int,
      epub_spine_path_pos = int,
      epub_manifest_names = ptr,
      epub_manifest_offsets = ptr,
      epub_manifest_lens = ptr,
      epub_manifest_count = int,
      epub_spine_entry_idx = ptr,
      deferred_img_nid = ptr,
      deferred_img_eid = ptr,
      deferred_img_count = int,
      epub_file_size = int,
      epub_cover_href = ptr,
      epub_cover_href_len = int,
      dup_choice = int,
      dup_overlay_id = int,
      reset_overlay_id = int,
      err_banner_id = int,
      import_card_id = int,
      import_card_bar_id = int,
      import_card_status_id = int,
      ctx_overlay_id = int,
      info_overlay_id = int,
      del_overlay_id = int,
      del_choice = int
    }

assume app_state = app_state_impl

(* ========== ward_arr helper functions ========== *)

(* Cast ptr to ward_arr for borrowing. $UNSAFE justification:
 * ptr was created by ward_arr_alloc in app_state_init and stored
 * as ptr in the datavtype. This cast borrows without consuming.
 * Alternative: datavtype with 14 existential addr vars — rejected
 * because ATS2 constraint solver performance is unknown with that
 * many existentials, and codegen may produce different struct layouts. *)
fn _arr_borrow {n:pos} (p: ptr, cap: int n): [l:agz] ward_arr(byte, l, n) =
  $UN.castvwtp1{[l:agz] ward_arr(byte, l, n)}(p)

(* Read byte from buffer at offset, bounds-checked *)
fn _arr_get_u8 (p: ptr, off: int, cap: int): int = let
  val n = _checked_pos(cap)
  val arr = _arr_borrow(p, n)
  val v = byte2int0(ward_arr_get<byte>(arr, _ward_idx(off, n)))
  val _ = $UN.castvwtp0{ptr}(arr)  (* un-borrow *)
in v end

(* Write byte to buffer at offset, bounds-checked *)
fn _arr_set_u8 (p: ptr, off: int, cap: int, v: int): void = let
  val n = _checked_pos(cap)
  val arr = _arr_borrow(p, n)
  val () = ward_arr_set<byte>(arr, _ward_idx(off, n), ward_int2byte(_checked_byte(v)))
  val _ = $UN.castvwtp0{ptr}(arr)  (* un-borrow *)
in end

(* Read little-endian i32 from 4 consecutive bytes *)
fn _arr_get_i32 (p: ptr, idx: int, cap: int): int = let
  val byte_off = idx * 4
  val b0 = _arr_get_u8(p, byte_off, cap)
  val b1 = _arr_get_u8(p, byte_off + 1, cap)
  val b2 = _arr_get_u8(p, byte_off + 2, cap)
  val b3 = _arr_get_u8(p, byte_off + 3, cap)
in bor_int_int(bor_int_int(b0, bsl_int_int(b1, 8)), bor_int_int(bsl_int_int(b2, 16), bsl_int_int(b3, 24))) end

(* Write little-endian i32 as 4 bytes *)
fn _arr_set_i32 (p: ptr, idx: int, cap: int, v: int): void = let
  val byte_off = idx * 4
  val () = _arr_set_u8(p, byte_off, cap, band_int_int(v, 255))
  val () = _arr_set_u8(p, byte_off + 1, cap, band_int_int(bsr_int_int(v, 8), 255))
  val () = _arr_set_u8(p, byte_off + 2, cap, band_int_int(bsr_int_int(v, 16), 255))
  val () = _arr_set_u8(p, byte_off + 3, cap, band_int_int(bsr_int_int(v, 24), 255))
in end

(* Helper: allocate ward_arr<byte> and cast to ptr for datavtype storage *)
fn _alloc_buf (sz: int): ptr = let
  val arr = ward_arr_alloc<byte>(_checked_arr_size(sz))
  val p = $UN.castvwtp0{ptr}(arr)
in p end

(* Helper: free a buffer ptr by casting back to ward_arr and freeing *)
fn _free_buf (p: ptr, sz: int): void = let
  val arr = $UN.castvwtp0{[l:agz] ward_arr(byte, l, 1)}(p)
  val () = ward_arr_free<byte>(arr)
in end

(* ========== Lifecycle ========== *)

implement app_state_init() =
  APP_STATE @{
    dom_next_node_id = 1,
    zip_entry_count = 0,
    zip_file_handle = 0,
    zip_name_offset = 0,
    zip_entries = _alloc_buf(ZIP_ENTRIES_SIZE),
    zip_name_buf = _alloc_buf(ZIP_NAMEBUF_SIZE),
    library_count = 0,
    lib_save_pending = 0,
    lib_load_pending = 0,
    lib_meta_save_pending = 0,
    lib_meta_load_pending = 0,
    lib_meta_load_index = 0 - 1,
    lib_view_mode = 0,
    lib_sort_mode = 2,
    library_books = _alloc_buf(LIB_BOOKS_SIZE),
    string_buffer = _alloc_buf(STRING_BUFFER_SIZE),
    fetch_buffer = _alloc_buf(FETCH_BUFFER_SIZE),
    diff_buffer = _alloc_buf(DIFF_BUFFER_SIZE),
    stg_font_size = 18,
    stg_font_family = 0,
    stg_theme = 0,
    stg_lh_tenths = 16,
    stg_margin = 2,
    stg_visible = 0,
    stg_overlay_id = 0,
    stg_close_id = 0,
    stg_root_id = 1,
    stg_btn_font_minus = 0,
    stg_btn_font_plus = 0,
    stg_btn_font_fam = 0,
    stg_btn_theme_l = 0,
    stg_btn_theme_d = 0,
    stg_btn_theme_s = 0,
    stg_btn_lh_minus = 0,
    stg_btn_lh_plus = 0,
    stg_btn_mg_minus = 0,
    stg_btn_mg_plus = 0,
    stg_disp_fs = 0,
    stg_disp_ff = 0,
    stg_disp_lh = 0,
    stg_disp_mg = 0,
    stg_save_pend = 0,
    stg_load_pend = 0,
    rdr_active = 0,
    rdr_book_index = 0 - 1,
    rdr_current_chapter = 0,
    rdr_current_page = 0,
    rdr_total_pages = 1,
    rdr_viewport_id = 0,
    rdr_container_id = 0,
    rdr_root_id = 0,
    rdr_file_handle = 0,
    rdr_page_info_id = 0,
    rdr_nav_id = 0,
    rdr_resume_page = 0,
    rdr_chrome_visible = 0,
    rdr_chrome_timer_gen = 0,
    rdr_chapter_title_id = 0,
    rdr_bm_count = 0,
    rdr_bm_btn_id = 0,
    rdr_bm_save_pending = 0,
    rdr_toc_panel_id = 0,
    rdr_toc_list_id = 0,
    rdr_toc_close_btn_id = 0,
    rdr_toc_bm_count_btn_id = 0,
    rdr_toc_switch_btn_id = 0,
    rdr_toc_view_mode = 0,
    rdr_toc_first_entry_id = 0,
    rdr_toc_entry_count = 0,
    rdr_bm_first_entry_id = 0,
    rdr_scrub_bar_id = 0,
    rdr_scrub_track_id = 0,
    rdr_scrub_fill_id = 0,
    rdr_scrub_handle_id = 0,
    rdr_scrub_tooltip_id = 0,
    rdr_scrub_text_id = 0,
    rdr_scrub_dragging = 0,
    rdr_scrub_drag_ch = 0,
    rdr_bm_buf = _alloc_buf(BOOKMARK_BUF_SIZE),
    rdr_btn_ids = _alloc_buf(RDR_BTNS_SIZE),
    epub_spine_count = 0,
    epub_title = _alloc_buf(EPUB_TITLE_SIZE),
    epub_title_len = 0,
    epub_author = _alloc_buf(EPUB_AUTHOR_SIZE),
    epub_author_len = 0,
    epub_book_id = _alloc_buf(EPUB_BOOKID_SIZE),
    epub_book_id_len = 0,
    epub_opf_path = _alloc_buf(EPUB_OPF_SIZE),
    epub_opf_path_len = 0,
    epub_opf_dir_len = 0,
    epub_state = 0,
    epub_spine_path_buf = _alloc_buf(EPUB_SPINE_BUF_SIZE),
    epub_spine_path_offsets = _alloc_buf(EPUB_SPINE_OFF_SIZE),
    epub_spine_path_lens = _alloc_buf(EPUB_SPINE_LEN_SIZE),
    epub_spine_path_count = 0,
    epub_spine_path_pos = 0,
    epub_manifest_names = _alloc_buf(EPUB_MANIFEST_NAMES_SIZE),
    epub_manifest_offsets = _alloc_buf(EPUB_MANIFEST_OFF_SIZE),
    epub_manifest_lens = _alloc_buf(EPUB_MANIFEST_LEN_SIZE),
    epub_manifest_count = 0,
    epub_spine_entry_idx = _alloc_buf(EPUB_SPINE_ENTRY_IDX_SIZE),
    deferred_img_nid = _alloc_buf(DEFERRED_IMG_NID_SIZE),
    deferred_img_eid = _alloc_buf(DEFERRED_IMG_EID_SIZE),
    deferred_img_count = 0,
    epub_file_size = 0,
    epub_cover_href = _alloc_buf(EPUB_COVER_HREF_SIZE),
    epub_cover_href_len = 0,
    dup_choice = 0,
    dup_overlay_id = 0,
    reset_overlay_id = 0,
    err_banner_id = 0,
    import_card_id = 0,
    import_card_bar_id = 0,
    import_card_status_id = 0,
    ctx_overlay_id = 0,
    info_overlay_id = 0,
    del_overlay_id = 0,
    del_choice = 0
  }

implement app_state_fini(st) = let
  val ~APP_STATE(r) = st
  val () = _free_buf(r.zip_entries, ZIP_ENTRIES_SIZE)
  val () = _free_buf(r.zip_name_buf, ZIP_NAMEBUF_SIZE)
  val () = _free_buf(r.library_books, LIB_BOOKS_SIZE)
  val () = _free_buf(r.string_buffer, STRING_BUFFER_SIZE)
  val () = _free_buf(r.fetch_buffer, FETCH_BUFFER_SIZE)
  val () = _free_buf(r.diff_buffer, DIFF_BUFFER_SIZE)
  val () = _free_buf(r.rdr_bm_buf, BOOKMARK_BUF_SIZE)
  val () = _free_buf(r.rdr_btn_ids, RDR_BTNS_SIZE)
  val () = _free_buf(r.epub_title, EPUB_TITLE_SIZE)
  val () = _free_buf(r.epub_author, EPUB_AUTHOR_SIZE)
  val () = _free_buf(r.epub_book_id, EPUB_BOOKID_SIZE)
  val () = _free_buf(r.epub_opf_path, EPUB_OPF_SIZE)
  val () = _free_buf(r.epub_spine_path_buf, EPUB_SPINE_BUF_SIZE)
  val () = _free_buf(r.epub_spine_path_offsets, EPUB_SPINE_OFF_SIZE)
  val () = _free_buf(r.epub_spine_path_lens, EPUB_SPINE_LEN_SIZE)
  val () = _free_buf(r.epub_manifest_names, EPUB_MANIFEST_NAMES_SIZE)
  val () = _free_buf(r.epub_manifest_offsets, EPUB_MANIFEST_OFF_SIZE)
  val () = _free_buf(r.epub_manifest_lens, EPUB_MANIFEST_LEN_SIZE)
  val () = _free_buf(r.epub_spine_entry_idx, EPUB_SPINE_ENTRY_IDX_SIZE)
  val () = _free_buf(r.deferred_img_nid, DEFERRED_IMG_NID_SIZE)
  val () = _free_buf(r.deferred_img_eid, DEFERRED_IMG_EID_SIZE)
  val () = _free_buf(r.epub_cover_href, EPUB_COVER_HREF_SIZE)
in end

(* ========== DOM state ========== *)

implement app_get_dom_next_id(st) = let
  val @APP_STATE(r) = st
  val v = r.dom_next_node_id
  prval () = fold@(st)
in v end

implement app_set_dom_next_id(st, v) = let
  val @APP_STATE(r) = st
  val () = r.dom_next_node_id := v
  prval () = fold@(st)
in end

(* ========== ZIP scalar state ========== *)

implement app_get_zip_entry_count(st) = let
  val @APP_STATE(r) = st
  val v = r.zip_entry_count
  prval () = fold@(st)
in v end

implement app_set_zip_entry_count(st, v) = let
  val @APP_STATE(r) = st
  val () = r.zip_entry_count := v
  prval () = fold@(st)
in end

implement app_get_zip_file_handle(st) = let
  val @APP_STATE(r) = st
  val v = r.zip_file_handle
  prval () = fold@(st)
in v end

implement app_set_zip_file_handle(st, v) = let
  val @APP_STATE(r) = st
  val () = r.zip_file_handle := v
  prval () = fold@(st)
in end

implement app_get_zip_name_offset(st) = let
  val @APP_STATE(r) = st
  val v = r.zip_name_offset
  prval () = fold@(st)
in v end

implement app_set_zip_name_offset(st, v) = let
  val @APP_STATE(r) = st
  val () = r.zip_name_offset := v
  prval () = fold@(st)
in end

(* ========== ZIP array storage ========== *)

(* ZIP entries: 256 entries x 7 ints each, stored as flat byte array.
 * Entry i has fields at i32 indices i*7+0..i*7+6:
 *   0=file_handle, 1=name_offset, 2=name_len, 3=compression,
 *   4=compressed_size, 5=uncompressed_size, 6=local_header_offset *)

implement _zip_entry_file_handle(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.zip_entries, i * 7 + 0, ZIP_ENTRIES_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_entry_name_offset(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.zip_entries, i * 7 + 1, ZIP_ENTRIES_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_entry_name_len(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.zip_entries, i * 7 + 2, ZIP_ENTRIES_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_entry_compression(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.zip_entries, i * 7 + 3, ZIP_ENTRIES_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_entry_compressed_size(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.zip_entries, i * 7 + 4, ZIP_ENTRIES_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_entry_uncompressed_size(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.zip_entries, i * 7 + 5, ZIP_ENTRIES_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_entry_local_offset(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.zip_entries, i * 7 + 6, ZIP_ENTRIES_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_name_char(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = if gte_int_int(off, 0) then
            if lt_int_int(off, ZIP_NAMEBUF_SIZE) then _arr_get_u8(r.zip_name_buf, off, ZIP_NAMEBUF_SIZE)
            else 0
          else 0
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_name_buf_put(off, byte_val) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = if gte_int_int(off, 0) then
            if lt_int_int(off, ZIP_NAMEBUF_SIZE) then let
              val () = _arr_set_u8(r.zip_name_buf, off, ZIP_NAMEBUF_SIZE, byte_val)
            in 1 end
            else 0
          else 0
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _zip_store_entry_at(idx, fh, no, nl, comp, cs, us, lo) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = if gte_int_int(idx, 0) then
    if lt_int_int(idx, 256) then let
      val p = r.zip_entries
      val base = idx * 7
      val () = _arr_set_i32(p, base + 0, ZIP_ENTRIES_SIZE, fh)
      val () = _arr_set_i32(p, base + 1, ZIP_ENTRIES_SIZE, no)
      val () = _arr_set_i32(p, base + 2, ZIP_ENTRIES_SIZE, nl)
      val () = _arr_set_i32(p, base + 3, ZIP_ENTRIES_SIZE, comp)
      val () = _arr_set_i32(p, base + 4, ZIP_ENTRIES_SIZE, cs)
      val () = _arr_set_i32(p, base + 5, ZIP_ENTRIES_SIZE, us)
      val () = _arr_set_i32(p, base + 6, ZIP_ENTRIES_SIZE, lo)
    in 1 end
    else 0
  else 0
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

(* ========== Library state ========== *)

implement app_get_library_count(st) = let
  val @APP_STATE(r) = st val v = r.library_count
  prval () = fold@(st) in v end
implement app_set_library_count(st, v) = let
  val @APP_STATE(r) = st val () = r.library_count := v
  prval () = fold@(st) in end

implement app_get_lib_save_pending(st) = let
  val @APP_STATE(r) = st val v = r.lib_save_pending
  prval () = fold@(st) in v end
implement app_set_lib_save_pending(st, v) = let
  val @APP_STATE(r) = st val () = r.lib_save_pending := v
  prval () = fold@(st) in end

implement app_get_lib_load_pending(st) = let
  val @APP_STATE(r) = st val v = r.lib_load_pending
  prval () = fold@(st) in v end
implement app_set_lib_load_pending(st, v) = let
  val @APP_STATE(r) = st val () = r.lib_load_pending := v
  prval () = fold@(st) in end

implement app_get_lib_meta_save_pending(st) = let
  val @APP_STATE(r) = st val v = r.lib_meta_save_pending
  prval () = fold@(st) in v end
implement app_set_lib_meta_save_pending(st, v) = let
  val @APP_STATE(r) = st val () = r.lib_meta_save_pending := v
  prval () = fold@(st) in end

implement app_get_lib_meta_load_pending(st) = let
  val @APP_STATE(r) = st val v = r.lib_meta_load_pending
  prval () = fold@(st) in v end
implement app_set_lib_meta_load_pending(st, v) = let
  val @APP_STATE(r) = st val () = r.lib_meta_load_pending := v
  prval () = fold@(st) in end

implement app_get_lib_meta_load_index(st) = let
  val @APP_STATE(r) = st val v = r.lib_meta_load_index
  prval () = fold@(st) in v end
implement app_set_lib_meta_load_index(st, v) = let
  val @APP_STATE(r) = st val () = r.lib_meta_load_index := v
  prval () = fold@(st) in end

implement app_get_lib_view_mode(st) = let
  val @APP_STATE(r) = st val v = r.lib_view_mode
  prval () = fold@(st) in v end
implement app_set_lib_view_mode(st, v) = let
  val @APP_STATE(r) = st val () = r.lib_view_mode := v
  prval () = fold@(st) in end

implement app_get_lib_sort_mode(st) = let
  val @APP_STATE(r) = st val v = r.lib_sort_mode
  prval () = fold@(st) in v end
implement app_set_lib_sort_mode(st, v) = let
  val @APP_STATE(r) = st val () = r.lib_sort_mode := v
  prval () = fold@(st) in end

(* ========== Duplicate detection state ========== *)

implement app_get_dup_choice(st) = let
  val @APP_STATE(r) = st val v = r.dup_choice
  prval () = fold@(st) in v end
implement app_set_dup_choice(st, v) = let
  val @APP_STATE(r) = st val () = r.dup_choice := v
  prval () = fold@(st) in end
implement app_get_dup_overlay_id(st) = let
  val @APP_STATE(r) = st val v = r.dup_overlay_id
  prval () = fold@(st) in v end
implement app_set_dup_overlay_id(st, v) = let
  val @APP_STATE(r) = st val () = r.dup_overlay_id := v
  prval () = fold@(st) in end

implement _app_dup_choice() = let val st = app_state_load()
  val v = app_get_dup_choice(st) val () = app_state_store(st) in v end
implement _app_set_dup_choice(v) = let val st = app_state_load()
  val () = app_set_dup_choice(st, v) val () = app_state_store(st) in end
implement _app_dup_overlay_id() = let val st = app_state_load()
  val v = app_get_dup_overlay_id(st) val () = app_state_store(st) in v end
implement _app_set_dup_overlay_id(v) = let val st = app_state_load()
  val () = app_set_dup_overlay_id(st, v) val () = app_state_store(st) in end

(* ========== Factory reset state ========== *)

implement app_get_reset_overlay_id(st) = let
  val @APP_STATE(r) = st val v = r.reset_overlay_id
  prval () = fold@(st) in v end
implement app_set_reset_overlay_id(st, v) = let
  val @APP_STATE(r) = st val () = r.reset_overlay_id := v
  prval () = fold@(st) in end

implement _app_reset_overlay_id() = let val st = app_state_load()
  val v = app_get_reset_overlay_id(st) val () = app_state_store(st) in v end
implement _app_set_reset_overlay_id(v) = let val st = app_state_load()
  val () = app_set_reset_overlay_id(st, v) val () = app_state_store(st) in end

(* ========== Error banner state ========== *)

implement app_get_err_banner_id(st) = let
  val @APP_STATE(r) = st val v = r.err_banner_id
  prval () = fold@(st) in v end
implement app_set_err_banner_id(st, v) = let
  val @APP_STATE(r) = st val () = r.err_banner_id := v
  prval () = fold@(st) in end

implement _app_err_banner_id() = let val st = app_state_load()
  val v = app_get_err_banner_id(st) val () = app_state_store(st) in v end
implement _app_set_err_banner_id(v) = let val st = app_state_load()
  val () = app_set_err_banner_id(st, v) val () = app_state_store(st) in end

(* ========== Import card state ========== *)

implement app_get_import_card_id(st) = let
  val @APP_STATE(r) = st val v = r.import_card_id
  prval () = fold@(st) in v end
implement app_set_import_card_id(st, v) = let
  val @APP_STATE(r) = st val () = r.import_card_id := v
  prval () = fold@(st) in end

implement app_get_import_card_bar_id(st) = let
  val @APP_STATE(r) = st val v = r.import_card_bar_id
  prval () = fold@(st) in v end
implement app_set_import_card_bar_id(st, v) = let
  val @APP_STATE(r) = st val () = r.import_card_bar_id := v
  prval () = fold@(st) in end

implement app_get_import_card_status_id(st) = let
  val @APP_STATE(r) = st val v = r.import_card_status_id
  prval () = fold@(st) in v end
implement app_set_import_card_status_id(st, v) = let
  val @APP_STATE(r) = st val () = r.import_card_status_id := v
  prval () = fold@(st) in end

implement app_get_ctx_overlay_id(st) = let
  val @APP_STATE(r) = st val v = r.ctx_overlay_id
  prval () = fold@(st) in v end
implement app_set_ctx_overlay_id(st, v) = let
  val @APP_STATE(r) = st val () = r.ctx_overlay_id := v
  prval () = fold@(st) in end

implement app_get_info_overlay_id(st) = let
  val @APP_STATE(r) = st val v = r.info_overlay_id
  prval () = fold@(st) in v end
implement app_set_info_overlay_id(st, v) = let
  val @APP_STATE(r) = st val () = r.info_overlay_id := v
  prval () = fold@(st) in end

(* ========== Delete modal state ========== *)

implement app_get_del_overlay_id(st) = let
  val @APP_STATE(r) = st val v = r.del_overlay_id
  prval () = fold@(st) in v end
implement app_set_del_overlay_id(st, v) = let
  val @APP_STATE(r) = st val () = r.del_overlay_id := v
  prval () = fold@(st) in end
implement app_get_del_choice(st) = let
  val @APP_STATE(r) = st val v = r.del_choice
  prval () = fold@(st) in v end
implement app_set_del_choice(st, v) = let
  val @APP_STATE(r) = st val () = r.del_choice := v
  prval () = fold@(st) in end

implement _app_import_card_id() = let val st = app_state_load()
  val v = app_get_import_card_id(st) val () = app_state_store(st) in v end
implement _app_set_import_card_id(v) = let val st = app_state_load()
  val () = app_set_import_card_id(st, v) val () = app_state_store(st) in end
implement _app_import_card_bar_id() = let val st = app_state_load()
  val v = app_get_import_card_bar_id(st) val () = app_state_store(st) in v end
implement _app_set_import_card_bar_id(v) = let val st = app_state_load()
  val () = app_set_import_card_bar_id(st, v) val () = app_state_store(st) in end
implement _app_import_card_status_id() = let val st = app_state_load()
  val v = app_get_import_card_status_id(st) val () = app_state_store(st) in v end
implement _app_set_import_card_status_id(v) = let val st = app_state_load()
  val () = app_set_import_card_status_id(st, v) val () = app_state_store(st) in end
implement _app_ctx_overlay_id() = let val st = app_state_load()
  val v = app_get_ctx_overlay_id(st) val () = app_state_store(st) in v end
implement _app_set_ctx_overlay_id(v) = let val st = app_state_load()
  val () = app_set_ctx_overlay_id(st, v) val () = app_state_store(st) in end
implement _app_info_overlay_id() = let val st = app_state_load()
  val v = app_get_info_overlay_id(st) val () = app_state_store(st) in v end
implement _app_set_info_overlay_id(v) = let val st = app_state_load()
  val () = app_set_info_overlay_id(st, v) val () = app_state_store(st) in end
implement _app_del_overlay_id() = let val st = app_state_load()
  val v = app_get_del_overlay_id(st) val () = app_state_store(st) in v end
implement _app_set_del_overlay_id(v) = let val st = app_state_load()
  val () = app_set_del_overlay_id(st, v) val () = app_state_store(st) in end
implement _app_del_choice() = let val st = app_state_load()
  val v = app_get_del_choice(st) val () = app_state_store(st) in v end
implement _app_set_del_choice(v) = let val st = app_state_load()
  val () = app_set_del_choice(st, v) val () = app_state_store(st) in end

(* ========== C-callable wrappers for library module ========== *)

implement _app_lib_count() = let val st = app_state_load()
  val v = app_get_library_count(st) val () = app_state_store(st) in v end
implement _app_set_lib_count(v) = let val st = app_state_load()
  val () = app_set_library_count(st, v) val () = app_state_store(st) in end
implement _app_lib_save_pend() = let val st = app_state_load()
  val v = app_get_lib_save_pending(st) val () = app_state_store(st) in v end
implement _app_set_lib_save_pend(v) = let val st = app_state_load()
  val () = app_set_lib_save_pending(st, v) val () = app_state_store(st) in end
implement _app_lib_load_pend() = let val st = app_state_load()
  val v = app_get_lib_load_pending(st) val () = app_state_store(st) in v end
implement _app_set_lib_load_pend(v) = let val st = app_state_load()
  val () = app_set_lib_load_pending(st, v) val () = app_state_store(st) in end
implement _app_lib_meta_save_pend() = let val st = app_state_load()
  val v = app_get_lib_meta_save_pending(st) val () = app_state_store(st) in v end
implement _app_set_lib_meta_save_pend(v) = let val st = app_state_load()
  val () = app_set_lib_meta_save_pending(st, v) val () = app_state_store(st) in end
implement _app_lib_meta_load_pend() = let val st = app_state_load()
  val v = app_get_lib_meta_load_pending(st) val () = app_state_store(st) in v end
implement _app_set_lib_meta_load_pend(v) = let val st = app_state_load()
  val () = app_set_lib_meta_load_pending(st, v) val () = app_state_store(st) in end
implement _app_lib_meta_load_idx() = let val st = app_state_load()
  val v = app_get_lib_meta_load_index(st) val () = app_state_store(st) in v end
implement _app_set_lib_meta_load_idx(v) = let val st = app_state_load()
  val () = app_set_lib_meta_load_index(st, v) val () = app_state_store(st) in end
implement _app_lib_view_mode() = let val st = app_state_load()
  val v = app_get_lib_view_mode(st) val () = app_state_store(st) in v end
implement _app_set_lib_view_mode(v) = let val st = app_state_load()
  val () = app_set_lib_view_mode(st, v) val () = app_state_store(st) in end
implement _app_lib_sort_mode() = let val st = app_state_load()
  val v = app_get_lib_sort_mode(st) val () = app_state_store(st) in v end
implement _app_set_lib_sort_mode(v) = let val st = app_state_load()
  val () = app_set_lib_sort_mode(st, v) val () = app_state_store(st) in end

(* ========== Library books buffer accessors ========== *)

implement _app_lib_books_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.library_books, off, LIB_BOOKS_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_lib_books_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.library_books, off, LIB_BOOKS_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_lib_books_get_i32(idx) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.library_books, idx, LIB_BOOKS_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_lib_books_set_i32(idx, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.library_books, idx, LIB_BOOKS_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== Settings state ========== *)

implement app_get_stg_font_size(st) = let
  val @APP_STATE(r) = st val v = r.stg_font_size
  prval () = fold@(st) in v end
implement app_set_stg_font_size(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_font_size := v
  prval () = fold@(st) in end
implement app_get_stg_font_family(st) = let
  val @APP_STATE(r) = st val v = r.stg_font_family
  prval () = fold@(st) in v end
implement app_set_stg_font_family(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_font_family := v
  prval () = fold@(st) in end
implement app_get_stg_theme(st) = let
  val @APP_STATE(r) = st val v = r.stg_theme
  prval () = fold@(st) in v end
implement app_set_stg_theme(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_theme := v
  prval () = fold@(st) in end
implement app_get_stg_lh_tenths(st) = let
  val @APP_STATE(r) = st val v = r.stg_lh_tenths
  prval () = fold@(st) in v end
implement app_set_stg_lh_tenths(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_lh_tenths := v
  prval () = fold@(st) in end
implement app_get_stg_margin(st) = let
  val @APP_STATE(r) = st val v = r.stg_margin
  prval () = fold@(st) in v end
implement app_set_stg_margin(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_margin := v
  prval () = fold@(st) in end

implement app_get_stg_visible(st) = let
  val @APP_STATE(r) = st val v = r.stg_visible
  prval () = fold@(st) in v end
implement app_set_stg_visible(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_visible := v
  prval () = fold@(st) in end
implement app_get_stg_overlay_id(st) = let
  val @APP_STATE(r) = st val v = r.stg_overlay_id
  prval () = fold@(st) in v end
implement app_set_stg_overlay_id(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_overlay_id := v
  prval () = fold@(st) in end
implement app_get_stg_close_id(st) = let
  val @APP_STATE(r) = st val v = r.stg_close_id
  prval () = fold@(st) in v end
implement app_set_stg_close_id(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_close_id := v
  prval () = fold@(st) in end
implement app_get_stg_root_id(st) = let
  val @APP_STATE(r) = st val v = r.stg_root_id
  prval () = fold@(st) in v end
implement app_set_stg_root_id(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_root_id := v
  prval () = fold@(st) in end

implement app_get_stg_btn_font_minus(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_font_minus
  prval () = fold@(st) in v end
implement app_set_stg_btn_font_minus(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_font_minus := v
  prval () = fold@(st) in end
implement app_get_stg_btn_font_plus(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_font_plus
  prval () = fold@(st) in v end
implement app_set_stg_btn_font_plus(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_font_plus := v
  prval () = fold@(st) in end
implement app_get_stg_btn_font_fam(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_font_fam
  prval () = fold@(st) in v end
implement app_set_stg_btn_font_fam(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_font_fam := v
  prval () = fold@(st) in end
implement app_get_stg_btn_theme_l(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_theme_l
  prval () = fold@(st) in v end
implement app_set_stg_btn_theme_l(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_theme_l := v
  prval () = fold@(st) in end
implement app_get_stg_btn_theme_d(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_theme_d
  prval () = fold@(st) in v end
implement app_set_stg_btn_theme_d(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_theme_d := v
  prval () = fold@(st) in end
implement app_get_stg_btn_theme_s(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_theme_s
  prval () = fold@(st) in v end
implement app_set_stg_btn_theme_s(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_theme_s := v
  prval () = fold@(st) in end
implement app_get_stg_btn_lh_minus(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_lh_minus
  prval () = fold@(st) in v end
implement app_set_stg_btn_lh_minus(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_lh_minus := v
  prval () = fold@(st) in end
implement app_get_stg_btn_lh_plus(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_lh_plus
  prval () = fold@(st) in v end
implement app_set_stg_btn_lh_plus(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_lh_plus := v
  prval () = fold@(st) in end
implement app_get_stg_btn_mg_minus(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_mg_minus
  prval () = fold@(st) in v end
implement app_set_stg_btn_mg_minus(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_mg_minus := v
  prval () = fold@(st) in end
implement app_get_stg_btn_mg_plus(st) = let
  val @APP_STATE(r) = st val v = r.stg_btn_mg_plus
  prval () = fold@(st) in v end
implement app_set_stg_btn_mg_plus(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_btn_mg_plus := v
  prval () = fold@(st) in end

implement app_get_stg_disp_fs(st) = let
  val @APP_STATE(r) = st val v = r.stg_disp_fs
  prval () = fold@(st) in v end
implement app_set_stg_disp_fs(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_disp_fs := v
  prval () = fold@(st) in end
implement app_get_stg_disp_ff(st) = let
  val @APP_STATE(r) = st val v = r.stg_disp_ff
  prval () = fold@(st) in v end
implement app_set_stg_disp_ff(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_disp_ff := v
  prval () = fold@(st) in end
implement app_get_stg_disp_lh(st) = let
  val @APP_STATE(r) = st val v = r.stg_disp_lh
  prval () = fold@(st) in v end
implement app_set_stg_disp_lh(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_disp_lh := v
  prval () = fold@(st) in end
implement app_get_stg_disp_mg(st) = let
  val @APP_STATE(r) = st val v = r.stg_disp_mg
  prval () = fold@(st) in v end
implement app_set_stg_disp_mg(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_disp_mg := v
  prval () = fold@(st) in end

implement app_get_stg_save_pend(st) = let
  val @APP_STATE(r) = st val v = r.stg_save_pend
  prval () = fold@(st) in v end
implement app_set_stg_save_pend(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_save_pend := v
  prval () = fold@(st) in end
implement app_get_stg_load_pend(st) = let
  val @APP_STATE(r) = st val v = r.stg_load_pend
  prval () = fold@(st) in v end
implement app_set_stg_load_pend(st, v) = let
  val @APP_STATE(r) = st val () = r.stg_load_pend := v
  prval () = fold@(st) in end

(* ========== Reader state ========== *)

implement app_get_rdr_active(st) = let
  val @APP_STATE(r) = st val v = r.rdr_active
  prval () = fold@(st) in v end
implement app_set_rdr_active(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_active := v
  prval () = fold@(st) in end
implement app_get_rdr_book_index(st) = let
  val @APP_STATE(r) = st val v = r.rdr_book_index
  prval () = fold@(st) in v end
implement app_set_rdr_book_index(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_book_index := v
  prval () = fold@(st) in end
implement app_get_rdr_current_chapter(st) = let
  val @APP_STATE(r) = st val v = r.rdr_current_chapter
  prval () = fold@(st) in v end
implement app_set_rdr_current_chapter(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_current_chapter := v
  prval () = fold@(st) in end
implement app_get_rdr_current_page(st) = let
  val @APP_STATE(r) = st val v = r.rdr_current_page
  prval () = fold@(st) in v end
implement app_set_rdr_current_page(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_current_page := v
  prval () = fold@(st) in end
implement app_get_rdr_total_pages(st) = let
  val @APP_STATE(r) = st val v = r.rdr_total_pages
  prval () = fold@(st) in v end
implement app_set_rdr_total_pages(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_total_pages := v
  prval () = fold@(st) in end
implement app_get_rdr_viewport_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_viewport_id
  prval () = fold@(st) in v end
implement app_set_rdr_viewport_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_viewport_id := v
  prval () = fold@(st) in end
implement app_get_rdr_container_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_container_id
  prval () = fold@(st) in v end
implement app_set_rdr_container_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_container_id := v
  prval () = fold@(st) in end
implement app_get_rdr_root_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_root_id
  prval () = fold@(st) in v end
implement app_set_rdr_root_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_root_id := v
  prval () = fold@(st) in end
implement app_get_rdr_file_handle(st) = let
  val @APP_STATE(r) = st val v = r.rdr_file_handle
  prval () = fold@(st) in v end
implement app_set_rdr_file_handle(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_file_handle := v
  prval () = fold@(st) in end
implement app_get_rdr_page_info_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_page_info_id
  prval () = fold@(st) in v end
implement app_set_rdr_page_info_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_page_info_id := v
  prval () = fold@(st) in end
implement app_get_rdr_nav_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_nav_id
  prval () = fold@(st) in v end
implement app_set_rdr_nav_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_nav_id := v
  prval () = fold@(st) in end
implement app_get_rdr_resume_page(st) = let
  val @APP_STATE(r) = st val v = r.rdr_resume_page
  prval () = fold@(st) in v end
implement app_set_rdr_resume_page(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_resume_page := v
  prval () = fold@(st) in end
implement app_get_rdr_chrome_visible(st) = let
  val @APP_STATE(r) = st val v = r.rdr_chrome_visible
  prval () = fold@(st) in v end
implement app_set_rdr_chrome_visible(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_chrome_visible := v
  prval () = fold@(st) in end
implement app_get_rdr_chrome_timer_gen(st) = let
  val @APP_STATE(r) = st val v = r.rdr_chrome_timer_gen
  prval () = fold@(st) in v end
implement app_set_rdr_chrome_timer_gen(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_chrome_timer_gen := v
  prval () = fold@(st) in end
implement app_get_rdr_chapter_title_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_chapter_title_id
  prval () = fold@(st) in v end
implement app_set_rdr_chapter_title_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_chapter_title_id := v
  prval () = fold@(st) in end

implement app_get_rdr_bm_count(st) = let
  val @APP_STATE(r) = st val v = r.rdr_bm_count
  prval () = fold@(st) in v end
implement app_set_rdr_bm_count(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_bm_count := v
  prval () = fold@(st) in end
implement app_get_rdr_bm_btn_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_bm_btn_id
  prval () = fold@(st) in v end
implement app_set_rdr_bm_btn_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_bm_btn_id := v
  prval () = fold@(st) in end
implement app_get_rdr_bm_save_pending(st) = let
  val @APP_STATE(r) = st val v = r.rdr_bm_save_pending
  prval () = fold@(st) in v end
implement app_set_rdr_bm_save_pending(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_bm_save_pending := v
  prval () = fold@(st) in end

implement app_get_rdr_toc_panel_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_toc_panel_id
  prval () = fold@(st) in v end
implement app_set_rdr_toc_panel_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_toc_panel_id := v
  prval () = fold@(st) in end
implement app_get_rdr_toc_list_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_toc_list_id
  prval () = fold@(st) in v end
implement app_set_rdr_toc_list_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_toc_list_id := v
  prval () = fold@(st) in end
implement app_get_rdr_toc_close_btn_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_toc_close_btn_id
  prval () = fold@(st) in v end
implement app_set_rdr_toc_close_btn_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_toc_close_btn_id := v
  prval () = fold@(st) in end
implement app_get_rdr_toc_bm_count_btn_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_toc_bm_count_btn_id
  prval () = fold@(st) in v end
implement app_set_rdr_toc_bm_count_btn_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_toc_bm_count_btn_id := v
  prval () = fold@(st) in end
implement app_get_rdr_toc_switch_btn_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_toc_switch_btn_id
  prval () = fold@(st) in v end
implement app_set_rdr_toc_switch_btn_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_toc_switch_btn_id := v
  prval () = fold@(st) in end
implement app_get_rdr_toc_view_mode(st) = let
  val @APP_STATE(r) = st val v = r.rdr_toc_view_mode
  prval () = fold@(st) in v end
implement app_set_rdr_toc_view_mode(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_toc_view_mode := v
  prval () = fold@(st) in end
implement app_get_rdr_toc_first_entry_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_toc_first_entry_id
  prval () = fold@(st) in v end
implement app_set_rdr_toc_first_entry_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_toc_first_entry_id := v
  prval () = fold@(st) in end
implement app_get_rdr_toc_entry_count(st) = let
  val @APP_STATE(r) = st val v = r.rdr_toc_entry_count
  prval () = fold@(st) in v end
implement app_set_rdr_toc_entry_count(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_toc_entry_count := v
  prval () = fold@(st) in end
implement app_get_rdr_bm_first_entry_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_bm_first_entry_id
  prval () = fold@(st) in v end
implement app_set_rdr_bm_first_entry_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_bm_first_entry_id := v
  prval () = fold@(st) in end

implement app_get_rdr_scrub_bar_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_scrub_bar_id
  prval () = fold@(st) in v end
implement app_set_rdr_scrub_bar_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_scrub_bar_id := v
  prval () = fold@(st) in end
implement app_get_rdr_scrub_track_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_scrub_track_id
  prval () = fold@(st) in v end
implement app_set_rdr_scrub_track_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_scrub_track_id := v
  prval () = fold@(st) in end
implement app_get_rdr_scrub_fill_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_scrub_fill_id
  prval () = fold@(st) in v end
implement app_set_rdr_scrub_fill_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_scrub_fill_id := v
  prval () = fold@(st) in end
implement app_get_rdr_scrub_handle_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_scrub_handle_id
  prval () = fold@(st) in v end
implement app_set_rdr_scrub_handle_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_scrub_handle_id := v
  prval () = fold@(st) in end
implement app_get_rdr_scrub_tooltip_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_scrub_tooltip_id
  prval () = fold@(st) in v end
implement app_set_rdr_scrub_tooltip_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_scrub_tooltip_id := v
  prval () = fold@(st) in end
implement app_get_rdr_scrub_text_id(st) = let
  val @APP_STATE(r) = st val v = r.rdr_scrub_text_id
  prval () = fold@(st) in v end
implement app_set_rdr_scrub_text_id(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_scrub_text_id := v
  prval () = fold@(st) in end
implement app_get_rdr_scrub_dragging(st) = let
  val @APP_STATE(r) = st val v = r.rdr_scrub_dragging
  prval () = fold@(st) in v end
implement app_set_rdr_scrub_dragging{d}(pf | st, v) = let
  prval _ = pf
  val @APP_STATE(r) = st val () = r.rdr_scrub_dragging := v
  prval () = fold@(st) in end
implement app_get_rdr_scrub_drag_ch(st) = let
  val @APP_STATE(r) = st val v = r.rdr_scrub_drag_ch
  prval () = fold@(st) in v end
implement app_set_rdr_scrub_drag_ch(st, v) = let
  val @APP_STATE(r) = st val () = r.rdr_scrub_drag_ch := v
  prval () = fold@(st) in end

implement _app_rdr_toc_panel_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_panel_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_toc_panel_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_panel_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_toc_list_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_list_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_toc_list_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_list_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_toc_close_btn_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_close_btn_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_toc_close_btn_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_close_btn_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_toc_bm_count_btn_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_bm_count_btn_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_toc_bm_count_btn_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_bm_count_btn_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_toc_switch_btn_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_switch_btn_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_toc_switch_btn_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_switch_btn_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_toc_view_mode() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_view_mode(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_toc_view_mode(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_view_mode(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_toc_first_entry_id() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_first_entry_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_toc_first_entry_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_first_entry_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_toc_entry_count() = let
  val st = app_state_load()
  val v = app_get_rdr_toc_entry_count(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_toc_entry_count(v) = let
  val st = app_state_load()
  val () = app_set_rdr_toc_entry_count(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_bm_first_entry_id() = let
  val st = app_state_load()
  val v = app_get_rdr_bm_first_entry_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_bm_first_entry_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_bm_first_entry_id(st, v)
  val () = app_state_store(st)
in end

implement _app_rdr_scrub_bar_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_bar_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_scrub_bar_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_bar_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_scrub_track_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_track_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_scrub_track_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_track_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_scrub_fill_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_fill_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_scrub_fill_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_fill_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_scrub_handle_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_handle_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_scrub_handle_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_handle_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_scrub_tooltip_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_tooltip_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_scrub_tooltip_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_tooltip_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_scrub_text_id() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_text_id(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_scrub_text_id(v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_text_id(st, v)
  val () = app_state_store(st)
in end
implement _app_rdr_scrub_dragging() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_dragging(st)
  val () = app_state_store(st)
in v end
implement _app_rdr_scrub_drag_ch() = let
  val st = app_state_load()
  val v = app_get_rdr_scrub_drag_ch(st)
  val () = app_state_store(st)
in v end
implement _app_set_rdr_scrub_drag_ch(v) = let
  val st = app_state_load()
  val () = app_set_rdr_scrub_drag_ch(st, v)
  val () = app_state_store(st)
in end

implement _app_bm_buf_get_i32(idx) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.rdr_bm_buf, idx, BOOKMARK_BUF_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_bm_buf_set_i32(idx, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.rdr_bm_buf, idx, BOOKMARK_BUF_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement app_get_rdr_btn_id(st, idx) = let
  val @APP_STATE(r) = st
  val v = if gte_int_int(idx, 0) then
            if lt_int_int(idx, 128) then _arr_get_i32(r.rdr_btn_ids, idx, RDR_BTNS_SIZE)
            else 0 - 1
          else 0 - 1
  prval () = fold@(st)
in v end
implement app_set_rdr_btn_id(st, idx, v) = let
  val @APP_STATE(r) = st
  val () = if gte_int_int(idx, 0) then
             if lt_int_int(idx, 128) then _arr_set_i32(r.rdr_btn_ids, idx, RDR_BTNS_SIZE, v)
  prval () = fold@(st)
in end

(* ========== EPUB scalar state ========== *)

implement app_get_epub_spine_count(st) = let
  val @APP_STATE(r) = st val v = r.epub_spine_count
  prval () = fold@(st) in v end
implement app_set_epub_spine_count(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_spine_count := v
  prval () = fold@(st) in end

implement app_get_epub_title_len(st) = let
  val @APP_STATE(r) = st val v = r.epub_title_len
  prval () = fold@(st) in v end
implement app_set_epub_title_len(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_title_len := v
  prval () = fold@(st) in end
implement app_get_epub_author_len(st) = let
  val @APP_STATE(r) = st val v = r.epub_author_len
  prval () = fold@(st) in v end
implement app_set_epub_author_len(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_author_len := v
  prval () = fold@(st) in end
implement app_get_epub_book_id_len(st) = let
  val @APP_STATE(r) = st val v = r.epub_book_id_len
  prval () = fold@(st) in v end
implement app_set_epub_book_id_len(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_book_id_len := v
  prval () = fold@(st) in end
implement app_get_epub_opf_path_len(st) = let
  val @APP_STATE(r) = st val v = r.epub_opf_path_len
  prval () = fold@(st) in v end
implement app_set_epub_opf_path_len(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_opf_path_len := v
  prval () = fold@(st) in end
implement app_get_epub_opf_dir_len(st) = let
  val @APP_STATE(r) = st val v = r.epub_opf_dir_len
  prval () = fold@(st) in v end
implement app_set_epub_opf_dir_len(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_opf_dir_len := v
  prval () = fold@(st) in end
implement app_get_epub_state(st) = let
  val @APP_STATE(r) = st val v = r.epub_state
  prval () = fold@(st) in v end
implement app_set_epub_state(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_state := v
  prval () = fold@(st) in end
implement app_get_epub_spine_path_count(st) = let
  val @APP_STATE(r) = st val v = r.epub_spine_path_count
  prval () = fold@(st) in v end
implement app_set_epub_spine_path_count(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_spine_path_count := v
  prval () = fold@(st) in end
implement app_get_epub_spine_path_pos(st) = let
  val @APP_STATE(r) = st val v = r.epub_spine_path_pos
  prval () = fold@(st) in v end
implement app_set_epub_spine_path_pos(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_spine_path_pos := v
  prval () = fold@(st) in end

(* ========== C-callable wrappers for settings module ========== *)

implement _app_stg_font_size() = let val st = app_state_load()
  val v = app_get_stg_font_size(st) val () = app_state_store(st) in v end
implement _app_set_stg_font_size(v) = let val st = app_state_load()
  val () = app_set_stg_font_size(st, v) val () = app_state_store(st) in end
implement _app_stg_font_family() = let val st = app_state_load()
  val v = app_get_stg_font_family(st) val () = app_state_store(st) in v end
implement _app_set_stg_font_family(v) = let val st = app_state_load()
  val () = app_set_stg_font_family(st, v) val () = app_state_store(st) in end
implement _app_stg_theme() = let val st = app_state_load()
  val v = app_get_stg_theme(st) val () = app_state_store(st) in v end
implement _app_set_stg_theme(v) = let val st = app_state_load()
  val () = app_set_stg_theme(st, v) val () = app_state_store(st) in end
implement _app_stg_lh_tenths() = let val st = app_state_load()
  val v = app_get_stg_lh_tenths(st) val () = app_state_store(st) in v end
implement _app_set_stg_lh_tenths(v) = let val st = app_state_load()
  val () = app_set_stg_lh_tenths(st, v) val () = app_state_store(st) in end
implement _app_stg_margin() = let val st = app_state_load()
  val v = app_get_stg_margin(st) val () = app_state_store(st) in v end
implement _app_set_stg_margin(v) = let val st = app_state_load()
  val () = app_set_stg_margin(st, v) val () = app_state_store(st) in end
implement _app_stg_visible() = let val st = app_state_load()
  val v = app_get_stg_visible(st) val () = app_state_store(st) in v end
implement _app_set_stg_visible(v) = let val st = app_state_load()
  val () = app_set_stg_visible(st, v) val () = app_state_store(st) in end
implement _app_stg_overlay_id() = let val st = app_state_load()
  val v = app_get_stg_overlay_id(st) val () = app_state_store(st) in v end
implement _app_set_stg_overlay_id(v) = let val st = app_state_load()
  val () = app_set_stg_overlay_id(st, v) val () = app_state_store(st) in end
implement _app_stg_close_id() = let val st = app_state_load()
  val v = app_get_stg_close_id(st) val () = app_state_store(st) in v end
implement _app_set_stg_close_id(v) = let val st = app_state_load()
  val () = app_set_stg_close_id(st, v) val () = app_state_store(st) in end
implement _app_stg_root_id() = let val st = app_state_load()
  val v = app_get_stg_root_id(st) val () = app_state_store(st) in v end
implement _app_set_stg_root_id(v) = let val st = app_state_load()
  val () = app_set_stg_root_id(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_font_minus() = let val st = app_state_load()
  val v = app_get_stg_btn_font_minus(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_font_minus(v) = let val st = app_state_load()
  val () = app_set_stg_btn_font_minus(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_font_plus() = let val st = app_state_load()
  val v = app_get_stg_btn_font_plus(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_font_plus(v) = let val st = app_state_load()
  val () = app_set_stg_btn_font_plus(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_font_fam() = let val st = app_state_load()
  val v = app_get_stg_btn_font_fam(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_font_fam(v) = let val st = app_state_load()
  val () = app_set_stg_btn_font_fam(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_theme_l() = let val st = app_state_load()
  val v = app_get_stg_btn_theme_l(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_theme_l(v) = let val st = app_state_load()
  val () = app_set_stg_btn_theme_l(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_theme_d() = let val st = app_state_load()
  val v = app_get_stg_btn_theme_d(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_theme_d(v) = let val st = app_state_load()
  val () = app_set_stg_btn_theme_d(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_theme_s() = let val st = app_state_load()
  val v = app_get_stg_btn_theme_s(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_theme_s(v) = let val st = app_state_load()
  val () = app_set_stg_btn_theme_s(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_lh_minus() = let val st = app_state_load()
  val v = app_get_stg_btn_lh_minus(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_lh_minus(v) = let val st = app_state_load()
  val () = app_set_stg_btn_lh_minus(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_lh_plus() = let val st = app_state_load()
  val v = app_get_stg_btn_lh_plus(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_lh_plus(v) = let val st = app_state_load()
  val () = app_set_stg_btn_lh_plus(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_mg_minus() = let val st = app_state_load()
  val v = app_get_stg_btn_mg_minus(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_mg_minus(v) = let val st = app_state_load()
  val () = app_set_stg_btn_mg_minus(st, v) val () = app_state_store(st) in end
implement _app_stg_btn_mg_plus() = let val st = app_state_load()
  val v = app_get_stg_btn_mg_plus(st) val () = app_state_store(st) in v end
implement _app_set_stg_btn_mg_plus(v) = let val st = app_state_load()
  val () = app_set_stg_btn_mg_plus(st, v) val () = app_state_store(st) in end
implement _app_stg_disp_fs() = let val st = app_state_load()
  val v = app_get_stg_disp_fs(st) val () = app_state_store(st) in v end
implement _app_set_stg_disp_fs(v) = let val st = app_state_load()
  val () = app_set_stg_disp_fs(st, v) val () = app_state_store(st) in end
implement _app_stg_disp_ff() = let val st = app_state_load()
  val v = app_get_stg_disp_ff(st) val () = app_state_store(st) in v end
implement _app_set_stg_disp_ff(v) = let val st = app_state_load()
  val () = app_set_stg_disp_ff(st, v) val () = app_state_store(st) in end
implement _app_stg_disp_lh() = let val st = app_state_load()
  val v = app_get_stg_disp_lh(st) val () = app_state_store(st) in v end
implement _app_set_stg_disp_lh(v) = let val st = app_state_load()
  val () = app_set_stg_disp_lh(st, v) val () = app_state_store(st) in end
implement _app_stg_disp_mg() = let val st = app_state_load()
  val v = app_get_stg_disp_mg(st) val () = app_state_store(st) in v end
implement _app_set_stg_disp_mg(v) = let val st = app_state_load()
  val () = app_set_stg_disp_mg(st, v) val () = app_state_store(st) in end
implement _app_stg_save_pend() = let val st = app_state_load()
  val v = app_get_stg_save_pend(st) val () = app_state_store(st) in v end
implement _app_set_stg_save_pend(v) = let val st = app_state_load()
  val () = app_set_stg_save_pend(st, v) val () = app_state_store(st) in end
implement _app_stg_load_pend() = let val st = app_state_load()
  val v = app_get_stg_load_pend(st) val () = app_state_store(st) in v end
implement _app_set_stg_load_pend(v) = let val st = app_state_load()
  val () = app_set_stg_load_pend(st, v) val () = app_state_store(st) in end

(* ========== C-callable wrappers for EPUB scalar fields ========== *)

implement _app_epub_spine_count() = let val st = app_state_load()
  val v = app_get_epub_spine_count(st) val () = app_state_store(st) in v end
implement _app_set_epub_spine_count(v) = let val st = app_state_load()
  val () = app_set_epub_spine_count(st, v) val () = app_state_store(st) in end
implement _app_epub_title_len() = let val st = app_state_load()
  val v = app_get_epub_title_len(st) val () = app_state_store(st) in v end
implement _app_set_epub_title_len(v) = let val st = app_state_load()
  val () = app_set_epub_title_len(st, v) val () = app_state_store(st) in end
implement _app_epub_author_len() = let val st = app_state_load()
  val v = app_get_epub_author_len(st) val () = app_state_store(st) in v end
implement _app_set_epub_author_len(v) = let val st = app_state_load()
  val () = app_set_epub_author_len(st, v) val () = app_state_store(st) in end
implement _app_epub_book_id_len() = let val st = app_state_load()
  val v = app_get_epub_book_id_len(st) val () = app_state_store(st) in v end
implement _app_set_epub_book_id_len(v) = let val st = app_state_load()
  val () = app_set_epub_book_id_len(st, v) val () = app_state_store(st) in end
implement _app_epub_opf_path_len() = let val st = app_state_load()
  val v = app_get_epub_opf_path_len(st) val () = app_state_store(st) in v end
implement _app_set_epub_opf_path_len(v) = let val st = app_state_load()
  val () = app_set_epub_opf_path_len(st, v) val () = app_state_store(st) in end
implement _app_epub_opf_dir_len() = let val st = app_state_load()
  val v = app_get_epub_opf_dir_len(st) val () = app_state_store(st) in v end
implement _app_set_epub_opf_dir_len(v) = let val st = app_state_load()
  val () = app_set_epub_opf_dir_len(st, v) val () = app_state_store(st) in end
implement _app_epub_state() = let val st = app_state_load()
  val v = app_get_epub_state(st) val () = app_state_store(st) in v end
implement _app_set_epub_state(v) = let val st = app_state_load()
  val () = app_set_epub_state(st, v) val () = app_state_store(st) in end
implement _app_epub_spine_path_count() = let val st = app_state_load()
  val v = app_get_epub_spine_path_count(st) val () = app_state_store(st) in v end
implement _app_set_epub_spine_path_count(v) = let val st = app_state_load()
  val () = app_set_epub_spine_path_count(st, v) val () = app_state_store(st) in end
implement _app_epub_spine_path_pos() = let val st = app_state_load()
  val v = app_get_epub_spine_path_pos(st) val () = app_state_store(st) in v end
implement _app_set_epub_spine_path_pos(v) = let val st = app_state_load()
  val () = app_set_epub_spine_path_pos(st, v) val () = app_state_store(st) in end

(* ========== EPUB title buffer accessors ========== *)

implement _app_epub_title_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.epub_title, off, EPUB_TITLE_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_title_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.epub_title, off, EPUB_TITLE_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== EPUB author buffer accessors ========== *)

implement _app_epub_author_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.epub_author, off, EPUB_AUTHOR_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_author_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.epub_author, off, EPUB_AUTHOR_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== EPUB book ID buffer accessors ========== *)

implement _app_epub_book_id_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.epub_book_id, off, EPUB_BOOKID_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_book_id_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.epub_book_id, off, EPUB_BOOKID_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== EPUB OPF path buffer accessors ========== *)

implement _app_epub_opf_path_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.epub_opf_path, off, EPUB_OPF_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_opf_path_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.epub_opf_path, off, EPUB_OPF_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== EPUB spine path buffer accessors ========== *)

implement _app_epub_spine_buf_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.epub_spine_path_buf, off, EPUB_SPINE_BUF_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_spine_buf_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.epub_spine_path_buf, off, EPUB_SPINE_BUF_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== EPUB spine offsets/lens (i32 access) ========== *)

implement _app_epub_spine_offsets_get_i32(idx) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.epub_spine_path_offsets, idx, EPUB_SPINE_OFF_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_spine_offsets_set_i32(idx, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.epub_spine_path_offsets, idx, EPUB_SPINE_OFF_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_epub_spine_lens_get_i32(idx) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.epub_spine_path_lens, idx, EPUB_SPINE_LEN_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_spine_lens_set_i32(idx, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.epub_spine_path_lens, idx, EPUB_SPINE_LEN_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== String buffer accessors ========== *)

implement _app_sbuf_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.string_buffer, off, STRING_BUFFER_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_sbuf_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.string_buffer, off, STRING_BUFFER_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== Fetch buffer accessors ========== *)

implement _app_fbuf_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.fetch_buffer, off, FETCH_BUFFER_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_fbuf_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.fetch_buffer, off, FETCH_BUFFER_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== Diff buffer accessors ========== *)

implement _app_dbuf_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.diff_buffer, off, DIFF_BUFFER_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_dbuf_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.diff_buffer, off, DIFF_BUFFER_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_dbuf_get_i32(idx) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.diff_buffer, idx, DIFF_BUFFER_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_dbuf_set_i32(idx, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.diff_buffer, idx, DIFF_BUFFER_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== Bulk copy functions ========== *)
(* Single load/store cycle for tight loops — avoids per-byte stash overhead *)

implement _app_copy_fbuf_to_epub_title(src_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, fp: ptr, tp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(fp, src_off + i, FETCH_BUFFER_SIZE)
      val () = _arr_set_u8(tp, i, EPUB_TITLE_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, fp, tp) end
  val () = loop(_checked_nat(len), 0, r.fetch_buffer, r.epub_title)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_fbuf_to_epub_author(src_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, fp: ptr, ap: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(fp, src_off + i, FETCH_BUFFER_SIZE)
      val () = _arr_set_u8(ap, i, EPUB_AUTHOR_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, fp, ap) end
  val () = loop(_checked_nat(len), 0, r.fetch_buffer, r.epub_author)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_fbuf_to_epub_book_id(src_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, fp: ptr, bp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(fp, src_off + i, FETCH_BUFFER_SIZE)
      val () = _arr_set_u8(bp, i, EPUB_BOOKID_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, fp, bp) end
  val () = loop(_checked_nat(len), 0, r.fetch_buffer, r.epub_book_id)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_fbuf_to_epub_opf_path(src_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, fp: ptr, ofp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(fp, src_off + i, FETCH_BUFFER_SIZE)
      val () = _arr_set_u8(ofp, i, EPUB_OPF_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, fp, ofp) end
  val () = loop(_checked_nat(len), 0, r.fetch_buffer, r.epub_opf_path)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_fbuf_to_epub_spine_buf(src_off, dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, fp: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(fp, src_off + i, FETCH_BUFFER_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, EPUB_SPINE_BUF_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, fp, sp) end
  val () = loop(_checked_nat(len), 0, r.fetch_buffer, r.epub_spine_path_buf)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_opf_path_to_epub_spine_buf(dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, opp: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(opp, i, EPUB_OPF_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, EPUB_SPINE_BUF_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, opp, sp) end
  val () = loop(_checked_nat(len), 0, r.epub_opf_path, r.epub_spine_path_buf)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_epub_title_to_sbuf(dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, tp: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(tp, i, EPUB_TITLE_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, STRING_BUFFER_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, tp, sp) end
  val () = loop(_checked_nat(len), 0, r.epub_title, r.string_buffer)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_epub_author_to_sbuf(dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, ap: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(ap, i, EPUB_AUTHOR_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, STRING_BUFFER_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, ap, sp) end
  val () = loop(_checked_nat(len), 0, r.epub_author, r.string_buffer)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_epub_book_id_to_sbuf(dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, bp: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(bp, i, EPUB_BOOKID_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, STRING_BUFFER_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, bp, sp) end
  val () = loop(_checked_nat(len), 0, r.epub_book_id, r.string_buffer)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_epub_opf_path_to_sbuf(dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, opp: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(opp, i, EPUB_OPF_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, STRING_BUFFER_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, opp, sp) end
  val () = loop(_checked_nat(len), 0, r.epub_opf_path, r.string_buffer)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_epub_spine_buf_to_sbuf(src_off, dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, ep: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(ep, src_off + i, EPUB_SPINE_BUF_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, STRING_BUFFER_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, ep, sp) end
  val () = loop(_checked_nat(len), 0, r.epub_spine_path_buf, r.string_buffer)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_sbuf_to_lib_books(dst_off, src_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, sp: ptr, lp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(sp, src_off + i, STRING_BUFFER_SIZE)
      val () = _arr_set_u8(lp, dst_off + i, LIB_BOOKS_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, sp, lp) end
  val () = loop(_checked_nat(len), 0, r.string_buffer, r.library_books)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_copy_lib_books_to_sbuf(src_off, dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, lp: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(lp, src_off + i, LIB_BOOKS_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, STRING_BUFFER_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, lp, sp) end
  val () = loop(_checked_nat(len), 0, r.library_books, r.string_buffer)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* Match epub_book_id against library_books at book_base offset.
 * Returns 1 if all bid_len bytes match, 0 otherwise. *)
implement _app_lib_books_match_bid(book_base, bid_len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, bp: ptr, lp: ptr): int =
    if lte_g1(rem, 0) then 1
    else if lt_int_int(i, bid_len) then let
      val b = _arr_get_u8(bp, i, EPUB_BOOKID_SIZE)
      val l = _arr_get_u8(lp, book_base + i, LIB_BOOKS_SIZE)
    in
      if eq_int_int(b, l) then loop(sub_g1(rem, 1), i + 1, bp, lp)
      else 0
    end
    else 1
  val v = loop(_checked_nat(bid_len), 0, r.epub_book_id, r.library_books)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

(* ========== EPUB manifest buffer accessors ========== *)

implement _app_epub_manifest_count() = let val st = app_state_load()
  val @APP_STATE(r) = st val v = r.epub_manifest_count
  prval () = fold@(st) val () = app_state_store(st) in v end
implement _app_set_epub_manifest_count(v) = let val st = app_state_load()
  val @APP_STATE(r) = st val () = r.epub_manifest_count := v
  prval () = fold@(st) val () = app_state_store(st) in end

implement _app_epub_manifest_names_get_u8(off) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.epub_manifest_names, off, EPUB_MANIFEST_NAMES_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_manifest_names_set_u8(off, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.epub_manifest_names, off, EPUB_MANIFEST_NAMES_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_epub_manifest_offsets_get_i32(idx) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.epub_manifest_offsets, idx, EPUB_MANIFEST_OFF_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_manifest_offsets_set_i32(idx, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.epub_manifest_offsets, idx, EPUB_MANIFEST_OFF_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_epub_manifest_lens_get_i32(idx) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.epub_manifest_lens, idx, EPUB_MANIFEST_LEN_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_manifest_lens_set_i32(idx, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.epub_manifest_lens, idx, EPUB_MANIFEST_LEN_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== Spine→entry index mapping ========== *)

implement _app_epub_spine_entry_idx_get(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.epub_spine_entry_idx, i, EPUB_SPINE_ENTRY_IDX_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_epub_spine_entry_idx_set(i, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.epub_spine_entry_idx, i, EPUB_SPINE_ENTRY_IDX_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* ========== Deferred image resolution queue ========== *)

implement _app_deferred_img_node_id_get(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.deferred_img_nid, i, DEFERRED_IMG_NID_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_deferred_img_node_id_set(i, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.deferred_img_nid, i, DEFERRED_IMG_NID_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_deferred_img_entry_idx_get(i) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_i32(r.deferred_img_eid, i, DEFERRED_IMG_EID_SIZE)
  prval () = fold@(st)
  val () = app_state_store(st)
in v end

implement _app_deferred_img_entry_idx_set(i, v) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_i32(r.deferred_img_eid, i, DEFERRED_IMG_EID_SIZE, v)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

implement _app_deferred_img_count() = let val st = app_state_load()
  val @APP_STATE(r) = st val v = r.deferred_img_count
  prval () = fold@(st) val () = app_state_store(st) in v end
implement _app_set_deferred_img_count(v) = let val st = app_state_load()
  val @APP_STATE(r) = st val () = r.deferred_img_count := v
  prval () = fold@(st) val () = app_state_store(st) in end

implement _app_epub_file_size() = let val st = app_state_load()
  val @APP_STATE(r) = st val v = r.epub_file_size
  prval () = fold@(st) val () = app_state_store(st) in v end
implement _app_set_epub_file_size(v) = let val st = app_state_load()
  val @APP_STATE(r) = st val () = r.epub_file_size := v
  prval () = fold@(st) val () = app_state_store(st) in end

(* EPUB cover href buffer accessors *)
implement _app_epub_cover_href_len() = let val st = app_state_load()
  val @APP_STATE(r) = st val v = r.epub_cover_href_len
  prval () = fold@(st) val () = app_state_store(st) in v end
implement _app_set_epub_cover_href_len(v) = let val st = app_state_load()
  val @APP_STATE(r) = st val () = r.epub_cover_href_len := v
  prval () = fold@(st) val () = app_state_store(st) in end

implement _app_epub_cover_href_get_u8(off) = let val st = app_state_load()
  val @APP_STATE(r) = st
  val v = _arr_get_u8(r.epub_cover_href, off, EPUB_COVER_HREF_SIZE)
  prval () = fold@(st) val () = app_state_store(st) in v end
implement _app_epub_cover_href_set_u8(off, v) = let val st = app_state_load()
  val @APP_STATE(r) = st
  val () = _arr_set_u8(r.epub_cover_href, off, EPUB_COVER_HREF_SIZE, v)
  prval () = fold@(st) val () = app_state_store(st) in end

implement _app_copy_epub_cover_href_to_sbuf(dst_off, len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, cp: ptr, sp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, len) then let
      val v = _arr_get_u8(cp, i, EPUB_COVER_HREF_SIZE)
      val () = _arr_set_u8(sp, dst_off + i, STRING_BUFFER_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, cp, sp) end
  val () = loop(_checked_nat(len), 0, r.epub_cover_href, r.string_buffer)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* Copy book_id bytes from library_books at book_base to epub_book_id *)
implement _app_copy_lib_book_id_to_epub(book_base, bid_len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  fun loop {k:nat} .<k>.
    (rem: int(k), i: int, lp: ptr, bp: ptr): void =
    if lte_g1(rem, 0) then ()
    else if lt_int_int(i, bid_len) then let
      val v = _arr_get_u8(lp, book_base + i, LIB_BOOKS_SIZE)
      val () = _arr_set_u8(bp, i, EPUB_BOOKID_SIZE, v)
    in loop(sub_g1(rem, 1), i + 1, lp, bp) end
  val () = loop(_checked_nat(bid_len), 0, r.library_books, r.epub_book_id)
  prval () = fold@(st)
  val () = app_state_store(st)
in end

(* Compare sbuf[0..sbuf_len-1] against manifest name at (name_off, name_len) *)
implement _app_manifest_name_match_sbuf(name_off, name_len, sbuf_len) = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val result =
    if neq_int_int(name_len, sbuf_len) then 0
    else let
      fun loop {k:nat} .<k>.
        (rem: int(k), i: int, mp: ptr, sp: ptr): int =
        if lte_g1(rem, 0) then 1
        else if lt_int_int(i, name_len) then let
          val a = _arr_get_u8(mp, name_off + i, EPUB_MANIFEST_NAMES_SIZE)
          val b = _arr_get_u8(sp, i, STRING_BUFFER_SIZE)
        in
          if eq_int_int(a, b) then loop(sub_g1(rem, 1), i + 1, mp, sp)
          else 0
        end
        else 1
    in loop(_checked_nat(name_len), 0, r.epub_manifest_names, r.string_buffer) end
  prval () = fold@(st)
  val () = app_state_store(st)
in result end

(* ========== Listener table stash ========== *)

(* app_state is stored in ward's listener table at slot 127.
 * mac# declarations erase app_state to atstype_ptrk, matching
 * ward_listener_set/get signatures. Same trust boundary as
 * ward's own resolver stash: one load per store. *)

extern fun _app_stash_set
  (id: int, st: app_state): void = "mac#ward_listener_set"
extern fun _app_stash_get
  (id: int): app_state = "mac#ward_listener_get"

implement app_state_register(st) =
  _app_stash_set(APP_STATE_SLOT, st)

implement app_state_store(st) =
  _app_stash_set(APP_STATE_SLOT, st)

implement app_state_load() =
  _app_stash_get(APP_STATE_SLOT)
