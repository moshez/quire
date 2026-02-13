/* quire_prelude.h — Quire-specific C declarations
 *
 * Ward's runtime.h provides all ATS2 codegen macros, atspre_*
 * arithmetic, bitwise ops, and calloc. Cross-module function
 * declarations are handled by ATS2's .sats type system.
 *
 * This file contains only C-level definitions that cannot be
 * expressed in ATS2.
 */

#ifndef QUIRE_PRELUDE_H
#define QUIRE_PRELUDE_H

/* ATS2 abstract type erasure — absvtype app_state erases to ptr */
#define app_state atstype_ptrk

/* Pointer comparison — no ward atspre_* for ptr == ptr */
#define quire_ptr_eq(a, b) ((a) == (b))

#endif /* QUIRE_PRELUDE_H */
