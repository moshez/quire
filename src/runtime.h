/* runtime.h - ATS2 runtime macros and typedefs for freestanding WASM builds
 *
 * This header is included via -include in all ATS-generated C files.
 * Actual function implementations are in runtime.c.
 */

#ifndef QUIRE_RUNTIME_H
#define QUIRE_RUNTIME_H

typedef __SIZE_TYPE__ size_t;

/* Minimal ATS2 runtime macros for freestanding builds */
#ifdef _ATS_CCOMP_HEADER_NONE_

/* Basic typedefs */
typedef void atsvoid_t0ype;
typedef void* atstype_exnconptr;
typedef char* atstype_string;
typedef void* atstype_ptr;
typedef void* atstype_ptrk;
typedef void* atstype_cptr;
typedef int atstype_int;
typedef int atstype_bool;
typedef void* atstype_boxed;

/* Struct keyword for ATS-generated type layouts */
#define ATSstruct struct

/* Type kind macros - resolve to the actual type */
#define atstkind_type(tk) tk
#define atstkind_t0ype(tk) tk

/* Function structure macros */
#define ATSextern() extern
#define ATSextcode_beg()
#define ATSextcode_end()
#define ATSfunbody_beg()
#define ATSfunbody_end()
#define ATSreturn(x) return(x)
#define ATSreturn_void(x) return
#define ATSif(x) if(x)
#define ATSthen()
#define ATSelse() else
#define ATSendif

/* Dynamic loading */
#define ATSdynload()
#define ATSdynloadflag_ext(flag) extern int flag
#define ATSdynloadset(flag) flag = 1

/* Temporary variable declarations */
#define ATStmpdec(tmp, ty) ty tmp
#define ATStmpdec_void(tmp, ty) ty tmp

/* Instructions */
#define ATSINSmove(dst, src) dst = (src)
#define ATSINSmove_void(dst, src) src
#define ATSINSflab(lab) lab
#define ATSINSlab(lab) lab
#define ATSINSgoto(lab) goto lab

/* Case/branch control flow */
#define ATScaseof_beg()
#define ATScaseof_end()
#define ATSbranch_beg()
#define ATSbranch_end()
#define ATSifthen(x) if(x)

/* Tail call optimization */
#define ATStailcal_beg()
#define ATStailcal_end()
#define ATSINSmove_tlcal(dst, src) dst = (src)
#define ATSINSargmove_tlcal(dst, src) dst = (src)
#define ATSINSfgoto(lab) goto lab
#define ATSINSdeadcode_fail() /* unreachable */

/* Datavtype (heap-allocated tagged union) support */
#define ATSCKptriscons(p) ((p) != (void*)0)
#define ATSCKptrisnull(p) ((p) == (void*)0)
#define ATSSELcon(p, tysum, lab) (((tysum*)(p))->lab)
#define ATSifnthen(x) if(!(x))
#define ATSCKpat_con0(p, tag) ((p)==(void*)0)
#define ATSCKpat_con1(p, tag) (((int*)(p))[0]==(tag))
#define ATSSELcon(p, tysum, lab) (((tysum*)(p))->lab)
#define ATSINSfreecon(p) /* bump allocator: free is no-op */
#define ATSINSmove_nil(dst) (dst) = (void*)0
#define ATSINSmove_con0(dst, tag) (dst) = (void*)0
#define ATSINSmove_con1_beg()
#define ATSINSmove_con1_end()
#define ATSINSmove_con1_new(dst, tysum) (dst) = malloc(sizeof(tysum))
#define ATSINSstore_con1_tag(dst, tag) (((int*)(dst))[0] = (tag))
#define ATSINSstore_con1_ofs(dst, tysum, lab, val) (((tysum*)(dst))->lab) = (val)

/* Borrow parameter support (! in ATS2 function signatures) */
#define atsrefarg0_type(ty) ty
#define atsrefarg1_type(ty) ty*
#define ATSPMVrefarg0(x) (x)
#define ATSPMVrefarg1(x) (&(x))
#define ATSderefarg1(x) (*(x))

/* Flat record (tuple) support */
#define ATSINSmove_fltrec_beg()
#define ATSINSmove_fltrec_end()
#define ATSINSstore_fltrec_ofs(dst, tyrec, lab, val) ((dst).lab = (val))
#define ATSSELfltrec(rec, tyrec, lab) ((rec).lab)

