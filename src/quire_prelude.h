/* quire_prelude.h — Freestanding arithmetic macros for ATS2
 *
 * ATS2 operators (+, -, *, =, >=, >) generate calls to prelude
 * template functions (e.g. atspre_g0int_eq_int) which don't exist
 * in freestanding mode. These macros provide the implementations.
 *
 * Ward's runtime.h already defines: atspre_g0int_add_int,
 * atspre_g0int_gt_int, atspre_g0int2uint_int_size,
 * atspre_g0int2int_int_int. We only add the missing ones here.
 */

#ifndef QUIRE_PRELUDE_H
#define QUIRE_PRELUDE_H

/* ATS2 abstract type erasure — absvtype app_state erases to ptr */
#define app_state atstype_ptrk

/* Arithmetic — quire_* names for explicit extern fun declarations */
#define quire_add(a, b) ((a) + (b))
#define quire_sub(a, b) ((a) - (b))
#define quire_mul(a, b) ((a) * (b))
#define quire_div(a, b) ((a) / (b))
#define quire_mod(a, b) ((a) % (b))

/* Comparison — quire_* names for explicit extern fun declarations */
#define quire_eq(a, b) ((a) == (b))
#define quire_neq(a, b) ((a) != (b))
#define quire_gte(a, b) ((a) >= (b))
#define quire_gt(a, b) ((a) > (b))
#define quire_lt(a, b) ((a) < (b))
#define quire_lte(a, b) ((a) <= (b))

/* int2byte0 — not in ward runtime.h, needed for ward_arr_set<byte> */
#ifndef atspre_int2byte0
#define atspre_int2byte0(x) ((unsigned char)(x))
#endif

/* ATS2 prelude names NOT already in ward runtime.h */
#ifndef atspre_g0int_eq_int
#define atspre_g0int_eq_int(a, b) ((a) == (b))
#endif
#ifndef atspre_g0int_neq_int
#define atspre_g0int_neq_int(a, b) ((a) != (b))
#endif
#ifndef atspre_g0int_gte_int
#define atspre_g0int_gte_int(a, b) ((a) >= (b))
#endif
#ifndef atspre_g0int_lte_int
#define atspre_g0int_lte_int(a, b) ((a) <= (b))
#endif
#ifndef atspre_g0int_lt_int
#define atspre_g0int_lt_int(a, b) ((a) < (b))
#endif
#ifndef atspre_g0int_sub_int
#define atspre_g0int_sub_int(a, b) ((a) - (b))
#endif
#ifndef atspre_g0int_mul_int
#define atspre_g0int_mul_int(a, b) ((a) * (b))
#endif

/* g1int (dependent int) variants — same operations, tracked statically.
 * ward runtime.h already defines: g1int_add, g1int_mul, g1int_lt */
#ifndef atspre_g1int_sub_int
#define atspre_g1int_sub_int(a, b) ((a) - (b))
#endif
#ifndef atspre_g1int_add_int
#define atspre_g1int_add_int(a, b) ((a) + (b))
#endif
#ifndef atspre_g1int_mul_int
#define atspre_g1int_mul_int(a, b) ((a) * (b))
#endif
#ifndef atspre_g1int_neg_int
#define atspre_g1int_neg_int(a) (-(a))
#endif
#ifndef atspre_g1int_eq_int
#define atspre_g1int_eq_int(a, b) ((a) == (b))
#endif
#ifndef atspre_g1int_neq_int
#define atspre_g1int_neq_int(a, b) ((a) != (b))
#endif
#ifndef atspre_g1int_gt_int
#define atspre_g1int_gt_int(a, b) ((a) > (b))
#endif
#ifndef atspre_g1int_gte_int
#define atspre_g1int_gte_int(a, b) ((a) >= (b))
#endif
#ifndef atspre_g1int_lt_int
#define atspre_g1int_lt_int(a, b) ((a) < (b))
#endif
#ifndef atspre_g1int_lte_int
#define atspre_g1int_lte_int(a, b) ((a) <= (b))
#endif

/* Record-in-singleton selection — for datavtype with one-field record.
 * ATS2 optimizes single-field records: the record IS the field value.
 * ATSSELrecsin just returns the value unchanged. */
#ifndef ATSSELrecsin
#define ATSSELrecsin(pmv, tyrec, lab) (pmv)
#endif

/* Datavtype (tagged union) construction and matching.
 * ward runtime.h provides: ATSINSmove_con1_beg/end/new, ATSINSstore_con1_ofs,
 * ATSINSfreecon, ATSSELcon, ATSSELfltrec. We only add what's missing. */
#ifndef ATSINSstore_con1_tag
#define ATSINSstore_con1_tag(dst, tag) (((int*)(dst))[0] = (tag))
#endif
#ifndef ATSINSmove_con0
#define ATSINSmove_con0(dst, tag) ((dst) = (void*)0)
#endif
#ifndef ATSCKpat_con0
#define ATSCKpat_con0(p, tag) ((p) == (void*)0)
#endif
#ifndef ATSCKpat_con1
#define ATSCKpat_con1(p, tag) (((int*)(p))[0] == (tag))
#endif

/* Pointer arithmetic */
#define ptr_add_int(p, n) ((void*)((char*)(p) + (n)))
#define quire_ptr_add(p, n) ((void*)((char*)(p) + (n)))

/* Null pointer and pointer comparison */
#define quire_null_ptr() ((void*)0)
#define quire_ptr_eq(a, b) ((a) == (b))

