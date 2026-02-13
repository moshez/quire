(* arith.sats — freestanding arithmetic for ATS2 without prelude
 *
 * All mac# targets point to ward's runtime.h atspre_* macros.
 * staload this file from every .dats instead of duplicating
 * extern fun declarations per module.
 *)

(* ========== Arithmetic ========== *)
fun add_int_int(a: int, b: int): int = "mac#atspre_g0int_add_int"
fun sub_int_int(a: int, b: int): int = "mac#atspre_g0int_sub_int"
fun mul_int_int(a: int, b: int): int = "mac#atspre_g0int_mul_int"
fun div_int_int(a: int, b: int): int = "mac#atspre_g0int_div_int"
fun mod_int_int(a: int, b: int): int = "mac#atspre_g0int_mod_int"

(* ========== Comparison ========== *)
fun eq_int_int(a: int, b: int): bool = "mac#atspre_g0int_eq_int"
fun neq_int_int(a: int, b: int): bool = "mac#atspre_g0int_neq_int"
fun gt_int_int(a: int, b: int): bool = "mac#atspre_g0int_gt_int"
fun gte_int_int(a: int, b: int): bool = "mac#atspre_g0int_gte_int"
fun lt_int_int(a: int, b: int): bool = "mac#atspre_g0int_lt_int"
fun lte_int_int(a: int, b: int): bool = "mac#atspre_g0int_lte_int"

(* Dependent comparison — preserves static info for array bounds *)
fun gt1_int_int {a,b:int} (a: int a, b: int b): bool(a > b) = "mac#atspre_g0int_gt_int"

(* ========== Bitwise ========== *)
fun bor_int_int(a: int, b: int): int = "mac#atspre_g0int_lor_int"
fun bsl_int_int(a: int, n: int): int = "mac#atspre_g0int_asl_int"
fun band_int_int(a: int, b: int): int = "mac#atspre_g0int_land_int"
fun bsr_int_int(a: int, n: int): int = "mac#atspre_g0int_asr_int"

(* ========== Pointer ========== *)
fun _null_ptr(): ptr = "mac#atspre_ptr_null"
fun _ptr_add(p: ptr, n: int): ptr = "mac#atspre_add_ptr0_bsz"
fun eq_ptr_ptr(a: ptr, b: ptr): bool = "mac#quire_ptr_eq"

(* ========== Operator overloads (priority 10 beats prelude) ========== *)
overload + with add_int_int of 10
overload - with sub_int_int of 10
overload * with mul_int_int of 10

(* ========== Runtime-checked castfns ========== *)
castfn _checked_pos(x: int): [n:pos] int n
castfn _checked_nat(x: int): [n:nat] int n
castfn _checked_byte(x: int): [v:nat | v < 256] int v

(* Index castfn — asserts offset is within [0, n) for ward_arr access.
 * Replaces runtime bounds check of _ward_arr_byte macro. *)
castfn _ward_idx {n:pos} (x: int, len: int n): [i:nat | i < n] int i
