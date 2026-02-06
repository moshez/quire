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

/* Primitive values */
#define ATSPMVi0nt(i) (i)
#define ATSPMVint(i) (i)
#define ATSPMVbool_true() 1
#define ATSPMVbool_false() 0
#define ATSPMVstring(s) (s)
#define ATSPMVempty() /* empty */

/* Checks */
#define ATSCKiseqz(x) ((x)==0)
#define ATSCKisneqz(x) ((x)!=0)
#define ATSCKpat_int(x, v) ((x)==(v))

/* External function declarations for mac# functions */
#define ATSdyncst_mac(f) /* external C function */
#define ATSdyncst_extfun(f, argtys, restys) /* external function */
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

#endif /* QUIRE_RUNTIME_H */
