(* app_state.dats -- Linear application state implementation
 *
 * Pure ATS2 datavtype. No C code. Fields accessed via @-unfold
 * pattern which generates direct struct member access in C.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./app_state.sats"
staload "./buf.sats"

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
      epub_spine_path_pos = int
    }

assume app_state = app_state_impl

staload "./arith.sats"
staload "./buf.sats"

(* Bump allocator — never freed. Zero-initialized by calloc. *)
extern fun _calloc(n: int, sz: int): ptr = "mac#calloc"

(* Allocate btn_ids array: 32 ints × 4 bytes = 128 bytes *)
fn _rdr_btn_alloc(): ptr = _calloc(32, 4)

implement app_state_init() =
  APP_STATE @{
    dom_next_node_id = 1,
    zip_entry_count = 0,
    zip_file_handle = 0,
    zip_name_offset = 0,
    zip_entries = _calloc(256 * 7, 4),
    zip_name_buf = _calloc(1, 8192),
    library_count = 0,
    lib_save_pending = 0,
    lib_load_pending = 0,
    lib_meta_save_pending = 0,
    lib_meta_load_pending = 0,
    lib_meta_load_index = 0 - 1,
    library_books = _calloc(32 * 150, 4),
    string_buffer = _calloc(1, 4096),
    fetch_buffer = _calloc(1, 16384),
    diff_buffer = _calloc(1, 4096),
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
    rdr_btn_ids = _rdr_btn_alloc(),
    epub_spine_count = 0,
    epub_title = _calloc(1, 256),
    epub_title_len = 0,
    epub_author = _calloc(1, 256),
    epub_author_len = 0,
    epub_book_id = _calloc(1, 64),
    epub_book_id_len = 0,
    epub_opf_path = _calloc(1, 256),
    epub_opf_path_len = 0,
    epub_opf_dir_len = 0,
    epub_state = 0,
    epub_spine_path_buf = _calloc(1, 4096),
    epub_spine_path_offsets = _calloc(32, 4),
    epub_spine_path_lens = _calloc(32, 4),
    epub_spine_path_count = 0,
    epub_spine_path_pos = 0
  }

implement app_state_fini(st) = let
  val ~APP_STATE(_) = st
in end

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

