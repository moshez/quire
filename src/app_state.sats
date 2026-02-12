(* app_state.sats — Linear application state type
 *
 * Single linear type holding all mutable application state.
 * Threaded through functions as a parameter; stored in the
 * callback registry context across async boundaries.
 *
 * No mutable globals. No C code.
 *)

absvtype app_state

(* Lifecycle *)
fun app_state_init(): app_state
fun app_state_fini(st: app_state): void

(* Callback registry stash — for async boundaries.
 * register: first-time init, creates callback entry and stashes state.
 * store: puts state back into the callback registry ctx slot.
 * load: recovers state from the callback registry ctx slot.
 * load/store are the irreducible trust boundary — same pattern as
 * ward_dom_load in vendor/ward/lib/dom.dats. *)
fun app_state_register(st: app_state): void
fun app_state_store(st: app_state): void
fun app_state_load(): app_state

(* DOM state *)
fun app_get_dom_next_id(st: !app_state): int
fun app_set_dom_next_id(st: !app_state, v: int): void

(* ZIP state *)
fun app_get_zip_entry_count(st: !app_state): int
fun app_set_zip_entry_count(st: !app_state, v: int): void
fun app_get_zip_file_handle(st: !app_state): int
fun app_set_zip_file_handle(st: !app_state, v: int): void
fun app_get_zip_name_offset(st: !app_state): int
fun app_set_zip_name_offset(st: !app_state, v: int): void

(* Library state *)
fun app_get_library_count(st: !app_state): int
fun app_set_library_count(st: !app_state, v: int): void
fun app_get_lib_save_pending(st: !app_state): int
fun app_set_lib_save_pending(st: !app_state, v: int): void
fun app_get_lib_load_pending(st: !app_state): int
fun app_set_lib_load_pending(st: !app_state, v: int): void
fun app_get_lib_meta_save_pending(st: !app_state): int
fun app_set_lib_meta_save_pending(st: !app_state, v: int): void
fun app_get_lib_meta_load_pending(st: !app_state): int
fun app_set_lib_meta_load_pending(st: !app_state, v: int): void
fun app_get_lib_meta_load_index(st: !app_state): int
fun app_set_lib_meta_load_index(st: !app_state, v: int): void
fun app_get_library_books(st: !app_state): ptr

(* Buffer pointers — bridge shared memory *)
fun app_get_string_buffer(st: !app_state): ptr
fun app_get_fetch_buffer(st: !app_state): ptr
fun app_get_diff_buffer(st: !app_state): ptr

(* Settings values *)
fun app_get_stg_font_size(st: !app_state): int
fun app_set_stg_font_size(st: !app_state, v: int): void
fun app_get_stg_font_family(st: !app_state): int
fun app_set_stg_font_family(st: !app_state, v: int): void
fun app_get_stg_theme(st: !app_state): int
fun app_set_stg_theme(st: !app_state, v: int): void
fun app_get_stg_lh_tenths(st: !app_state): int
fun app_set_stg_lh_tenths(st: !app_state, v: int): void
fun app_get_stg_margin(st: !app_state): int
fun app_set_stg_margin(st: !app_state, v: int): void

(* Settings UI state *)
fun app_get_stg_visible(st: !app_state): int
fun app_set_stg_visible(st: !app_state, v: int): void
fun app_get_stg_overlay_id(st: !app_state): int
fun app_set_stg_overlay_id(st: !app_state, v: int): void
fun app_get_stg_close_id(st: !app_state): int
fun app_set_stg_close_id(st: !app_state, v: int): void
fun app_get_stg_root_id(st: !app_state): int
fun app_set_stg_root_id(st: !app_state, v: int): void

(* Settings button IDs *)
fun app_get_stg_btn_font_minus(st: !app_state): int
fun app_set_stg_btn_font_minus(st: !app_state, v: int): void
fun app_get_stg_btn_font_plus(st: !app_state): int
fun app_set_stg_btn_font_plus(st: !app_state, v: int): void
fun app_get_stg_btn_font_fam(st: !app_state): int
fun app_set_stg_btn_font_fam(st: !app_state, v: int): void
fun app_get_stg_btn_theme_l(st: !app_state): int
fun app_set_stg_btn_theme_l(st: !app_state, v: int): void
fun app_get_stg_btn_theme_d(st: !app_state): int
fun app_set_stg_btn_theme_d(st: !app_state, v: int): void
fun app_get_stg_btn_theme_s(st: !app_state): int
fun app_set_stg_btn_theme_s(st: !app_state, v: int): void
fun app_get_stg_btn_lh_minus(st: !app_state): int
fun app_set_stg_btn_lh_minus(st: !app_state, v: int): void
fun app_get_stg_btn_lh_plus(st: !app_state): int
fun app_set_stg_btn_lh_plus(st: !app_state, v: int): void
fun app_get_stg_btn_mg_minus(st: !app_state): int
fun app_set_stg_btn_mg_minus(st: !app_state, v: int): void
fun app_get_stg_btn_mg_plus(st: !app_state): int
fun app_set_stg_btn_mg_plus(st: !app_state, v: int): void

