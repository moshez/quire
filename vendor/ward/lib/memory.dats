(* memory.dats -- Ward: linear memory safety implementations *)
(* The "unsafe core" that the type system protects users from touching. *)
(* At runtime all proofs are erased — zero overhead. *)

#include "share/atspre_staload.hats"
staload "./memory.sats"

local

  assume ward_arr(a, l, n) = ptr l
  assume ward_arr_frozen(a, l, n, k) = ptr l
  assume ward_arr_borrow(a, l, n) = ptr l
  assume ward_safe_text(n) = ptr
  assume ward_text_builder(n, i) = ptr

in

(*
 * $<M>UNSAFE justifications — each use is marked with its pattern tag.
 *
 * [U1] ptr0_get/ptr0_set (get, set, read, safe_text_get, text_putc):
 *   Dereferences ptr at computed offset to read/write element of type a.
 *   Alternative considered: ATS2 arrayptr_get_at/set_at with array_v views.
 *   Rejected: ward uses absvtype (opaque linear types) assumed as ptr,
 *   not ATS2's view system. Exposing array_v in .sats would couple users
 *   to implementation details. Bounds safety is enforced by {i < n} in .sats.
 *
 * [U2] cast{ptr(l+m)} (split, borrow_split):
 *   Casts ptr_add<a> result to statically-typed address ptr(l+m).
 *   Root cause: ATS2 constraint solver cannot reduce sizeof(a) at the
 *   static level (known limitation). No safe alternative exists.
 *
 *)

(*
 * _proven_int2byte: narrowing int-to-byte cast with proven {i < 256}.
 *
 * ATS2's byte type is not dependently indexed, so there is no safe
 * cast from int(i) to byte even when {0 <= i < 256} is proven.
 * Alternatives researched:
 *   castfn int2byte{i:nat | i < 256}(int i): byte — would work if
 *     byte were indexed (byte(i)), but ATS2's byte is a flat type.
 *   prelude int2byte0 — unavailable in freestanding mode, and itself
 *     just does (unsigned char)(i) with no proof obligation.
 * This is the same boundary hit by every dependent type system:
 *   Idris2 uses believe_me for Fin→Bits8, Coq erases proofs at
 *   extraction, Ada/SPARK has first-class range subtypes (the only
 *   system that avoids it). See memory notes for full comparison.
 *)
fn _proven_int2byte{i:nat | i < 256}(i: int i): byte =
  $UNSAFE.cast{byte}(i)

extern fun _ward_malloc_bytes (n: int): [l:agz] ptr l = "mac#malloc"

implement{a}
ward_arr_alloc{n}(n) = let
  val nbytes = n * sz2i(sizeof<a>)
  val p = _ward_malloc_bytes(nbytes)
  val () = $extfcall(void, "memset", p, 0, nbytes)
in
  p
end

implement{a}
ward_arr_free{l}{n}(arr) =
  $extfcall(void, "free", arr)

implement{a}
ward_arr_get{l}{n,i}(arr, i) =
  $UNSAFE.ptr0_get<a>(ptr_add<a>(arr, i)) (* [U1] *)

implement{a}
ward_arr_set{l}{n,i}(arr, i, v) =
  $UNSAFE.ptr0_set<a>(ptr_add<a>(arr, i), v) (* [U1] *)

implement{a}
ward_arr_split{l}{n,m}(arr, m) = let
  val tail = $UNSAFE.cast{ptr(l+m)}(ptr_add<a>(arr, m)) (* [U2] *)
in
  @(arr, tail)
end

implement{a}
ward_arr_join{l}{n,m}(left, right) = left

implement{a}
ward_arr_freeze{l}{n}(arr) = @(arr, arr)

implement{a}
ward_arr_thaw{l}{n}(frozen) = frozen

implement{a}
ward_arr_dup{l}{n}{k}(frozen, borrow) = borrow

implement{a}
ward_arr_drop{l}{n}{k}(frozen, borrow) = ()

implement{a}
ward_arr_read{l}{n,i}(borrow, i) =
  $UNSAFE.ptr0_get<a>(ptr_add<a>(borrow, i)) (* [U1] *)

