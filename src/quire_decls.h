/* quire_decls.h — C forward declarations for cross-module mac# functions.
 *
 * ATS2 mac# declarations don't generate C prototypes (ATSdyncst_mac is a
 * no-op in ward's runtime.h). Functions implemented via ext# in one .dats
 * file and called via mac# from others need explicit C prototypes to avoid
 * -Wimplicit-function-declaration warnings.
 *
 * These functions are implemented in buf.dats (buf_*) and app_state.dats
 * (get_*_buffer_ptr). The ATS-level typed APIs live in buf.sats. */

#ifndef QUIRE_DECLS_H
#define QUIRE_DECLS_H

/* buf.dats ext# — raw byte/i32 buffer access */
int buf_get_u8(void *p, int off);
void buf_set_u8(void *p, int off, int v);
int buf_get_i32(void *p, int idx);
void buf_set_i32(void *p, int idx, int v);

/* app_state.dats ext# — buffer pointer accessors */
void *get_string_buffer_ptr(void);
void *get_fetch_buffer_ptr(void);
void *get_diff_buffer_ptr(void);

#endif
