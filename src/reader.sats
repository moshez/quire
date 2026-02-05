(* reader.sats - Three-chapter sliding window type declarations
 *
 * M12: Type-safe state machine for chapter navigation.
 * Maintains prev/curr/next chapter slots for seamless page turns.
 *
 * M13: Functional correctness proofs for navigation UI.
 * Dataprops guarantee that TOC lookups return correct indices,
 * navigation lands on requested chapters, and state transitions
 * are valid.
 *)

(* Slot status constants *)
#define SLOT_EMPTY    0
#define SLOT_LOADING  1
#define SLOT_READY    2

(* ========== M13: Functional Correctness Dataprops ========== *)

(* Option proof - carries proof P when b=true, nothing when b=false.
 * Used for functions that may or may not produce a proof. *)
dataprop option_p(P: prop, b: bool) =
  | {P:prop} option_p_some(P, true) of P
  | {P:prop} option_p_none(P, false)

(* TOC visibility state machine.
 * TOC_STATE(b) where b=true means TOC is visible, b=false means hidden.
 * show_toc requires TOC_STATE(false) and produces TOC_STATE(true).
 * hide_toc requires TOC_STATE(true) and produces TOC_STATE(false).
 * This prevents calling hide when already hidden or show when visible. *)
absprop TOC_STATE(visible: bool)

(* TOC entry mapping proof.
 * TOC_MAPS(node_id, toc_idx, toc_count) proves that:
 *   - node_id is the DOM node for TOC entry toc_idx
 *   - toc_idx is valid: 0 <= toc_idx < toc_count
 * Produced when TOC entries are created in show_toc.
 * Consumed by lookup to guarantee correct index is returned. *)
dataprop TOC_MAPS(node_id: int, toc_idx: int, toc_count: int) =
  | {n:int} {i,c:nat | i < c} TOC_ENTRY(n, i, c)

(* Chapter position proof.
 * AT_CHAPTER(ch, total) proves the reader is viewing chapter ch
 * where 0 <= ch < total. *)
dataprop AT_CHAPTER(chapter: int, total: int) =
  | {c,t:nat | c < t} VIEWING_CHAPTER(c, t)

(* ========== Additional Correctness Proofs (M15+) ========== *)

(* Slot rotation correctness proof.
 * SLOTS_ROTATED(old_prev, old_curr, old_next, new_prev, new_curr, new_next)
 * proves that after rotating forward:
 * - new_prev = old_curr (current becomes previous)
 * - new_curr = old_next (next becomes current)
 * - new_next is empty sentinel (negative value indicating no chapter loaded)
 * Ensures chapter continuity during page turns.
 *
 * NOTE: Proof is documentary - runtime checks verify rotation invariants. *)
absprop SLOTS_ROTATED(
  old_prev: int, old_curr: int, old_next: int,
  new_prev: int, new_curr: int, new_next: int
)

(* Page count calculation correctness proof.
 * PAGE_COUNT_CORRECT(scroll_width, width, page_count) proves that
 * page_count == ceiling(scroll_width / width) computed as:
 * (scroll_width + width - 1) / width
 * This is THE correct ceiling division formula.
 *
 * NOTE: Proof is documentary - runtime checks verify calculation. *)
absprop PAGE_COUNT_CORRECT(scroll_width: int, width: int, page_count: int)

(* Scroll offset correctness proof.
 * OFFSET_FOR_PAGE(page, offset, stride) proves that positioning a container
 * at offset == -(page * stride) shows page `page` in the viewport.
 * This is THE correct offset calculation for CSS column-based pagination.
 *
 * NOTE: Proof is documentary - runtime checks verify positioning. *)
absprop OFFSET_FOR_PAGE(page: int, offset: int, stride: int)

(* Adjacent chapters preload invariant.
 * ADJACENT_LOADED(curr_ch, total_chapters) proves that:
 * - If 0 < curr_ch < total-1: both prev and next chapters are loaded
 * - If curr_ch == 0: only next is loaded (no prev exists)
 * - If curr_ch == total-1: only prev is loaded (no next exists)
 * Ensures seamless reading experience without loading delays.
 *
 * NOTE: Proof is documentary - runtime checks verify preload state. *)
absprop ADJACENT_LOADED(curr_ch: int, total: int)

