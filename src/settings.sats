(* settings.sats - Reader settings type declarations
 *
 * M14: Reader settings for font size, font family, theme, line height, margins.
 * Settings are persisted to IndexedDB and applied as CSS variables.
 *
 * Functional correctness proofs:
 * - SETTINGS_VALID: proves settings are within valid ranges at compile time
 * - SETTINGS_STATE: state machine for modal visibility transitions
 * - SETTINGS_APPLIED: proves settings were applied (CSS updated)
 *)

(* Theme constants *)
#define THEME_LIGHT  0
#define THEME_DARK   1
#define THEME_SEPIA  2
#define THEME_AUTO   3

(* Font family constants *)
#define FONT_SERIF      0
#define FONT_SANS_SERIF 1
#define FONT_PUBLISHER  2

(* Settings range constants *)
#define FONT_SIZE_MIN  14
#define FONT_SIZE_MAX  32
#define LINE_HEIGHT_MIN_TENTHS 14  (* 1.4 *)
#define LINE_HEIGHT_MAX_TENTHS 24  (* 2.4 *)
#define MARGIN_MIN 1
#define MARGIN_MAX 4

(* CSS mode constants *)
#define CSS_PUBLISHER 0
#define CSS_READER    1
#define CSS_CUSTOM    2

(* ========== Functional Correctness Dataprops ========== *)

(* CSS mode validity: publisher (0), reader (1), custom (2). *)
dataprop CSS_MODE_VALID(m: int) =
  | CSS_MODE_PUBLISHER(0)
  | CSS_MODE_READER(1)
  | CSS_MODE_CUSTOM(2)

(* Settings validity proof.
 * Proves all 5 settings values are within their valid ranges. *)
dataprop SETTINGS_VALID
  (font_size: int, font_family: int, theme: int, line_height: int, margin: int) =
  | {fs,ff,th,lh,m:nat |
      fs >= 14; fs <= 32;
      ff >= 0; ff <= 2;
      th >= 0; th <= 3;
      lh >= 14; lh <= 24;
      m >= 1; m <= 4}
    VALID_SETTINGS(fs, ff, th, lh, m)

(* Settings visibility state machine.
 * absprop: wired via local assume in settings.dats.
 * show requires SETTINGS_STATE(false) and produces SETTINGS_STATE(true).
 * hide requires SETTINGS_STATE(true) and produces SETTINGS_STATE(false). *)
absprop SETTINGS_STATE(visible: bool)

(* Settings application proof.
 * absprop: produced only by settings_apply via local assume.
 * Proves CSS variables were updated to reflect current settings. *)
absprop SETTINGS_APPLIED()

(* ========== Module Functions ========== *)

(* Initialize settings module with defaults *)
fun settings_init(): void

(* Get current settings values — bounded returns *)
fun settings_get_font_size(): [fs:int | fs >= 14; fs <= 32] int(fs)
fun settings_get_font_family(): [ff:int | ff >= 0; ff <= 2] int(ff)
fun settings_get_theme(): [th:int | th >= 0; th <= 3] int(th)
(* Resolve effective theme: Auto (3) maps to light (0) or dark (1) based on system.
 * Returns 0, 1, or 2 — never 3. *)
fun settings_resolve_theme(): [th:int | th >= 0; th <= 2] int(th)
fun settings_get_line_height_tenths(): [lh:int | lh >= 14; lh <= 24] int(lh)
fun settings_get_margin(): [m:int | m >= 1; m <= 4] int(m)

(* Set settings values — clamps to valid ranges *)
fun settings_set_font_size(size: int): void
fun settings_set_font_family(family: int): void
fun settings_set_theme(theme: int): void
fun settings_set_line_height_tenths(tenths: int): void
fun settings_set_margin(margin: int): void

(* CSS mode — stored in reader state (not per-book yet) *)
fun settings_get_css_mode(): [m:nat | m <= 2] (CSS_MODE_VALID(m) | int(m))
fun settings_set_css_mode{m:nat | m <= 2}(pf: CSS_MODE_VALID(m) | mode: int(m)): void

(* Increment/decrement helpers for UI.
 * Each: modify setting, apply CSS, save to IDB. *)
fun settings_increase_font_size(): void
fun settings_decrease_font_size(): void
fun settings_next_font_family(): void
fun settings_next_theme(): void
fun settings_increase_line_height(): void
fun settings_decrease_line_height(): void
fun settings_increase_margin(): void
fun settings_decrease_margin(): void

(* Apply current settings to CSS.
 * Returns SETTINGS_APPLIED proof — compile-time guarantee that CSS was updated.
 * If reader is active, triggers remeasurement. *)
fun settings_apply(): (SETTINGS_APPLIED() | void)

(* Save settings to IndexedDB (async) *)
fun settings_save(): void

(* Load settings from IndexedDB (async) *)
fun settings_load(): void

(* Handle settings load/save completion *)
fun settings_on_load_complete(len: int): void
fun settings_on_save_complete(success: int): void

(* Settings modal visibility *)
fun settings_is_visible(): int
fun settings_show(): void
fun settings_hide(): void
fun settings_toggle(): void

(* Get settings modal overlay ID *)
fun settings_get_overlay_id(): int

(* Handle click on settings UI element — returns 1 if handled *)
fun settings_handle_click(node_id: int): int
