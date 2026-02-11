/* quire_runtime.c — Minimal C runtime for quire WASM */

/* quire_ptr_add and quire_get_byte are defined as macros in quire_prelude.h.
 * No function definitions needed here. */

/* Buffer support for xml.dats and dom.dats (tree renderer). */
#define STRING_BUFFER_SIZE 4096
#define FETCH_BUFFER_SIZE 16384
#define DIFF_BUFFER_SIZE 4096

static unsigned char _string_buffer[STRING_BUFFER_SIZE];
static unsigned char _fetch_buffer[FETCH_BUFFER_SIZE];
static unsigned char _diff_buffer[DIFF_BUFFER_SIZE];

unsigned char *get_string_buffer_ptr(void) { return _string_buffer; }
unsigned char *get_fetch_buffer_ptr(void) { return _fetch_buffer; }
unsigned char *get_diff_buffer_ptr(void) { return _diff_buffer; }

/* parseHTML result stash */
static void *_parse_html_ptr = 0;

void ward_parse_html_stash(void *p) {
    _parse_html_ptr = p;
}

void *ward_parse_html_get_ptr(void) {
    return _parse_html_ptr;
}

/* ========== Text constants for UI strings ========== */

/* Text IDs — must match #define TEXT_* in quire.dats */
static const struct { const char *str; int len; } _text_table[] = {
    /* 0 */ {"No books yet", 12},
    /* 1 */ {".epub", 5},
    /* 2 */ {"Not started", 11},
};
#define TEXT_TABLE_SIZE (sizeof(_text_table) / sizeof(_text_table[0]))

/* Fill a ward_arr (erased to ptr) with text constant bytes.
 * Returns bytes written, 0 on invalid id. */
int _fill_text(void *arr, int text_id) {
    if (text_id < 0 || text_id >= (int)TEXT_TABLE_SIZE) return 0;
    const char *src = _text_table[text_id].str;
    int len = _text_table[text_id].len;
    unsigned char *dst = (unsigned char *)arr;
    for (int i = 0; i < len; i++) dst[i] = (unsigned char)src[i];
    return len;
}

/* ========== ZIP module storage ========== */

#define MAX_ZIP_ENTRIES 256
#define ZIP_NAME_BUFFER_SIZE 8192

typedef struct {
    int file_handle;
    int name_offset;
    int name_len;
    int compression;
    int compressed_size;
    int uncompressed_size;
    int local_header_offset;
} zip_entry_t;

static zip_entry_t _zip_entries[MAX_ZIP_ENTRIES];
static char _zip_name_buffer[ZIP_NAME_BUFFER_SIZE];

int _zip_entry_file_handle(int i) { return _zip_entries[i].file_handle; }
int _zip_entry_name_offset(int i) { return _zip_entries[i].name_offset; }
int _zip_entry_name_len(int i) { return _zip_entries[i].name_len; }
int _zip_entry_compression(int i) { return _zip_entries[i].compression; }
int _zip_entry_compressed_size(int i) { return _zip_entries[i].compressed_size; }
int _zip_entry_uncompressed_size(int i) { return _zip_entries[i].uncompressed_size; }
int _zip_entry_local_offset(int i) { return _zip_entries[i].local_header_offset; }

int _zip_name_char(int off) { return (int)(unsigned char)_zip_name_buffer[off]; }

int _zip_store_entry_at(int idx, int file_handle, int name_offset, int name_len,
                        int compression, int compressed_size,
                        int uncompressed_size, int local_offset) {
    if (idx < 0 || idx >= MAX_ZIP_ENTRIES) return 0;
    _zip_entries[idx].file_handle = file_handle;
    _zip_entries[idx].name_offset = name_offset;
    _zip_entries[idx].name_len = name_len;
    _zip_entries[idx].compression = compression;
    _zip_entries[idx].compressed_size = compressed_size;
    _zip_entries[idx].uncompressed_size = uncompressed_size;
    _zip_entries[idx].local_header_offset = local_offset;
    return 1;
}

int _zip_name_buf_put(int off, int byte_val) {
    if (off < 0 || off >= ZIP_NAME_BUFFER_SIZE) return 0;
    _zip_name_buffer[off] = (char)byte_val;
    return 1;
}

/* ========== DOM module helpers ========== */

/* Byte copy for tree rendering */
int _copy_to_arr(void *dst, void *src, int off, int count) {
    unsigned char *d = (unsigned char*)dst;
    unsigned char *s = (unsigned char*)src;
    for (int i = 0; i < count; i++) {
        d[i] = s[off + i];
    }
    return 0;
}

