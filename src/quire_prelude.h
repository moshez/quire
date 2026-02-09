/* quire_prelude.h — Freestanding arithmetic macros for ATS2
 *
 * ATS2 operators (+, -, *, =, >=, >) generate calls to prelude
 * template functions (e.g. atspre_g0int_eq_int) which don't exist
 * in freestanding mode. These macros provide the implementations.
 *
 * Ward's runtime.h already defines: atspre_g0int_add_int,
 * atspre_g0int_gt_int, atspre_g0int2uint_int_size,
 * atspre_g0int2int_int_int. We only add the missing ones here.
 */

#ifndef QUIRE_PRELUDE_H
#define QUIRE_PRELUDE_H

/* Arithmetic — quire_* names for explicit extern fun declarations */
#define quire_add(a, b) ((a) + (b))
#define quire_sub(a, b) ((a) - (b))
#define quire_mul(a, b) ((a) * (b))

/* Comparison — quire_* names for explicit extern fun declarations */
#define quire_eq(a, b) ((a) == (b))
#define quire_neq(a, b) ((a) != (b))
#define quire_gte(a, b) ((a) >= (b))
#define quire_gt(a, b) ((a) > (b))
#define quire_lt(a, b) ((a) < (b))
#define quire_lte(a, b) ((a) <= (b))

/* ATS2 prelude names NOT already in ward runtime.h */
#ifndef atspre_g0int_eq_int
#define atspre_g0int_eq_int(a, b) ((a) == (b))
#endif
#ifndef atspre_g0int_neq_int
#define atspre_g0int_neq_int(a, b) ((a) != (b))
#endif
#ifndef atspre_g0int_gte_int
#define atspre_g0int_gte_int(a, b) ((a) >= (b))
#endif
#ifndef atspre_g0int_lte_int
#define atspre_g0int_lte_int(a, b) ((a) <= (b))
#endif
#ifndef atspre_g0int_lt_int
#define atspre_g0int_lt_int(a, b) ((a) < (b))
#endif
#ifndef atspre_g0int_sub_int
#define atspre_g0int_sub_int(a, b) ((a) - (b))
#endif
#ifndef atspre_g0int_mul_int
#define atspre_g0int_mul_int(a, b) ((a) * (b))
#endif

/* g1int (dependent int) variants — same operations, tracked statically.
 * ward runtime.h already defines: g1int_add, g1int_mul, g1int_lt */
#ifndef atspre_g1int_sub_int
#define atspre_g1int_sub_int(a, b) ((a) - (b))
#endif
#ifndef atspre_g1int_add_int
#define atspre_g1int_add_int(a, b) ((a) + (b))
#endif
#ifndef atspre_g1int_mul_int
#define atspre_g1int_mul_int(a, b) ((a) * (b))
#endif
#ifndef atspre_g1int_neg_int
#define atspre_g1int_neg_int(a) (-(a))
#endif
#ifndef atspre_g1int_eq_int
#define atspre_g1int_eq_int(a, b) ((a) == (b))
#endif
#ifndef atspre_g1int_neq_int
#define atspre_g1int_neq_int(a, b) ((a) != (b))
#endif
#ifndef atspre_g1int_gt_int
#define atspre_g1int_gt_int(a, b) ((a) > (b))
#endif
#ifndef atspre_g1int_gte_int
#define atspre_g1int_gte_int(a, b) ((a) >= (b))
#endif
#ifndef atspre_g1int_lt_int
#define atspre_g1int_lt_int(a, b) ((a) < (b))
#endif
#ifndef atspre_g1int_lte_int
#define atspre_g1int_lte_int(a, b) ((a) <= (b))
#endif

/* Datavtype (tagged union) construction and matching.
 * ATS2 datavtype generates con1 (non-null constructors) as malloc'd structs
 * with a tag field and data fields. con0 (nullary) represented as NULL. */
#define ATSINSmove_con1_beg()
#define ATSINSmove_con1_end()
#define ATSINSmove_con1_new(dst, tysum) ((dst) = malloc(sizeof(tysum)))
#define ATSINSstore_con1_tag(dst, tag) (((int*)(dst))[0] = (tag))
#define ATSINSstore_con1_ofs(dst, tysum, lab, val) (((tysum*)(dst))->lab = (val))
#ifndef ATSINSmove_con0
#define ATSINSmove_con0(dst, tag) ((dst) = (void*)0)
#endif
#define ATSINSfreecon(p) /* bump allocator: no-op */
#define ATSCKpat_con0(p, tag) ((p) == (void*)0)
#define ATSCKpat_con1(p, tag) (((int*)(p))[0] == (tag))
#define ATSSELcon(p, tysum, lab) (((tysum*)(p))->lab)

/* Pointer arithmetic */
#define ptr_add_int(p, n) ((void*)((char*)(p) + (n)))
#define quire_ptr_add(p, n) ((void*)((char*)(p) + (n)))

/* Null pointer and pointer comparison */
#define quire_null_ptr() ((void*)0)
#define quire_ptr_eq(a, b) ((a) == (b))

/* Byte-level memory access (for xml.dats, zip.dats buffer parsing) */
#define buf_get_u8(p, off) ((int)(((unsigned char*)(p))[(off)]))
#define buf_set_u8(p, off, v) (((unsigned char*)(p))[(off)] = (unsigned char)(v))

/* sbuf_write — copy len bytes from src to dst */
#define sbuf_write(dst, src, len) do { \
    const unsigned char *_s = (const unsigned char *)(src); \
    unsigned char *_d = (unsigned char *)(dst); \
    for (int _i = 0; _i < (len); _i++) _d[_i] = _s[_i]; \
} while(0)

/* Buffer accessors (implemented in quire_runtime.c).
 * ATS2 mac# can generate unsigned char* or void* depending on module.
 * Use unsigned char* to match epub.dats generated code. */
extern unsigned char *get_string_buffer_ptr(void);
extern unsigned char *get_fetch_buffer_ptr(void);
extern unsigned char *get_diff_buffer_ptr(void);
extern int quire_get_byte(void *p, int off);

/* DOM next-node-id state (used by dom.dats via extern fun) */
extern int get_dom_next_node_id(void);
extern int set_dom_next_node_id(int v);

/* DOM lookup tables and copy (used by dom.dats tree renderer) */
extern int lookup_tag(void *base, int offset, int name_len);
extern int lookup_attr(void *base, int offset, int name_len);
extern int _copy_to_arr(void *dst, void *src, int offset, int count);

/* Bounds-checked byte read from ward_arr (erased to ptr at runtime).
 * Returns byte value if 0 <= off < len, else 0. */
#ifndef _ward_arr_byte
#define _ward_arr_byte(arr, off, len) \
  (((off) >= 0 && (off) < (len)) ? ((int)((unsigned char*)(arr))[(off)]) : 0)
#endif

/* Bitwise operations (may also be in ward runtime.h) */
#ifndef quire_bor
#define quire_bor(a, b) ((int)((unsigned int)(a) | (unsigned int)(b)))
#endif
#ifndef quire_bsl
#define quire_bsl(a, n) ((int)((unsigned int)(a) << (n)))
#endif

#endif /* QUIRE_PRELUDE_H */
