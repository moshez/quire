(* app_state.sats — Linear application state type
 *
 * Single linear type holding all mutable application state.
 * Threaded through functions as a parameter; stored in the
 * callback registry context across async boundaries.
 *
 * All buffer fields are ward_arr(byte, l, CAP) — linear, bounds-checked.
 * No mutable globals. No C code. No raw ptr in any declaration.
 *)

staload "./buf.sats"

absvtype app_state = ptr

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
fun app_get_lib_view_mode(st: !app_state): int
fun app_set_lib_view_mode(st: !app_state, v: int): void
fun app_get_lib_sort_mode(st: !app_state): int
fun app_set_lib_sort_mode(st: !app_state, v: int): void

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
fun app_get_rdr_page_info_id(st: !app_state): int
fun app_set_rdr_page_info_id(st: !app_state, v: int): void
fun app_get_rdr_nav_id(st: !app_state): int
fun app_set_rdr_nav_id(st: !app_state, v: int): void
fun app_get_rdr_btn_id(st: !app_state, idx: int): int
fun app_set_rdr_btn_id(st: !app_state, idx: int, v: int): void
fun app_get_rdr_resume_page(st: !app_state): int
fun app_set_rdr_resume_page(st: !app_state, v: int): void

(* EPUB state *)
fun app_get_epub_spine_count(st: !app_state): int
fun app_set_epub_spine_count(st: !app_state, v: int): void
fun app_get_epub_title_len(st: !app_state): int
fun app_set_epub_title_len(st: !app_state, v: int): void
fun app_get_epub_author_len(st: !app_state): int
fun app_set_epub_author_len(st: !app_state, v: int): void
fun app_get_epub_book_id_len(st: !app_state): int
fun app_set_epub_book_id_len(st: !app_state, v: int): void
fun app_get_epub_opf_path_len(st: !app_state): int
fun app_set_epub_opf_path_len(st: !app_state, v: int): void
fun app_get_epub_opf_dir_len(st: !app_state): int
fun app_set_epub_opf_dir_len(st: !app_state, v: int): void
fun app_get_epub_state(st: !app_state): int
fun app_set_epub_state(st: !app_state, v: int): void
fun app_get_epub_spine_path_count(st: !app_state): int
fun app_set_epub_spine_path_count(st: !app_state, v: int): void
fun app_get_epub_spine_path_pos(st: !app_state): int
fun app_set_epub_spine_path_pos(st: !app_state, v: int): void

(* Duplicate detection state *)
fun app_get_dup_choice(st: !app_state): int
fun app_set_dup_choice(st: !app_state, v: int): void
fun app_get_dup_overlay_id(st: !app_state): int
fun app_set_dup_overlay_id(st: !app_state, v: int): void

(* Factory reset state *)
fun app_get_reset_overlay_id(st: !app_state): int
fun app_set_reset_overlay_id(st: !app_state, v: int): void

(* Error banner state *)
fun app_get_err_banner_id(st: !app_state): int
fun app_set_err_banner_id(st: !app_state, v: int): void

(* Import card state *)
fun app_get_import_card_id(st: !app_state): int
fun app_set_import_card_id(st: !app_state, v: int): void
fun app_get_import_card_bar_id(st: !app_state): int
fun app_set_import_card_bar_id(st: !app_state, v: int): void
fun app_get_import_card_status_id(st: !app_state): int
fun app_set_import_card_status_id(st: !app_state, v: int): void

(* Context menu state *)
fun app_get_ctx_overlay_id(st: !app_state): int
fun app_set_ctx_overlay_id(st: !app_state, v: int): void

(* Info overlay state *)
fun app_get_info_overlay_id(st: !app_state): int
fun app_set_info_overlay_id(st: !app_state, v: int): void

(* Delete modal state *)
fun app_get_del_overlay_id(st: !app_state): int
fun app_set_del_overlay_id(st: !app_state, v: int): void
fun app_get_del_choice(st: !app_state): int
fun app_set_del_choice(st: !app_state, v: int): void

