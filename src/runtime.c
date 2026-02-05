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
    void* ptr = malloc(n * size);
    if (ptr) __builtin_memset(ptr, 0, n * size);
    return ptr;
}

void* memcpy(void* dst, const void* src, size_t n) {
    return __builtin_memcpy(dst, src, n);
}

void* memset(void* dst, int c, size_t n) {
    return __builtin_memset(dst, c, n);
}

void* memmove(void* dst, const void* src, size_t n) {
    return __builtin_memmove(dst, src, n);
}

int memcmp(const void* a, const void* b, size_t n) {
    return __builtin_memcmp(a, b, n);
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