/* Freestanding memcmp — no libc available */
static int _dom_memcmp(const void *a, const void *b, int n) {
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    for (int i = 0; i < n; i++) {
        if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return 0;
}

/* Tag lookup table — maps tag name bytes to index */
typedef struct { const char *name; int len; } _dom_tag_entry;

static const _dom_tag_entry TAG_TABLE[] = {
  {"div", 3}, {"span", 4}, {"button", 6}, {"style", 5},
  {"h1", 2}, {"h2", 2}, {"h3", 2}, {"p", 1},
  {"input", 5}, {"label", 5}, {"select", 6}, {"option", 6},
  {"a", 1}, {"img", 3},
  /* EPUB content tags */
  {"b", 1}, {"i", 1}, {"u", 1}, {"s", 1}, {"q", 1},
  {"em", 2}, {"br", 2}, {"hr", 2}, {"li", 2},
  {"dd", 2}, {"dl", 2}, {"dt", 2}, {"ol", 2}, {"ul", 2},
  {"td", 2}, {"th", 2}, {"tr", 2},
  {"h4", 2}, {"h5", 2}, {"h6", 2},
  {"pre", 3}, {"sub", 3}, {"sup", 3}, {"var", 3}, {"wbr", 3},
  {"nav", 3}, {"kbd", 3},
  {"code", 4}, {"mark", 4}, {"cite", 4}, {"abbr", 4},
  {"dfn", 3}, {"main", 4}, {"time", 4}, {"ruby", 4},
  {"aside", 5}, {"small", 5}, {"table", 5}, {"thead", 5},
  {"tbody", 5}, {"tfoot", 5},
  {"strong", 6}, {"figure", 6}, {"footer", 6}, {"header", 6},
  {"section", 7}, {"article", 7}, {"details", 7}, {"summary", 7},
  {"caption", 7},
  {"blockquote", 10}, {"figcaption", 10},
  /* SVG */
  {"svg", 3}, {"g", 1}, {"path", 4}, {"circle", 6},
  {"rect", 4}, {"line", 4}, {"polyline", 8}, {"polygon", 7},
  {"text", 4}, {"tspan", 5}, {"use", 3}, {"defs", 4},
  {"image", 5}, {"symbol", 6}, {"title", 5}, {"desc", 4},
  /* MathML */
  {"math", 4}, {"mi", 2}, {"mn", 2}, {"mo", 2},
  {"mrow", 4}, {"msup", 4}, {"msub", 4},
  {"mfrac", 5}, {"msqrt", 5}, {"mroot", 5}, {"mover", 5},
  {"munder", 6}, {"mtable", 6}, {"mtr", 3}, {"mtd", 3},
  {"rp", 2}, {"rt", 2},
};
#define TAG_TABLE_SIZE (sizeof(TAG_TABLE) / sizeof(TAG_TABLE[0]))

int lookup_tag(void *base, int offset, int name_len) {
    unsigned char *bytes = (unsigned char*)base + offset;
    for (int i = 0; i < (int)TAG_TABLE_SIZE; i++) {
        if (TAG_TABLE[i].len == name_len &&
            _dom_memcmp(bytes, TAG_TABLE[i].name, name_len) == 0) {
            return i;
        }
    }
    return -1;
}

/* Attribute lookup table */
static const _dom_tag_entry ATTR_TABLE[] = {
  {"class", 5}, {"id", 2}, {"type", 4}, {"for", 3},
  {"accept", 6}, {"href", 4}, {"src", 3}, {"alt", 3},
  {"title", 5}, {"width", 5}, {"height", 6}, {"lang", 4},
  {"dir", 3}, {"role", 4}, {"tabindex", 8},
  {"colspan", 7}, {"rowspan", 7}, {"xmlns", 5},
  {"d", 1}, {"fill", 4}, {"stroke", 6},
  {"cx", 2}, {"cy", 2}, {"r", 1}, {"x", 1}, {"y", 1},
  {"transform", 9}, {"viewBox", 7},
  {"aria-label", 10}, {"aria-hidden", 11},
  {"name", 4}, {"value", 5},
};
#define ATTR_TABLE_SIZE (sizeof(ATTR_TABLE) / sizeof(ATTR_TABLE[0]))

int lookup_attr(void *base, int offset, int name_len) {
    unsigned char *bytes = (unsigned char*)base + offset;
    for (int i = 0; i < (int)ATTR_TABLE_SIZE; i++) {
        if (ATTR_TABLE[i].len == name_len &&
            _dom_memcmp(bytes, ATTR_TABLE[i].name, name_len) == 0) {
            return i;
        }
    }
    return -1;
}
