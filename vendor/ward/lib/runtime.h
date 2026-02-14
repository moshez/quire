/* runtime.h -- Freestanding WASM runtime for ward */
/* Replaces ATS2 pats_ccomp_{basics,typedefs,instrset}.h for --target=wasm32 */
#ifndef WARD_RUNTIME_H
#define WARD_RUNTIME_H

/* === Type definitions (pats_ccomp_typedefs.h) === */

typedef void atstype_void;
typedef void atsvoid_t0ype;

typedef int atstype_int;
typedef unsigned int atstype_uint;
typedef long int atstype_lint;
typedef unsigned long int atstype_ulint;
typedef long long int atstype_llint;
typedef unsigned long long int atstype_ullint;
typedef short int atstype_sint;
typedef unsigned short int atstype_usint;

typedef atstype_lint atstype_ssize;
typedef atstype_ulint atstype_size;

typedef int atstype_bool;
typedef unsigned char atstype_byte;
typedef char atstype_char;
typedef signed char atstype_schar;
typedef unsigned char atstype_uchar;
typedef char *atstype_string;
typedef char *atstype_stropt;
typedef char *atstype_strptr;
typedef void *atstype_ptr;
typedef void *atstype_ptrk;
typedef void *atstype_ref;
typedef void *atstype_boxed;
typedef void *atstype_datconptr;
typedef void *atstype_datcontyp;
typedef void *atstype_arrptr;
typedef void *atstype_funptr;
typedef void *atstype_cloptr;

#define atstkind_type(tk) tk
#define atstkind_t0ype(tk) tk

#ifndef _ATSTYPE_VAR_SIZE_
#define _ATSTYPE_VAR_SIZE_ 0X10000
#endif
typedef struct { char _[_ATSTYPE_VAR_SIZE_]; } atstype_var[0];

#define atstyvar_type(a) atstype_var
#define atstybox_type(hit) atstype_boxed
#define atsrefarg0_type(hit) hit
#define atsrefarg1_type(hit) atstype_ref

/* === Basics (pats_ccomp_basics.h) === */

#define atsbool_true 1
#define atsbool_false 0
#define atsptr_null ((void*)0)
#define the_atsptr_null ((void*)0)

#define ATSstruct struct

#define ATSextern() extern
#define ATSstatic() static
#define ATSinline() static inline

#define ATSdynload()
#define ATSdynloadflag_sta(flag)
#define ATSdynloadflag_ext(flag) extern int flag
#define ATSdynloadflag_init(flag) int flag = 0
#define ATSdynloadflag_minit(flag) int flag = 0
#define ATSdynloadset(flag) flag = 1
#define ATSdynloadfcall(dynloadfun) dynloadfun()

#define ATSassume(flag) void *flag = (void*)0

#define ATSdyncst_mac(d2c)
#define ATSdyncst_castfn(d2c)
#define ATSdyncst_extfun(d2c, targs, tres) extern tres d2c targs
#define ATSdyncst_stafun(d2c, targs, tres) static tres d2c targs
#define ATSdyncst_valimp(d2c, type) type d2c
#define ATSdyncst_valdec(d2c, type) extern type d2c

/* === Instruction set (pats_ccomp_instrset.h) === */

#define ATSif(x) if(x)
#define ATSthen()
#define ATSelse() else
#define ATSifthen(x) if(x)
#define ATSifnthen(x) if(!(x))

#define ATSreturn(x) return(x)
#define ATSreturn_void(x) return

#define ATSfunbody_beg()
#define ATSfunbody_end()

#define ATSPMVint(i) i
#define ATSPMVintrep(rep) (rep)
#define ATSPMVbool_true() atsbool_true
#define ATSPMVbool_false() atsbool_false
#define ATSPMVchar(c) (c)
#define ATSPMVstring(str) (str)
#define ATSPMVi0nt(tok) (tok)
#define ATSPMVempty() /*empty*/
#define ATSPMVextval(name) (name)
#define ATSPMVptrof(lval) (&(lval))
#define ATSPMVptrof_void(lval) ((void*)0)
#define ATSPMVrefarg0(val) (val)
#define ATSPMVrefarg1(ref) (ref)
#define ATSPMVsizeof(hit) (sizeof(hit))
#define ATSPMVfunlab(flab) (flab)
#define ATSPMVcastfn(d2c, hit, arg) ((hit)arg)
#define ATSPMVtyrep(rep) (rep)