implement{a}
ward_arr_borrow_split{l}{n,m}{k}(frozen, borrow, m) = let
  val tail = $UNSAFE.cast{ptr(l+m)}(ptr_add<a>(borrow, m)) (* [U2] *)
in
  @(borrow, tail)
end

implement{a}
ward_arr_borrow_join{l}{n,m}{k}(frozen, left, right) = left

implement
ward_text_build{n}(n) = _ward_malloc_bytes(n)

implement
ward_text_putc{c}{n}{i}(b, i, c) = let
  val () = $UNSAFE.ptr0_set<byte>(ptr_add<byte>(b, i), _proven_int2byte(c)) (* [U1] *)
in b end

implement
ward_text_done{n}(b) = b

implement
ward_safe_text_get{n,i}(t, i) =
  $UNSAFE.ptr0_get<byte>(ptr_add<byte>(t, i)) (* [U1] *)

implement
ward_text_from_bytes{lb}{n}(src, len) = let
  fun loop {i:nat | i <= n}
    (src: ptr, i: int i, len: int n): bool =
    if i >= len then true
    else let
      val b = byte2int0(
        $UNSAFE.ptr0_get<byte>(ptr_add<byte>(src, i))) (* [U1] *)
    in
      if (b >= 97 andalso b <= 122)       (* a-z *)
         orelse (b >= 65 andalso b <= 90)  (* A-Z *)
         orelse (b >= 48 andalso b <= 57)  (* 0-9 *)
         orelse b = 45                     (* - *)
      then loop(src, i + 1, len)
      else false
    end
  val all_safe = loop(src, 0, len)
in
  if all_safe then let
    val p = _ward_malloc_bytes(len)
    val () = $extfcall(void, "memcpy", p, src, len)
    val t = $UNSAFE.cast{ward_safe_text(n)}(p) (* [U1] *)
  in ward_text_ok(t) end
  else ward_text_fail()
end

implement
ward_int2byte{i}(i) = _proven_int2byte(i)

(*
 * Array write operations — byte-level, for DOM streaming.
 * No $<M>UNSAFE needed: inside the local block, ward_arr(byte, l, n) = ptr l,
 * ward_arr_borrow(byte, ls, n) = ptr ls, ward_safe_text(n) = ptr.
 * The $extfcall targets (ward_set_byte, ward_set_i32, ward_copy_at) are
 * C helpers in runtime.h / ward_prelude.h that operate on raw pointers.
 *)

implement
ward_arr_write_byte{l}{n}{i}{v}(arr, i, v) =
  $extfcall(void, "ward_set_byte", arr, i, v)

implement
ward_arr_write_i32{l}{n}{i}(arr, i, v) =
  $extfcall(void, "ward_set_i32", arr, i, v)

implement
ward_arr_write_borrow{ld}{ls}{m}{n}{off}(dst, off_val, src, len) =
  $extfcall(void, "ward_copy_at", dst, off_val, src, len)

implement
ward_arr_write_safe_text{l}{m}{n}{off}(dst, off_val, src, len) =
  $extfcall(void, "ward_copy_at", dst, off_val, src, len)

(* JS data stash import — pulls stashed data into WASM-owned buffer.
   No $UNSAFE needed: inside the local block, ward_arr(byte, l, n) = ptr l,
   so _ward_malloc_bytes(len) returns [l:agz] ptr l which satisfies the return type.
   p is ptr at C level, matching the void *dest import. *)
extern fun _ward_js_stash_read
  (stash_id: int, dest: ptr, len: int): void = "mac#ward_js_stash_read"

implement
ward_bridge_recv{n}(stash_id, len) = let
  val p = _ward_malloc_bytes(len)
  val () = _ward_js_stash_read(stash_id, p, len)
in p end

implement
ward_arr_write_u16le{l}{n}{i}{v}(arr, i, v) = let
  val v0 : int = v
  val () = $extfcall(void, "ward_set_byte", arr, i, v0)
  val () = $extfcall(void, "ward_set_byte", arr, i + 1, v0 / 256)
in () end

end (* local *)
