/* repro_render.c -- Crash reproduction: complex render loop with malloc(4097).
 *
 * This matches the key characteristics of quire's loop_280 (render_tree_with_images):
 * - 30+ local variables
 * - 165+ memory load/store operations
 * - Complex control flow with switch (compiles to br_table)
 * - Attribute parsing loops with byte-level buffer reads
 * - Multiple malloc calls from within the loop
 * - Recursive calls
 * - JS import calls (dom_flush)
 * - Helper functions called from the loop
 *
 * Build (LTO across two files, matching quire's build):
 *   clang --target=wasm32 -O2 -flto -nostdlib -ffreestanding \
 *     repro_runtime.c repro_render.c \
 *     -o crash_repro.wasm \
 *     -Wl,--no-entry,--lto-O2,--export=run_repro,--export=malloc,--export=memory \
 *     -Wl,-z,stack-size=1048576,--initial-memory=16777216,--max-memory=268435456
 */

/* ---- External declarations ---- */

extern void *malloc(int size);
extern void free(void *ptr);
extern void *memset(void *s, int c, unsigned int n);
extern void *memcpy(void *dst, const void *src, unsigned int n);

/* ---- JS imports ---- */

__attribute__((import_module("env"), import_name("dom_flush")))
void dom_flush(int buf_ptr, int len);

__attribute__((import_module("env"), import_name("log_int")))
void log_int(int val);

/* ---- DOM diff buffer (simulates ward_dom_stream) ---- */

/* 262144 bytes = 256KB, matching real ward DOM buffer */
#define DOM_BUF_SIZE 262144
static unsigned char *dom_buf = 0;
static int dom_pos = 0;
static int next_node_id = 100;

/* Auto-flush when buffer is getting full (like ward_dom_stream) */
static void dom_check_flush(int need) {
    if (dom_pos + need > DOM_BUF_SIZE) {
        dom_flush((int)dom_buf, dom_pos);
        dom_pos = 0;
    }
}

/* Create element: writes opcode + node_id + parent_id + tag bytes to diff buffer.
 * Matches ward_dom_stream_create_element complexity. */
