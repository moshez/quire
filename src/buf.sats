(* buf.sats - General-purpose sized buffer type
 *
 * Provides a pointer type that tracks remaining capacity at the type level.
 * Capacity is phantom — it exists only for the constraint solver, not in
 * generated code. At runtime, sized_buf erases to plain ptr.
 *
 * The buffer size literal (e.g. 4096) appears ONLY here, at the definition
 * site. Downstream modules reference the abstract capacity through the
 * sized_buf type returned by accessor functions and never hardcode sizes.
 *
 * Pattern:
 *   val buf = get_string_buf()          -- sized_buf(SBUF_CAP)
 *   val () = sbuf_write(buf, src, n)    -- ATS checks: n <= SBUF_CAP
 *   val buf = sbuf_advance(buf, n)      -- sized_buf(SBUF_CAP - n)
 *   val () = sbuf_write(buf, src2, m)   -- ATS checks: m <= SBUF_CAP - n
 *)

(* ========== Buffer Capacities (type-level) ========== *)
(* Single source of truth for buffer sizes used in proofs.
 * These stadefs are the ONLY place the concrete sizes appear.
 * All API constraints reference these, never raw literals. *)
stadef SBUF_CAP = 4096     (* string buffer capacity *)
stadef FBUF_CAP = 16384    (* fetch buffer capacity *)

(* ========== Buffer Size Constants (dynamic-level) ========== *)
(* Runtime values for C code and dynamic ATS expressions. *)
#define STRING_BUFFER_SIZE 4096
#define FETCH_BUFFER_SIZE  16384
#define DIFF_BUFFER_SIZE   4096

(* ========== Sized Buffer Type ========== *)
(* A pointer that knows its remaining capacity at the type level.
 * Erased to plain ptr at runtime. The capacity is a phantom index —
 * it exists only for the constraint solver, not in generated code.
 *
 * The buffer accessors (get_string_buf, get_fetch_buf) are the single
 * source of truth for buffer sizes. All write operations check against
 * the capacity carried by the sized_buf, never against a hardcoded
 * constant. If a buffer size changes, only the accessor needs updating. *)
abstype sized_buf(cap: int) = ptr

(* ========== Buffer Accessors (typed) ========== *)
(* These connect the abstract sized_buf type to concrete buffers.
 * The capacity parameter is set HERE, at the definition site —
 * callers receive the capacity through the type, never hardcode it. *)

(* Get the string buffer with its full capacity *)
fun get_string_buf(): sized_buf(SBUF_CAP) = "mac#get_string_buffer_ptr"

(* Get the fetch buffer with its full capacity *)
fun get_fetch_buf(): sized_buf(FBUF_CAP) = "mac#get_fetch_buffer_ptr"

(* ========== Buffer Operations ========== *)

(* Write len bytes at the start of a sized buffer.
 * Requires: len <= remaining capacity. *)
fun sbuf_write {cap,l:nat | l <= cap}
  (dst: sized_buf(cap), src: ptr, len: int l): void = "mac#memcpy"

(* Advance a buffer pointer by n bytes, reducing capacity.
 * Returns a sub-buffer starting n bytes later with cap-n remaining. *)
fun sbuf_advance {cap,n:nat | n <= cap}
  (buf: sized_buf(cap), n: int n): sized_buf(cap - n) = "mac#atspre_add_ptr0_bsz"

(* ========== Buffer Accessors (raw) ========== *)
(* Raw pointer accessors for C interop and low-level operations.
 * Prefer the typed accessors above for new ATS code. *)

fun get_diff_buffer_ptr(): ptr = "mac#"
fun get_string_buffer_ptr(): ptr = "mac#"
fun get_fetch_buffer_ptr(): ptr = "mac#"

(* ========== Low-level Memory Access ========== *)
(* Byte-level access — C macros in quire_prelude.h *)
fun buf_get_u8(p: ptr, off: int): int = "mac#"
fun buf_set_u8(p: ptr, off: int, v: int): void = "mac#"
fun buf_get_i32(p: ptr, idx: int): int = "mac#"
fun buf_set_i32(p: ptr, idx: int, v: int): void = "mac#"
fun ptr_add_int(p: ptr, n: int): ptr = "mac#atspre_add_ptr0_bsz"