/* Byte-level memory access (for xml.dats, zip.dats buffer parsing) */
#define buf_get_u8(p, off) ((int)(((unsigned char*)(p))[(off)]))
#define buf_set_u8(p, off, v) (((unsigned char*)(p))[(off)] = (unsigned char)(v))

/* sbuf_write — copy len bytes from src to dst */
#define sbuf_write(dst, src, len) do { \
    const unsigned char *_s = (const unsigned char *)(src); \
    unsigned char *_d = (unsigned char *)(dst); \
    for (int _i = 0; _i < (len); _i++) _d[_i] = _s[_i]; \
} while(0)

/* Buffer accessors (implemented in quire_runtime.c).
 * ATS2 mac# can generate unsigned char* or void* depending on module.
 * Use unsigned char* to match epub.dats generated code. */
extern unsigned char *get_string_buffer_ptr(void);
extern unsigned char *get_fetch_buffer_ptr(void);
extern unsigned char *get_diff_buffer_ptr(void);
#define quire_get_byte(p, off) ((int)(((unsigned char*)(p))[(off)]))

/* DOM next-node-id — REMOVED: now in app_state.dats (ATS2 datavtype) */

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

/* Zip entry accessors (implemented in quire_runtime.c) */
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

/* DOM lookup tables and copy (used by dom.dats tree renderer) */
extern int lookup_tag(void *base, int offset, int name_len);
extern int lookup_attr(void *base, int offset, int name_len);
extern int _copy_to_arr(void *dst, void *src, int offset, int count);

/* Text constant filler (implemented in quire_runtime.c) */
extern int _fill_text(void *arr, int text_id);

/* Bounds-checked byte read from ward_arr (erased to ptr at runtime).
 * Returns byte value if 0 <= off < len, else 0. */
#ifndef _ward_arr_byte
#define _ward_arr_byte(arr, off, len) \
  (((off) >= 0 && (off) < (len)) ? ((int)((unsigned char*)(arr))[(off)]) : 0)
#endif

/* Bitwise operations (may also be in ward runtime.h) */
#ifndef quire_bor
#define quire_bor(a, b) ((int)((unsigned int)(a) | (unsigned int)(b)))
#endif
#ifndef quire_bsl
#define quire_bsl(a, n) ((int)((unsigned int)(a) << (n)))
#endif

/* ZIP module functions (zip.sats — implemented in zip.dats, mac# linkage) */
extern int zip_open(int file_handle, int file_size);
extern int zip_get_entry(int index, void *entry);
extern int zip_find_entry(void *name_ptr, int name_len);
extern int zip_get_data_offset(int index);

/* EPUB module (implemented in quire_runtime.c) */
extern int epub_parse_container_bytes(void *buf, int len);
extern int epub_parse_opf_bytes(void *buf, int len);
extern void* epub_get_opf_path_ptr(void);
extern int epub_get_opf_path_len(void);
extern void* get_str_container_ptr(void);

/* String buffer copy (implemented in quire_runtime.c) */
extern void _copy_from_sbuf(void *dst, int len);

/* Spine path accessors (implemented in quire_runtime.c) */
extern void* epub_get_spine_path_ptr(int index);
extern int epub_get_spine_path_len(int index);

/* EPUB module functions (epub.sats — implemented in quire_runtime.c) */
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

/* Library module functions (library.sats — implemented in quire_runtime.c) */
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

/* Reader module functions (reader.sats — implemented in quire_runtime.c) */
extern void reader_init(void);
extern void reader_enter(int root_id, int container_hide_id);
extern void reader_exit(void);
extern int reader_is_active(void);
extern int reader_get_current_chapter(void);
extern int reader_get_current_page(void);
extern int reader_get_total_pages(void);
extern int reader_get_chapter_count(void);
extern void reader_next_page(void);
extern void reader_prev_page(void);
extern void reader_go_to_page(int page);
extern void reader_on_chapter_loaded(int len);
extern void reader_on_chapter_blob_loaded(int handle, int size);
extern int reader_get_viewport_id(void);
extern int reader_get_viewport_width(void);
extern int reader_get_page_indicator_id(void);
extern void reader_update_page_display(void);
extern int reader_is_loading(void);
extern void reader_remeasure_all(void);
extern void reader_go_to_chapter(int chapter_index, int total_chapters);
extern void reader_show_toc(void);
extern void reader_hide_toc(void);
extern void reader_toggle_toc(void);
extern int reader_is_toc_visible(void);
extern int reader_get_toc_id(void);
extern int reader_get_progress_bar_id(void);
extern int reader_get_toc_index_for_node(int node_id);
extern void reader_on_toc_click(int node_id);
extern void reader_enter_at(int root_id, int container_hide_id, int chapter, int page);
extern int reader_get_back_btn_id(void);

/* Extra reader accessors for quire.dats orchestration */
extern void reader_set_viewport_id(int id);
extern void reader_set_container_id(int id);
extern int reader_get_container_id(void);
extern void reader_set_book_index(int idx);
extern int reader_get_book_index(void);
extern void reader_set_file_handle(int h);
extern int reader_get_file_handle(void);
extern void reader_set_btn_id(int book_index, int node_id);
extern int reader_get_btn_id(int book_index);
extern int reader_set_total_pages(int n);
extern int read_payload_click_x(void *arr);

#endif /* QUIRE_PRELUDE_H */
