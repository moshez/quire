(* library.dats - Book library implementation
 *
 * All library functions are implemented in quire_runtime.c and linked
 * via "mac#" declarations in library.sats. This file exists only as
 * the ATS2 compilation unit.
 *)

#define ATS_DYNLOADFLAG 0

staload "library.sats"

(* All implementations provided by quire_runtime.c via mac# linkage *)