#define ATStyclo() struct{ void *cfun; }
#define ATSfunclo_fun(pmv, targs, tres) ((tres(*)targs)(pmv))
#define ATSfunclo_clo(pmv, targs, tres) ((tres(*)targs)(((ATStyclo()*)pmv)->cfun))

#define ATSfuncall(fun, funarg) (fun)funarg
#define ATSextfcall(fun, funarg) (fun)funarg
#define ATSextmcall(obj, mtd, funarg) (obj->mtd)funarg

#define ATStmpdec(tmp, hit) hit tmp
#define ATStmpdec_void(tmp)
#define ATSstatmpdec(tmp, hit) static hit tmp
#define ATSstatmpdec_void(tmp)

#define ATSderef(pmv, hit) (*(hit*)pmv)

#define ATSCKnot(x) ((x)==0)
#define ATSCKiseqz(x) ((x)==0)
#define ATSCKisneqz(x) ((x)!=0)
#define ATSCKptriscons(x) (0 != (void*)(x))
#define ATSCKptrisnull(x) (0 == (void*)(x))

#define ATSINSlab(lab) lab
#define ATSINSgoto(lab) goto lab
#define ATSINSflab(flab) flab
#define ATSINSfgoto(flab) goto flab

#define ATSINSmove(tmp, val) (tmp = val)
#define ATSINSpmove(tmp, hit, val) (*(hit*)tmp = val)
#define ATSINSmove_void(tmp, command) command
#define ATSINSpmove_void(tmp, hit, command) command
#define ATSINSmove_nil(tmp) (tmp = ((void*)0))

#define ATSSELfltrec(pmv, tyrec, lab) ((pmv).lab)
#define ATSSELcon(pmv, tycon, lab) (((tycon*)(pmv))->lab)

#define ATSINSmove_con1_beg()
#define ATSINSmove_con1_new(tmp, tycon) (tmp = ATS_MALLOC(sizeof(tycon)))
#define ATSINSstore_con1_ofs(tmp, tycon, lab, val) (((tycon*)(tmp))->lab = val)
#define ATSINSmove_con1_end()
#define ATSINSfreecon(ptr) ATS_MFREE(ptr)

#define ATSSELrecsin(pmv, tyrec, lab) (pmv)
#define ATSINSstore_con1_tag(dst, tag) (((int*)(dst))[0] = (tag))
#define ATSINSmove_con0(dst, tag) ((dst) = (void*)(tag))
#define ATSCKpat_con0(p, tag) ((p) == (void*)(tag))
#define ATSCKpat_con1(p, tag) (((int*)(p))[0] == (tag))

#define ATSINSmove_fltrec_beg()
#define ATSINSmove_fltrec_end()
#define ATSINSstore_fltrec_ofs(tmp, tyrec, lab, val) ((tmp).lab = val)

#define ATSINSload(tmp, pmv) (tmp = pmv)
#define ATSINSstore(pmv1, pmv2) (pmv1 = pmv2)
#define ATSINSxstore(tmp, pmv1, pmv2) (tmp = pmv1, pmv1 = pmv2, pmv2 = tmp)

#define ATStailcal_beg() do {
#define ATStailcal_end() } while(0) ;
#define ATSINSmove_tlcal(apy, tmp) (apy = tmp)
#define ATSINSargmove_tlcal(arg, apy) (arg = apy)

#define ATSbranch_beg()
#define ATSbranch_end() break ;
#define ATScaseof_beg() do {
#define ATScaseof_end() } while(0) ;

#define ATSextcode_beg()
#define ATSextcode_end()

/* === Prelude function macros (used by template instantiations) === */

