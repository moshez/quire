(* import_ui.sats — Import progress UI declarations *)

staload "./../vendor/ward/lib/memory.sats"
staload "./../vendor/ward/lib/dom.sats"
staload "./quire_text.sats"

(* ========== Import progress proofs ========== *)

(* PROGRESS_PHASE — lock phase <-> bar width <-> text ID.
 * BUG PREVENTED: Showing "Adding to library" while bar is at 10%.
 * Four indices — phase, bar percentage, text ID, AND text length. *)
dataprop PROGRESS_PHASE(phase: int, bar_pct: int, text_id: int, text_len: int) =
  | PHASE_FILE_OPEN(0, 10, 5, 12)
  | PHASE_ZIP_PARSE(1, 30, 6, 15)
  | PHASE_READ_META(2, 60, 7, 16)
  | PHASE_ADD_BOOK(3, 90, 8, 17)

(* Import display phase ordering: proves each phase follows the previous.
 * BUG PREVENTED: Copy-paste reordering of import phases would break
 * the proof chain — each phase requires the previous phase's proof.
 * Replaces IMPORT_PHASE — unifies import logic and display ordering. *)
dataprop IMPORT_DISPLAY_PHASE(phase: int) =
  | IDP_OPEN(0)
  | {p:int | p == 0} IDP_ZIP(1) of IMPORT_DISPLAY_PHASE(p)
  | {p:int | p == 1} IDP_META(2) of IMPORT_DISPLAY_PHASE(p)
  | {p:int | p == 2} IDP_ADD(3) of IMPORT_DISPLAY_PHASE(p)

(* PROGRESS_TERMINAL — card removal requires terminal state.
 * BUG PREVENTED: removing the card before import finishes. *)
dataprop PROGRESS_TERMINAL() =
  | PTERMINAL_OK() of IMPORT_DISPLAY_PHASE(3)
  | {ph:nat | ph <= 3} PTERMINAL_ERR() of IMPORT_DISPLAY_PHASE(ph)

(* ========== Linear import outcome ========== *)

(* import_handled is LINEAR — must be consumed exactly once.
 * Only import_mark_success and import_mark_failed can create it.
 * import_complete consumes it and logs "import-done".
 * If any if-then-else branch forgets a token, ATS2 rejects. *)
absvt@ype import_handled = int

fun import_mark_success(): import_handled
fun import_mark_failed {n:pos}
  (msg: ward_safe_text(n), len: int n): import_handled
fun import_complete(h: import_handled): void

(* ========== CSS class builders ========== *)

fun cls_import_card(): ward_safe_text(11)
fun cls_import_bar(): ward_safe_text(10)
fun cls_import_fill(): ward_safe_text(11)

(* ========== Import progress card functions ========== *)

fun render_import_card(list_id: int, root: int)
  : [c,b,t:pos] (IMPORT_DISPLAY_PHASE(0) | int(c), int(b), int(t))

fun update_import_bar
  {ph:nat}{pct:nat | pct >= 10; pct <= 99}{tid:nat}{tl:nat}
  (pf: !PROGRESS_PHASE(ph, pct, tid, tl) |
   bar_id: int, bar_pct: int(pct)): void

fun remove_import_card
  {c:pos}
  (pf_term: PROGRESS_TERMINAL() | card_id: int(c)): void

fun import_finish(h: import_handled, label_id: int, span_id: int, status_id: int): void

fun import_finish_with_card
  {c:pos}
  (pf_term: PROGRESS_TERMINAL() |
   h: import_handled, card_id: int(c), label_id: int, span_id: int, status_id: int): void

(* ========== Import progress DOM update helpers ========== *)

fun update_status_text {tid:nat}{tl:pos | tl < 65536}
  (pf: VALID_TEXT(tid, tl) | nid: int, text_id: int(tid), text_len: int(tl)): void

fun update_import_label_class(label_id: int, importing: int): void