/* Primitive values */
#define ATSPMVi0nt(i) (i)
#define ATSPMVint(i) (i)
#define ATSPMVintrep(i) (i)
#define ATSPMVbool_true() 1
#define ATSPMVbool_false() 0
#define ATSPMVstring(s) (s)
#define ATSPMVempty() /* empty */
#define ATSPMVcastfn(castfn, ty, val) ((ty)(val))
#define ATSextfcall(f, args) f args

/* Checks */
#define ATSCKiseqz(x) ((x)==0)
#define ATSCKisneqz(x) ((x)!=0)
#define ATSCKpat_int(x, v) ((x)==(v))

/* External function declarations for mac# functions */
#define ATSdyncst_mac(f) /* external C function */
#define ATSdyncst_extfun(f, argtys, restys) extern restys f argtys
#define ATSdyncst_valimp(f, ty) /* value implementation */

/* Static load flags */
#define ATSstaticdec() static
#define ATSstatic() static

/* Forward declarations for DOM functions (defined in dom_dats.c) */
extern void dom_init(void);
extern void* dom_root_proof(void);
extern void* dom_create_element(void*, int, int, void*, int);
extern void dom_remove_child(void*, int);
extern void* dom_set_text(void*, int, void*, int);
extern void* dom_set_text_offset(void*, int, int, int);
extern void* dom_set_attr(void*, int, void*, int, void*, int);
extern void* dom_set_attr_checked(void*, int, void*, int, void*, int);
extern void* dom_set_transform(void*, int, int, int);
extern void* dom_set_inner_html(void*, int, int, int);
extern int dom_next_id(void);
extern void dom_drop_proof(void*);

#endif /* _ATS_CCOMP_HEADER_NONE_ */

/* Forward declarations for runtime functions */
extern void* malloc(size_t size);
extern void free(void* ptr);
extern void* calloc(size_t n, size_t size);
extern void* memcpy(void* dst, const void* src, size_t n);
extern void* memset(void* dst, int c, size_t n);
extern void* memmove(void* dst, const void* src, size_t n);
extern int memcmp(const void* a, const void* b, size_t n);

extern unsigned char* get_event_buffer_ptr(void);
extern unsigned char* get_diff_buffer_ptr(void);
extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);

/* Bridge import: flush pending diffs */
extern void js_apply_diffs(void);

/* DOM next-node-id state (used by dom.dats via extern fun) */
extern unsigned int get_dom_next_node_id(void);
extern void set_dom_next_node_id(unsigned int v);

/* Byte-level memory access for ATS2 freestanding (no prelude).
 * These are the irreducible primitives that ATS2 cannot express
 * without C bindings — each is a single expression. */
#define buf_get_u8(p, off) ((int)(((unsigned char*)(p))[(off)]))
#define buf_set_u8(p, off, v) (((unsigned char*)(p))[(off)] = (unsigned char)(v))
#define ptr_add_int(p, n) ((void*)((unsigned char*)(p) + (n)))
#define sbuf_write(dst, src, len) memcpy((void*)(dst), (void*)(src), (len))

/* Bitwise operations for ATS2 freestanding (no prelude) */
#define quire_band(a, b) ((int)((unsigned int)(a) & (unsigned int)(b)))
#define quire_bor(a, b) ((int)((unsigned int)(a) | (unsigned int)(b)))
#define quire_bsl(a, n) ((int)((unsigned int)(a) << (n)))
#define quire_bsr(a, n) ((int)((unsigned int)(a) >> (n)))
#define quire_int2uint(x) ((unsigned int)(x))
#define quire_byte2int(b) ((int)(unsigned char)(b))

/* Integer arithmetic for ATS2 freestanding (replaces prelude templates) */
#define quire_add(a, b) ((a) + (b))
#define quire_mul(a, b) ((a) * (b))
#define quire_gte(a, b) ((a) >= (b))
#define quire_gt(a, b) ((a) > (b))
#define quire_lt(a, b) ((a) < (b))
#define quire_lte(a, b) ((a) <= (b))
#define quire_eq(a, b) ((a) == (b))
#define quire_neq(a, b) ((a) != (b))
#define quire_ptr_eq(a, b) ((a) == (b))
#define quire_sub(a, b) ((a) - (b))
#define quire_neg(a) (-(a))
#define quire_ptr_add(p, n) ((void*)((unsigned char*)(p) + (n)))

/* Null pointer for proof construction */
#define quire_null_ptr() ((void*)0)

#endif /* QUIRE_RUNTIME_H */