#define atspre_g1uint2int_size_int(x) ((int)(x))
#define atspre_g0int_add_int(x, y) ((x) + (y))
#define atspre_g1int_mul_int(x, y) ((x) * (y))
#define atspre_g0int2uint_int_size(x) ((atstype_size)(x))
#define atspre_g0uint_mul_size(x, y) ((x) * (y))
#define atspre_add_ptr0_bsz(p, n) ((void*)((char*)(p) + (n)))
#define atspre_g1int2int_int_int(x) (x)
#define atspre_g1int_lt_int(x, y) ((x) < (y))
#define atspre_g1int_add_int(x, y) ((x) + (y))
#define atspre_char2int1(c) ((int)(c))
#define atspre_g0int2int_int_int(x) (x)
#define atspre_g0int_gt_int(x, y) ((x) > (y))
#define atspre_g1ofg0_int(x) (x)
#define atspre_g0ofg1_int(x) (x)
#define atspre_g1int_gt_int(x, y) ((x) > (y))
#define atspre_g1int_gte_int(x, y) ((x) >= (y))
#define atspre_g1int_lte_int(x, y) ((x) <= (y))
#define atspre_g1int_sub_int(x, y) ((x) - (y))
#define atspre_g1int_neg_int(x) (-(x))
#define atspre_g0int_gte_int(x, y) ((x) >= (y))
#define atspre_g0int_lte_int(x, y) ((x) <= (y))
#define atspre_g0int_eq_int(x, y) ((x) == (y))
#define atspre_g0int_mul_int(x, y) ((x) * (y))
#define atspre_g0int_sub_int(x, y) ((x) - (y))
#define atspre_g0int_neq_int(x, y) ((x) != (y))
#define atspre_g0int_lt_int(x, y) ((x) < (y))
#define atspre_g0int_div_int(x, y) ((x) / (y))
#define atspre_g0int_mod_int(x, y) ((x) % (y))
#define atspre_g1int_div_int(x, y) ((x) / (y))
#define atspre_g1int_eq_int(x, y) ((x) == (y))
#define atspre_g1int_neq_int(x, y) ((x) != (y))
#define atspre_g0int_asl_int(x, n) ((x) << (n))
#define atspre_g0int_asr_int(x, n) ((x) >> (n))
#define atspre_g0int_lor_int(x, y) ((x) | (y))
#define atspre_g0int_land_int(x, y) ((x) & (y))

/* Prelude functions not in freestanding mode since CATS files are suppressed */
#define atspre_byte2int0(b) ((int)(b))
#define atspre_ptr_null() ((void*)0)
#define atspre_ptr_isnot_null(p) ((p) != 0)
#define atspre_ptr0_isnot_null atspre_ptr_isnot_null

/* === Closure support (needed for cloref1 lambdas) === */

#define ATS_MALLOC(sz) malloc(sz)
#define ATS_MFREE(ptr) free(ptr)
#define ATSINScloptr_make(tmp, sz) (tmp = ATS_MALLOC(sz))
#define ATSINScloptr_free(tmp) ATS_MFREE(tmp)

#define ATSclosurerize_beg(flab, tenvs, targs, tres)
#define ATSclosurerize_end()
#define ATSFCreturn(x) return(x)
#define ATSFCreturn_void(x) (x); return
#define ATSPMVcfunlab(knd, flab, env) (flab##__closurerize)env

/* === Ward-specific === */

/* Ward viewtypes are all pointers at runtime */
#define ward_arr(...) atstype_ptrk
#define ward_arr_frozen(...) atstype_ptrk
#define ward_arr_borrow(...) atstype_ptrk
#define ward_safe_text(...) atstype_ptrk
#define ward_text_builder(...) atstype_ptrk
#define ward_text_result(...) atstype_ptrk

/* Memory operations (implemented in runtime.c) */
void *malloc(int size);
void free(void *ptr);
void *memset(void *s, int c, unsigned int n);
void *memcpy(void *dst, const void *src, unsigned int n);
static inline void *calloc(int n, int sz) { return malloc(n * sz); }

/* Promise types */
#define ward_promise(...) atstype_ptrk
#define ward_promise_resolver(...) atstype_ptrk

/* Promise chain resolution (implemented in promise.dats) */
void _ward_resolve_chain(void *p, void *v);

/* Invoke a cloref1 closure: first word is function pointer */
static inline void *ward_cloref1_invoke(void *clo, void *arg) {
  typedef void *(*cfun)(void *clo, void *arg);
  cfun fp = *(cfun*)clo;
  return fp(clo, arg);
}

/* Self-freeing closure wrapper for linear closures (cloptr1).
   When resolve_chain invokes this via ward_cloref1_invoke, the wrapper
   invokes the real cloptr1 then frees both it and the wrapper.
   Layout: [0]=wrapper_fn_ptr, [1]=real_cloptr1 */
static inline void *_ward_cloptr1_wrapper_invoke(void *wrapper, void *arg) {
  void **w = (void **)wrapper;
  void *real_clo = w[1];
  void *result = ward_cloref1_invoke(real_clo, arg);
  free(real_clo);
  free(wrapper);
  return result;
}

static inline void *_ward_cloptr1_wrap(void *f) {
  typedef void *(*cfun)(void *, void *);
  void **wrapper = (void **)malloc(2 * sizeof(void*));
  wrapper[0] = (void *)(cfun)_ward_cloptr1_wrapper_invoke;
  wrapper[1] = f;
  return (void *)wrapper;
}