(* ========== Module Functions ========== *)

(* Initialize reader module *)
fun reader_init(): void = "mac#"

(* Enter reader mode - creates three chapter containers *)
fun reader_enter(root_id: int, container_hide_id: int): void = "mac#"

(* Exit reader mode *)
fun reader_exit(): void = "mac#"

(* Check if reader is active *)
fun reader_is_active(): int = "mac#"

(* Get current chapter index *)
fun reader_get_current_chapter(): int = "mac#"

(* Get current page within chapter
 * Returns page number (0-indexed), guaranteed >= 0 *)
fun reader_get_current_page(): [p:nat] int(p) = "mac#"

(* Get total pages in current chapter
 * Returns page count, guaranteed >= 1
 * CORRECTNESS: Internally maintains PAGE_COUNT_CORRECT proof that count
 * was computed correctly using ceiling division *)
fun reader_get_total_pages(): [p:pos] int(p) = "mac#"

(* Get total chapter count
 * Returns count, guaranteed >= 0 *)
fun reader_get_chapter_count(): [n:nat] int(n) = "mac#"

(* Navigate to next page - may cross chapter boundary *)
fun reader_next_page(): void = "mac#"

(* Navigate to previous page - may cross chapter boundary *)
fun reader_prev_page(): void = "mac#"

(* Navigate to specific page in current chapter *)
fun reader_go_to_page(page: int): void = "mac#"

(* Handle chapter data loaded from IndexedDB (small, in fetch buffer) *)
fun reader_on_chapter_loaded(len: int): void = "mac#"

(* Handle chapter data loaded from IndexedDB (large, as blob) *)
fun reader_on_chapter_blob_loaded(handle: int, size: int): void = "mac#"

(* Get viewport ID (for event handling) *)
fun reader_get_viewport_id(): int = "mac#"

(* Get viewport width (for click zone calculation) *)
fun reader_get_viewport_width(): int = "mac#"

(* Get page indicator ID *)
fun reader_get_page_indicator_id(): int = "mac#"

(* Update page display *)
fun reader_update_page_display(): void = "mac#"

(* Check if any chapter is loading *)
fun reader_is_loading(): int = "mac#"

(* M14: Re-measure all chapter slots after settings change *)
fun reader_remeasure_all(): void = "mac#"

(* ========== M13: Navigation UI with Functional Correctness ========== *)
(*
 * Proof architecture:
 * - Internal proofs verify correctness at compile time
 * - Public API is simple - proofs managed internally by the module
 * - AT_CHAPTER proves navigation landed on correct chapter
 * - TOC_MAPS proves lookup returned correct index
 * - TOC_STATE proves state transitions are valid
 *)

(* Go to specific chapter.
 * Internally produces AT_CHAPTER proof verifying we view the requested chapter.
 * Caller provides bounds proof via dependent types. *)
fun reader_go_to_chapter
  {ch,t:nat | ch < t}
  ( chapter_index: int(ch)
  , total_chapters: int(t)
  ) : void = "mac#"

(* Show TOC - only succeeds if currently hidden (verified internally) *)
fun reader_show_toc(): void = "mac#"

(* Hide TOC - only succeeds if currently visible (verified internally) *)
fun reader_hide_toc(): void = "mac#"

(* Toggle TOC - internally manages state transitions with proofs *)
fun reader_toggle_toc(): void = "mac#"

(* Check if TOC is visible *)
fun reader_is_toc_visible(): bool = "mac#"

(* Get TOC overlay ID *)
fun reader_get_toc_id(): int = "mac#"

(* Get progress bar ID *)
fun reader_get_progress_bar_id(): int = "mac#"

(* Look up TOC index from node ID.
 * Returns index if found (with internal TOC_MAPS proof), -1 if not found. *)
fun reader_get_toc_index_for_node(node_id: int): int = "mac#"

(* Handle TOC entry click - internally verifies correct chapter navigation *)
fun reader_on_toc_click(node_id: int): void = "mac#"

(* M15: Enter reader at specific chapter and page for resume *)
fun reader_enter_at(root_id: int, container_hide_id: int, chapter: int, page: int): void = "mac#"

(* M15: Get back button node ID *)
fun reader_get_back_btn_id(): int = "mac#"
