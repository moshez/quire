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
staload "./quire_text.sats"
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

(* Theme CSS — written to a <style> element that persists across page turns.
 * Dark: explicit dark colors on html/body, viewport, container, nav, scrubber, settings.
 * Sepia: warm paper tones on all surfaces.
 * Light: empty string (base app.css handles light mode). *)
#define DARK_THEME_CSS_LEN 316
#define SEPIA_THEME_CSS_LEN 287

(* Fill dark theme CSS bytes into arr using _w4 (little-endian int32 packing).
 * CSS: html,body{background:#222;color:#939393}.reader-viewport{background:#222}
 *      .chapter-container{background:#222;color:#939393}
 *      .chapter-container a{color:#6898b8}
 *      .stg-overlay{background:rgba(0,0,0,.7)}
 *      .stg-row button{background:#333;color:#ccc;border-color:#555}
 *      .reader-nav{background:#222}.reader-bottom{background:#222} *)
fn _fill_dark_theme {l:agz}{n:int | n >= 316}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  val () = _w4(arr, alen, 0, 1819112552)
  val () = _w4(arr, alen, 4, 1685021228)
  val () = _w4(arr, alen, 8, 1633844089)
  val () = _w4(arr, alen, 12, 1919380323)
  val () = _w4(arr, alen, 16, 1684960623)
  val () = _w4(arr, alen, 20, 842146618)
  val () = _w4(arr, alen, 24, 1868774194)
  val () = _w4(arr, alen, 28, 980578156)
  val () = _w4(arr, alen, 32, 959658275)
  val () = _w4(arr, alen, 36, 2100508979)
  val () = _w4(arr, alen, 40, 1634038318)
  val () = _w4(arr, alen, 44, 762471780)
  val () = _w4(arr, alen, 48, 2003134838)
  val () = _w4(arr, alen, 52, 1953656688)
  val () = _w4(arr, alen, 56, 1667326587)
  val () = _w4(arr, alen, 60, 1869768555)
  val () = _w4(arr, alen, 64, 979660405)
  val () = _w4(arr, alen, 68, 842150435)
  val () = _w4(arr, alen, 72, 1751330429)
  val () = _w4(arr, alen, 76, 1702129761)
  val () = _w4(arr, alen, 80, 1868770674)
  val () = _w4(arr, alen, 84, 1767994478)
  val () = _w4(arr, alen, 88, 2071094638)
  val () = _w4(arr, alen, 92, 1801675106)
  val () = _w4(arr, alen, 96, 1970238055)
  val () = _w4(arr, alen, 100, 591029358)
  val () = _w4(arr, alen, 104, 993145394)
  val () = _w4(arr, alen, 108, 1869377379)
  val () = _w4(arr, alen, 112, 958610034)
  val () = _w4(arr, alen, 116, 959658291)
  val () = _w4(arr, alen, 120, 1663991091)
  val () = _w4(arr, alen, 124, 1953522024)
  val () = _w4(arr, alen, 128, 1663922789)
  val () = _w4(arr, alen, 132, 1635020399)
  val () = _w4(arr, alen, 136, 1919250025)
  val () = _w4(arr, alen, 140, 1669030176)
  val () = _w4(arr, alen, 144, 1919904879)
  val () = _w4(arr, alen, 148, 943072058)
  val () = _w4(arr, alen, 152, 945961017)
  val () = _w4(arr, alen, 156, 1953705597)
  val () = _w4(arr, alen, 160, 1986997607)
  val () = _w4(arr, alen, 164, 1634497125)
  val () = _w4(arr, alen, 168, 1633844089)
  val () = _w4(arr, alen, 172, 1919380323)
  val () = _w4(arr, alen, 176, 1684960623)
  val () = _w4(arr, alen, 180, 1650946618)
  val () = _w4(arr, alen, 184, 741353569)
  val () = _w4(arr, alen, 188, 741354544)
  val () = _w4(arr, alen, 192, 2099853102)
  val () = _w4(arr, alen, 196, 1735684910)
  val () = _w4(arr, alen, 200, 2003792429)
  val () = _w4(arr, alen, 204, 1953849888)
  val () = _w4(arr, alen, 208, 2070835060)
  val () = _w4(arr, alen, 212, 1801675106)
  val () = _w4(arr, alen, 216, 1970238055)
  val () = _w4(arr, alen, 220, 591029358)
  val () = _w4(arr, alen, 224, 993211187)
  val () = _w4(arr, alen, 228, 1869377379)
  val () = _w4(arr, alen, 232, 1663253106)
  val () = _w4(arr, alen, 236, 1648059235)
  val () = _w4(arr, alen, 240, 1701081711)
  val () = _w4(arr, alen, 244, 1868770674)
  val () = _w4(arr, alen, 248, 980578156)
  val () = _w4(arr, alen, 252, 892679459)
  val () = _w4(arr, alen, 256, 1701981821)
  val () = _w4(arr, alen, 260, 1919247457)
  val () = _w4(arr, alen, 264, 1986096685)
  val () = _w4(arr, alen, 268, 1667326587)
  val () = _w4(arr, alen, 272, 1869768555)
  val () = _w4(arr, alen, 276, 979660405)
  val () = _w4(arr, alen, 280, 842150435)
  val () = _w4(arr, alen, 284, 1701981821)
  val () = _w4(arr, alen, 288, 1919247457)
  val () = _w4(arr, alen, 292, 1953456685)
  val () = _w4(arr, alen, 296, 2070769524)
  val () = _w4(arr, alen, 300, 1801675106)
  val () = _w4(arr, alen, 304, 1970238055)
  val () = _w4(arr, alen, 308, 591029358)
  val () = _w4(arr, alen, 312, 2100441650)
in end

(* Fill sepia theme CSS bytes into arr using _w4.
 * CSS: html,body{background:#f0e6d2;color:#3a3020}.reader-viewport{background:#f0e6d2}
 *      .chapter-container{background:#f0e6d2;color:#3a3020}
 *      .chapter-container a{color:#5a4020}
 *      .stg-row button{background:#e8dcc8;border-color:#c0b090}
 *      .reader-nav{background:#f0e6d2}.reader-bottom{background:#f0e6d2} *)
fn _fill_sepia_theme {l:agz}{n:int | n >= 288}
  (arr: !ward_arr(byte, l, n), alen: int n): void = let
  val () = _w4(arr, alen, 0, 1819112552)
  val () = _w4(arr, alen, 4, 1685021228)
  val () = _w4(arr, alen, 8, 1633844089)
  val () = _w4(arr, alen, 12, 1919380323)
  val () = _w4(arr, alen, 16, 1684960623)
  val () = _w4(arr, alen, 20, 812000058)
  val () = _w4(arr, alen, 24, 845428325)
  val () = _w4(arr, alen, 28, 1819239227)
  val () = _w4(arr, alen, 32, 591032943)
  val () = _w4(arr, alen, 36, 808673587)
  val () = _w4(arr, alen, 40, 779956274)
  val () = _w4(arr, alen, 44, 1684104562)
  val () = _w4(arr, alen, 48, 1982689893)
  val () = _w4(arr, alen, 52, 1886872937)
  val () = _w4(arr, alen, 56, 2071229039)
  val () = _w4(arr, alen, 60, 1801675106)
  val () = _w4(arr, alen, 64, 1970238055)
  val () = _w4(arr, alen, 68, 591029358)
  val () = _w4(arr, alen, 72, 912601190)
  val () = _w4(arr, alen, 76, 779956836)
  val () = _w4(arr, alen, 80, 1885431907)
  val () = _w4(arr, alen, 84, 762471796)
  val () = _w4(arr, alen, 88, 1953394531)
  val () = _w4(arr, alen, 92, 1701734753)
  val () = _w4(arr, alen, 96, 1633844082)
  val () = _w4(arr, alen, 100, 1919380323)
  val () = _w4(arr, alen, 104, 1684960623)
  val () = _w4(arr, alen, 108, 812000058)
  val () = _w4(arr, alen, 112, 845428325)
  val () = _w4(arr, alen, 116, 1819239227)
  val () = _w4(arr, alen, 120, 591032943)
  val () = _w4(arr, alen, 124, 808673587)
  val () = _w4(arr, alen, 128, 779956274)
  val () = _w4(arr, alen, 132, 1885431907)
  val () = _w4(arr, alen, 136, 762471796)
  val () = _w4(arr, alen, 140, 1953394531)
  val () = _w4(arr, alen, 144, 1701734753)
  val () = _w4(arr, alen, 148, 2069962866)
  val () = _w4(arr, alen, 152, 1869377379)
  val () = _w4(arr, alen, 156, 891501170)
  val () = _w4(arr, alen, 160, 842019937)
  val () = _w4(arr, alen, 164, 1932426544)
  val () = _w4(arr, alen, 168, 1915578228)
  val () = _w4(arr, alen, 172, 1646294895)
  val () = _w4(arr, alen, 176, 1869902965)
  val () = _w4(arr, alen, 180, 1633844078)
  val () = _w4(arr, alen, 184, 1919380323)
  val () = _w4(arr, alen, 188, 1684960623)
  val () = _w4(arr, alen, 192, 946152250)
  val () = _w4(arr, alen, 196, 946037604)
  val () = _w4(arr, alen, 200, 1919902267)
  val () = _w4(arr, alen, 204, 762471780)
  val () = _w4(arr, alen, 208, 1869377379)
  val () = _w4(arr, alen, 212, 1663253106)
  val () = _w4(arr, alen, 216, 959472176)
  val () = _w4(arr, alen, 220, 1915649328)
  val () = _w4(arr, alen, 224, 1701077349)
  val () = _w4(arr, alen, 228, 1634610546)
  val () = _w4(arr, alen, 232, 1633844086)
  val () = _w4(arr, alen, 236, 1919380323)
  val () = _w4(arr, alen, 240, 1684960623)
  val () = _w4(arr, alen, 244, 812000058)
  val () = _w4(arr, alen, 248, 845428325)
  val () = _w4(arr, alen, 252, 1701981821)
  val () = _w4(arr, alen, 256, 1919247457)
  val () = _w4(arr, alen, 260, 1953456685)
  val () = _w4(arr, alen, 264, 2070769524)
  val () = _w4(arr, alen, 268, 1801675106)
  val () = _w4(arr, alen, 272, 1970238055)
  val () = _w4(arr, alen, 276, 591029358)
  val () = _w4(arr, alen, 280, 912601190)
  val () = _w4(arr, alen, 284, 545075812)
in end

(* Apply theme CSS to the persistent <style> element.
 * resolved: 0=light, 1=dark, 2=sepia *)
fn _apply_theme_style(resolved: int): void = let
  val style_id = reader_get_theme_style_id()
in
  if gt_int_int(style_id, 0) then
    if eq_int_int(resolved, 1) then let
      (* Dark theme *)
      val arr = ward_arr_alloc<byte>(DARK_THEME_CSS_LEN)
      val () = _fill_dark_theme(arr, DARK_THEME_CSS_LEN)
      val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
      val dom = ward_dom_init()
      val s = ward_dom_stream_begin(dom)
      val s = ward_dom_stream_set_text(s, style_id, borrow, DARK_THEME_CSS_LEN)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val arr = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(arr)
    in end
    else if eq_int_int(resolved, 2) then let
      (* Sepia theme — 287 bytes, padded array to 288 *)
      val arr = ward_arr_alloc<byte>(288)
      val () = _fill_sepia_theme(arr, 288)
      val @(used, rest) = ward_arr_split<byte>(arr, SEPIA_THEME_CSS_LEN)
      val () = ward_arr_free<byte>(rest)
      val @(frozen, borrow) = ward_arr_freeze<byte>(used)
      val dom = ward_dom_init()
      val s = ward_dom_stream_begin(dom)
      val s = ward_dom_stream_set_text(s, style_id, borrow, SEPIA_THEME_CSS_LEN)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val used = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(used)
    in end
    else let
      (* Light theme — single space clears all theme overrides.
       * CSS ignores whitespace-only <style> content. *)
      val arr = ward_arr_alloc<byte>(1)
      val () = ward_arr_set<byte>(arr, 0, _byte(32)) (* ' ' *)
      val @(frozen, borrow) = ward_arr_freeze<byte>(arr)
      val dom = ward_dom_init()
      val s = ward_dom_stream_begin(dom)
      val s = ward_dom_stream_set_text(s, style_id, borrow, 1)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val arr = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(arr)
    in end
  else ()
end

implement settings_apply() = let
  val active = reader_is_active()
  val () = if eq_int_int(active, 1) then let
    val () = reader_remeasure_all()
    val resolved = settings_resolve_theme()
  in
    _apply_theme_style(resolved)
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

(* ========== Display update helpers ========== *)

(* Set text on a DOM node to a 1-3 digit decimal number *)
fn _set_num_text(node_id: int, v: int): void = let
  val arr = ward_arr_alloc<byte>(12)
in
  if gt_int_int(v, 99) then let
    (* 3 digits -- shouldn't happen for our ranges but safe *)
    val d2 = div_int_int(v, 100)
    val d1 = div_int_int(mod_int_int(v, 100), 10)
    val d0 = mod_int_int(v, 10)
    val () = ward_arr_set<byte>(arr, 0, ward_int2byte(_checked_byte(48 + d2)))
    val () = ward_arr_set<byte>(arr, 1, ward_int2byte(_checked_byte(48 + d1)))
    val () = ward_arr_set<byte>(arr, 2, ward_int2byte(_checked_byte(48 + d0)))
    val @(used, rest) = ward_arr_split<byte>(arr, 3)
    val () = ward_arr_free<byte>(rest)
    val @(frozen, borrow) = ward_arr_freeze<byte>(used)
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_set_text(s, node_id, borrow, 3)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = ward_arr_drop<byte>(frozen, borrow)
    val used = ward_arr_thaw<byte>(frozen)
    val () = ward_arr_free<byte>(used)
  in end
  else if gt_int_int(v, 9) then let
    (* 2 digits *)
    val d1 = div_int_int(v, 10)
    val d0 = mod_int_int(v, 10)
    val () = ward_arr_set<byte>(arr, 0, ward_int2byte(_checked_byte(48 + d1)))
    val () = ward_arr_set<byte>(arr, 1, ward_int2byte(_checked_byte(48 + d0)))
    val @(used, rest) = ward_arr_split<byte>(arr, 2)
    val () = ward_arr_free<byte>(rest)
    val @(frozen, borrow) = ward_arr_freeze<byte>(used)
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_set_text(s, node_id, borrow, 2)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = ward_arr_drop<byte>(frozen, borrow)
    val used = ward_arr_thaw<byte>(frozen)
    val () = ward_arr_free<byte>(used)
  in end
  else let
    (* 1 digit *)
    val () = ward_arr_set<byte>(arr, 0, ward_int2byte(_checked_byte(48 + v)))
    val @(used, rest) = ward_arr_split<byte>(arr, 1)
    val () = ward_arr_free<byte>(rest)
    val @(frozen, borrow) = ward_arr_freeze<byte>(used)
    val dom = ward_dom_init()
    val s = ward_dom_stream_begin(dom)
    val s = ward_dom_stream_set_text(s, node_id, borrow, 1)
    val dom = ward_dom_stream_end(s)
    val () = ward_dom_fini(dom)
    val () = ward_arr_drop<byte>(frozen, borrow)
    val used = ward_arr_thaw<byte>(frozen)
    val () = ward_arr_free<byte>(used)
  in end
end

(* Set line height display: tenths like 16 -> "1.6" *)
fn _set_lh_text(node_id: int, tenths: int): void = let
  val whole = div_int_int(tenths, 10)
  val frac = mod_int_int(tenths, 10)
  val arr = ward_arr_alloc<byte>(12)
  val () = ward_arr_set<byte>(arr, 0, ward_int2byte(_checked_byte(48 + whole)))
  val () = ward_arr_set<byte>(arr, 1, _byte(46)) (* '.' *)
  val () = ward_arr_set<byte>(arr, 2, ward_int2byte(_checked_byte(48 + frac)))
  val @(used, rest) = ward_arr_split<byte>(arr, 3)
  val () = ward_arr_free<byte>(rest)
  val @(frozen, borrow) = ward_arr_freeze<byte>(used)
  val dom = ward_dom_init()
  val s = ward_dom_stream_begin(dom)
  val s = ward_dom_stream_set_text(s, node_id, borrow, 3)
  val dom = ward_dom_stream_end(s)
  val () = ward_dom_fini(dom)
  val () = ward_arr_drop<byte>(frozen, borrow)
  val used = ward_arr_thaw<byte>(frozen)
  val () = ward_arr_free<byte>(used)
in end

(* Update all settings display nodes *)
fn _update_all_displays(): void = let
  val st = app_state_load()
  val disp_fs = app_get_stg_disp_fs(st)
  val disp_ff = app_get_stg_disp_ff(st)
  val disp_lh = app_get_stg_disp_lh(st)
  val disp_mg = app_get_stg_disp_mg(st)
  val btn_ff = app_get_stg_btn_font_fam(st)
  val () = app_state_store(st)
  val fs = settings_get_font_size()
  val ff = settings_get_font_family()
  val lh = settings_get_line_height_tenths()
  val mg = settings_get_margin()
  val () = if gt_int_int(disp_fs, 0) then _set_num_text(disp_fs, fs) else ()
  val () = if gt_int_int(disp_lh, 0) then _set_lh_text(disp_lh, lh) else ()
  val () = if gt_int_int(disp_mg, 0) then _set_num_text(disp_mg, mg) else ()
  (* Update font family button text *)
  val () = if gt_int_int(btn_ff, 0) then let
    val arr = ward_arr_alloc<byte>(12)
  in
    if eq_int_int(ff, 1) then let
      (* "Sans" *)
      val () = ward_arr_set<byte>(arr, 0, _byte(83))  (* S *)
      val () = ward_arr_set<byte>(arr, 1, _byte(97))  (* a *)
      val () = ward_arr_set<byte>(arr, 2, _byte(110)) (* n *)
      val () = ward_arr_set<byte>(arr, 3, _byte(115)) (* s *)
      val @(used, rest) = ward_arr_split<byte>(arr, 4)
      val () = ward_arr_free<byte>(rest)
      val @(frozen, borrow) = ward_arr_freeze<byte>(used)
      val dom = ward_dom_init()
      val s = ward_dom_stream_begin(dom)
      val s = ward_dom_stream_set_text(s, btn_ff, borrow, 4)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val used = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(used)
    in end
    else if eq_int_int(ff, 2) then let
      (* "Pub" *)
      val () = ward_arr_set<byte>(arr, 0, _byte(80))  (* P *)
      val () = ward_arr_set<byte>(arr, 1, _byte(117)) (* u *)
      val () = ward_arr_set<byte>(arr, 2, _byte(98))  (* b *)
      val @(used, rest) = ward_arr_split<byte>(arr, 3)
      val () = ward_arr_free<byte>(rest)
      val @(frozen, borrow) = ward_arr_freeze<byte>(used)
      val dom = ward_dom_init()
      val s = ward_dom_stream_begin(dom)
      val s = ward_dom_stream_set_text(s, btn_ff, borrow, 3)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val used = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(used)
    in end
    else let
      (* "Serif" *)
      val () = ward_arr_set<byte>(arr, 0, _byte(83))  (* S *)
      val () = ward_arr_set<byte>(arr, 1, _byte(101)) (* e *)
      val () = ward_arr_set<byte>(arr, 2, _byte(114)) (* r *)
      val () = ward_arr_set<byte>(arr, 3, _byte(105)) (* i *)
      val () = ward_arr_set<byte>(arr, 4, _byte(102)) (* f *)
      val @(used, rest) = ward_arr_split<byte>(arr, 5)
      val () = ward_arr_free<byte>(rest)
      val @(frozen, borrow) = ward_arr_freeze<byte>(used)
      val dom = ward_dom_init()
      val s = ward_dom_stream_begin(dom)
      val s = ward_dom_stream_set_text(s, btn_ff, borrow, 5)
      val dom = ward_dom_stream_end(s)
      val () = ward_dom_fini(dom)
      val () = ward_arr_drop<byte>(frozen, borrow)
      val used = ward_arr_thaw<byte>(frozen)
      val () = ward_arr_free<byte>(used)
    in end
  end
  else ()
in end

(* ========== Click handler ========== *)

implement settings_handle_click(node_id) = let
  val st = app_state_load()
  val btn_fs_m = app_get_stg_btn_font_minus(st)
  val btn_fs_p = app_get_stg_btn_font_plus(st)
  val btn_ff = app_get_stg_btn_font_fam(st)
  val btn_th_l = app_get_stg_btn_theme_l(st)
  val btn_th_d = app_get_stg_btn_theme_d(st)
  val btn_th_s = app_get_stg_btn_theme_s(st)
  val btn_lh_m = app_get_stg_btn_lh_minus(st)
  val btn_lh_p = app_get_stg_btn_lh_plus(st)
  val btn_mg_m = app_get_stg_btn_mg_minus(st)
  val btn_mg_p = app_get_stg_btn_mg_plus(st)
  val () = app_state_store(st)
in
  if eq_int_int(node_id, btn_fs_m) then let
    val () = settings_decrease_font_size()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_fs_p) then let
    val () = settings_increase_font_size()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_ff) then let
    val () = settings_next_font_family()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_th_l) then let
    val () = settings_set_theme(THEME_LIGHT)
    val (_pf | ()) = settings_apply()
    val () = settings_save()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_th_d) then let
    val () = settings_set_theme(THEME_DARK)
    val (_pf | ()) = settings_apply()
    val () = settings_save()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_th_s) then let
    val () = settings_set_theme(THEME_SEPIA)
    val (_pf | ()) = settings_apply()
    val () = settings_save()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_lh_m) then let
    val () = settings_decrease_line_height()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_lh_p) then let
    val () = settings_increase_line_height()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_mg_m) then let
    val () = settings_decrease_margin()
    val () = _update_all_displays()
  in 1 end
  else if eq_int_int(node_id, btn_mg_p) then let
    val () = settings_increase_margin()
    val () = _update_all_displays()
  in 1 end
  else 0
end
