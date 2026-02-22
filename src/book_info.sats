(* book_info.sats — Book info overlay declarations *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./dom.sats"
staload "./arith.sats"
staload "./library.sats"

(* ========== Book info listener IDs ========== *)

#define LISTENER_INFO_BACK 24
#define LISTENER_INFO_DISMISS 25
#define LISTENER_INFO_HIDE 26
#define LISTENER_INFO_ARCHIVE 27
#define LISTENER_INFO_DELETE 28

(* ========== Size display proof ========== *)

dataprop SIZE_UNIT(size: int, unit: int) =
  | {s:nat | s >= 1048576} SIZE_IS_MB(s, 1)
  | {s:nat | s < 1048576} SIZE_IS_KB(s, 0)

(* ========== Month days proof ========== *)

(* MONTH_DAYS: days in each month.
 * Feb has two variants for leap/non-leap years.
 * Used by next_day to prove each branch is correct. *)
dataprop MONTH_DAYS(m: int, d: int) =
  | MD_JAN(1, 31)  | MD_FEB28(2, 28) | MD_FEB29(2, 29)
  | MD_MAR(3, 31)  | MD_APR(4, 30)   | MD_MAY(5, 31)
  | MD_JUN(6, 30)  | MD_JUL(7, 31)   | MD_AUG(8, 31)
  | MD_SEP(9, 30)  | MD_OCT(10, 31)  | MD_NOV(11, 30)
  | MD_DEC(12, 31)

(* ========== Render proof chain ========== *)

(* Render proof chain -- each step produces a token.
 * show_book_info must collect all tokens; missing one -> compile error. *)
dataprop INFO_HEADER_DONE() = | HEADER_RENDERED()
dataprop INFO_COVER_DONE() = | COVER_RENDERED()
dataprop INFO_TITLE_DONE() = | TITLE_RENDERED()
dataprop INFO_AUTHOR_DONE() = | AUTHOR_RENDERED()
dataprop INFO_META_DONE() = | META_RENDERED()
dataprop INFO_ACTIONS_DONE() = | ACTIONS_RENDERED()

(* Metadata row proofs -- _render_info_meta collects all 4 *)
dataprop ROW_PROGRESS_DONE() = | PROGRESS_ROW_DONE()
dataprop ROW_ADDED_DONE() = | ADDED_ROW_DONE()
dataprop ROW_LASTREAD_DONE() = | LASTREAD_ROW_DONE()
dataprop ROW_SIZE_DONE() = | SIZE_ROW_DONE()

(* ========== CSS class builders ========== *)

fun cls_info_overlay(): ward_safe_text(12)
fun cls_info_header(): ward_safe_text(11)
fun cls_info_back(): ward_safe_text(9)
fun cls_info_cover(): ward_safe_text(10)
fun cls_info_title(): ward_safe_text(10)
fun cls_info_author(): ward_safe_text(11)
fun cls_info_meta(): ward_safe_text(9)
fun cls_info_row(): ward_safe_text(8)
fun cls_info_row_label(): ward_safe_text(14)
fun cls_info_row_value(): ward_safe_text(14)
fun cls_info_actions(): ward_safe_text(12)
fun cls_info_btn(): ward_safe_text(8)
fun cls_info_btn_danger(): ward_safe_text(15)
