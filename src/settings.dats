(* settings.dats - Reader settings implementation
 *
 * All settings state stored in app_state.
 * CSS variables applied via DOM style injection.
 * Persisted to IndexedDB under "settings" key.
 *)

#define ATS_DYNLOADFLAG 0

#include "share/atspre_staload.hats"
staload "./settings.sats"
staload "./app_state.sats"
staload "./arith.sats"
staload "./reader.sats"
staload "./dom.sats"
staload "./quire_ext.sats"

(* Forward declaration for JS import — suppresses C99 warning *)
%{
extern int quire_get_dark_mode(void);
%}
staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload _ = "./../vendor/ward/lib/memory.dats"
staload _ = "./../vendor/ward/lib/dom.dats"

extern castfn _byte {c:int | 0 <= c; c <= 255} (c: int c): byte

(* ========== Castfns for bounded returns ========== *)

extern castfn _clamp_fs(x: int): [fs:int | fs >= 14; fs <= 32] int(fs)
extern castfn _clamp_ff(x: int): [ff:int | ff >= 0; ff <= 2] int(ff)
extern castfn _clamp_th(x: int): [th:int | th >= 0; th <= 2] int(th)
extern castfn _clamp_lh(x: int): [lh:int | lh >= 14; lh <= 24] int(lh)
extern castfn _clamp_mg(x: int): [m:int | m >= 1; m <= 4] int(m)

(* ========== Init ========== *)

implement settings_init() = let
  val st = app_state_load()
  val () = app_set_stg_font_size(st, 18)
  val () = app_set_stg_font_family(st, FONT_SERIF)
  val () = app_set_stg_theme(st, THEME_AUTO)
  val () = app_set_stg_lh_tenths(st, 16)
  val () = app_set_stg_margin(st, 2)
  val () = app_set_stg_visible(st, 0)
  val () = app_set_stg_overlay_id(st, 0)
  val () = app_set_stg_save_pend(st, 0)
  val () = app_set_stg_load_pend(st, 0)
  val () = app_state_store(st)
in end

(* ========== Getters ========== *)

implement settings_get_font_size() = let
  val st = app_state_load()
  val v = app_get_stg_font_size(st)
  val () = app_state_store(st)
in
  if v >= FONT_SIZE_MIN then
    if v <= FONT_SIZE_MAX then _clamp_fs(v)
    else _clamp_fs(FONT_SIZE_MAX)
  else _clamp_fs(FONT_SIZE_MIN)
end

implement settings_get_font_family() = let
  val st = app_state_load()
  val v = app_get_stg_font_family(st)
  val () = app_state_store(st)
in
  if eq_int_int(v, 1) then _clamp_ff(1)
  else if eq_int_int(v, 2) then _clamp_ff(2)
  else _clamp_ff(0)
end

extern castfn _clamp_th3(x: int): [th:int | th >= 0; th <= 3] int(th)

implement settings_get_theme() = let
  val st = app_state_load()
  val v = app_get_stg_theme(st)
  val () = app_state_store(st)
in
  if eq_int_int(v, 1) then _clamp_th3(1)
  else if eq_int_int(v, 2) then _clamp_th3(2)
  else if eq_int_int(v, 3) then _clamp_th3(3)
  else _clamp_th3(0)
end

implement settings_get_line_height_tenths() = let
  val st = app_state_load()
  val v = app_get_stg_lh_tenths(st)
  val () = app_state_store(st)
in
  if v >= LINE_HEIGHT_MIN_TENTHS then
    if v <= LINE_HEIGHT_MAX_TENTHS then _clamp_lh(v)
    else _clamp_lh(LINE_HEIGHT_MAX_TENTHS)
  else _clamp_lh(LINE_HEIGHT_MIN_TENTHS)
end

implement settings_get_margin() = let
  val st = app_state_load()
  val v = app_get_stg_margin(st)
  val () = app_state_store(st)
in
  if v >= MARGIN_MIN then
    if v <= MARGIN_MAX then _clamp_mg(v)
    else _clamp_mg(MARGIN_MAX)
  else _clamp_mg(MARGIN_MIN)
