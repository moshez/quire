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

(* ========== Convenience wrappers (load/store internally) ========== *)
(* These load app_state from the callback registry, access the field,
 * then store it back. Prefer using app_get_*/app_set_* with !app_state
 * when you already hold the state. *)

(* Library accessors *)
fun _app_lib_count(): int
fun _app_set_lib_count(v: int): void
fun _app_lib_save_pend(): int
fun _app_set_lib_save_pend(v: int): void
fun _app_lib_load_pend(): int
fun _app_set_lib_load_pend(v: int): void
fun _app_lib_meta_save_pend(): int
fun _app_set_lib_meta_save_pend(v: int): void
fun _app_lib_meta_load_pend(): int
fun _app_set_lib_meta_load_pend(v: int): void
fun _app_lib_meta_load_idx(): int
fun _app_set_lib_meta_load_idx(v: int): void
fun _app_lib_books_ptr(): ptr

(* Settings accessors *)
fun _app_stg_font_size(): int
fun _app_set_stg_font_size(v: int): void
fun _app_stg_font_family(): int
fun _app_set_stg_font_family(v: int): void
fun _app_stg_theme(): int
fun _app_set_stg_theme(v: int): void
fun _app_stg_lh_tenths(): int
fun _app_set_stg_lh_tenths(v: int): void
fun _app_stg_margin(): int
fun _app_set_stg_margin(v: int): void
fun _app_stg_visible(): int
fun _app_set_stg_visible(v: int): void
fun _app_stg_overlay_id(): int
fun _app_set_stg_overlay_id(v: int): void
fun _app_stg_close_id(): int
fun _app_set_stg_close_id(v: int): void
fun _app_stg_root_id(): int
fun _app_set_stg_root_id(v: int): void
fun _app_stg_btn_font_minus(): int
fun _app_set_stg_btn_font_minus(v: int): void
fun _app_stg_btn_font_plus(): int
fun _app_set_stg_btn_font_plus(v: int): void
fun _app_stg_btn_font_fam(): int
fun _app_set_stg_btn_font_fam(v: int): void
fun _app_stg_btn_theme_l(): int
fun _app_set_stg_btn_theme_l(v: int): void
fun _app_stg_btn_theme_d(): int
fun _app_set_stg_btn_theme_d(v: int): void
fun _app_stg_btn_theme_s(): int
fun _app_set_stg_btn_theme_s(v: int): void
fun _app_stg_btn_lh_minus(): int
fun _app_set_stg_btn_lh_minus(v: int): void
fun _app_stg_btn_lh_plus(): int
fun _app_set_stg_btn_lh_plus(v: int): void
fun _app_stg_btn_mg_minus(): int
fun _app_set_stg_btn_mg_minus(v: int): void
fun _app_stg_btn_mg_plus(): int
fun _app_set_stg_btn_mg_plus(v: int): void
fun _app_stg_disp_fs(): int
fun _app_set_stg_disp_fs(v: int): void
fun _app_stg_disp_ff(): int
fun _app_set_stg_disp_ff(v: int): void
fun _app_stg_disp_lh(): int
fun _app_set_stg_disp_lh(v: int): void
fun _app_stg_disp_mg(): int
fun _app_set_stg_disp_mg(v: int): void
fun _app_stg_save_pend(): int
fun _app_set_stg_save_pend(v: int): void
fun _app_stg_load_pend(): int
fun _app_set_stg_load_pend(v: int): void

(* EPUB accessors *)
fun _app_epub_spine_count(): int
fun _app_set_epub_spine_count(v: int): void
fun _app_epub_title_ptr(): ptr
fun _app_epub_title_len(): int
fun _app_set_epub_title_len(v: int): void
fun _app_epub_author_ptr(): ptr
fun _app_epub_author_len(): int
fun _app_set_epub_author_len(v: int): void
fun _app_epub_book_id_ptr(): ptr
fun _app_epub_book_id_len(): int
fun _app_set_epub_book_id_len(v: int): void
fun _app_epub_opf_path_ptr(): ptr
fun _app_epub_opf_path_len(): int
fun _app_set_epub_opf_path_len(v: int): void
fun _app_epub_opf_dir_len(): int
fun _app_set_epub_opf_dir_len(v: int): void
fun _app_epub_state(): int
fun _app_set_epub_state(v: int): void
fun _app_epub_spine_path_buf(): ptr
fun _app_epub_spine_path_offsets(): ptr
fun _app_epub_spine_path_lens(): ptr
fun _app_epub_spine_path_count(): int
fun _app_set_epub_spine_path_count(v: int): void
fun _app_epub_spine_path_pos(): int
fun _app_set_epub_spine_path_pos(v: int): void

(* ZIP accessors *)
fun _zip_entry_file_handle(i: int): int
fun _zip_entry_name_offset(i: int): int
fun _zip_entry_name_len(i: int): int
fun _zip_entry_compression(i: int): int
fun _zip_entry_compressed_size(i: int): int
fun _zip_entry_uncompressed_size(i: int): int
fun _zip_entry_local_offset(i: int): int
fun _zip_name_char(off: int): int
fun _zip_name_buf_put(off: int, byte_val: int): int
fun _zip_store_entry_at(idx: int, fh: int, no: int, nl: int,
  comp: int, cs: int, us: int, lo: int): int

(* Buffer accessors — declared in buf.sats, implemented here *)