(* ========== ZIP array storage (ext# wrappers) ========== *)

(* ZIP entries: 256 entries × 7 ints each, stored as flat int array.
 * Entry i has fields at indices i*7+0..i*7+6:
 *   0=file_handle, 1=name_offset, 2=name_len, 3=compression,
 *   4=compressed_size, 5=uncompressed_size, 6=local_header_offset *)

fn _zip_get_entries_ptr(): ptr = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val p = r.zip_entries
  prval () = fold@(st)
  val () = app_state_store(st)
in p end

fn _zip_get_name_buf_ptr(): ptr = let
  val st = app_state_load()
  val @APP_STATE(r) = st
  val p = r.zip_name_buf
  prval () = fold@(st)
  val () = app_state_store(st)
in p end

implement _zip_entry_file_handle(i) = buf_get_i32(_zip_get_entries_ptr(), i * 7 + 0)
implement _zip_entry_name_offset(i) = buf_get_i32(_zip_get_entries_ptr(), i * 7 + 1)
implement _zip_entry_name_len(i) = buf_get_i32(_zip_get_entries_ptr(), i * 7 + 2)
implement _zip_entry_compression(i) = buf_get_i32(_zip_get_entries_ptr(), i * 7 + 3)
implement _zip_entry_compressed_size(i) = buf_get_i32(_zip_get_entries_ptr(), i * 7 + 4)
implement _zip_entry_uncompressed_size(i) = buf_get_i32(_zip_get_entries_ptr(), i * 7 + 5)
implement _zip_entry_local_offset(i) = buf_get_i32(_zip_get_entries_ptr(), i * 7 + 6)

implement _zip_name_char(off) = let
  val p = _zip_get_name_buf_ptr()
in
  if off >= 0 then
    if off < 8192 then buf_get_u8(p, off)
    else 0
  else 0
end

implement _zip_name_buf_put(off, byte_val) =
  if off >= 0 then
    if off < 8192 then let
      val () = buf_set_u8(_zip_get_name_buf_ptr(), off, byte_val)
    in 1 end
    else 0
  else 0

implement _zip_store_entry_at(idx, fh, no, nl, comp, cs, us, lo) =
  if idx >= 0 then
    if idx < 256 then let
      val p = _zip_get_entries_ptr()
      val base = idx * 7
      val () = buf_set_i32(p, base + 0, fh)
      val () = buf_set_i32(p, base + 1, no)
      val () = buf_set_i32(p, base + 2, nl)
      val () = buf_set_i32(p, base + 3, comp)
      val () = buf_set_i32(p, base + 4, cs)
      val () = buf_set_i32(p, base + 5, us)
      val () = buf_set_i32(p, base + 6, lo)
    in 1 end
    else 0
  else 0

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
implement app_get_library_books(st) = let
  val @APP_STATE(r) = st val v = r.library_books
  prval () = fold@(st) in v end
implement app_get_string_buffer(st) = let
  val @APP_STATE(r) = st val v = r.string_buffer
  prval () = fold@(st) in v end
implement app_get_fetch_buffer(st) = let
  val @APP_STATE(r) = st val v = r.fetch_buffer
  prval () = fold@(st) in v end
implement app_get_diff_buffer(st) = let
  val @APP_STATE(r) = st val v = r.diff_buffer
  prval () = fold@(st) in v end

(* ========== C-callable wrappers for library module ========== *)

(* Each does a load/use/store cycle on the callback registry stash. *)

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
implement _app_lib_books_ptr() = let val st = app_state_load()
  val v = app_get_library_books(st) val () = app_state_store(st) in v end

(* ========== Buffer ext# wrappers ========== *)
(* Buffers are calloc'd in app_state_init and stored as ptr fields. *)

implement get_string_buffer_ptr() = let val st = app_state_load()
  val v = app_get_string_buffer(st) val () = app_state_store(st) in v end
implement get_fetch_buffer_ptr() = let val st = app_state_load()
  val v = app_get_fetch_buffer(st) val () = app_state_store(st) in v end
implement get_diff_buffer_ptr() = let val st = app_state_load()
  val v = app_get_diff_buffer(st) val () = app_state_store(st) in v end

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

implement app_get_rdr_btn_id(st, idx) = let
  val @APP_STATE(r) = st
  val v = if idx >= 0 then
            if idx < 32 then buf_get_i32(r.rdr_btn_ids, idx)
            else 0 - 1
          else 0 - 1
  prval () = fold@(st)
in v end
implement app_set_rdr_btn_id(st, idx, v) = let
  val @APP_STATE(r) = st
  val () = if idx >= 0 then
             if idx < 32 then buf_set_i32(r.rdr_btn_ids, idx, v)
  prval () = fold@(st)
in end

(* ========== EPUB spine count ========== *)

implement app_get_epub_spine_count(st) = let
  val @APP_STATE(r) = st val v = r.epub_spine_count
  prval () = fold@(st) in v end
implement app_set_epub_spine_count(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_spine_count := v
  prval () = fold@(st) in end

implement app_get_epub_title(st) = let
  val @APP_STATE(r) = st val v = r.epub_title
  prval () = fold@(st) in v end
implement app_get_epub_title_len(st) = let
  val @APP_STATE(r) = st val v = r.epub_title_len
  prval () = fold@(st) in v end
implement app_set_epub_title_len(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_title_len := v
  prval () = fold@(st) in end
implement app_get_epub_author(st) = let
  val @APP_STATE(r) = st val v = r.epub_author
  prval () = fold@(st) in v end
implement app_get_epub_author_len(st) = let
  val @APP_STATE(r) = st val v = r.epub_author_len
  prval () = fold@(st) in v end
implement app_set_epub_author_len(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_author_len := v
  prval () = fold@(st) in end
implement app_get_epub_book_id(st) = let
  val @APP_STATE(r) = st val v = r.epub_book_id
  prval () = fold@(st) in v end
implement app_get_epub_book_id_len(st) = let
  val @APP_STATE(r) = st val v = r.epub_book_id_len
  prval () = fold@(st) in v end
implement app_set_epub_book_id_len(st, v) = let
  val @APP_STATE(r) = st val () = r.epub_book_id_len := v
  prval () = fold@(st) in end
implement app_get_epub_opf_path(st) = let
  val @APP_STATE(r) = st val v = r.epub_opf_path
  prval () = fold@(st) in v end
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
implement app_get_epub_spine_path_buf(st) = let
  val @APP_STATE(r) = st val v = r.epub_spine_path_buf
  prval () = fold@(st) in v end
implement app_get_epub_spine_path_offsets(st) = let
  val @APP_STATE(r) = st val v = r.epub_spine_path_offsets
  prval () = fold@(st) in v end
implement app_get_epub_spine_path_lens(st) = let
  val @APP_STATE(r) = st val v = r.epub_spine_path_lens
  prval () = fold@(st) in v end
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

(* ========== C-callable wrappers for epub fields ========== *)

implement _app_epub_spine_count() = let val st = app_state_load()
  val v = app_get_epub_spine_count(st) val () = app_state_store(st) in v end
implement _app_set_epub_spine_count(v) = let val st = app_state_load()
  val () = app_set_epub_spine_count(st, v) val () = app_state_store(st) in end
implement _app_epub_title_ptr() = let val st = app_state_load()
  val v = app_get_epub_title(st) val () = app_state_store(st) in v end
implement _app_epub_title_len() = let val st = app_state_load()
  val v = app_get_epub_title_len(st) val () = app_state_store(st) in v end
implement _app_set_epub_title_len(v) = let val st = app_state_load()
  val () = app_set_epub_title_len(st, v) val () = app_state_store(st) in end
implement _app_epub_author_ptr() = let val st = app_state_load()
  val v = app_get_epub_author(st) val () = app_state_store(st) in v end
implement _app_epub_author_len() = let val st = app_state_load()
  val v = app_get_epub_author_len(st) val () = app_state_store(st) in v end
implement _app_set_epub_author_len(v) = let val st = app_state_load()
  val () = app_set_epub_author_len(st, v) val () = app_state_store(st) in end
implement _app_epub_book_id_ptr() = let val st = app_state_load()
  val v = app_get_epub_book_id(st) val () = app_state_store(st) in v end
implement _app_epub_book_id_len() = let val st = app_state_load()
  val v = app_get_epub_book_id_len(st) val () = app_state_store(st) in v end
implement _app_set_epub_book_id_len(v) = let val st = app_state_load()
  val () = app_set_epub_book_id_len(st, v) val () = app_state_store(st) in end
implement _app_epub_opf_path_ptr() = let val st = app_state_load()
  val v = app_get_epub_opf_path(st) val () = app_state_store(st) in v end
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
implement _app_epub_spine_path_buf() = let val st = app_state_load()
  val v = app_get_epub_spine_path_buf(st) val () = app_state_store(st) in v end
implement _app_epub_spine_path_offsets() = let val st = app_state_load()
  val v = app_get_epub_spine_path_offsets(st) val () = app_state_store(st) in v end
implement _app_epub_spine_path_lens() = let val st = app_state_load()
  val v = app_get_epub_spine_path_lens(st) val () = app_state_store(st) in v end
implement _app_epub_spine_path_count() = let val st = app_state_load()
  val v = app_get_epub_spine_path_count(st) val () = app_state_store(st) in v end
implement _app_set_epub_spine_path_count(v) = let val st = app_state_load()
  val () = app_set_epub_spine_path_count(st, v) val () = app_state_store(st) in end
implement _app_epub_spine_path_pos() = let val st = app_state_load()
  val v = app_get_epub_spine_path_pos(st) val () = app_state_store(st) in v end
implement _app_set_epub_spine_path_pos(v) = let val st = app_state_load()
  val () = app_set_epub_spine_path_pos(st, v) val () = app_state_store(st) in end

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
