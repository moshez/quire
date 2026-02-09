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
 * $UNSAFE justifications — each use is marked with its pattern tag.
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
 *   Alternative considered: praxi proof of address equality.
 *   Rejected: equally unsafe, more complex. Root cause: ATS2 constraint
 *   solver cannot reduce sizeof(a) at the static level (known limitation).
 *
 * [U3] cast{byte}(c) (text_putc):
 *   Converts int char code to byte for storage.
 *   Alternative considered: int2byte0 from ATS2 prelude.
 *   Rejected: unavailable in freestanding mode (_ATS_CCOMP_PRELUDE_NONE_).
 *)

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
  val () = $UNSAFE.ptr0_set<byte>(ptr_add<byte>(b, i), $UNSAFE.cast{byte}(c)) (* [U1]+[U3] *)
in b end

implement
ward_text_done{n}(b) = b

implement
ward_safe_text_get{n,i}(t, i) =
  $UNSAFE.ptr0_get<byte>(ptr_add<byte>(t, i)) (* [U1] *)

implement
ward_int2byte(i) = $UNSAFE.cast{byte}(i) (* [U3] *)

end (* local *)
