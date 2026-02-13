(* buf.dats — Raw byte access primitives (ext# linkage)
 *
 * These functions are NOT in buf.sats — they use raw ptr which
 * is module-internal only. Each module that needs byte access
 * declares them locally with "ext#". This keeps ptr out of
 * all public cross-module APIs.
 *
 * $UNSAFE justification [U1]: dereferences ptr at computed offset.
 * Irreducible C operations. Bounds safety ensured by callers.
 * To be replaced when app_state fields migrate from ptr to ward_arr.
 *)

#include "share/atspre_staload.hats"
staload UN = "prelude/SATS/unsafe.sats"
staload "./buf.sats"

extern fun buf_get_u8(p: ptr, off: int): int = "ext#"
extern fun buf_set_u8(p: ptr, off: int, v: int): void = "ext#"
extern fun buf_get_i32(p: ptr, idx: int): int = "ext#"
extern fun buf_set_i32(p: ptr, idx: int, v: int): void = "ext#"

implement buf_get_u8(p, off) =
  byte2int0($UN.ptr0_get<byte>(ptr_add<byte>(p, off))) (* [U1] *)

implement buf_set_u8(p, off, v) =
  $UN.ptr0_set<byte>(ptr_add<byte>(p, off), $UN.cast{byte}(v)) (* [U1] *)

implement buf_get_i32(p, idx) =
  $UN.ptr0_get<int>(ptr_add<int>(p, idx)) (* [U1] *)

implement buf_set_i32(p, idx, v) =
  $UN.ptr0_set<int>(ptr_add<int>(p, idx), v) (* [U1] *)
