/* runtime.c -- Freestanding WASM runtime: free-list allocator + memory ops */

/* Heap: grows upward from __heap_base (set by linker) */
extern unsigned char __heap_base;
static unsigned char *heap_ptr = &__heap_base;

/* --- Free-list allocator with size classes ---
 *
 * Block layout:  [header: 8 bytes][user area ...]
 *                                 ^-- returned by malloc
 *
 * Header stores usable size (4 bytes) + 4 bytes padding so the user
 * pointer stays 8-byte aligned when the block start is 8-byte aligned.
 *
 * Free blocks: first word of user area is the next-free pointer.
 * No separate metadata -- the chain lives inside freed blocks.
 *
 * Size classes: 32, 128, 512, 4096.  Anything larger goes to a single
 * oversized free list with first-fit (block_size >= n && <= 2*n).
 */

#define WARD_HEADER 8
#define WARD_NBUCKET 4

static const unsigned int ward_bsz[WARD_NBUCKET] = { 32, 128, 512, 4096 };
static void *ward_fl[WARD_NBUCKET] = { 0, 0, 0, 0 };
static void *ward_fl_over = 0;

static inline unsigned int ward_hdr_read(void *p) {
    return *(unsigned int *)((char *)p - WARD_HEADER);
}

static inline void ward_hdr_write(void *p, unsigned int sz) {
    *(unsigned int *)((char *)p - WARD_HEADER) = sz;
}

static inline int ward_bucket(unsigned int n) {
    if (n <= 32)   return 0;
    if (n <= 128)  return 1;
    if (n <= 512)  return 2;
    if (n <= 4096) return 3;
    return -1;
}

static void *ward_bump(unsigned int usable) {
    unsigned long a = (unsigned long)heap_ptr;
    a = (a + 7u) & ~7u;                       /* align block start */
    *(unsigned int *)a = usable;               /* write size header */
    void *p = (void *)(a + WARD_HEADER);       /* user pointer      */
    heap_ptr = (unsigned char *)(a + WARD_HEADER + usable);
    return p;
}

void *malloc(int size) {
    if (size <= 0) size = 1;
    unsigned int n = (unsigned int)size;

    /* Bucketed path */
    int b = ward_bucket(n);
    if (b >= 0) {
        unsigned int bsz = ward_bsz[b];
        void *p;
        if (ward_fl[b]) {
            p = ward_fl[b];
            ward_fl[b] = *(void **)p;
        } else {
            p = ward_bump(bsz);
        }
        memset(p, 0, bsz);
        return p;
    }

    /* Oversized: first-fit where block_size >= n && block_size <= 2*n */
    void **prev = &ward_fl_over;
    void *cur = ward_fl_over;
    while (cur) {
        unsigned int bsz = ward_hdr_read(cur);
        if (bsz >= n && bsz <= 2 * n) {
            *prev = *(void **)cur;
            memset(cur, 0, bsz);
            return cur;
        }
        prev = (void **)cur;
        cur = *(void **)cur;
    }

    /* No fit -- bump */
    void *p = ward_bump(n);
    memset(p, 0, n);
    return p;
}

void free(void *ptr) {
    if (!ptr) return;
    unsigned int sz = ward_hdr_read(ptr);
    int b = ward_bucket(sz);
    if (b >= 0 && ward_bsz[b] == sz) {
        *(void **)ptr = ward_fl[b];
        ward_fl[b] = ptr;
    } else {
        *(void **)ptr = ward_fl_over;
        ward_fl_over = ptr;
    }
}

void *memset(void *s, int c, unsigned int n) {
    unsigned char *p = (unsigned char *)s;
    unsigned char byte = (unsigned char)c;
    while (n--) *p++ = byte;
    return s;
}

void *memcpy(void *dst, const void *src, unsigned int n) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) *d++ = *s++;
    return dst;
}

/* DOM state global — single-instance for ward_dom_store/ward_dom_load */
static void *_ward_dom_stored = 0;
void ward_dom_global_set(void *p) { _ward_dom_stored = p; }
void *ward_dom_global_get(void) { return _ward_dom_stored; }

/* IDB result stash — JS stores malloc'd ptr here, ATS2 recovers via ward_idb_get_result */
static void *_ward_idb_stash_ptr = 0;
static int _ward_idb_stash_len = 0;
void ward_idb_stash_set(void *p, int len) {
    _ward_idb_stash_ptr = p; _ward_idb_stash_len = len;
}
void *ward_idb_stash_get_ptr(void) { return _ward_idb_stash_ptr; }

/* Bridge stash — shared by fetch, file, decompress, notify, listener */
static void *_ward_bridge_stash_ptr = 0;
static int _ward_bridge_stash_int[4] = {0};
void ward_bridge_stash_set_ptr(void *p) { _ward_bridge_stash_ptr = p; }
void *ward_bridge_stash_get_ptr(void) { return _ward_bridge_stash_ptr; }
void ward_bridge_stash_set_int(int slot, int v) { _ward_bridge_stash_int[slot] = v; }
int ward_bridge_stash_get_int(int slot) { return _ward_bridge_stash_int[slot]; }

/* Measure stash — 6 slots for x, y, w, h, top, left */
static int _ward_measure[6] = {0};
void ward_measure_set(int slot, int v) { _ward_measure[slot] = v; }
int ward_measure_get(int slot) { return _ward_measure[slot]; }

/* Listener table — max 64 listeners */
#define WARD_MAX_LISTENERS 64
static void *_ward_listener_table[WARD_MAX_LISTENERS] = {0};
void ward_listener_set(int id, void *cb) {
    if (id >= 0 && id < WARD_MAX_LISTENERS) _ward_listener_table[id] = cb;
}
void *ward_listener_get(int id) {
    if (id >= 0 && id < WARD_MAX_LISTENERS) return _ward_listener_table[id];
    return (void*)0;
}

/* Callback registry — max 128 entries */
#define WARD_MAX_CALLBACKS 128
static int _ward_cb_ids[WARD_MAX_CALLBACKS];
static void *_ward_cb_fns[WARD_MAX_CALLBACKS];
static void *_ward_cb_ctx[WARD_MAX_CALLBACKS];
static int _ward_cb_count = 0;

int ward_cb_get_id(int idx) { return _ward_cb_ids[idx]; }
void ward_cb_set_id(int idx, int id) { _ward_cb_ids[idx] = id; }
void *ward_cb_get_fn(int idx) { return _ward_cb_fns[idx]; }
void ward_cb_set_fn(int idx, void *fn) { _ward_cb_fns[idx] = fn; }
void *ward_cb_get_ctx(int idx) { return _ward_cb_ctx[idx]; }
void ward_cb_set_ctx(int idx, void *ctx) { _ward_cb_ctx[idx] = ctx; }
int ward_cb_get_count(void) { return _ward_cb_count; }
void ward_cb_set_count(int n) { _ward_cb_count = n; }
