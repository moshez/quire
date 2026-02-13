(* buf.sats - Typed buffer accessors
 *
 * Provides sized_buf — a pointer type that tracks remaining capacity
 * at the type level. Capacity is phantom: exists only for the constraint
 * solver, erased at runtime. Buffer sizes appear ONLY here.
 *
 * Pattern:
 *   val buf = get_string_buf()          -- sized_buf(SBUF_CAP)
 *   val b = sbuf_get_u8(buf, off)      -- typed byte read
 *   val () = sbuf_write(buf, src, n)   -- ATS checks: n <= SBUF_CAP
 *   val buf = sbuf_advance(buf, n)     -- sized_buf(SBUF_CAP - n)
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
stadef EPUB_SPINE_OFF_CAP = 128   (* 32 entries × 4 bytes *)
stadef EPUB_SPINE_LEN_CAP = 128   (* 32 entries × 4 bytes *)

(* Library storage *)
stadef LIB_BOOKS_CAP = 19200      (* 32 books × 150 ints × 4 bytes *)

(* ZIP storage *)
stadef ZIP_ENTRIES_CAP = 7168     (* 256 entries × 7 ints × 4 bytes *)
stadef ZIP_NAMEBUF_CAP = 8192

(* Reader button IDs *)
stadef RDR_BTNS_CAP = 128        (* 32 ints × 4 bytes *)

(* ========== Buffer Size Constants (dynamic-level) ========== *)
#define STRING_BUFFER_SIZE 4096
#define FETCH_BUFFER_SIZE  16384
#define DIFF_BUFFER_SIZE   4096

(* ========== Sized Buffer Type ========== *)
abstype sized_buf(cap: int) = ptr

(* ========== Buffer Accessors ========== *)
fun get_string_buf(): sized_buf(SBUF_CAP) = "mac#get_string_buffer_ptr"
fun get_fetch_buf(): sized_buf(FBUF_CAP) = "mac#get_fetch_buffer_ptr"

(* ========== Buffer Operations ========== *)
fun sbuf_write {cap,l:nat | l <= cap}
  (dst: sized_buf(cap), src: ptr, len: int l): void = "mac#memcpy"

fun sbuf_advance {cap,n:nat | n <= cap}
  (buf: sized_buf(cap), n: int n): sized_buf(cap - n) = "mac#atspre_add_ptr0_bsz"

(* ========== Typed Byte Access ========== *)
(* Read/write bytes and i32s through sized_buf. Takes sized_buf(cap)
 * which carries capacity at the type level. At runtime, sized_buf
 * erases to the same representation as the underlying buffer.
 * Implemented in buf.dats. *)
fun sbuf_get_u8 {cap:nat} (b: sized_buf(cap), off: int): int = "mac#buf_get_u8"
fun sbuf_set_u8 {cap:nat} (b: sized_buf(cap), off: int, v: int): void = "mac#buf_set_u8"
fun sbuf_get_i32 {cap:nat} (b: sized_buf(cap), idx: int): int = "mac#buf_get_i32"
fun sbuf_set_i32 {cap:nat} (b: sized_buf(cap), idx: int, v: int): void = "mac#buf_set_i32"
