(* epub.sats - EPUB import pipeline type declarations
 *
 * Handles EPUB file parsing, metadata extraction, and IndexedDB storage.
 * Uses zip.sats for ZIP parsing and xml.sats for XML parsing.
 *)

(* EPUB import state *)
#define EPUB_STATE_IDLE           0
#define EPUB_STATE_OPENING_FILE   1
#define EPUB_STATE_PARSING_ZIP    2
#define EPUB_STATE_READING_CONTAINER 3
#define EPUB_STATE_READING_OPF    4
#define EPUB_STATE_OPENING_DB     5
#define EPUB_STATE_DECOMPRESSING  6
#define EPUB_STATE_STORING        7
#define EPUB_STATE_DONE           8
#define EPUB_STATE_ERROR          99

(* Initialize EPUB module *)
fun epub_init(): void = "mac#"

(* Start EPUB import from file input node
 * file_input_node_id: the DOM node ID of the file input element
 * Returns 1 if import started, 0 on error *)
fun epub_start_import(file_input_node_id: int): int = "mac#"

(* Get current import state *)
fun epub_get_state(): int = "mac#"

(* Get import progress (0-100) *)
fun epub_get_progress(): int = "mac#"

(* Get last error message into string buffer
 * Returns message length *)
fun epub_get_error(buf_offset: int): int = "mac#"

(* Get book title into string buffer (after import completes)
 * Returns title length *)
fun epub_get_title(buf_offset: int): int = "mac#"

(* Get book author into string buffer (after import completes)
 * Returns author length *)
fun epub_get_author(buf_offset: int): int = "mac#"

(* Get book ID (hash of title+author or generated)
 * Returns ID into string buffer *)
fun epub_get_book_id(buf_offset: int): int = "mac#"

(* Get total number of chapters in spine *)
fun epub_get_chapter_count(): int = "mac#"

(* Continue processing (called from async callbacks)
 * Called after file open, decompress, or IDB operations complete *)
fun epub_continue(): void = "mac#"

(* Handle file open completion (called by bridge callback) *)
fun epub_on_file_open(handle: int, size: int): void = "mac#"

(* Handle decompress completion (called by bridge callback) *)
fun epub_on_decompress(blob_handle: int, size: int): void = "mac#"

(* Handle IndexedDB open completion *)
fun epub_on_db_open(success: int): void = "mac#"

(* Handle IndexedDB put completion *)
fun epub_on_db_put(success: int): void = "mac#"

(* Cancel current import *)
fun epub_cancel(): void = "mac#"
