(* reader.sats - Three-chapter sliding window state machine
 *
 * M12: Implements the sliding window model from quire-design.md section 4.3.
 * Three chapter containers are maintained in the DOM:
 *   - prev: previous chapter (empty at first chapter)
 *   - curr: currently visible chapter
 *   - next: next chapter (empty at last chapter)
 *
 * Page turns within a chapter use SET_TRANSFORM.
 * Chapter boundary crossings rotate the containers.
 *)

(* Slot identifiers for the three chapter containers *)
#define SLOT_PREV 0
#define SLOT_CURR 1
#define SLOT_NEXT 2

(* Loading states for chapter slots *)
#define LOAD_EMPTY    0   (* No chapter assigned to slot *)
#define LOAD_PENDING  1   (* Chapter requested, waiting for data *)
#define LOAD_READY    2   (* Chapter loaded and measured *)

(* Initialize the reader module - call once at startup *)
fun reader_init(): void = "mac#"

(* Enter reader mode - creates viewport and three containers, loads initial chapters *)
fun reader_enter(total_chapters: int): void = "mac#"

(* Exit reader mode - cleans up containers *)
fun reader_exit(): void = "mac#"

(* Check if reader is active *)
fun reader_is_active(): int = "mac#"

(* Get current chapter index (0-based) *)
fun reader_get_chapter(): int = "mac#"

(* Get current page within chapter (0-based) *)
fun reader_get_page(): int = "mac#"

(* Get total pages in current chapter *)
fun reader_get_total_pages(): int = "mac#"

(* Navigate to next page (may cross chapter boundary) *)
fun reader_next_page(): void = "mac#"

(* Navigate to previous page (may cross chapter boundary) *)
fun reader_prev_page(): void = "mac#"

(* Navigate to specific page in current chapter *)
fun reader_go_to_page(page: int): void = "mac#"

(* Handle chapter data loaded from IndexedDB (small, in fetch buffer) *)
fun reader_on_chapter_loaded(slot: int, len: int): void = "mac#"

(* Handle chapter data loaded from IndexedDB (large, as blob) *)
fun reader_on_chapter_blob_loaded(slot: int, handle: int, size: int): void = "mac#"

(* Get slot that is currently being loaded (for routing callbacks) *)
fun reader_get_loading_slot(): int = "mac#"

(* Get viewport width for click zone handling *)
fun reader_get_viewport_width(): int = "mac#"

(* Update page indicator display *)
fun reader_update_display(): void = "mac#"

(* Request a chapter be loaded into a slot *)
fun reader_request_chapter(slot: int, chapter_idx: int): void = "mac#"

(* Get node ID for a slot's container (for external DOM ops) *)
fun reader_get_slot_node_id(slot: int): int = "mac#"
