(* reader.dats - Three-chapter sliding window implementation
 *
 * All reader functions are implemented in quire_runtime.c and linked
 * via "mac#" declarations in reader.sats. This file exists only as
 * the ATS2 compilation unit.
 *)

#define ATS_DYNLOADFLAG 0

staload "./reader.sats"
staload "./dom.sats"

(* All implementations provided by quire_runtime.c via mac# linkage *)
