/* repro_runtime.c -- Exact copy of ward runtime.c allocator for standalone repro.
 * Compiled as a separate translation unit with LTO to match quire's build. */

extern unsigned char __heap_base;
static unsigned char *heap_ptr = &__heap_base;

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

static void *ward_bump(unsigned int usable) {
    unsigned long a = (unsigned long)heap_ptr;
    a = (a + 7u) & ~7u;
    unsigned long end = a + WARD_HEADER + usable;
    unsigned long limit = (unsigned long)__builtin_wasm_memory_size(0) * 65536UL;
    if (end > limit) {
        unsigned long pages = (end - limit + 65535UL) / 65536UL;
        if (__builtin_wasm_memory_grow(0, pages) == (unsigned long)(-1))
            return (void*)0;
    }
    *(unsigned int *)a = usable;
    void *p = (void *)(a + WARD_HEADER);
    heap_ptr = (unsigned char *)end;
    return p;
}

void *malloc(int size) {
    if (size <= 0) size = 1;
    unsigned int n = (unsigned int)size;

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
