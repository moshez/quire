(* settings.dats - Reader settings implementation
 *
 * All settings functions are implemented in quire_runtime.c and linked
 * via "mac#" declarations in settings.sats. This file exists only as
 * the ATS2 compilation unit.
 *)

#define ATS_DYNLOADFLAG 0

staload "settings.sats"

(* All implementations provided by quire_runtime.c via mac# linkage *)