(* Settings display IDs *)
fun app_get_stg_disp_fs(st: !app_state): int
fun app_set_stg_disp_fs(st: !app_state, v: int): void
fun app_get_stg_disp_ff(st: !app_state): int
fun app_set_stg_disp_ff(st: !app_state, v: int): void
fun app_get_stg_disp_lh(st: !app_state): int
fun app_set_stg_disp_lh(st: !app_state, v: int): void
fun app_get_stg_disp_mg(st: !app_state): int
fun app_set_stg_disp_mg(st: !app_state, v: int): void

(* Settings pending *)
fun app_get_stg_save_pend(st: !app_state): int
fun app_set_stg_save_pend(st: !app_state, v: int): void
fun app_get_stg_load_pend(st: !app_state): int
fun app_set_stg_load_pend(st: !app_state, v: int): void

(* Reader state *)
fun app_get_rdr_active(st: !app_state): int
fun app_set_rdr_active(st: !app_state, v: int): void
fun app_get_rdr_book_index(st: !app_state): int
fun app_set_rdr_book_index(st: !app_state, v: int): void
fun app_get_rdr_current_chapter(st: !app_state): int
fun app_set_rdr_current_chapter(st: !app_state, v: int): void
fun app_get_rdr_current_page(st: !app_state): int
fun app_set_rdr_current_page(st: !app_state, v: int): void
fun app_get_rdr_total_pages(st: !app_state): int
fun app_set_rdr_total_pages(st: !app_state, v: int): void
fun app_get_rdr_viewport_id(st: !app_state): int
fun app_set_rdr_viewport_id(st: !app_state, v: int): void
fun app_get_rdr_container_id(st: !app_state): int
fun app_set_rdr_container_id(st: !app_state, v: int): void
fun app_get_rdr_root_id(st: !app_state): int
fun app_set_rdr_root_id(st: !app_state, v: int): void
fun app_get_rdr_file_handle(st: !app_state): int
fun app_set_rdr_file_handle(st: !app_state, v: int): void
fun app_get_rdr_btn_id(st: !app_state, idx: int): int
fun app_set_rdr_btn_id(st: !app_state, idx: int, v: int): void

(* EPUB state *)
fun app_get_epub_spine_count(st: !app_state): int
fun app_set_epub_spine_count(st: !app_state, v: int): void
fun app_get_epub_title(st: !app_state): ptr
fun app_get_epub_title_len(st: !app_state): int
fun app_set_epub_title_len(st: !app_state, v: int): void
fun app_get_epub_author(st: !app_state): ptr
fun app_get_epub_author_len(st: !app_state): int
fun app_set_epub_author_len(st: !app_state, v: int): void
fun app_get_epub_book_id(st: !app_state): ptr
fun app_get_epub_book_id_len(st: !app_state): int
fun app_set_epub_book_id_len(st: !app_state, v: int): void
fun app_get_epub_opf_path(st: !app_state): ptr
fun app_get_epub_opf_path_len(st: !app_state): int
fun app_set_epub_opf_path_len(st: !app_state, v: int): void
fun app_get_epub_opf_dir_len(st: !app_state): int
fun app_set_epub_opf_dir_len(st: !app_state, v: int): void
fun app_get_epub_state(st: !app_state): int
fun app_set_epub_state(st: !app_state, v: int): void
fun app_get_epub_spine_path_buf(st: !app_state): ptr
fun app_get_epub_spine_path_offsets(st: !app_state): ptr
fun app_get_epub_spine_path_lens(st: !app_state): ptr
fun app_get_epub_spine_path_count(st: !app_state): int
fun app_set_epub_spine_path_count(st: !app_state, v: int): void
fun app_get_epub_spine_path_pos(st: !app_state): int
fun app_set_epub_spine_path_pos(st: !app_state, v: int): void
