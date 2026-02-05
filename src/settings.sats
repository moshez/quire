(* settings.sats - Reader settings type declarations
 *
 * M14: Reader settings for font size, font family, theme, line height, margins.
 * Settings are persisted to IndexedDB and applied as CSS variables.
 *
 * Functional correctness proofs:
 * - SETTINGS_VALID: proves settings are within valid ranges
 * - Settings changes trigger re-measurement to ensure correct pagination
 *)

(* Theme constants *)
#define THEME_LIGHT  0
#define THEME_DARK   1
#define THEME_SEPIA  2

(* Font family constants *)
#define FONT_SERIF      0
#define FONT_SANS_SERIF 1
#define FONT_MONOSPACE  2

(* Settings range constants *)
#define FONT_SIZE_MIN  14
#define FONT_SIZE_MAX  32
#define LINE_HEIGHT_MIN_TENTHS 14  (* 1.4 *)
#define LINE_HEIGHT_MAX_TENTHS 24  (* 2.4 *)
#define MARGIN_MIN 1
#define MARGIN_MAX 4

(* ========== Functional Correctness Dataprops ========== *)

(* Settings validity proof.
 * SETTINGS_VALID(font_size, font_family, theme, line_height, margin) proves:
 * - FONT_SIZE_MIN <= font_size <= FONT_SIZE_MAX
 * - 0 <= font_family <= 2
 * - 0 <= theme <= 2
 * - LINE_HEIGHT_MIN <= line_height <= LINE_HEIGHT_MAX
 * - MARGIN_MIN <= margin <= MARGIN_MAX
 *)
dataprop SETTINGS_VALID
  (font_size: int, font_family: int, theme: int, line_height: int, margin: int) =
  | {fs,ff,th,lh,m:nat |
      fs >= 14; fs <= 32;
      ff >= 0; ff <= 2;
      th >= 0; th <= 2;
      lh >= 14; lh <= 24;
      m >= 1; m <= 4}
    VALID_SETTINGS(fs, ff, th, lh, m)

(* ========== Module Functions ========== *)

(* Initialize settings module with defaults *)
fun settings_init(): void = "mac#"

(* Get current settings values *)
fun settings_get_font_size(): int = "mac#"
fun settings_get_font_family(): int = "mac#"
fun settings_get_theme(): int = "mac#"
fun settings_get_line_height_tenths(): int = "mac#"
fun settings_get_margin(): int = "mac#"

(* Set settings values - clamps to valid ranges *)
fun settings_set_font_size(size: int): void = "mac#"
fun settings_set_font_family(family: int): void = "mac#"
fun settings_set_theme(theme: int): void = "mac#"
fun settings_set_line_height_tenths(tenths: int): void = "mac#"
fun settings_set_margin(margin: int): void = "mac#"

(* Increment/decrement helpers for UI *)
fun settings_increase_font_size(): void = "mac#"
fun settings_decrease_font_size(): void = "mac#"
fun settings_next_font_family(): void = "mac#"
fun settings_next_theme(): void = "mac#"
fun settings_increase_line_height(): void = "mac#"
fun settings_decrease_line_height(): void = "mac#"
fun settings_increase_margin(): void = "mac#"
fun settings_decrease_margin(): void = "mac#"

(* Apply current settings to CSS - rebuilds CSS with new values *)
fun settings_apply(): void = "mac#"

(* Build CSS variable string for current settings into fetch buffer
 * Returns length of CSS string *)
fun settings_build_css_vars(buf_offset: int): int = "mac#"

(* Save settings to IndexedDB (async - callback via on_kv_complete) *)
fun settings_save(): void = "mac#"

(* Load settings from IndexedDB (async - callback via settings_on_load_complete) *)
fun settings_load(): void = "mac#"

(* Handle settings load completion *)
fun settings_on_load_complete(len: int): void = "mac#"

(* Handle settings save completion *)
fun settings_on_save_complete(success: int): void = "mac#"

(* Check if settings modal is visible *)
fun settings_is_visible(): int = "mac#"

(* Show settings modal *)
fun settings_show(): void = "mac#"

(* Hide settings modal *)
fun settings_hide(): void = "mac#"

(* Toggle settings modal *)
fun settings_toggle(): void = "mac#"

(* Get settings modal overlay ID *)
fun settings_get_overlay_id(): int = "mac#"

(* Handle click on settings UI element
 * Returns 1 if click was handled, 0 if not a settings element *)
fun settings_handle_click(node_id: int): int = "mac#"
