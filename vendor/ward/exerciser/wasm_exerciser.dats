(* wasm_exerciser.dats -- WASM exerciser: exports functions that exercise ward *)

#include "share/atspre_staload.hats"
staload "./../lib/memory.sats"
dynload "./../lib/memory.dats"
staload _ = "./../lib/memory.dats"

(* === Export: exercise byte arrays (alloc, split, set, join, free) === *)
extern fun ward_test_raw (): int = "mac#"
implement ward_test_raw () = let
  val arr = ward_arr_alloc<byte> (40)
  val @(head, tail) = ward_arr_split<byte> (arr, 16)
  val () = ward_arr_set<byte> (head, 0, $UNSAFE.cast{byte}(170))
  val whole = ward_arr_join<byte> (head, tail)
  val () = ward_arr_free<byte> (whole)
in
  1 (* success *)
end

(* === Export: exercise borrow protocol === *)
extern fun ward_test_borrow (): int = "mac#"
implement ward_test_borrow () = let
  val arr = ward_arr_alloc<byte> (16)
  val () = ward_arr_set<byte> (arr, 0, $UNSAFE.cast{byte}(42))
  val @(frozen, borrow1) = ward_arr_freeze<byte> (arr)
  val v = $UNSAFE.cast{int}(ward_arr_read<byte> (borrow1, 0))
  val borrow2 = ward_arr_dup<byte> (frozen, borrow1)
  val () = ward_arr_drop<byte> (frozen, borrow1)
  val () = ward_arr_drop<byte> (frozen, borrow2)
  val arr = ward_arr_thaw<byte> (frozen)
  val () = ward_arr_free<byte> (arr)
in
  v (* return the byte we read *)
end

(* === Export: exercise typed int arrays === *)
extern fun ward_test_typed (): int = "mac#"
implement ward_test_typed () = let
  val arr = ward_arr_alloc<int> (10)
  val () = ward_arr_set<int> (arr, 5, 42)
  val v1 = ward_arr_get<int> (arr, 5)
  val @(frozen, borrow1) = ward_arr_freeze<int> (arr)
  val v2 = ward_arr_read<int> (borrow1, 5)
  val () = ward_arr_drop<int> (frozen, borrow1)
  val arr2 = ward_arr_thaw<int> (frozen)
  val () = ward_arr_set<int> (arr2, 5, 99)
  val v3 = ward_arr_get<int> (arr2, 5)
  val () = ward_arr_free<int> (arr2)
in
  v1 + v2 + v3 (* 42 + 42 + 99 = 183 *)
end

(* === Export: exercise safe text === *)
extern fun ward_test_safe_text (): int = "mac#"
implement ward_test_safe_text () = let
  val b = ward_text_build(3)
  val b = ward_text_putc(b, 0, char2int1('a'))
  val b = ward_text_putc(b, 1, char2int1('b'))
  val b = ward_text_putc(b, 2, char2int1('c'))
  val t = ward_text_done(b)
  val v0 = $UNSAFE.cast{int}(ward_safe_text_get(t, 0))
  val v2 = $UNSAFE.cast{int}(ward_safe_text_get(t, 2))
in
  v0 + v2 (* 97 + 99 = 196 *)
end

(* === Export: exercise large allocation (triggers memory.grow) === *)
extern fun ward_test_large_alloc (): int = "mac#"
implement ward_test_large_alloc () = let
  (* Two 12MB allocations -- first may fit in initial 16MB, second forces
     memory.grow since total exceeds 16MB initial WASM memory *)
  val arr1 = ward_arr_alloc<byte> (12582912)
  val () = ward_arr_set<byte> (arr1, 0, $UNSAFE.cast{byte}(0xAA))
  val () = ward_arr_set<byte> (arr1, 12582911, $UNSAFE.cast{byte}(0xBB))
  val arr2 = ward_arr_alloc<byte> (12582912)
  val () = ward_arr_set<byte> (arr2, 0, $UNSAFE.cast{byte}(0xCC))
  val () = ward_arr_set<byte> (arr2, 12582911, $UNSAFE.cast{byte}(0xDD))
  val v0 = $UNSAFE.cast{int}(ward_arr_get<byte> (arr1, 0))
  val v1 = $UNSAFE.cast{int}(ward_arr_get<byte> (arr2, 12582911))
  val () = ward_arr_free<byte> (arr1)
  val () = ward_arr_free<byte> (arr2)
in
  v0 + v1 (* 0xAA + 0xDD = 170 + 221 = 391 *)
end