static int dom_create_element(int parent_id, unsigned char *tree, int tag_off, int tag_len) {
    int nid = next_node_id++;
    dom_check_flush(16 + tag_len);

    /* Opcode byte */
    dom_buf[dom_pos++] = 4; /* CREATE_ELEMENT */
    /* Node ID (4 bytes LE) */
    dom_buf[dom_pos++] = (unsigned char)(nid & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((nid >> 8) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((nid >> 16) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((nid >> 24) & 0xFF);
    /* Parent ID (4 bytes LE) */
    dom_buf[dom_pos++] = (unsigned char)(parent_id & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((parent_id >> 8) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((parent_id >> 16) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((parent_id >> 24) & 0xFF);
    /* Tag length (2 bytes LE) */
    dom_buf[dom_pos++] = (unsigned char)(tag_len & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((tag_len >> 8) & 0xFF);
    /* Tag bytes */
    for (int i = 0; i < tag_len; i++) {
        dom_buf[dom_pos++] = tree[tag_off + i];
    }

    return nid;
}

/* Set text: writes opcode + node_id + text to diff buffer.
 * Allocates temporary buffer for text (matching ward pattern of alloc→freeze→set→free). */
static void dom_set_text(int node_id, unsigned char *tree, int text_off, int text_len) {
    /* Allocate temp buffer (matches ward_arr_alloc pattern) */
    unsigned char *tmp = (unsigned char *)malloc(text_len);
    memcpy(tmp, tree + text_off, text_len);

    dom_check_flush(12 + text_len);

    dom_buf[dom_pos++] = 2; /* SET_TEXT */
    dom_buf[dom_pos++] = (unsigned char)(node_id & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((node_id >> 8) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((node_id >> 16) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((node_id >> 24) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)(text_len & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((text_len >> 8) & 0xFF);
    for (int i = 0; i < text_len; i++) {
        dom_buf[dom_pos++] = tmp[i];
    }

    free(tmp);
}

/* Set attribute: writes opcode + node_id + name + value to diff buffer.
 * Allocates temporary buffer for value (matching ward pattern). */
static void dom_set_attr(int node_id,
    unsigned char *tree, int name_off, int name_len,
    int val_off, int val_len) {

    /* Allocate temp buffer for value (matches ward_arr_alloc pattern) */
    unsigned char *val_tmp = (unsigned char *)malloc(val_len);
    memcpy(val_tmp, tree + val_off, val_len);

    dom_check_flush(16 + name_len + val_len);

    dom_buf[dom_pos++] = 5; /* SET_ATTR */
    dom_buf[dom_pos++] = (unsigned char)(node_id & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((node_id >> 8) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((node_id >> 16) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((node_id >> 24) & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)(name_len & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((name_len >> 8) & 0xFF);
    for (int i = 0; i < name_len; i++) {
        dom_buf[dom_pos++] = tree[name_off + i];
    }
    dom_buf[dom_pos++] = (unsigned char)(val_len & 0xFF);
    dom_buf[dom_pos++] = (unsigned char)((val_len >> 8) & 0xFF);
    for (int i = 0; i < val_len; i++) {
        dom_buf[dom_pos++] = val_tmp[i];
    }

    free(val_tmp);
}

/* ---- Tag/attribute name lookup (simulates get_attr_by_index) ---- */

/* Tag name table (simplified version of quire's rodata tables) */
static const char *tag_names[] = {
    "div", "span", "button", "style", "h1", "h2", "h3", "p",
    "input", "label", "select", "option", "a", "img", "b", "i",
    "u", "s", "q", "em", "br", "hr", "li", "dd", "dl", "dt",
    "ol", "ul", "td", "th", "tr", "h4", "h5", "h6", "pre",
    "sub", "sup", "var", "wbr", "nav", "kbd", "code", "mark",
    "cite", "abbr", "dfn", "main", "time", "ruby", "aside",
    "small", "table", "thead", "tbody", "tfoot", "strong",
    "figure", "footer", "header", "section", "article",
    "details", "summary", "caption", "blockquote", "figcaption",
    "svg", "g", "path", "circle", "rect", "line",
    0
};

static const char *attr_names[] = {
    "class", "id", "type", "for", "accept", "href", "src", "alt",
    "title", "width", "height", "lang", "dir", "role", "tabindex",
    "colspan", "rowspan", "xmlns", "d", "fill", "stroke",
    "cx", "cy", "rx", "x", "y", "transform", "viewBox",
    "aria-label", "aria-hidden", "name", "value",
    0
};

/* Look up attribute name by index — allocates buffer (matches get_attr_by_index) */
static int get_attr_name(int index, unsigned char *out_buf) {
    if (index < 0 || index > 31) return 0;
    const char *name = attr_names[index];
    if (!name) return 0;
    int len = 0;
    while (name[len]) { out_buf[len] = name[len]; len++; }
    return len;
}

/* ---- Attribute parsing (simulates emit_attrs_noimg / emit_attrs_img) ---- */

/* Parse and emit attributes for a non-img element.
 * Recursive over attribute list in the SAX buffer.
 * Each attribute: [name_idx:1][val_len:1][val_bytes:val_len] */
static int emit_attrs(unsigned char *tree, int pos, int len,
    int node_id, int attr_count, int is_img, int *out_src_off, int *out_src_len) {

    unsigned char name_buf[64];
    int src_off = 0, src_len = 0;

    for (int a = 0; a < attr_count && pos + 2 <= len; a++) {
        int name_idx = tree[pos++];
        int val_len = tree[pos++];

        if (pos + val_len > len) break;

        int name_len = get_attr_name(name_idx, name_buf);

        /* For img elements, check if this is the "src" attribute (index 6) */
        if (is_img && name_idx == 6) {
            src_off = pos;
            src_len = val_len;
        } else if (name_len > 0 && val_len > 0) {
            /* Emit attribute to DOM diff buffer */
            dom_set_attr(node_id, tree, pos - val_len - 2, name_len,
                pos, val_len);
        }

        pos += val_len;
    }

    if (out_src_off) *out_src_off = src_off;
    if (out_src_len) *out_src_len = src_len;

    return pos;
}

/* ---- Skip nested elements (simulates skip_element_img) ---- */

static int skip_element(unsigned char *tree, int pos, int len) {
    int depth = 1;
    while (pos < len && depth > 0) {
        unsigned char opc = tree[pos++];
        if (opc == 1) {
            /* ELEMENT_OPEN: read tag_len + attrs */
            if (pos + 2 > len) break;
            int tag_len = tree[pos++];
            int attr_count = tree[pos++];
            pos += tag_len;
            for (int a = 0; a < attr_count && pos + 2 <= len; a++) {
                pos++; /* name_idx */
                int val_len = tree[pos++];
                pos += val_len;
            }
            depth++;
        }
        else if (opc == 2) { /* ELEMENT_CLOSE */
            depth--;
        }
        else if (opc == 3) { /* TEXT */
            if (pos + 2 > len) break;
            int text_len = tree[pos] | (tree[pos + 1] << 8);
            pos += 2 + text_len;
        }
        else if (opc == 4) { /* IMAGE */
            if (pos + 2 > len) break;
            int attr_count = tree[pos++];
            int img_tag_len = tree[pos++];
            pos += img_tag_len;
            for (int a = 0; a < attr_count && pos + 2 <= len; a++) {
                pos++; /* name_idx */
                int val_len = tree[pos++];
                pos += val_len;
            }
        }
    }
    return pos;
}

/* ---- The main render loop ---- */

/* This function is designed to match the complexity characteristics of quire's loop_280:
 * - 7 parameters (matching the type signature)
 * - 23+ additional local variables (for a total of 30+)
 * - Complex switch/br_table on opcodes
 * - Recursive call to itself
 * - Multiple calls to DOM stream functions (which do memory ops + JS calls)
 * - malloc(4097) in IMAGE handler
 * - Complex attribute parsing with byte-level buffer reads
 *
 * SAX binary format:
 *   ELEMENT_OPEN(1): [1][tag_len:1][attr_count:1][tag_bytes:tag_len][attrs...]
 *   ELEMENT_CLOSE(2): [2]
 *   TEXT(3): [3][text_len:2LE][text_bytes:text_len]
 *   IMAGE(4): [4][attr_count:1][tag_len:1][tag_bytes:tag_len][attrs...]
 */
static void render_loop(
    unsigned char *tree, int tree_len,
    int pos, int len, int parent,
    int has_child, int ecnt,
    int file_handle, int max_elements,
    int depth, int extra_param,
    int *out_pos, int *out_ecnt)
{
    /* Local variables to match loop_280's 23 additional locals */
    int tag_off, tag_len, attr_count;
    int child_id, text_off, text_len;
    int src_off, src_len;
    int name_idx, val_len, val_off;
    int opc, nest, skip_pos;
    unsigned char *attr_ptr;
    int attr_pos, cur_attr;
    int nid_lo, nid_hi, pid_lo, pid_hi;
    int buf_remaining, flush_needed;
    int is_whitespace, wrap_in_span;
    int saved_pos, iteration;

    iteration = 0;

    while (pos < len && ecnt < max_elements) {
        opc = tree[pos++];
        iteration++;

        switch (opc) {
        case 1: { /* ELEMENT_OPEN */
            if (pos + 2 > len) goto done;
            tag_len = tree[pos++];
            attr_count = tree[pos++];
            tag_off = pos;
            pos += tag_len;

            /* Create element in DOM */
            child_id = dom_create_element(parent, tree, tag_off, tag_len);
            ecnt++;
            has_child = 1;

            /* Parse and emit attributes */
            if (attr_count > 0) {
                pos = emit_attrs(tree, pos, len, child_id, attr_count,
                    0, (void*)0, (void*)0);
            }

            /* Recurse for children */
            {
                int child_pos = pos;
                int child_ecnt = ecnt;
                render_loop(tree, tree_len,
                    child_pos, len, child_id,
                    0, child_ecnt,
                    file_handle, max_elements,
                    depth + 1, extra_param,
                    &pos, &ecnt);
            }
            break;
        }

        case 2: /* ELEMENT_CLOSE */
            goto done;

        case 3: { /* TEXT */
            if (pos + 2 > len) goto done;
            text_len = tree[pos] | (tree[pos + 1] << 8);
            pos += 2;
            text_off = pos;

            if (text_len > 0 && text_off + text_len <= len) {
                /* Check if whitespace-only */
                is_whitespace = 1;
                for (int i = 0; i < text_len; i++) {
                    unsigned char c = tree[text_off + i];
                    if (c != 0x20 && c != 0x0A && c != 0x0D && c != 0x09) {
                        is_whitespace = 0;
                        break;
                    }
                }

                if (!is_whitespace) {
                    if (has_child) {
                        /* Wrap in span to avoid destroying siblings */
                        int span_id = dom_create_element(parent, tree, tag_off, 0);
                        dom_set_text(span_id, tree, text_off, text_len);
                    } else {
                        dom_set_text(parent, tree, text_off, text_len);
                    }
                    has_child = 1;
                }
            }

            pos = text_off + text_len;
            break;
        }

        case 4: { /* IMAGE — this triggers the crash */
            if (pos + 2 > len) goto done;
            attr_count = tree[pos++];
            tag_len = tree[pos++];
            tag_off = pos;
            pos += tag_len;

            /* Create img element */
            child_id = dom_create_element(parent, tree, tag_off, tag_len);
            ecnt++;
            has_child = 1;

            /* Parse attributes, extract src */
            src_off = 0;
            src_len = 0;
            if (attr_count > 0) {
                pos = emit_attrs(tree, pos, len, child_id, attr_count,
                    1, &src_off, &src_len);
            }

            /* THE CRASH TRIGGER: malloc(4097) from inside the render loop.
             * In the real app, this is try_set_image → ward_arr_alloc.
             * This allocation (>4096 bytes) crashes Chromium's renderer
             * when called from inside this recursive function. */
            if (src_len > 0) {
                void *img_buf = malloc(4097);
                log_int((int)img_buf);
                /* Leak intentionally — matches diagnostic 10 behavior */
            }
            break;
        }

        default:
            /* Unknown opcode — skip */
            break;
        }
    }

done:
    *out_pos = pos;
    *out_ecnt = ecnt;
}

/* ---- Build a test tree with enough complexity ---- */

static unsigned char tree_buf[8192];

static int build_test_tree(void) {
    int i = 0;

    /* Simulate a typical EPUB chapter:
     * <body>
     *   <div class="chapter">
     *     <h1>Title</h1>
     *     <p>First paragraph with some text content here.</p>
     *     <p>Second paragraph.</p>
     *     <img src="image.jpg" alt="photo">
     *     <p>Third paragraph after image.</p>
     *   </div>
     * </body>
     */

    /* <body> */
    tree_buf[i++] = 1; /* ELEMENT_OPEN */
    tree_buf[i++] = 4; /* tag_len = 4 ("body") */
    tree_buf[i++] = 0; /* attr_count = 0 */
    tree_buf[i++] = 'b'; tree_buf[i++] = 'o'; tree_buf[i++] = 'd'; tree_buf[i++] = 'y';

      /* <div class="chapter"> */
      tree_buf[i++] = 1; /* ELEMENT_OPEN */
      tree_buf[i++] = 3; /* tag_len = 3 ("div") */
      tree_buf[i++] = 1; /* attr_count = 1 */
      tree_buf[i++] = 'd'; tree_buf[i++] = 'i'; tree_buf[i++] = 'v';
      /* attr: class="chapter" */
      tree_buf[i++] = 0;  /* name_idx = 0 (class) */
      tree_buf[i++] = 7;  /* val_len = 7 */
      tree_buf[i++] = 'c'; tree_buf[i++] = 'h'; tree_buf[i++] = 'a';
      tree_buf[i++] = 'p'; tree_buf[i++] = 't'; tree_buf[i++] = 'e';
      tree_buf[i++] = 'r';

        /* <h1> */
        tree_buf[i++] = 1; /* ELEMENT_OPEN */
        tree_buf[i++] = 2; /* tag_len */
        tree_buf[i++] = 0; /* attr_count */
        tree_buf[i++] = 'h'; tree_buf[i++] = '1';
          /* "Chapter Title" */
          tree_buf[i++] = 3; /* TEXT */
          tree_buf[i++] = 13; tree_buf[i++] = 0; /* text_len = 13 */
          { const char *t = "Chapter Title"; for (int j = 0; j < 13; j++) tree_buf[i++] = t[j]; }
        tree_buf[i++] = 2; /* ELEMENT_CLOSE </h1> */

        /* <p> */
        tree_buf[i++] = 1;
        tree_buf[i++] = 1; tree_buf[i++] = 0;
        tree_buf[i++] = 'p';
          tree_buf[i++] = 3;
          tree_buf[i++] = 45; tree_buf[i++] = 0;
          { const char *t = "First paragraph with some text content here."; for (int j = 0; j < 45; j++) tree_buf[i++] = t[j]; }
        tree_buf[i++] = 2;

        /* <p> */
        tree_buf[i++] = 1;
        tree_buf[i++] = 1; tree_buf[i++] = 0;
        tree_buf[i++] = 'p';
          tree_buf[i++] = 3;
          tree_buf[i++] = 17; tree_buf[i++] = 0;
          { const char *t = "Second paragraph."; for (int j = 0; j < 17; j++) tree_buf[i++] = t[j]; }
        tree_buf[i++] = 2;

        /* <img src="image.jpg" alt="photo"> — the crash trigger */
        tree_buf[i++] = 4; /* IMAGE */
        tree_buf[i++] = 2; /* attr_count = 2 */
        tree_buf[i++] = 3; /* tag_len = 3 ("img") */
        tree_buf[i++] = 'i'; tree_buf[i++] = 'm'; tree_buf[i++] = 'g';
        /* attr: src="image.jpg" (name_idx 6 = src) */
        tree_buf[i++] = 6;  /* name_idx = 6 (src) */
        tree_buf[i++] = 9;  /* val_len = 9 */
        tree_buf[i++] = 'i'; tree_buf[i++] = 'm'; tree_buf[i++] = 'a';
        tree_buf[i++] = 'g'; tree_buf[i++] = 'e'; tree_buf[i++] = '.';
        tree_buf[i++] = 'j'; tree_buf[i++] = 'p'; tree_buf[i++] = 'g';
        /* attr: alt="photo" (name_idx 7 = alt) */
        tree_buf[i++] = 7;  /* name_idx = 7 (alt) */
        tree_buf[i++] = 5;  /* val_len = 5 */
        tree_buf[i++] = 'p'; tree_buf[i++] = 'h'; tree_buf[i++] = 'o';
        tree_buf[i++] = 't'; tree_buf[i++] = 'o';

        /* <p> after image */
        tree_buf[i++] = 1;
        tree_buf[i++] = 1; tree_buf[i++] = 0;
        tree_buf[i++] = 'p';
          tree_buf[i++] = 3;
          tree_buf[i++] = 30; tree_buf[i++] = 0;
          { const char *t = "Third paragraph after image."; /* 28 chars but I said 30, let me fix */
            for (int j = 0; j < 28; j++) tree_buf[i++] = t[j];
            tree_buf[i++] = '.'; tree_buf[i++] = '.'; /* pad to 30 */
          }
        tree_buf[i++] = 2;

      tree_buf[i++] = 2; /* ELEMENT_CLOSE </div> */

    tree_buf[i++] = 2; /* ELEMENT_CLOSE </body> */

    return i;
}

/* ---- Padding functions to increase module size ---- */

/* These dummy functions increase the WASM module size to be closer to
 * quire.wasm (~87KB). V8 might use different compilation strategies
 * for larger modules. Each function has enough complexity to avoid
 * being optimized away by LTO. */

#define PADDING_FN(name, seed) \
    __attribute__((noinline)) \
    int name(unsigned char *buf, int len) { \
        int acc = seed; \
        for (int i = 0; i < len; i++) { \
            acc = acc ^ buf[i]; \
            acc = (acc << 3) | (acc >> 29); \
            if (acc & 1) acc += buf[i]; \
            else acc -= buf[i]; \
            buf[i] = (unsigned char)(acc & 0xFF); \
        } \
        return acc; \
    }

PADDING_FN(pad_fn_01, 0x12345678)
PADDING_FN(pad_fn_02, 0x23456789)
PADDING_FN(pad_fn_03, 0x3456789A)
PADDING_FN(pad_fn_04, 0x456789AB)
PADDING_FN(pad_fn_05, 0x56789ABC)
PADDING_FN(pad_fn_06, 0x6789ABCD)
PADDING_FN(pad_fn_07, 0x789ABCDE)
PADDING_FN(pad_fn_08, 0x89ABCDEF)
PADDING_FN(pad_fn_09, 0x9ABCDEF0)
PADDING_FN(pad_fn_10, 0xABCDEF01)
PADDING_FN(pad_fn_11, 0xBCDEF012)
PADDING_FN(pad_fn_12, 0xCDEF0123)
PADDING_FN(pad_fn_13, 0xDEF01234)
PADDING_FN(pad_fn_14, 0xEF012345)
PADDING_FN(pad_fn_15, 0xF0123456)
PADDING_FN(pad_fn_16, 0x01234567)
PADDING_FN(pad_fn_17, 0x13579BDF)
PADDING_FN(pad_fn_18, 0x2468ACE0)
PADDING_FN(pad_fn_19, 0x369BE147)
PADDING_FN(pad_fn_20, 0x48ADF258)
PADDING_FN(pad_fn_21, 0x5A0C1E3F)
PADDING_FN(pad_fn_22, 0x6B1D2F40)
PADDING_FN(pad_fn_23, 0x7C2E3051)
PADDING_FN(pad_fn_24, 0x8D3F4162)
PADDING_FN(pad_fn_25, 0x9E405273)
PADDING_FN(pad_fn_26, 0xAF516384)
PADDING_FN(pad_fn_27, 0xB0627495)
PADDING_FN(pad_fn_28, 0xC17385A6)
PADDING_FN(pad_fn_29, 0xD28496B7)
PADDING_FN(pad_fn_30, 0xE395A7C8)

/* Use padding functions so LTO doesn't eliminate them */
static int use_padding(unsigned char *buf, int len) {
    int r = 0;
    r ^= pad_fn_01(buf, len > 16 ? 16 : len);
    r ^= pad_fn_02(buf, len > 16 ? 16 : len);
    r ^= pad_fn_03(buf, len > 16 ? 16 : len);
    r ^= pad_fn_04(buf, len > 16 ? 16 : len);
    r ^= pad_fn_05(buf, len > 16 ? 16 : len);
    r ^= pad_fn_06(buf, len > 16 ? 16 : len);
    r ^= pad_fn_07(buf, len > 16 ? 16 : len);
    r ^= pad_fn_08(buf, len > 16 ? 16 : len);
    r ^= pad_fn_09(buf, len > 16 ? 16 : len);
    r ^= pad_fn_10(buf, len > 16 ? 16 : len);
    r ^= pad_fn_11(buf, len > 16 ? 16 : len);
    r ^= pad_fn_12(buf, len > 16 ? 16 : len);
    r ^= pad_fn_13(buf, len > 16 ? 16 : len);
    r ^= pad_fn_14(buf, len > 16 ? 16 : len);
    r ^= pad_fn_15(buf, len > 16 ? 16 : len);
    r ^= pad_fn_16(buf, len > 16 ? 16 : len);
    r ^= pad_fn_17(buf, len > 16 ? 16 : len);
    r ^= pad_fn_18(buf, len > 16 ? 16 : len);
    r ^= pad_fn_19(buf, len > 16 ? 16 : len);
    r ^= pad_fn_20(buf, len > 16 ? 16 : len);
    r ^= pad_fn_21(buf, len > 16 ? 16 : len);
    r ^= pad_fn_22(buf, len > 16 ? 16 : len);
    r ^= pad_fn_23(buf, len > 16 ? 16 : len);
    r ^= pad_fn_24(buf, len > 16 ? 16 : len);
    r ^= pad_fn_25(buf, len > 16 ? 16 : len);
    r ^= pad_fn_26(buf, len > 16 ? 16 : len);
    r ^= pad_fn_27(buf, len > 16 ? 16 : len);
    r ^= pad_fn_28(buf, len > 16 ? 16 : len);
    r ^= pad_fn_29(buf, len > 16 ? 16 : len);
    r ^= pad_fn_30(buf, len > 16 ? 16 : len);
    return r;
}

/* ---- Simulate prior app activity (chapter 1 rendering) ---- */

static void simulate_chapter1(void) {
    /* Simulate library rendering: many small allocations */
    for (int i = 0; i < 50; i++) {
        void *p = malloc(32 + (i % 100));
        /* Don't free — simulates retained library UI state */
    }

    /* Simulate chapter 1 rendering: text + attributes */
    for (int i = 0; i < 200; i++) {
        void *p = malloc(8 + (i % 60));
        free(p); /* Text/attr buffers are freed after use */
    }

    /* Flush simulated DOM */
    dom_flush((int)dom_buf, dom_pos);
    dom_pos = 0;
}

/* ---- Exported entry point ---- */

__attribute__((export_name("run_repro")))
int run_repro(void) {
    /* Allocate DOM buffer (simulates ward_dom_init) */
    dom_buf = (unsigned char *)malloc(DOM_BUF_SIZE);
    dom_pos = 0;

    /* Run padding functions to prevent LTO elimination */
    unsigned char pad_buf[32];
    memset(pad_buf, 0x42, 32);
    int pad_result = use_padding(pad_buf, 32);

    /* Phase 1: Simulate prior app activity */
    simulate_chapter1();

    /* Phase 2: Build and render chapter 2 with an image */
    int tree_len = build_test_tree();

    int out_pos = 0, out_ecnt = 0;
    render_loop(
        tree_buf, tree_len,
        0, tree_len, 1,    /* pos=0, len, parent=1 */
        0, 0,              /* has_child=0, ecnt=0 */
        1, 10000,          /* file_handle=1, max_elements=10000 */
        0, 42,             /* depth=0, extra_param=42 */
        &out_pos, &out_ecnt
    );

    /* Flush remaining DOM diffs */
    dom_flush((int)dom_buf, dom_pos);
    dom_pos = 0;

    return out_ecnt + (pad_result & 0); /* pad_result prevents optimizer removing padding */
}
