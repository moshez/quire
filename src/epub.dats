(* epub.dats - EPUB import pipeline implementation
 *
 * All epub functions are implemented in quire_runtime.c and linked
 * via "mac#" declarations in epub.sats. This file exists only as
 * the ATS2 compilation unit.
 *)

#define ATS_DYNLOADFLAG 0

staload "./epub.sats"
staload "./zip.sats"
staload "./xml.sats"

(* All implementations provided by quire_runtime.c via mac# linkage *)