(* ========== Convenience wrappers (load/store internally) ========== *)
(* These load app_state from the callback registry, access the field,
 * then store it back. Prefer using app_get_*/app_set_* with !app_state
 * when you already hold the state. *)

(* Duplicate detection *)
fun _app_dup_choice(): int
fun _app_set_dup_choice(v: int): void
fun _app_dup_overlay_id(): int
fun _app_set_dup_overlay_id(v: int): void

(* Factory reset *)
fun _app_reset_overlay_id(): int
fun _app_set_reset_overlay_id(v: int): void

(* Error banner *)
fun _app_err_banner_id(): int
fun _app_set_err_banner_id(v: int): void

(* Import card *)
fun _app_import_card_id(): int
fun _app_set_import_card_id(v: int): void
fun _app_import_card_bar_id(): int
fun _app_set_import_card_bar_id(v: int): void
fun _app_import_card_status_id(): int
fun _app_set_import_card_status_id(v: int): void

(* Context menu *)
fun _app_ctx_overlay_id(): int
fun _app_set_ctx_overlay_id(v: int): void

(* Info overlay *)
fun _app_info_overlay_id(): int
fun _app_set_info_overlay_id(v: int): void

(* Delete modal *)
fun _app_del_overlay_id(): int
fun _app_set_del_overlay_id(v: int): void
fun _app_del_choice(): int
fun _app_set_del_choice(v: int): void

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
fun _app_lib_view_mode(): int
fun _app_set_lib_view_mode(v: int): void
fun _app_lib_sort_mode(): int
fun _app_set_lib_sort_mode(v: int): void

(* Library books — per-byte/i32 accessors (bounds-checked via ward_arr) *)
fun _app_lib_books_get_u8(off: int): int
fun _app_lib_books_set_u8(off: int, v: int): void
fun _app_lib_books_get_i32(idx: int): int
fun _app_lib_books_set_i32(idx: int, v: int): void

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

(* EPUB accessors — per-buffer byte/i32 access (bounds-checked) *)
fun _app_epub_spine_count(): int
fun _app_set_epub_spine_count(v: int): void
fun _app_epub_title_len(): int
fun _app_set_epub_title_len(v: int): void
fun _app_epub_author_len(): int
fun _app_set_epub_author_len(v: int): void
fun _app_epub_book_id_len(): int
fun _app_set_epub_book_id_len(v: int): void
fun _app_epub_opf_path_len(): int
fun _app_set_epub_opf_path_len(v: int): void
fun _app_epub_opf_dir_len(): int
fun _app_set_epub_opf_dir_len(v: int): void
fun _app_epub_state(): int
fun _app_set_epub_state(v: int): void
fun _app_epub_spine_path_count(): int
fun _app_set_epub_spine_path_count(v: int): void
fun _app_epub_spine_path_pos(): int
fun _app_set_epub_spine_path_pos(v: int): void

(* EPUB title buffer *)
fun _app_epub_title_get_u8(off: int): int
fun _app_epub_title_set_u8(off: int, v: int): void

(* EPUB author buffer *)
fun _app_epub_author_get_u8(off: int): int
fun _app_epub_author_set_u8(off: int, v: int): void

(* EPUB book ID buffer *)
fun _app_epub_book_id_get_u8(off: int): int
fun _app_epub_book_id_set_u8(off: int, v: int): void

(* EPUB OPF path buffer *)
fun _app_epub_opf_path_get_u8(off: int): int
fun _app_epub_opf_path_set_u8(off: int, v: int): void

(* EPUB spine path buffer *)
fun _app_epub_spine_buf_get_u8(off: int): int
fun _app_epub_spine_buf_set_u8(off: int, v: int): void

(* EPUB spine offsets/lens (i32 access) *)
fun _app_epub_spine_offsets_get_i32(idx: int): int
fun _app_epub_spine_offsets_set_i32(idx: int, v: int): void
fun _app_epub_spine_lens_get_i32(idx: int): int
fun _app_epub_spine_lens_set_i32(idx: int, v: int): void