end

(* Resolve effective theme: Auto (3) maps to light/dark based on system preference *)
implement settings_resolve_theme() = let
  val th = settings_get_theme()
in
  if eq_int_int(th, 3) then let
    val dark = quire_get_dark_mode()
  in
    if eq_int_int(dark, 1) then _clamp_th(1) (* dark *)
    else _clamp_th(0) (* light *)
  end
  else if eq_int_int(th, 2) then _clamp_th(2) (* sepia *)
  else if eq_int_int(th, 1) then _clamp_th(1) (* dark *)
  else _clamp_th(0) (* light *)
end

(* CSS mode — stored in app_state settings area *)
implement settings_get_css_mode() = let
  val st = app_state_load()
  val v = app_get_stg_css_mode(st)
  val () = app_state_store(st)
in
  if eq_int_int(v, 0) then (CSS_MODE_PUBLISHER() | 0)
  else if eq_int_int(v, 2) then (CSS_MODE_CUSTOM() | 2)
  else (CSS_MODE_READER() | 1)
end

implement settings_set_css_mode{m}(pf | mode) = let
  prval _ = pf
  val st = app_state_load()
  val () = app_set_stg_css_mode(st, mode)
  val () = app_state_store(st)
in end

(* ========== Setters (clamp to valid range) ========== *)

implement settings_set_font_size(size) = let
  val clamped = if lt_int_int(size, FONT_SIZE_MIN) then FONT_SIZE_MIN
                else if gt_int_int(size, FONT_SIZE_MAX) then FONT_SIZE_MAX
                else size
  val st = app_state_load()
  val () = app_set_stg_font_size(st, clamped)
  val () = app_state_store(st)
in end

implement settings_set_font_family(family) = let
  val clamped = if lt_int_int(family, 0) then 0
                else if gt_int_int(family, 2) then 2
                else family
  val st = app_state_load()
  val () = app_set_stg_font_family(st, clamped)
  val () = app_state_store(st)
in end

implement settings_set_theme(theme) = let
  val clamped = if lt_int_int(theme, 0) then 0
                else if gt_int_int(theme, 3) then 3
                else theme
  val st = app_state_load()
  val () = app_set_stg_theme(st, clamped)
  val () = app_state_store(st)
in end

implement settings_set_line_height_tenths(tenths) = let
  val clamped = if lt_int_int(tenths, LINE_HEIGHT_MIN_TENTHS) then LINE_HEIGHT_MIN_TENTHS
                else if gt_int_int(tenths, LINE_HEIGHT_MAX_TENTHS) then LINE_HEIGHT_MAX_TENTHS
                else tenths
  val st = app_state_load()
  val () = app_set_stg_lh_tenths(st, clamped)
  val () = app_state_store(st)
in end

implement settings_set_margin(margin) = let
  val clamped = if lt_int_int(margin, MARGIN_MIN) then MARGIN_MIN
                else if gt_int_int(margin, MARGIN_MAX) then MARGIN_MAX
                else margin
  val st = app_state_load()
  val () = app_set_stg_margin(st, clamped)
  val () = app_state_store(st)
in end

(* ========== Apply ========== *)

local
  assume SETTINGS_APPLIED() = unit_p
in

(* Dark mode CSS: invert chapter container colors, preserve images.
 * "filter:invert(1) hue-rotate(180deg)" inverts all colors while
 * preserving hue relationships. Apply reverse filter on images. *)
#define DARK_CSS_LEN 128

fn _inject_dark_mode_css(container_id: int): void = let
  (* CSS: .chapter-container{filter:invert(1) hue-rotate(180deg)}
   *      .chapter-container img{filter:invert(1) hue-rotate(180deg)} *)
  val arr = ward_arr_alloc<byte>(DARK_CSS_LEN)
  (* Build: "filter:invert(1) hue-rotate(180deg)" = 39 chars *)
  val filter_css = "filter:invert(1) hue-rotate(180deg)"
  (* Use a simple approach: set the style directly on the container *)
