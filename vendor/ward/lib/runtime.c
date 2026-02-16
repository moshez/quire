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
    unsigned long end = a + WARD_HEADER + usable;
    unsigned long limit = (unsigned long)__builtin_wasm_memory_size(0) * 65536UL;
    if (end > limit) {
        unsigned long pages = (end - limit + 65535UL) / 65536UL;
        if (__builtin_wasm_memory_grow(0, pages) == (unsigned long)(-1))
            return (void*)0; /* memory.grow failed — let caller handle OOM */
    }
    *(unsigned int *)a = usable;               /* write size header */
    void *p = (void *)(a + WARD_HEADER);       /* user pointer      */
    heap_ptr = (unsigned char *)end;
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

/* Bridge int stash — 4 slots for stash IDs and metadata */
static int _ward_bridge_stash_int[4] = {0};
void ward_bridge_stash_set_int(int slot, int v) { _ward_bridge_stash_int[slot] = v; }
int ward_bridge_stash_get_int(int slot) { return _ward_bridge_stash_int[slot]; }

/* Measure stash — 6 slots for x, y, w, h, top, left */
static int _ward_measure[6] = {0};
void ward_measure_set(int slot, int v) { _ward_measure[slot] = v; }
int ward_measure_get(int slot) { return _ward_measure[slot]; }

/* Listener table — max 128 listeners */
#define WARD_MAX_LISTENERS 128
static void *_ward_listener_table[WARD_MAX_LISTENERS] = {0};
void ward_listener_set(int id, void *cb) {
    if (id >= 0 && id < WARD_MAX_LISTENERS) _ward_listener_table[id] = cb;
}
void *ward_listener_get(int id) {
    if (id >= 0 && id < WARD_MAX_LISTENERS) return _ward_listener_table[id];
    return (void*)0;
}

/* Resolver stash — linear: each slot consumed exactly once */
#define WARD_MAX_RESOLVERS 64
static void *_ward_resolver_table[WARD_MAX_RESOLVERS] = {0};

int ward_resolver_stash(void *resolver) {
    for (int i = 0; i < WARD_MAX_RESOLVERS; i++) {
        if (!_ward_resolver_table[i]) {
            _ward_resolver_table[i] = resolver;
            return i;
        }
    }
    return -1; /* resolver table full — 64 concurrent async ops exceeded */
}

void *ward_resolver_unstash(int id) {
    if (id < 0 || id >= WARD_MAX_RESOLVERS) return (void*)0;
    void *r = _ward_resolver_table[id];
    _ward_resolver_table[id] = 0; /* clear-on-take: linear consumption */
    return r; /* NULL if already consumed or never stashed */
}

/* Combined unstash + resolve — safe against bad IDs from JS.
   If ID is invalid or already consumed, silently no-ops. */
void ward_resolver_fire(int id, int value) {
    void *r = ward_resolver_unstash(id);
    if (r) _ward_resolve_chain(r, (void*)(long)value);
}
