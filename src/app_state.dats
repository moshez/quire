(* app_state.dats — Linear application state implementation
 *
 * Pure ATS2 datavtype. No C code. Fields accessed via @-unfold
 * pattern which generates direct struct member access in C.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./app_state.sats"
staload "./../vendor/ward/lib/callback.sats"
staload _ = "./../vendor/ward/lib/callback.dats"

(* Well-known callback ID for the app_state stash.
 * This entry's ctx slot holds the app_state pointer. *)
#define APP_STATE_CB_ID 0

datavtype app_state_impl =
  | APP_STATE of @{
      dom_next_node_id = int,
      zip_entry_count = int,
      zip_file_handle = int,
      zip_name_offset = int,
      library_count = int,
      lib_save_pending = int,
      lib_load_pending = int,
      lib_meta_save_pending = int,
      lib_meta_load_pending = int,
      lib_meta_load_index = int,
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
      stg_load_pend = int
    }

assume app_state = app_state_impl

implement app_state_init() =
  APP_STATE @{
    dom_next_node_id = 1,
    zip_entry_count = 0,
    zip_file_handle = 0,
    zip_name_offset = 0,
    library_count = 0,
    lib_save_pending = 0,
    lib_load_pending = 0,
    lib_meta_save_pending = 0,
    lib_meta_load_pending = 0,
    lib_meta_load_index = 0 - 1,
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
    stg_load_pend = 0
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

(* ========== C-callable wrappers for library module ========== *)

(* These use ext# so C code in quire_runtime.c can call them.
 * Each does a load/use/store cycle on the callback registry stash. *)

extern fun _app_lib_count(): int = "ext#_app_lib_count"
extern fun _app_set_lib_count(v: int): void = "ext#_app_set_lib_count"
extern fun _app_lib_save_pend(): int = "ext#_app_lib_save_pend"
extern fun _app_set_lib_save_pend(v: int): void = "ext#_app_set_lib_save_pend"
extern fun _app_lib_load_pend(): int = "ext#_app_lib_load_pend"
extern fun _app_set_lib_load_pend(v: int): void = "ext#_app_set_lib_load_pend"
extern fun _app_lib_meta_save_pend(): int = "ext#_app_lib_meta_save_pend"
extern fun _app_set_lib_meta_save_pend(v: int): void = "ext#_app_set_lib_meta_save_pend"
extern fun _app_lib_meta_load_pend(): int = "ext#_app_lib_meta_load_pend"
extern fun _app_set_lib_meta_load_pend(v: int): void = "ext#_app_set_lib_meta_load_pend"
extern fun _app_lib_meta_load_idx(): int = "ext#_app_lib_meta_load_idx"
extern fun _app_set_lib_meta_load_idx(v: int): void = "ext#_app_set_lib_meta_load_idx"

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

(* ========== C-callable wrappers for settings module ========== *)

extern fun _app_stg_font_size(): int = "ext#_app_stg_font_size"
extern fun _app_set_stg_font_size(v: int): void = "ext#_app_set_stg_font_size"
extern fun _app_stg_font_family(): int = "ext#_app_stg_font_family"
extern fun _app_set_stg_font_family(v: int): void = "ext#_app_set_stg_font_family"
extern fun _app_stg_theme(): int = "ext#_app_stg_theme"
extern fun _app_set_stg_theme(v: int): void = "ext#_app_set_stg_theme"
extern fun _app_stg_lh_tenths(): int = "ext#_app_stg_lh_tenths"
extern fun _app_set_stg_lh_tenths(v: int): void = "ext#_app_set_stg_lh_tenths"
extern fun _app_stg_margin(): int = "ext#_app_stg_margin"
extern fun _app_set_stg_margin(v: int): void = "ext#_app_set_stg_margin"
extern fun _app_stg_visible(): int = "ext#_app_stg_visible"
extern fun _app_set_stg_visible(v: int): void = "ext#_app_set_stg_visible"
extern fun _app_stg_overlay_id(): int = "ext#_app_stg_overlay_id"
extern fun _app_set_stg_overlay_id(v: int): void = "ext#_app_set_stg_overlay_id"
extern fun _app_stg_close_id(): int = "ext#_app_stg_close_id"
extern fun _app_set_stg_close_id(v: int): void = "ext#_app_set_stg_close_id"
extern fun _app_stg_root_id(): int = "ext#_app_stg_root_id"
extern fun _app_set_stg_root_id(v: int): void = "ext#_app_set_stg_root_id"
extern fun _app_stg_btn_font_minus(): int = "ext#_app_stg_btn_font_minus"
extern fun _app_set_stg_btn_font_minus(v: int): void = "ext#_app_set_stg_btn_font_minus"
extern fun _app_stg_btn_font_plus(): int = "ext#_app_stg_btn_font_plus"
extern fun _app_set_stg_btn_font_plus(v: int): void = "ext#_app_set_stg_btn_font_plus"
extern fun _app_stg_btn_font_fam(): int = "ext#_app_stg_btn_font_fam"
extern fun _app_set_stg_btn_font_fam(v: int): void = "ext#_app_set_stg_btn_font_fam"
extern fun _app_stg_btn_theme_l(): int = "ext#_app_stg_btn_theme_l"
extern fun _app_set_stg_btn_theme_l(v: int): void = "ext#_app_set_stg_btn_theme_l"
extern fun _app_stg_btn_theme_d(): int = "ext#_app_stg_btn_theme_d"
extern fun _app_set_stg_btn_theme_d(v: int): void = "ext#_app_set_stg_btn_theme_d"
extern fun _app_stg_btn_theme_s(): int = "ext#_app_stg_btn_theme_s"
extern fun _app_set_stg_btn_theme_s(v: int): void = "ext#_app_set_stg_btn_theme_s"
extern fun _app_stg_btn_lh_minus(): int = "ext#_app_stg_btn_lh_minus"
extern fun _app_set_stg_btn_lh_minus(v: int): void = "ext#_app_set_stg_btn_lh_minus"
extern fun _app_stg_btn_lh_plus(): int = "ext#_app_stg_btn_lh_plus"
extern fun _app_set_stg_btn_lh_plus(v: int): void = "ext#_app_set_stg_btn_lh_plus"
extern fun _app_stg_btn_mg_minus(): int = "ext#_app_stg_btn_mg_minus"
extern fun _app_set_stg_btn_mg_minus(v: int): void = "ext#_app_set_stg_btn_mg_minus"
extern fun _app_stg_btn_mg_plus(): int = "ext#_app_stg_btn_mg_plus"
extern fun _app_set_stg_btn_mg_plus(v: int): void = "ext#_app_set_stg_btn_mg_plus"
extern fun _app_stg_disp_fs(): int = "ext#_app_stg_disp_fs"
extern fun _app_set_stg_disp_fs(v: int): void = "ext#_app_set_stg_disp_fs"
extern fun _app_stg_disp_ff(): int = "ext#_app_stg_disp_ff"
extern fun _app_set_stg_disp_ff(v: int): void = "ext#_app_set_stg_disp_ff"
extern fun _app_stg_disp_lh(): int = "ext#_app_stg_disp_lh"
extern fun _app_set_stg_disp_lh(v: int): void = "ext#_app_set_stg_disp_lh"
extern fun _app_stg_disp_mg(): int = "ext#_app_stg_disp_mg"
extern fun _app_set_stg_disp_mg(v: int): void = "ext#_app_set_stg_disp_mg"
extern fun _app_stg_save_pend(): int = "ext#_app_stg_save_pend"
extern fun _app_set_stg_save_pend(v: int): void = "ext#_app_set_stg_save_pend"
extern fun _app_stg_load_pend(): int = "ext#_app_stg_load_pend"
extern fun _app_set_stg_load_pend(v: int): void = "ext#_app_set_stg_load_pend"

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

(* ========== Callback registry stash ========== *)

(*
 * $UNSAFE justifications:
 * [U-store] castvwtp0{ptr}(st) — erase linear app_state to ptr for
 *   callback registry storage. Same pattern as ward's promise/event
 *   resolver storage. The linear ownership is preserved by convention:
 *   exactly one load follows each store.
 * [U-load] castvwtp0{app_state}(p) — recover linear app_state from
 *   ptr retrieved from callback registry. Same as ward_dom_load in
 *   vendor/ward/lib/dom.dats:141. Trust boundary: we trust that the
 *   pointer was stored by a prior store/register and not aliased.
 *)

implement app_state_register(st) = let
  val p = $UNSAFE.castvwtp0{ptr}(st) (* [U-store] *)
  val dummy = lam (payload: int): int =<cloref1> 0
in
  ward_callback_register_ctx(APP_STATE_CB_ID, p, dummy)
end

implement app_state_store(st) = let
  val p = $UNSAFE.castvwtp0{ptr}(st) (* [U-store] *)
in
  ward_callback_set_ctx(APP_STATE_CB_ID, p)
end

implement app_state_load() = let
  val p = ward_callback_get_ctx(APP_STATE_CB_ID)
in
  $UNSAFE.castvwtp0{app_state}(p) (* [U-load] *)
end