in
  if gt_int_int(container_id, 0) then let
    val style_arr = ward_arr_alloc<byte>(48)
    (* "filter:invert(1) hue-rotate(180deg)" = 39 bytes *)
    val () = ward_arr_set<byte>(style_arr, 0, _byte(102))   (* f *)
    val () = ward_arr_set<byte>(style_arr, 1, _byte(105))   (* i *)
    val () = ward_arr_set<byte>(style_arr, 2, _byte(108))   (* l *)
    val () = ward_arr_set<byte>(style_arr, 3, _byte(116))   (* t *)
    val () = ward_arr_set<byte>(style_arr, 4, _byte(101))   (* e *)
    val () = ward_arr_set<byte>(style_arr, 5, _byte(114))   (* r *)
    val () = ward_arr_set<byte>(style_arr, 6, _byte(58))    (* : *)
    val () = ward_arr_set<byte>(style_arr, 7, _byte(105))   (* i *)
    val () = ward_arr_set<byte>(style_arr, 8, _byte(110))   (* n *)
    val () = ward_arr_set<byte>(style_arr, 9, _byte(118))   (* v *)
    val () = ward_arr_set<byte>(style_arr, 10, _byte(101))  (* e *)
    val () = ward_arr_set<byte>(style_arr, 11, _byte(114))  (* r *)
    val () = ward_arr_set<byte>(style_arr, 12, _byte(116))  (* t *)
    val () = ward_arr_set<byte>(style_arr, 13, _byte(40))   (* ( *)
    val () = ward_arr_set<byte>(style_arr, 14, _byte(49))   (* 1 *)
    val () = ward_arr_set<byte>(style_arr, 15, _byte(41))   (* ) *)
    val () = ward_arr_set<byte>(style_arr, 16, _byte(32))   (* ' ' *)
    val () = ward_arr_set<byte>(style_arr, 17, _byte(104))  (* h *)
    val () = ward_arr_set<byte>(style_arr, 18, _byte(117))  (* u *)
    val () = ward_arr_set<byte>(style_arr, 19, _byte(101))  (* e *)
    val () = ward_arr_set<byte>(style_arr, 20, _byte(45))   (* - *)
    val () = ward_arr_set<byte>(style_arr, 21, _byte(114))  (* r *)
    val () = ward_arr_set<byte>(style_arr, 22, _byte(111))  (* o *)
    val () = ward_arr_set<byte>(style_arr, 23, _byte(116))  (* t *)
    val () = ward_arr_set<byte>(style_arr, 24, _byte(97))   (* a *)
    val () = ward_arr_set<byte>(style_arr, 25, _byte(116))  (* t *)
    val () = ward_arr_set<byte>(style_arr, 26, _byte(101))  (* e *)
    val () = ward_arr_set<byte>(style_arr, 27, _byte(40))   (* ( *)
    val () = ward_arr_set<byte>(style_arr, 28, _byte(49))   (* 1 *)
    val () = ward_arr_set<byte>(style_arr, 29, _byte(56))   (* 8 *)
    val () = ward_arr_set<byte>(style_arr, 30, _byte(48))   (* 0 *)
    val () = ward_arr_set<byte>(style_arr, 31, _byte(100))  (* d *)
    val () = ward_arr_set<byte>(style_arr, 32, _byte(101))  (* e *)
    val () = ward_arr_set<byte>(style_arr, 33, _byte(103))  (* g *)
    val () = ward_arr_set<byte>(style_arr, 34, _byte(41))   (* ) *)
    val @(used, rest) = ward_arr_split<byte>(style_arr, 35)
    val () = ward_arr_free<byte>(rest)
    val @(frozen, borrow) = ward_arr_freeze<byte>(used)
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_set_style(s, container_id, borrow, 35)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = ward_arr_drop<byte>(frozen, borrow)
    val used = ward_arr_thaw<byte>(frozen)
    val () = ward_arr_free<byte>(used)
    val () = ward_arr_free<byte>(arr)
  in end
  else ward_arr_free<byte>(arr)
end

