(* buf.dats — Pure ATS2 implementations of buffer access primitives
 *
 * Replaces C macros from quire_prelude.h with safe ATS2 using
 * ward's runtime.h for ptr0_get/ptr0_set/ptr_add.
 *
 * $UNSAFE justification [U1]: dereferences ptr at computed offset.
 * These are irreducible C operations (raw pointer byte/int access).
 * Bounds safety must be ensured by callers. Alternative considered:
 * ward_arr_get<byte> — rejected because 238 call sites use raw ptr
 * from app_state accessors, not ward_arr.
 *)

#include "share/atspre_staload.hats"
staload UN = "prelude/SATS/unsafe.sats"
staload "./buf.sats"

implement buf_get_u8(p, off) =
  byte2int0($UN.ptr0_get<byte>(ptr_add<byte>(p, off))) (* [U1] *)

implement buf_set_u8(p, off, v) =
  $UN.ptr0_set<byte>(ptr_add<byte>(p, off), $UN.cast{byte}(v)) (* [U1] *)

implement buf_get_i32(p, idx) =
  $UN.ptr0_get<int>(ptr_add<int>(p, idx)) (* [U1] *)

implement buf_set_i32(p, idx, v) =
  $UN.ptr0_set<int>(ptr_add<int>(p, idx), v) (* [U1] *)
