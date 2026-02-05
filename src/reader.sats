(* reader.sats - Three-chapter sliding window type declarations
 *
 * M12: Type-safe state machine for chapter navigation.
 * Maintains prev/curr/next chapter slots for seamless page turns.
 *)

(* Slot status constants *)
#define SLOT_EMPTY    0
#define SLOT_LOADING  1
#define SLOT_READY    2

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

(* Get current page within chapter *)
fun reader_get_current_page(): int = "mac#"

(* Get total pages in current chapter *)
fun reader_get_total_pages(): int = "mac#"

(* Get total chapter count *)
fun reader_get_chapter_count(): int = "mac#"

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

(* M13: Navigation UI functions *)

(* Go to specific chapter *)
fun reader_go_to_chapter(chapter_index: int): void = "mac#"

(* Show Table of Contents overlay *)
fun reader_show_toc(): void = "mac#"

(* Hide Table of Contents overlay *)
fun reader_hide_toc(): void = "mac#"

(* Check if TOC is visible *)
fun reader_is_toc_visible(): int = "mac#"

(* Toggle TOC visibility *)
fun reader_toggle_toc(): void = "mac#"

(* Get TOC overlay ID (for click handling) *)
fun reader_get_toc_id(): int = "mac#"

(* Get progress bar ID *)
fun reader_get_progress_bar_id(): int = "mac#"

(* Look up TOC index from node ID, returns -1 if not found *)
fun reader_get_toc_index_for_node(node_id: int): int = "mac#"

(* Handle TOC entry click by node ID *)
fun reader_on_toc_click(node_id: int): void = "mac#"
