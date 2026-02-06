/* runtime.c - minimal C runtime for freestanding WASM
 *
 * Provides:
 * - Bump allocator (malloc/free/calloc)
 * - Memory operations (memcpy/memset/memmove/memcmp)
 * - Shared buffers for bridge communication
 */

typedef __SIZE_TYPE__ size_t;

#define HEAP_SIZE (1 << 20)  /* 1 MB initial heap */

static unsigned char __heap[HEAP_SIZE];
static size_t __heap_offset = 0;

void* malloc(size_t size) {
    size = (size + 7) & ~7;  /* 8-byte align */
    if (__heap_offset + size > HEAP_SIZE) return 0;
    void* ptr = &__heap[__heap_offset];
    __heap_offset += size;
    return ptr;
}

void free(void* ptr) {
    /* bump allocator: free is a no-op */
    /* safe because ATS2 linear types prevent use-after-free */
    (void)ptr;
}

void* calloc(size_t n, size_t size) {
    size_t total = n * size;
    void* ptr = malloc(total);
    if (ptr) {
        unsigned char* d = (unsigned char*)ptr;
        for (size_t i = 0; i < total; i++) d[i] = 0;
    }
    return ptr;
}

/* Manual byte loops to avoid __builtin_* lowering to recursive calls
 * in freestanding WASM (clang may emit memcpy calls for __builtin_memcpy). */

void* memcpy(void* dst, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dst;
    const unsigned char* s = (const unsigned char*)src;
    for (size_t i = 0; i < n; i++) d[i] = s[i];
    return dst;
}

void* memset(void* dst, int c, size_t n) {
    unsigned char* d = (unsigned char*)dst;
    for (size_t i = 0; i < n; i++) d[i] = (unsigned char)c;
    return dst;
}

void* memmove(void* dst, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dst;
    const unsigned char* s = (const unsigned char*)src;
    if (d < s) {
        for (size_t i = 0; i < n; i++) d[i] = s[i];
    } else {
        for (size_t i = n; i > 0; i--) d[i-1] = s[i-1];
    }
    return dst;
}

int memcmp(const void* a, const void* b, size_t n) {
    const unsigned char* pa = (const unsigned char*)a;
    const unsigned char* pb = (const unsigned char*)b;
    for (size_t i = 0; i < n; i++) {
        if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
    }
    return 0;
}

/* Shared buffers - addresses exported to bridge */
static unsigned char event_buffer[256];
static unsigned char diff_buffer[4096];
static unsigned char fetch_buffer[16384];
static unsigned char string_buffer[4096];

unsigned char* get_event_buffer_ptr(void) { return event_buffer; }
unsigned char* get_diff_buffer_ptr(void)  { return diff_buffer; }
unsigned char* get_fetch_buffer_ptr(void) { return fetch_buffer; }
unsigned char* get_string_buffer_ptr(void) { return string_buffer; }

/* DOM next-node-id state (WASM owns the ID space, 1 is reserved for root) */
static unsigned int dom_next_node_id = 2;
unsigned int get_dom_next_node_id(void) { return dom_next_node_id; }
void set_dom_next_node_id(unsigned int v) { dom_next_node_id = v; }