fn _clear_dark_mode_css(container_id: int): void = let
in
  if gt_int_int(container_id, 0) then let
    (* Set empty style to clear the filter *)
    val arr = ward_arr_alloc<byte>(12)
    val () = ward_arr_set<byte>(arr, 0, _byte(102))  (* f *)
    val () = ward_arr_set<byte>(arr, 1, _byte(105))  (* i *)
    val () = ward_arr_set<byte>(arr, 2, _byte(108))  (* l *)
    val () = ward_arr_set<byte>(arr, 3, _byte(116))  (* t *)
    val () = ward_arr_set<byte>(arr, 4, _byte(101))  (* e *)
    val () = ward_arr_set<byte>(arr, 5, _byte(114))  (* r *)
    val () = ward_arr_set<byte>(arr, 6, _byte(58))   (* : *)
    val () = ward_arr_set<byte>(arr, 7, _byte(110))  (* n *)
    val () = ward_arr_set<byte>(arr, 8, _byte(111))  (* o *)
    val () = ward_arr_set<byte>(arr, 9, _byte(110))  (* n *)
    val () = ward_arr_set<byte>(arr, 10, _byte(101)) (* e *)
    val @(used, rest) = ward_arr_split<byte>(arr, 11)
    val () = ward_arr_free<byte>(rest)
    val @(frozen, borrow) = ward_arr_freeze<byte>(used)
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_set_style(s, container_id, borrow, 11)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = ward_arr_drop<byte>(frozen, borrow)
    val used = ward_arr_thaw<byte>(frozen)
    val () = ward_arr_free<byte>(used)
  in end
  else ()
end

implement settings_apply() = let
  val active = reader_is_active()
  val () = if eq_int_int(active, 1) then let
    val () = reader_remeasure_all()
    (* Apply dark mode inversion if theme is dark *)
    val resolved = settings_resolve_theme()
    val cid = reader_get_container_id()
  in
    if eq_int_int(resolved, 1) then _inject_dark_mode_css(cid)
    else _clear_dark_mode_css(cid)
  end
  else ()
in (unit_p() | ()) end

end (* local SETTINGS_APPLIED *)

(* ========== Increment/Decrement helpers ========== *)

implement settings_increase_font_size() = let
  val cur = settings_get_font_size()
  val () = settings_set_font_size(cur + 1)
  val (_pf | ()) = settings_apply()
  val () = settings_save()
in end

implement settings_decrease_font_size() = let
  val cur = settings_get_font_size()
  val () = settings_set_font_size(cur - 1)
  val (_pf | ()) = settings_apply()
  val () = settings_save()
in end

implement settings_next_font_family() = let
  val cur = settings_get_font_family()
  val next = if gte_int_int(cur, 2) then 0 else cur + 1
  val () = settings_set_font_family(next)
  val (_pf | ()) = settings_apply()
  val () = settings_save()
in end

implement settings_next_theme() = let
  val cur = settings_get_theme()
  val next = if gte_int_int(cur, 3) then 0 else cur + 1
  val () = settings_set_theme(next)
  val (_pf | ()) = settings_apply()
  val () = settings_save()
in end

implement settings_increase_line_height() = let
  val cur = settings_get_line_height_tenths()
  val () = settings_set_line_height_tenths(cur + 1)
  val (_pf | ()) = settings_apply()
  val () = settings_save()
in end

implement settings_decrease_line_height() = let
  val cur = settings_get_line_height_tenths()
  val () = settings_set_line_height_tenths(cur - 1)
  val (_pf | ()) = settings_apply()
  val () = settings_save()
in end

implement settings_increase_margin() = let
  val cur = settings_get_margin()
  val () = settings_set_margin(cur + 1)
  val (_pf | ()) = settings_apply()
  val () = settings_save()
in end

implement settings_decrease_margin() = let
  val cur = settings_get_margin()
  val () = settings_set_margin(cur - 1)
  val (_pf | ()) = settings_apply()
  val () = settings_save()
in end

(* ========== IDB Persistence (stub — will be implemented with full serialization) ========== *)

implement settings_save() = ()
implement settings_on_save_complete(success) = ()
implement settings_load() = ()
implement settings_on_load_complete(len) = ()

