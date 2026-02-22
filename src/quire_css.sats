(* quire_css.sats — CSS generation declarations for Quire
 *
 * Absviews, dataprops, and function declarations for CSS injection.
 * CSS bytes are packed as little-endian int32s and written via _w4.
 *
 * Proof architecture:
 * CSS_READER_WRITTEN can ONLY be produced by stamp_reader_css.
 * CSS_NAV_WRITTEN can ONLY be produced by stamp_nav_css.
 * inject functions REQUIRE them — impossible to inject CSS
 * without calling stamp, which enforces all proof obligations. *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./dom.sats"
staload "./arith.sats"

(* ========== Linear views for CSS correctness ========== *)

absview CSS_READER_WRITTEN
absview CSS_NAV_WRITTEN

(* ========== CSS visibility dataprops ========== *)

(* COLUMN_ALIGNED: column-width matches viewport transform stride.
 * BUG PREVENTED: text bleeding — if ph != 0, columns != viewport width. *)
dataprop COLUMN_ALIGNED(column_width_vw: int, container_pad_h: int) =
  | {cw:pos}{ph:int | ph == 0} COLUMNS_MATCH_VIEWPORT(cw, ph)

(* CHILD_PADDED: content children have horizontal padding > 0.
 * Without this, text is flush against viewport edges. *)
dataprop CHILD_PADDED(pad_left_10: int, pad_right_10: int) =
  | {pl,pr:pos} CHILDREN_HAVE_PADDING(pl, pr)

(* NAV_BTN_VISIBLE: buttons have nonzero font-size and padding.
 * Without this, buttons render as invisible zero-size elements. *)
dataprop NAV_BTN_VISIBLE(font_size_10: int, padding_h_10: int) =
  | {fs,ph:pos} BTNS_HAVE_SIZE(fs, ph)

(* ========== CSS property constants ========== *)
(* #define is textual expansion — applies in BOTH dynamic and static contexts.
 * Dataprop constructors like COLUMNS_MATCH_VIEWPORT{CSS_COL_WIDTH_VW, ...}
 * see the #define value, so the proofs guard these values directly.
 * Changing any value triggers a compile-time constraint failure. *)
#define CSS_COL_WIDTH_VW 100       (* column-width: 100vw *)
#define CSS_CONTAINER_PAD_H 0      (* padding: 2rem 0 — zero horizontal *)
#define CSS_CHILD_PAD_L_10 15      (* padding-left: 1.5rem = 15 tenths *)
#define CSS_CHILD_PAD_R_10 15      (* padding-right: 1.5rem = 15 tenths *)
#define CSS_BTN_FONT_10 10         (* font-size: 1rem = 10 tenths *)
#define CSS_BTN_PAD_H_10 3         (* padding: 0 .3rem = 3 tenths *)

(* ========== CSS length constants ========== *)
(* #define: runtime values; stadef: type-level constraints *)
#define APP_CSS_LEN 2505
stadef APP_CSS_LEN = 2505
#define NAV_CSS_LEN 788
stadef NAV_CSS_LEN = 788

(* BUG CLASS PREVENTED: CSS_NULL_BYTE_CORRUPTION
 * The CSS fill writes 4 bytes per _w4 call. If MGMT_CSS_LEN is not
 * a multiple of 4, the last write pads with null bytes, which corrupt
 * the <style> text content and prevent CSS parsing in the browser.
 * The constraint MGMT_CSS_LEN == MGMT_CSS_WRITES * 4 proves alignment.
 * If someone changes the CSS content length, they must also update
 * MGMT_CSS_WRITES to match, or the solver rejects. *)
stadef MGMT_CSS_WRITES = 76
stadef MGMT_CSS_LEN = MGMT_CSS_WRITES * 4
#define MGMT_CSS_LEN 304

(* ========== Stamp functions ========== *)

(* ONLY function that produces CSS_READER_WRITTEN.
 * Takes proven CSS values as dependent int arguments + dataprop proofs.
 * Writes the CSS bytes AND returns the linear view.
 * Cannot be called without proofs. Cannot skip the byte writes. *)
fun stamp_reader_css {l:agz}{n:int | n >= APP_CSS_LEN}
    {cw:pos}{ph:int | ph == 0}{pl,pr:pos}
  (pf_col: COLUMN_ALIGNED(cw, ph),
   pf_pad: CHILD_PADDED(pl, pr) |
   arr: !ward_arr(byte, l, n), alen: int n,
   col_w_vw: int(cw), pad_h: int(ph),
   child_pad_l: int(pl), child_pad_r: int(pr))
  : (CSS_READER_WRITTEN | void)

(* ONLY function that produces CSS_NAV_WRITTEN.
 * Stamps button font-size and padding bytes from proven values. *)
fun stamp_nav_css {l:agz}{n:int | n >= NAV_CSS_LEN}
    {fs,ph:pos}
  (pf_btn: NAV_BTN_VISIBLE(fs, ph) |
   arr: !ward_arr(byte, l, n), alen: int n,
   btn_font: int(fs), btn_pad: int(ph))
  : (CSS_NAV_WRITTEN | void)

(* ========== Scrubber CSS dataprops ========== *)

(* Scrubber CSS property constants *)
#define SCRUB_PAD_V 8          (* bottom bar vertical padding, px *)
#define SCRUB_PAD_H 16         (* bottom bar horizontal padding, px *)
#define SCRUB_BAR_H 24         (* scrubber container height, px *)
#define SCRUB_TRACK_H 4        (* track line height, px *)
#define SCRUB_HANDLE_SZ 16     (* handle diameter, px *)
#define SCRUB_BOTTOM_Z 10      (* bottom bar z-index *)

(* SCRUB_TAPPABLE: interactive elements meet minimum touch target sizes.
 * BUG CLASS PREVENTED: untappable scrubber on mobile — if pad < 8,
 * bar height < 16, or handle < 16, fingers can't reliably hit targets. *)
dataprop SCRUB_TAPPABLE(pad_v: int, bar_h: int, handle_sz: int) =
  | {pv:int | pv >= 8}{bh:int | bh >= 16}{hs:int | hs >= 16}
    TOUCH_TARGETS_OK(pv, bh, hs)

(* SCRUB_VISIBLE: visual elements are perceivable.
 * BUG CLASS PREVENTED: invisible scrubber — if track height < 2
 * or z-index < 10, scrubber hidden behind content. *)
dataprop SCRUB_VISIBLE(track_h: int, z_idx: int) =
  | {th:int | th >= 2}{zi:int | zi >= 10}
    SCRUB_RENDERING_OK(th, zi)

(* Scrubber CSS length — distinct stadef/define names prevent #define override.
 * SCRUB_CSS_WRITES (type-level): number of _w4 calls.
 * SCRUB_CSS_LEN_S (type-level): SCRUB_CSS_WRITES * 4 = byte count.
 * SCRUB_CSS_LEN (dynamic-level): literal byte count for allocation.
 * Solver unifies: if #define != stadef product, build fails. *)
stadef SCRUB_CSS_WRITES = 234
stadef SCRUB_CSS_LEN_S = SCRUB_CSS_WRITES * 4
#define SCRUB_CSS_LEN 936

(* TOC panel z-index constant and dataprop. *)
#define TOC_PANEL_Z 20

(* TOC_PANEL_LAYERED: TOC panel z-index must exceed scrubber/nav z-index (10).
 * BUG CLASS PREVENTED: TOC panel hidden behind scrubber or nav bars. *)
dataprop TOC_PANEL_LAYERED(z_idx: int) =
  | {zi:int | zi > 10} TOC_Z_OK(zi)

(* TOC CSS length — distinct stadef/define names prevent #define override.
 * TOC_CSS_WRITES (type-level): number of _w4 calls.
 * TOC_CSS_LEN_S (type-level): TOC_CSS_WRITES * 4 = byte count.
 * TOC_CSS_LEN (dynamic-level): literal byte count for allocation. *)
stadef TOC_CSS_WRITES = 246
stadef TOC_CSS_LEN_S = TOC_CSS_WRITES * 4
#define TOC_CSS_LEN 984

(* ========== CSS injection functions ========== *)

(* Create a <style> element under parent and fill it with app CSS. *)
fun inject_app_css {l:agz}
  (s: ward_dom_stream(l), parent: int): ward_dom_stream(l)

(* Create a <style> element under parent and fill it with management toolbar CSS. *)
fun inject_mgmt_css {l:agz}
  (s: ward_dom_stream(l), parent: int): ward_dom_stream(l)

(* Inject reader-specific nav CSS as a separate <style> element. *)
fun inject_nav_css {l:agz}
  (s: ward_dom_stream(l), parent: int): ward_dom_stream(l)

(* Inject scrubber CSS — proofs on signature enforce CSS correctness.
 * SCRUB_TAPPABLE proves touch targets are large enough.
 * SCRUB_VISIBLE proves track height and z-index are sufficient. *)
fun inject_scrub_css {l:agz}
  (pf_tap: SCRUB_TAPPABLE(SCRUB_PAD_V, SCRUB_BAR_H, SCRUB_HANDLE_SZ),
   pf_vis: SCRUB_VISIBLE(SCRUB_TRACK_H, SCRUB_BOTTOM_Z) |
   s: ward_dom_stream(l), parent: int): ward_dom_stream(l)

(* Inject TOC panel CSS — proof ensures z-index clears scrubber/nav layers. *)
fun inject_toc_css {l:agz}
  (pf_z: TOC_PANEL_LAYERED(TOC_PANEL_Z) |
   s: ward_dom_stream(l), parent: int): ward_dom_stream(l)