/* DOM helpers */
#define ward_dom_state(...) atstype_ptrk
#define ward_dom_stream(...) atstype_ptrk
static inline void ward_set_byte(void *p, int off, int v) {
  ((unsigned char*)p)[off] = (unsigned char)v;
}
static inline void ward_set_i32(void *p, int off, int v) {
  unsigned char *d = (unsigned char*)p + off;
  d[0] = v & 0xFF; d[1] = (v >> 8) & 0xFF;
  d[2] = (v >> 16) & 0xFF; d[3] = (v >> 24) & 0xFF;
}
static inline void ward_copy_at(void *dst, int off, const void *src, int n) {
  memcpy((char*)dst + off, src, n);
}

/* Resolver stash (implemented in runtime.c) — linear clear-on-take */
int ward_resolver_stash(void *resolver);
void *ward_resolver_unstash(int id);
void ward_resolver_fire(int id, int value);

/* Event bridge (WASM imports from JS host) */
extern void ward_set_timer(int delay_ms, int resolver_id);
extern void ward_exit(void);

/* IDB JS imports */
extern void ward_idb_js_put(void *key, int key_len, void *val, int val_len, int resolver_id);
extern void ward_idb_js_get(void *key, int key_len, int resolver_id);
extern void ward_idb_js_delete(void *key, int key_len, int resolver_id);

/* Bridge int stash (implemented in runtime.c) — 4 slots for stash IDs and metadata */
void ward_bridge_stash_set_int(int slot, int v);
int ward_bridge_stash_get_int(int slot);

/* JS data stash — WASM pulls stashed data via this import */
extern void ward_js_stash_read(int stash_id, void *dest, int len);

/* Measure stash (implemented in runtime.c) — 6 slots: x, y, w, h, top, left */
void ward_measure_set(int slot, int v);
int ward_measure_get(int slot);

/* Listener table (implemented in runtime.c) — max 128 listeners */
void ward_listener_set(int id, void *cb);
void *ward_listener_get(int id);

/* Window JS imports */
extern void ward_js_focus_window(void);
extern int ward_js_get_visibility_state(void);
extern void ward_js_log(int level, void *msg, int msg_len);

/* Navigation JS imports */
extern int ward_js_get_url(void *out, int max_len);
extern int ward_js_get_url_hash(void *out, int max_len);
extern void ward_js_set_url_hash(void *hash, int hash_len);
extern void ward_js_replace_state(void *url, int url_len);
extern void ward_js_push_state(void *url, int url_len);

/* DOM read JS imports */
extern int ward_js_measure_node(int node_id);
extern int ward_js_query_selector(void *selector, int selector_len);

/* Event listener JS imports */
extern void ward_js_add_event_listener(int node_id, void *event_type, int type_len, int listener_id);
extern void ward_js_remove_event_listener(int listener_id);
extern void ward_js_prevent_default(void);

/* Fetch JS imports */
extern void ward_js_fetch(void *url, int url_len, int resolver_id);

/* Clipboard JS imports */
extern void ward_js_clipboard_write_text(void *text, int text_len, int resolver_id);

/* File JS imports */
extern void ward_js_file_open(int input_node_id, int resolver_id);
extern int ward_js_file_read(int handle, int file_offset, int len, void *out);
extern void ward_js_file_close(int handle);

/* Decompress JS imports */
extern void ward_js_decompress(void *data, int data_len, int method, int resolver_id);
extern int ward_js_blob_read(int handle, int blob_offset, int len, void *out);
extern void ward_js_blob_free(int handle);

/* Notification/Push JS imports */
extern void ward_js_notification_request_permission(int resolver_id);
extern void ward_js_notification_show(void *title, int title_len);
extern void ward_js_push_subscribe(void *vapid, int vapid_len, int resolver_id);
extern void ward_js_push_get_subscription(int resolver_id);

/* HTML parsing JS import */
extern int ward_js_parse_html(void *html, int html_len);

/* Callback registry — WASM export, JS calls this to fire callbacks */
void ward_on_callback(int id, int payload);

/* ward_dom_flush: stub by default, WASM import when WARD_NO_DOM_STUB */
#ifndef WARD_NO_DOM_STUB
static inline void ward_dom_flush(void *buf, int len) {
  /* stub — in WASM, this calls the JS bridge */
}
#else
extern void ward_dom_flush(void *buf, int len);
#endif

#endif /* WARD_RUNTIME_H */
