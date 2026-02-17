/* ward_prelude.h -- C-level primitives for ward (native build) */
#ifndef WARD_PRELUDE_H
#define WARD_PRELUDE_H

#include <stdlib.h>
#include <string.h>

/* Enable libc malloc/free for ATS2 datavtype constructors */
#define ATS_MEMALLOC_LIBC

/* All ward viewtypes are pointers at runtime */
#define ward_arr(...) atstype_ptrk
#define ward_arr_frozen(...) atstype_ptrk
#define ward_arr_borrow(...) atstype_ptrk
#define ward_safe_text(...) atstype_ptrk
#define ward_text_builder(...) atstype_ptrk
#define ward_text_result(...) atstype_ptrk
#define ward_safe_content_text(...) atstype_ptrk
#define ward_content_text_builder(...) atstype_ptrk
#define ward_arena(...) atstype_ptrk
#define ward_arena_token(...) atstype_ptrk

/* Promise types */
#define ward_promise(...) atstype_ptrk
#define ward_promise_resolver(...) atstype_ptrk

/* Promise chain resolution (implemented in promise.dats) */
void _ward_resolve_chain(void *p, void *v);

/* Promise field access — direct struct access for _ward_resolve_chain.
   Layout matches postiats_tysum for promise_mk(state, value, cb, chain).
   These helpers let _ward_resolve_chain avoid ATS2 datavtype casting
   for the "user holds reference" case, eliminating [U4] forget. */
static inline int _ward_promise_get_state_tag(void *p) {
    return (int)(long)(((void**)p)[0]);
}
static inline void *_ward_promise_get_value(void *p) {
    return ((void**)p)[1];
}
static inline void *_ward_promise_get_cb(void *p) {
    return ((void**)p)[2];
}
static inline void *_ward_promise_get_chain(void *p) {
    return ((void**)p)[3];
}
static inline void _ward_promise_set_resolved(void *p, void *value) {
    ((void**)p)[0] = (void*)2;  /* PState_resolved tag */
    ((void**)p)[1] = value;
}
static inline void _ward_promise_set_chain(void *p, void *chain) {
    ((void**)p)[3] = chain;
}

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
static inline void ward_dom_flush(void *buf, int len) {
  /* stub — in WASM, this calls the JS bridge */
}
static inline void ward_js_set_image_src(int n, void *d, int dl, void *m, int ml) {
  /* stub — in WASM, this calls the JS bridge */
}

/* Bridge int stash stubs (native build parity with runtime.c) */
static int _ward_bridge_stash_int[4] = {0};
static inline void ward_bridge_stash_set_int(int slot, int v) { _ward_bridge_stash_int[slot] = v; }
static inline int ward_bridge_stash_get_int(int slot) { return _ward_bridge_stash_int[slot]; }

/* JS data stash stub (native build — no-op) */
static inline void ward_js_stash_read(int stash_id, void *dest, int len) { /* stub */ }

/* Arena stubs (native build parity with runtime.c) */
static inline void *ward_arena_create(int max_size) {
    void *p = malloc(max_size + 8);
    if (!p) return (void*)0;
    *(int *)p = max_size;
    *((int *)p + 1) = 0;
    memset((char *)p + 8, 0, max_size);
    return p;
}
static inline void *ward_arena_alloc(void *arena, int size) {
    int max_size = *(int *)arena;
    int used = *((int *)arena + 1);
    used = (used + 7) & ~7;
    if (used + size > max_size) return (void*)0;
    *((int *)arena + 1) = used + size;
    return (char *)arena + 8 + used;
}
static inline void ward_arena_destroy(void *arena) { free(arena); }

/* Measure stash stubs */
static int _ward_measure[6] = {0};
static inline void ward_measure_set(int slot, int v) { _ward_measure[slot] = v; }
static inline int ward_measure_get(int slot) { return _ward_measure[slot]; }

/* Listener table stubs */
#define WARD_MAX_LISTENERS 128
static void *_ward_listener_table[WARD_MAX_LISTENERS] = {0};
static inline void ward_listener_set(int id, void *cb) {
  if (id >= 0 && id < WARD_MAX_LISTENERS) _ward_listener_table[id] = cb;
}
static inline void *ward_listener_get(int id) {
  if (id >= 0 && id < WARD_MAX_LISTENERS) return _ward_listener_table[id];
  return (void*)0;
}

/* Resolver stash stubs (native build) */
#define WARD_MAX_RESOLVERS 64
static void *_ward_resolver_table[WARD_MAX_RESOLVERS] = {0};
static inline int ward_resolver_stash(void *resolver) {
    for (int i = 0; i < WARD_MAX_RESOLVERS; i++) {
        if (!_ward_resolver_table[i]) { _ward_resolver_table[i] = resolver; return i; }
    }
    return -1; /* resolver table full — 64 concurrent async ops exceeded */
}
static inline void *ward_resolver_unstash(int id) {
    if (id < 0 || id >= WARD_MAX_RESOLVERS) return (void*)0;
    void *r = _ward_resolver_table[id]; _ward_resolver_table[id] = 0; return r;
}
extern void _ward_resolve_chain(void *p, void *v);
static inline void ward_resolver_fire(int id, int value) {
    void *r = ward_resolver_unstash(id);
    if (r) _ward_resolve_chain(r, (void*)(long)value);
}

#endif /* WARD_PRELUDE_H */