(* String buffer — byte access *)
fun _app_sbuf_get_u8(off: int): int
fun _app_sbuf_set_u8(off: int, v: int): void

(* Fetch buffer — byte access *)
fun _app_fbuf_get_u8(off: int): int
fun _app_fbuf_set_u8(off: int, v: int): void

(* Diff buffer — byte and i32 access *)
fun _app_dbuf_get_u8(off: int): int
fun _app_dbuf_set_u8(off: int, v: int): void
fun _app_dbuf_get_i32(idx: int): int
fun _app_dbuf_set_i32(idx: int, v: int): void

(* Bulk copy functions — single load/store cycle for tight loops *)
fun _app_copy_fbuf_to_epub_title(src_off: int, len: int): void
fun _app_copy_fbuf_to_epub_author(src_off: int, len: int): void
fun _app_copy_fbuf_to_epub_book_id(src_off: int, len: int): void
fun _app_copy_fbuf_to_epub_opf_path(src_off: int, len: int): void
fun _app_copy_fbuf_to_epub_spine_buf(src_off: int, dst_off: int, len: int): void
fun _app_copy_opf_path_to_epub_spine_buf(dst_off: int, len: int): void
fun _app_copy_epub_title_to_sbuf(dst_off: int, len: int): void
fun _app_copy_epub_author_to_sbuf(dst_off: int, len: int): void
fun _app_copy_epub_book_id_to_sbuf(dst_off: int, len: int): void
fun _app_copy_epub_opf_path_to_sbuf(dst_off: int, len: int): void
fun _app_copy_epub_spine_buf_to_sbuf(src_off: int, dst_off: int, len: int): void
fun _app_copy_sbuf_to_lib_books(dst_off: int, src_off: int, len: int): void
fun _app_copy_lib_books_to_sbuf(src_off: int, dst_off: int, len: int): void
fun _app_lib_books_match_bid(book_base: int, bid_len: int): int

(* EPUB manifest in-memory tables (loaded from IDB) *)
fun _app_epub_manifest_count(): int
fun _app_set_epub_manifest_count(v: int): void
fun _app_epub_manifest_names_get_u8(off: int): int
fun _app_epub_manifest_names_set_u8(off: int, v: int): void
fun _app_epub_manifest_offsets_get_i32(idx: int): int
fun _app_epub_manifest_offsets_set_i32(idx: int, v: int): void
fun _app_epub_manifest_lens_get_i32(idx: int): int
fun _app_epub_manifest_lens_set_i32(idx: int, v: int): void

(* Spine→entry index mapping *)
fun _app_epub_spine_entry_idx_get(i: int): int
fun _app_epub_spine_entry_idx_set(i: int, v: int): void

(* EPUB file size stash — captured at file-open time before stash slot 0 is overwritten *)
fun _app_epub_file_size(): int
fun _app_set_epub_file_size(v: int): void

(* Deferred image resolution queue *)
fun _app_deferred_img_node_id_get(i: int): int
fun _app_deferred_img_node_id_set(i: int, v: int): void
fun _app_deferred_img_entry_idx_get(i: int): int
fun _app_deferred_img_entry_idx_set(i: int, v: int): void
fun _app_deferred_img_count(): int
fun _app_set_deferred_img_count(v: int): void

(* EPUB cover href buffer *)
fun _app_epub_cover_href_len(): int
fun _app_set_epub_cover_href_len(v: int): void
fun _app_epub_cover_href_get_u8(off: int): int
fun _app_epub_cover_href_set_u8(off: int, v: int): void
fun _app_copy_epub_cover_href_to_sbuf(dst_off: int, len: int): void

(* Copy book_id bytes from library books at book_base to epub_book_id *)
fun _app_copy_lib_book_id_to_epub(book_base: int, bid_len: int): void

(* Compare sbuf[0..len-1] against manifest name at (off, nlen) *)
fun _app_manifest_name_match_sbuf(name_off: int, name_len: int, sbuf_len: int): int

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
