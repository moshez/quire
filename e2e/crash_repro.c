/* crash_repro.c — Standalone reproduction for Chromium renderer crash.
 *
 * This WASM module reproduces a "Target crashed" in Chromium's renderer
 * when malloc(>4096) is called from inside a recursive function.
 *
 * Key finding from diagnostics:
 * - JS → exports.malloc(4097) works at any point
 * - WASM → malloc(4097) from inside a recursive render loop crashes
 * - WASM → malloc(4097) outside the loop (but same call depth) works
 *
 * Build:
 *   clang --target=wasm32 -O2 -nostdlib -ffreestanding \
 *     -o crash_repro.wasm crash_repro.c \
 *     -Wl,--no-entry,--export=run_repro,--export=malloc,--export=memory \
 *     -Wl,-z,stack-size=65536,--initial-memory=16777216,--max-memory=268435456
 */

/* ---- Allocator (identical to ward runtime.c) ---- */

extern unsigned char __heap_base;
static unsigned char *heap_ptr = &__heap_base;

#define WARD_HEADER 8

void *memset(void *s, int c, unsigned int n) {
    unsigned char *p = (unsigned char *)s;
    unsigned char byte = (unsigned char)c;
    while (n--) *p++ = byte;
    return s;
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
    void *p = ward_bump(n);
    memset(p, 0, n);
    return p;
}

/* ---- Imports (simulate DOM bridge) ---- */

__attribute__((import_module("env"), import_name("dom_flush")))
void dom_flush(int buf_ptr, int len);

__attribute__((import_module("env"), import_name("log_int")))
void log_int(int val);

/* ---- Simulated render buffer ---- */

/* SAX-like binary tree: opcode bytes followed by data.
 * Opcodes: 1 = ELEMENT_OPEN, 2 = TEXT, 3 = IMAGE, 4 = ELEMENT_CLOSE */
static unsigned char tree_data[256];
static int tree_len = 0;

/* ---- DOM diff buffer (simulates ward_dom_stream) ---- */

static unsigned char diff_buf[4096];
static int diff_pos = 0;
static int next_node_id = 100;

static void emit_create_element(int parent_id) {
    int nid = next_node_id++;
    /* Write a small diff to the buffer */
    if (diff_pos + 16 <= 4096) {
        diff_buf[diff_pos++] = 4; /* CREATE_ELEMENT opcode */
        diff_buf[diff_pos++] = (unsigned char)(nid & 0xFF);
        diff_buf[diff_pos++] = (unsigned char)((nid >> 8) & 0xFF);
        diff_buf[diff_pos++] = (unsigned char)(parent_id & 0xFF);
        diff_buf[diff_pos++] = (unsigned char)((parent_id >> 8) & 0xFF);
        diff_buf[diff_pos++] = 3; /* tag "div" length */
        diff_buf[diff_pos++] = 0;
        diff_buf[diff_pos++] = 0;
        diff_buf[diff_pos++] = 0;
    }
}

static void emit_set_text(int node_id) {
    if (diff_pos + 12 <= 4096) {
        diff_buf[diff_pos++] = 2; /* SET_TEXT opcode */
        diff_buf[diff_pos++] = (unsigned char)(node_id & 0xFF);
        diff_buf[diff_pos++] = (unsigned char)((node_id >> 8) & 0xFF);
        diff_buf[diff_pos++] = 5; /* text "hello" length */
        diff_buf[diff_pos++] = 0;
        diff_buf[diff_pos++] = 0;
        diff_buf[diff_pos++] = 0;
    }
}

/* ---- Recursive render loop (matches quire's render_tree_with_images) ---- */

/* This function mirrors the structure of quire's render loop:
 * - Recursive (calls itself for nested elements)
 * - Many parameters (to create a similar stack frame)
 * - Reads from a buffer
 * - Calls imported JS functions (DOM operations)
 * - On IMAGE opcode: calls malloc(4097)
 */
static int render_loop(
    unsigned char *tree, int tree_len_param,
    int pos, int len, int parent,
    int has_child, int ecnt,
    int file_handle, int max_elements,
    int depth, int extra_param)
{
    while (pos < len && ecnt < max_elements) {
        unsigned char opc = tree[pos];
        pos++;

        if (opc == 1) { /* ELEMENT_OPEN */
            emit_create_element(parent);
            int child_id = next_node_id - 1;
            ecnt++;
            /* Recurse for children */
            ecnt = render_loop(tree, tree_len_param,
                pos, len, child_id,
                0, ecnt,
                file_handle, max_elements,
                depth + 1, extra_param);
            /* Skip to after ELEMENT_CLOSE */
            int nest = 1;
            while (pos < len && nest > 0) {
                if (tree[pos] == 1) nest++;
                else if (tree[pos] == 4) nest--;
                pos++;
            }
        }
        else if (opc == 2) { /* TEXT */
            emit_set_text(parent);
        }
        else if (opc == 3) { /* IMAGE — trigger malloc(4097) */
            void *p = malloc(4097);
            /* Just leak it — this is the crash trigger */
            log_int((int)p);
        }
        else if (opc == 4) { /* ELEMENT_CLOSE */
            return ecnt;
        }
    }
    return ecnt;
}

/* ---- Build a test tree and render it ---- */

static void build_test_tree(void) {
    int i = 0;
    /* <body> */
    tree_data[i++] = 1; /* ELEMENT_OPEN */
      /* <p> */
      tree_data[i++] = 1; /* ELEMENT_OPEN */
        tree_data[i++] = 2; /* TEXT: "hello" */
      tree_data[i++] = 4; /* ELEMENT_CLOSE */
      /* <img> — triggers malloc(4097) */
      tree_data[i++] = 3; /* IMAGE */
    tree_data[i++] = 4; /* ELEMENT_CLOSE: </body> */
    tree_len = i;
}

/* ---- Exported entry point ---- */

/* Call this from JS to trigger the crash.
 * First does some DOM operations (like app init),
 * then renders the test tree. */
__attribute__((export_name("run_repro")))
int run_repro(void) {
    /* Phase 1: Simulate app init — some small allocations + DOM operations */
    void *p1 = malloc(128);
    void *p2 = malloc(512);
    void *p3 = malloc(4096);

    /* Emit some DOM diffs and flush (simulates library UI rendering) */
    emit_create_element(1);
    emit_create_element(1);
    emit_set_text(next_node_id - 1);
    dom_flush((int)diff_buf, diff_pos);
    diff_pos = 0;

    /* Phase 2: Build and render a tree with an image */
    build_test_tree();

    int ecnt = render_loop(
        tree_data, tree_len,
        0, tree_len, 1, /* pos=0, len, parent=1 */
        0, 0,           /* has_child=0, ecnt=0 */
        1, 10000,       /* file_handle=1, max_elements=10000 */
        0, 42           /* depth=0, extra_param=42 */
    );

    /* Flush remaining DOM diffs */
    dom_flush((int)diff_buf, diff_pos);
    diff_pos = 0;

    return ecnt;
}
