/* quire_prelude.h — Quire-specific C declarations
 *
 * Ward's runtime.h now provides all ATS2 codegen macros, atspre_*
 * arithmetic, bitwise ops, and calloc. This file contains only
 * quire-specific declarations not covered by ward.
 */

#ifndef QUIRE_PRELUDE_H
#define QUIRE_PRELUDE_H

/* ATS2 abstract type erasure — absvtype app_state erases to ptr */
#define app_state atstype_ptrk

/* Pointer comparison — no ward atspre_* for ptr == ptr */
#define quire_ptr_eq(a, b) ((a) == (b))

/* Byte-level memory access (used by buf.sats buf_get_u8/buf_set_u8) */
#define buf_get_u8(p, off) ((int)(((unsigned char*)(p))[(off)]))
#define buf_set_u8(p, off, v) (((unsigned char*)(p))[(off)] = (unsigned char)(v))

/* Int array access on raw ptr (for btn_ids etc.) */
#define buf_get_i32(p, idx) (((int*)(p))[(idx)])
#define buf_set_i32(p, idx, v) (((int*)(p))[(idx)] = (v))


/* quire_get_byte — same as buf_get_u8 (used by zip.dats) */
#define quire_get_byte(p, off) ((int)(((unsigned char*)(p))[(off)]))



/* Buffer accessors (implemented in quire_runtime.c) */
extern void *get_string_buffer_ptr(void);
extern void *get_fetch_buffer_ptr(void);
extern void *get_diff_buffer_ptr(void);

/* C-callable app_state accessors (implemented in app_state.dats via ext#) */
extern int _app_lib_count(void);
extern void _app_set_lib_count(int v);
extern int _app_lib_save_pend(void);
extern void _app_set_lib_save_pend(int v);
extern int _app_lib_load_pend(void);
extern void _app_set_lib_load_pend(int v);
extern int _app_lib_meta_save_pend(void);
extern void _app_set_lib_meta_save_pend(int v);
extern int _app_lib_meta_load_pend(void);
extern void _app_set_lib_meta_load_pend(int v);
extern int _app_lib_meta_load_idx(void);
extern void _app_set_lib_meta_load_idx(int v);
extern void* _app_lib_books_ptr(void);

/* C-callable app_state accessors for settings module */
extern int _app_stg_font_size(void);
extern void _app_set_stg_font_size(int v);
extern int _app_stg_font_family(void);
extern void _app_set_stg_font_family(int v);
extern int _app_stg_theme(void);
extern void _app_set_stg_theme(int v);
extern int _app_stg_lh_tenths(void);
extern void _app_set_stg_lh_tenths(int v);
extern int _app_stg_margin(void);
extern void _app_set_stg_margin(int v);
extern int _app_stg_visible(void);
extern void _app_set_stg_visible(int v);
extern int _app_stg_overlay_id(void);
extern void _app_set_stg_overlay_id(int v);
extern int _app_stg_close_id(void);
extern void _app_set_stg_close_id(int v);
extern int _app_stg_root_id(void);
extern void _app_set_stg_root_id(int v);
extern int _app_stg_btn_font_minus(void);
extern void _app_set_stg_btn_font_minus(int v);
extern int _app_stg_btn_font_plus(void);
extern void _app_set_stg_btn_font_plus(int v);
extern int _app_stg_btn_font_fam(void);
extern void _app_set_stg_btn_font_fam(int v);
extern int _app_stg_btn_theme_l(void);
extern void _app_set_stg_btn_theme_l(int v);
extern int _app_stg_btn_theme_d(void);
extern void _app_set_stg_btn_theme_d(int v);
extern int _app_stg_btn_theme_s(void);
extern void _app_set_stg_btn_theme_s(int v);
extern int _app_stg_btn_lh_minus(void);
extern void _app_set_stg_btn_lh_minus(int v);
extern int _app_stg_btn_lh_plus(void);
extern void _app_set_stg_btn_lh_plus(int v);
extern int _app_stg_btn_mg_minus(void);
extern void _app_set_stg_btn_mg_minus(int v);
extern int _app_stg_btn_mg_plus(void);
extern void _app_set_stg_btn_mg_plus(int v);
extern int _app_stg_disp_fs(void);
extern void _app_set_stg_disp_fs(int v);
extern int _app_stg_disp_ff(void);
extern void _app_set_stg_disp_ff(int v);
extern int _app_stg_disp_lh(void);
extern void _app_set_stg_disp_lh(int v);
extern int _app_stg_disp_mg(void);
extern void _app_set_stg_disp_mg(int v);
extern int _app_stg_save_pend(void);
extern void _app_set_stg_save_pend(int v);
extern int _app_stg_load_pend(void);
extern void _app_set_stg_load_pend(int v);