(* ========== Style helpers ========== *)

fn _stg_set_style_none(node_id: int): void = let
  val arr = ward_arr_alloc<byte>(12)
  val () = ward_arr_set<byte>(arr, 0, _byte(100)) (* d *)
  val () = ward_arr_set<byte>(arr, 1, _byte(105)) (* i *)
  val () = ward_arr_set<byte>(arr, 2, _byte(115)) (* s *)
  val () = ward_arr_set<byte>(arr, 3, _byte(112)) (* p *)
  val () = ward_arr_set<byte>(arr, 4, _byte(108)) (* l *)
  val () = ward_arr_set<byte>(arr, 5, _byte(97))  (* a *)
  val () = ward_arr_set<byte>(arr, 6, _byte(121)) (* y *)
  val () = ward_arr_set<byte>(arr, 7, _byte(58))  (* : *)
  val () = ward_arr_set<byte>(arr, 8, _byte(110)) (* n *)
  val () = ward_arr_set<byte>(arr, 9, _byte(111)) (* o *)
  val () = ward_arr_set<byte>(arr, 10, _byte(110)) (* n *)
  val () = ward_arr_set<byte>(arr, 11, _byte(101)) (* e *)
  val @(used, rest) = ward_arr_split<byte>(arr, 12)
  val () = ward_arr_free<byte>(rest)
  val @(frozen, borrow) = ward_arr_freeze<byte>(used)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_set_style(s, node_id, borrow, 12)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val used = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(used)
in end

fn _stg_set_style_flex(node_id: int): void = let
  val arr = ward_arr_alloc<byte>(12)
  val () = ward_arr_set<byte>(arr, 0, _byte(100)) (* d *)
  val () = ward_arr_set<byte>(arr, 1, _byte(105)) (* i *)
  val () = ward_arr_set<byte>(arr, 2, _byte(115)) (* s *)
  val () = ward_arr_set<byte>(arr, 3, _byte(112)) (* p *)
  val () = ward_arr_set<byte>(arr, 4, _byte(108)) (* l *)
  val () = ward_arr_set<byte>(arr, 5, _byte(97))  (* a *)
  val () = ward_arr_set<byte>(arr, 6, _byte(121)) (* y *)
  val () = ward_arr_set<byte>(arr, 7, _byte(58))  (* : *)
  val () = ward_arr_set<byte>(arr, 8, _byte(102)) (* f *)
  val () = ward_arr_set<byte>(arr, 9, _byte(108)) (* l *)
  val () = ward_arr_set<byte>(arr, 10, _byte(101)) (* e *)
  val () = ward_arr_set<byte>(arr, 11, _byte(120)) (* x *)
  val @(used, rest) = ward_arr_split<byte>(arr, 12)
  val () = ward_arr_free<byte>(rest)
  val @(frozen, borrow) = ward_arr_freeze<byte>(used)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_set_style(s, node_id, borrow, 12)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val used = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(used)
in end

(* ========== Modal visibility ========== *)

implement settings_is_visible() = let
  val st = app_state_load()
  val v = app_get_stg_visible(st)
  val () = app_state_store(st)
in v end

implement settings_show() = let
  val st = app_state_load()
  val () = app_set_stg_visible(st, 1)
  val oid = app_get_stg_overlay_id(st)
  val () = app_state_store(st)
  val () = if gt_int_int(oid, 0) then _stg_set_style_flex(oid) else ()
in end

implement settings_hide() = let
  val st = app_state_load()
  val () = app_set_stg_visible(st, 0)
  val oid = app_get_stg_overlay_id(st)
  val () = app_state_store(st)
  val () = if gt_int_int(oid, 0) then _stg_set_style_none(oid) else ()
in end

implement settings_toggle() = let
  val vis = settings_is_visible()
in
  if eq_int_int(vis, 1) then settings_hide()
  else settings_show()
end

implement settings_get_overlay_id() = let
  val st = app_state_load()
  val v = app_get_stg_overlay_id(st)
  val () = app_state_store(st)
in v end

implement settings_handle_click(node_id) = 0
