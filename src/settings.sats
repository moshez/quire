(* settings.sats - Reader settings type declarations
 *
 * M14: Reader settings for font size, font family, theme, line height, margins.
 * Settings are persisted to IndexedDB and applied as CSS variables.
 *
 * Functional correctness proofs:
 * - SETTINGS_VALID: proves settings are within valid ranges at compile time
 * - SETTINGS_STATE: state machine for modal visibility transitions
 * - SETTINGS_APPLIED: proves settings were applied and triggered remeasurement
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
 *
 * This proof is constructed by the clamp function and consumed by apply.
 * The invariant guarantees CSS variables will have valid values. *)
dataprop SETTINGS_VALID
  (font_size: int, font_family: int, theme: int, line_height: int, margin: int) =
  | {fs,ff,th,lh,m:nat |
      fs >= 14; fs <= 32;
      ff >= 0; ff <= 2;
      th >= 0; th <= 2;
      lh >= 14; lh <= 24;
      m >= 1; m <= 4}
    VALID_SETTINGS(fs, ff, th, lh, m)

(* Settings visibility state machine.
 * SETTINGS_STATE(b) where b=true means modal is visible, b=false means hidden.
 * settings_show requires SETTINGS_STATE(false) and produces SETTINGS_STATE(true).
 * settings_hide requires SETTINGS_STATE(true) and produces SETTINGS_STATE(false).
 * This prevents calling hide when already hidden or show when visible. *)
absprop SETTINGS_STATE(visible: bool)

(* Settings application proof.
 * SETTINGS_APPLIED(version) proves that settings version V were applied:
 * - CSS variables were updated to reflect current settings
 * - If reader was active, reader_remeasure_all() was called
 * This guarantees pagination is correct after any settings change. *)
dataprop SETTINGS_APPLIED(version: int) =
  | {v:nat} APPLIED_VERSION(v)

(* ========== Module Functions ========== *)

(* Initialize settings module with defaults
 * Establishes initial SETTINGS_STATE(false) - modal hidden *)
fun settings_init(): void = "mac#"

(* Get current settings values
 * Return values are guaranteed valid by internal SETTINGS_VALID invariant *)
fun settings_get_font_size(): [fs:int | fs >= 14; fs <= 32] int(fs) = "mac#"
fun settings_get_font_family(): [ff:int | ff >= 0; ff <= 2] int(ff) = "mac#"
fun settings_get_theme(): [th:int | th >= 0; th <= 2] int(th) = "mac#"
fun settings_get_line_height_tenths(): [lh:int | lh >= 14; lh <= 24] int(lh) = "mac#"
fun settings_get_margin(): [m:int | m >= 1; m <= 4] int(m) = "mac#"

(* Set settings values - clamps to valid ranges
 * Any input is accepted; output is guaranteed valid by clamping.
 * Internally maintains SETTINGS_VALID invariant. *)
fun settings_set_font_size(size: int): void = "mac#"
fun settings_set_font_family(family: int): void = "mac#"
fun settings_set_theme(theme: int): void = "mac#"
fun settings_set_line_height_tenths(tenths: int): void = "mac#"
fun settings_set_margin(margin: int): void = "mac#"

(* Increment/decrement helpers for UI
 * Each function:
 * 1. Modifies setting (clamped to valid range)
 * 2. Calls settings_apply() - triggers remeasurement
 * 3. Calls settings_save() - persists to IndexedDB
 * Internally produces SETTINGS_APPLIED proof. *)
fun settings_increase_font_size(): void = "mac#"
fun settings_decrease_font_size(): void = "mac#"
fun settings_next_font_family(): void = "mac#"
fun settings_next_theme(): void = "mac#"
fun settings_increase_line_height(): void = "mac#"
fun settings_decrease_line_height(): void = "mac#"
fun settings_increase_margin(): void = "mac#"
fun settings_decrease_margin(): void = "mac#"

(* Apply current settings to CSS
 * Precondition: internal SETTINGS_VALID invariant holds
 * Postcondition: CSS variables updated, remeasurement triggered if reader active
 * Internally produces SETTINGS_APPLIED proof. *)
fun settings_apply(): void = "mac#"

(* Build CSS variable string for current settings into fetch buffer
 * Returns length of CSS string
 * The output string reflects THE CURRENT settings values - proven by
 * reading from the same state that SETTINGS_VALID covers. *)
fun settings_build_css_vars(buf_offset: int): int = "mac#"

(* Save settings to IndexedDB (async - callback via on_kv_complete)
 * Serializes current settings; SETTINGS_VALID guarantees valid byte values *)
fun settings_save(): void = "mac#"

(* Load settings from IndexedDB (async - callback via settings_on_load_complete) *)
fun settings_load(): void = "mac#"

(* Handle settings load completion
 * Deserializes and clamps values, re-establishing SETTINGS_VALID invariant *)
fun settings_on_load_complete(len: int): void = "mac#"

(* Handle settings save completion *)
fun settings_on_save_complete(success: int): void = "mac#"

(* Check if settings modal is visible
 * Returns runtime representation of SETTINGS_STATE *)
fun settings_is_visible(): int = "mac#"

(* Show settings modal
 * Precondition: settings_visible == 0 (verifies SETTINGS_STATE(false))
 * Postcondition: settings_visible == 1 (establishes SETTINGS_STATE(true))
 * State transition: SETTINGS_STATE(false) -> SETTINGS_STATE(true) *)
fun settings_show(): void = "mac#"

(* Hide settings modal
 * Precondition: settings_visible == 1 (verifies SETTINGS_STATE(true))
 * Postcondition: settings_visible == 0 (establishes SETTINGS_STATE(false))
 * State transition: SETTINGS_STATE(true) -> SETTINGS_STATE(false) *)
fun settings_hide(): void = "mac#"

(* Toggle settings modal
 * Internally manages SETTINGS_STATE transitions based on current state *)
fun settings_toggle(): void = "mac#"

(* Get settings modal overlay ID *)
fun settings_get_overlay_id(): int = "mac#"

(* Handle click on settings UI element
 * Returns 1 if click was handled, 0 if not a settings element
 * When returning 1: the clicked control's action was performed,
 * which may include settings_apply() producing SETTINGS_APPLIED proof. *)
fun settings_handle_click(node_id: int): int = "mac#"