/* ZIP module functions (zip.sats — implemented in zip.dats, mac# linkage) */
extern int zip_open(int file_handle, int file_size);
extern int zip_get_entry(int index, void *entry);
extern int zip_find_entry(void *name_ptr, int name_len);
extern int zip_get_data_offset(int index);

/* ZIP internal accessors (implemented in app_state.dats via ext#) */
extern int _zip_entry_file_handle(int i);
extern int _zip_entry_name_offset(int i);
extern int _zip_entry_name_len(int i);
extern int _zip_entry_compression(int i);
extern int _zip_entry_compressed_size(int i);
extern int _zip_entry_uncompressed_size(int i);
extern int _zip_entry_local_offset(int i);
extern int _zip_name_char(int off);
extern int _zip_name_buf_put(int off, int byte_val);
extern int _zip_store_entry_at(int idx, int fh, int no, int nl,
  int comp, int cs, int us, int lo);

/* Library module functions (library.sats — implemented in library.dats) */
extern void library_init(void);
extern int library_get_count(void);
extern int library_get_title(int index, int buf_offset);
extern int library_get_author(int index, int buf_offset);
extern int library_get_book_id(int index, int buf_offset);
extern int library_get_chapter(int index);
extern int library_get_page(int index);
extern int library_get_spine_count(int index);
extern int library_add_book(void);
extern void library_remove_book(int index);
extern void library_update_position(int index, int chapter, int page);
extern int library_find_book_by_id(void);
extern int library_serialize(void);
extern int library_deserialize(int len);
extern void library_save(void);
extern void library_load(void);
extern void library_on_load_complete(int len);
extern void library_on_save_complete(int success);
extern void library_save_book_metadata(void);
extern void library_load_book_metadata(int index);
extern void library_on_metadata_load_complete(int len);
extern void library_on_metadata_save_complete(int success);
extern int library_is_save_pending(void);
extern int library_is_load_pending(void);
extern int library_is_metadata_pending(void);

extern int read_payload_click_x(void *arr);
extern void ward_parse_html_stash(void *p);
extern void *ward_parse_html_get_ptr(void);

/* C-callable epub field accessors (implemented in app_state.dats via ext#) */
extern int _app_epub_spine_count(void);
extern void _app_set_epub_spine_count(int v);
extern void* _app_epub_title_ptr(void);
extern int _app_epub_title_len(void);
extern void _app_set_epub_title_len(int v);
extern void* _app_epub_author_ptr(void);
extern int _app_epub_author_len(void);
extern void _app_set_epub_author_len(int v);
extern void* _app_epub_book_id_ptr(void);
extern int _app_epub_book_id_len(void);
extern void _app_set_epub_book_id_len(int v);
extern void* _app_epub_opf_path_ptr(void);
extern int _app_epub_opf_path_len(void);
extern void _app_set_epub_opf_path_len(int v);
extern int _app_epub_opf_dir_len(void);
extern void _app_set_epub_opf_dir_len(int v);
extern int _app_epub_state(void);
extern void _app_set_epub_state(int v);
extern void* _app_epub_spine_path_buf(void);
extern void* _app_epub_spine_path_offsets(void);
extern void* _app_epub_spine_path_lens(void);
extern int _app_epub_spine_path_count(void);
extern void _app_set_epub_spine_path_count(int v);
extern int _app_epub_spine_path_pos(void);
extern void _app_set_epub_spine_path_pos(int v);

/* EPUB module functions (implemented in epub.dats via ext#) */
extern void epub_init(void);
extern int epub_start_import(int file_input_node_id);
extern int epub_get_state(void);
extern int epub_get_progress(void);
extern int epub_get_error(int buf_offset);
extern int epub_get_title(int buf_offset);
extern int epub_get_author(int buf_offset);
extern int epub_get_book_id(int buf_offset);
extern int epub_get_chapter_count(void);
extern int epub_get_chapter_key(int chapter_index, int buf_offset);
extern void epub_continue(void);
extern void epub_on_file_open(int handle, int size);
extern void epub_on_decompress(int blob_handle, int size);
extern void epub_on_db_open(int success);
extern void epub_on_db_put(int success);
extern void epub_cancel(void);
extern int epub_get_toc_count(void);
extern int epub_get_toc_label(int toc_index, int buf_offset);
extern int epub_get_toc_chapter(int toc_index);
extern int epub_get_toc_level(int toc_index);
extern int epub_get_chapter_title(int spine_index, int buf_offset);
extern int epub_serialize_metadata(void);
extern int epub_restore_metadata(int len);
extern void epub_reset(void);
extern int epub_parse_container_bytes(void *buf, int len);
extern int epub_parse_opf_bytes(void *buf, int len);
extern void* epub_get_opf_path_ptr(void);
extern int epub_get_opf_path_len(void);
extern void* get_str_container_ptr(void);
extern void* epub_get_spine_path_ptr(int index);
extern int epub_get_spine_path_len(int index);

#endif /* QUIRE_PRELUDE_H */
