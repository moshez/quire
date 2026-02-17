(* buf.sats - Buffer capacity constants
 *
 * Single source of truth for all buffer sizes in the application.
 * Type-level (stadef) for constraint solver, dynamic-level (#define)
 * for runtime use.
 *)

(* ========== Buffer Capacities (type-level) ========== *)
(* Bridge-shared buffers *)
stadef SBUF_CAP = 4096     (* string buffer capacity *)
stadef FBUF_CAP = 16384    (* fetch buffer capacity *)
stadef DBUF_CAP = 4096     (* diff buffer capacity *)

(* EPUB metadata buffers *)
stadef EPUB_TITLE_CAP = 256
stadef EPUB_AUTHOR_CAP = 256
stadef EPUB_BOOKID_CAP = 64
stadef EPUB_OPF_CAP = 256
stadef EPUB_SPINE_BUF_CAP = 4096
stadef EPUB_SPINE_OFF_CAP = 128   (* 32 entries x 4 bytes *)
stadef EPUB_SPINE_LEN_CAP = 128   (* 32 entries x 4 bytes *)

(* Library storage *)
stadef LIB_BOOKS_CAP = 19456      (* 32 books x 152 ints x 4 bytes *)
stadef LIB_BOOKS_CAP_S = 19456    (* type-level alias for sort proofs *)

(* ZIP storage *)
stadef ZIP_ENTRIES_CAP = 7168     (* 256 entries x 7 ints x 4 bytes *)
stadef ZIP_NAMEBUF_CAP = 8192

(* Reader button IDs — 64 slots: [0..31] read btns, [32..63] archive btns *)
stadef RDR_BTNS_CAP = 256        (* 64 ints x 4 bytes *)

(* ========== Buffer Size Constants (dynamic-level) ========== *)
#define STRING_BUFFER_SIZE 4096
#define FETCH_BUFFER_SIZE  16384
#define DIFF_BUFFER_SIZE   4096
#define EPUB_TITLE_SIZE 256
#define EPUB_AUTHOR_SIZE 256
#define EPUB_BOOKID_SIZE 64
#define EPUB_OPF_SIZE 256
#define EPUB_SPINE_BUF_SIZE 4096
#define EPUB_SPINE_OFF_SIZE 128
#define EPUB_SPINE_LEN_SIZE 128
#define LIB_BOOKS_SIZE 19456
#define ZIP_ENTRIES_SIZE 7168
#define ZIP_NAMEBUF_SIZE 8192
#define RDR_BTNS_SIZE 256
