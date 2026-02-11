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
    /* 3 */ {"Read", 4},
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

/* ========== String buffer copy helper ========== */

/* Copy len bytes from string_buffer to ward_arr (erased to ptr) */
void _copy_from_sbuf(void *dst, int len) {
    unsigned char *d = (unsigned char *)dst;
    for (int i = 0; i < len; i++) d[i] = _string_buffer[i];
}

/* ========== Byte search helper ========== */

static int _find_bytes(const unsigned char *hay, int hay_len,
                       const char *needle, int needle_len, int start) {
    int limit = hay_len - needle_len;
    for (int i = start; i <= limit; i++) {
        int match = 1;
        for (int j = 0; j < needle_len; j++) {
            if (hay[i + j] != (unsigned char)needle[j]) { match = 0; break; }
        }
        if (match) return i;
    }
    return -1;
}

/* ========== EPUB module storage ========== */

static char _epub_title[256];
static int _epub_title_len = 0;
static char _epub_author[256];
static int _epub_author_len = 0;
static char _epub_book_id[64];
static int _epub_book_id_len = 0;
static char _epub_opf_path[256];
static int _epub_opf_path_len = 0;
static char _epub_opf_dir[256];
static int _epub_opf_dir_len = 0;
static int _epub_spine_count = 0;
static int _epub_state = 0;

void epub_init(void) {
    _epub_title_len = 0;
    _epub_author_len = 0;
    _epub_book_id_len = 0;
    _epub_opf_path_len = 0;
    _epub_opf_dir_len = 0;
    _epub_spine_count = 0;
    _epub_state = 0;
}

int epub_get_state(void) { return _epub_state; }
int epub_get_progress(void) { return 0; }
int epub_get_error(int buf_offset) { return 0; }
int epub_start_import(int file_input_node_id) { return 0; }

int epub_get_title(int buf_offset) {
    for (int i = 0; i < _epub_title_len; i++)
        _string_buffer[buf_offset + i] = (unsigned char)_epub_title[i];
    return _epub_title_len;
}

int epub_get_author(int buf_offset) {
    for (int i = 0; i < _epub_author_len; i++)
        _string_buffer[buf_offset + i] = (unsigned char)_epub_author[i];
    return _epub_author_len;
}

int epub_get_book_id(int buf_offset) {
    for (int i = 0; i < _epub_book_id_len; i++)
        _string_buffer[buf_offset + i] = (unsigned char)_epub_book_id[i];
    return _epub_book_id_len;
}

int epub_get_chapter_count(void) {
    if (_epub_spine_count < 0) return 0;
    if (_epub_spine_count > 256) return 256;
    return _epub_spine_count;
}

int epub_get_chapter_key(int chapter_index, int buf_offset) { return 0; }
void epub_continue(void) {}
void epub_on_file_open(int handle, int size) {}
void epub_on_decompress(int blob_handle, int size) {}
void epub_on_db_open(int success) {}
void epub_on_db_put(int success) {}
void epub_cancel(void) { _epub_state = 0; }

/* TOC stubs */
int epub_get_toc_count(void) { return 0; }
int epub_get_toc_label(int toc_index, int buf_offset) { return 0; }
int epub_get_toc_chapter(int toc_index) { return -1; }
int epub_get_toc_level(int toc_index) { return 0; }
int epub_get_chapter_title(int spine_index, int buf_offset) { return 0; }

/* Serialization stubs */
int epub_serialize_metadata(void) { return 0; }
int epub_restore_metadata(int len) { return 0; }
void epub_reset(void) { epub_init(); }

/* Parse container.xml bytes to extract OPF path.
 * Finds full-path="..." in the XML and stores the path.
 * Returns 1 on success, 0 on failure. */
int epub_parse_container_bytes(void *buf, int len) {
    const unsigned char *data = (const unsigned char *)buf;
    int pos = _find_bytes(data, len, "full-path=\"", 11, 0);
    if (pos < 0) return 0;
    pos += 11;
    int end = pos;
    while (end < len && data[end] != '"') end++;
    if (end >= len) return 0;
    int path_len = end - pos;
    if (path_len <= 0 || path_len >= 256) return 0;
    for (int i = 0; i < path_len; i++) _epub_opf_path[i] = (char)data[pos + i];
    _epub_opf_path_len = path_len;
    /* Extract directory prefix (up to and including last '/') */
    int last_slash = -1;
    for (int i = 0; i < path_len; i++) {
        if (_epub_opf_path[i] == '/') last_slash = i;
    }
    if (last_slash >= 0) {
        _epub_opf_dir_len = last_slash + 1;
        for (int i = 0; i <= last_slash; i++) _epub_opf_dir[i] = _epub_opf_path[i];
    } else {
        _epub_opf_dir_len = 0;
    }
    return 1;
}

/* Parse content.opf bytes to extract title, author, book ID, and spine count.
 * Returns spine count on success, 0 on failure. */
int epub_parse_opf_bytes(void *buf, int len) {
    const unsigned char *data = (const unsigned char *)buf;
    int pos, end;

    /* Extract <dc:title>...</dc:title> */
    pos = _find_bytes(data, len, "<dc:title>", 10, 0);
    if (pos >= 0) {
        pos += 10;
        end = _find_bytes(data, len, "</dc:title>", 11, pos);
        if (end >= 0) {
            int tlen = end - pos;
            if (tlen > 255) tlen = 255;
            for (int i = 0; i < tlen; i++) _epub_title[i] = (char)data[pos + i];
            _epub_title_len = tlen;
        }
    }

    /* Extract <dc:creator>...</dc:creator> */
    pos = _find_bytes(data, len, "<dc:creator>", 12, 0);
    if (pos >= 0) {
        pos += 12;
        end = _find_bytes(data, len, "</dc:creator>", 13, pos);
        if (end >= 0) {
            int alen = end - pos;
            if (alen > 255) alen = 255;
            for (int i = 0; i < alen; i++) _epub_author[i] = (char)data[pos + i];
            _epub_author_len = alen;
        }
    }

    /* Extract <dc:identifier ...>...</dc:identifier> as book_id */
    pos = _find_bytes(data, len, "<dc:identifier", 14, 0);
    if (pos >= 0) {
        int gt = pos + 14;
        while (gt < len && data[gt] != '>') gt++;
        if (gt < len) {
            gt++;
            end = _find_bytes(data, len, "</dc:identifier>", 16, gt);
            if (end >= 0) {
                int id_len = end - gt;
                if (id_len > 63) id_len = 63;
                for (int i = 0; i < id_len; i++) _epub_book_id[i] = (char)data[gt + i];
                _epub_book_id_len = id_len;
            }
        }
    }

    /* Count <itemref elements in spine */
    _epub_spine_count = 0;
    pos = 0;
    for (;;) {
        pos = _find_bytes(data, len, "<itemref ", 9, pos);
        if (pos < 0) break;
        _epub_spine_count++;
        pos += 9;
    }

    _epub_state = 8; /* EPUB_STATE_DONE */
    return _epub_spine_count;
}

/* OPF path accessors for ATS2 ZIP lookup */
void* epub_get_opf_path_ptr(void) { return (void*)_epub_opf_path; }
int epub_get_opf_path_len(void) { return _epub_opf_path_len; }

/* String constant for "META-INF/container.xml" ZIP lookup */
static const char _str_container[] = "META-INF/container.xml";
void* get_str_container_ptr(void) { return (void*)_str_container; }

/* ========== Library module storage ========== */

#define MAX_LIB_BOOKS 32

typedef struct {
    char title[256];
    int title_len;
    char author[256];
    int author_len;
    char book_id[64];
    int book_id_len;
    int spine_count;
    int current_chapter;
    int current_page;
} library_book_t;

static library_book_t _library_books[MAX_LIB_BOOKS];

void library_init(void) {
    _app_set_lib_count(0);
}

int library_get_count(void) {
    int c = _app_lib_count();
    if (c < 0) return 0;
    if (c > 32) return 32;
    return c;
}

int library_add_book(void) {
    int count = _app_lib_count();
    if (count >= MAX_LIB_BOOKS) return -1;
    /* Deduplicate by book_id */
    for (int i = 0; i < count; i++) {
        if (_library_books[i].book_id_len == _epub_book_id_len) {
            int match = 1;
            for (int j = 0; j < _epub_book_id_len; j++) {
                if (_library_books[i].book_id[j] != _epub_book_id[j]) { match = 0; break; }
            }
            if (match) return i;
        }
    }
    library_book_t *b = &_library_books[count];
    for (int i = 0; i < _epub_title_len; i++) b->title[i] = _epub_title[i];
    b->title_len = _epub_title_len;
    for (int i = 0; i < _epub_author_len; i++) b->author[i] = _epub_author[i];
    b->author_len = _epub_author_len;
    for (int i = 0; i < _epub_book_id_len; i++) b->book_id[i] = _epub_book_id[i];
    b->book_id_len = _epub_book_id_len;
    b->spine_count = _epub_spine_count;
    b->current_chapter = 0;
    b->current_page = 0;
    _app_set_lib_count(count + 1);
    return count;
}

int library_get_title(int index, int buf_offset) {
    if (index < 0 || index >= _app_lib_count()) return 0;
    int len = _library_books[index].title_len;
    for (int i = 0; i < len; i++)
        _string_buffer[buf_offset + i] = (unsigned char)_library_books[index].title[i];
    return len;
}

int library_get_author(int index, int buf_offset) {
    if (index < 0 || index >= _app_lib_count()) return 0;
    int len = _library_books[index].author_len;
    for (int i = 0; i < len; i++)
        _string_buffer[buf_offset + i] = (unsigned char)_library_books[index].author[i];
    return len;
}

int library_get_book_id(int index, int buf_offset) {
    if (index < 0 || index >= _app_lib_count()) return 0;
    int len = _library_books[index].book_id_len;
    for (int i = 0; i < len; i++)
        _string_buffer[buf_offset + i] = (unsigned char)_library_books[index].book_id[i];
    return len;
}

int library_get_chapter(int index) {
    if (index < 0 || index >= _app_lib_count()) return 0;
    return _library_books[index].current_chapter;
}

int library_get_page(int index) {
    if (index < 0 || index >= _app_lib_count()) return 0;
    return _library_books[index].current_page;
}

int library_get_spine_count(int index) {
    if (index < 0 || index >= _app_lib_count()) return 0;
    return _library_books[index].spine_count;
}

void library_update_position(int index, int chapter, int page) {
    if (index < 0 || index >= _app_lib_count()) return;
    _library_books[index].current_chapter = chapter;
    _library_books[index].current_page = page;
}

int library_find_book_by_id(void) {
    int count = _app_lib_count();
    for (int i = 0; i < count; i++) {
        if (_library_books[i].book_id_len == _epub_book_id_len) {
            int match = 1;
            for (int j = 0; j < _epub_book_id_len; j++) {
                if (_library_books[i].book_id[j] != _epub_book_id[j]) { match = 0; break; }
            }
            if (match) return i;
        }
    }
    return -1;
}

void library_remove_book(int index) {
    int count = _app_lib_count();
    if (index < 0 || index >= count) return;
    for (int i = index; i < count - 1; i++) _library_books[i] = _library_books[i + 1];
    _app_set_lib_count(count - 1);
}

/* Library persistence stubs */
int library_serialize(void) { return 0; }
int library_deserialize(int len) { return 0; }
void library_save(void) {}
void library_load(void) {}
void library_on_load_complete(int len) {}
void library_on_save_complete(int success) {}
void library_save_book_metadata(void) {}
void library_load_book_metadata(int index) {}
void library_on_metadata_load_complete(int len) {}
void library_on_metadata_save_complete(int success) {}
int library_is_save_pending(void) { return 0; }
int library_is_load_pending(void) { return 0; }
int library_is_metadata_pending(void) { return 0; }

/* ========== Reader module stubs ========== */

void reader_init(void) {}
void reader_enter(int root_id, int container_hide_id) {}
void reader_exit(void) {}
int reader_is_active(void) { return 0; }
int reader_get_current_chapter(void) { return 0; }
int reader_get_current_page(void) { return 0; }
int reader_get_total_pages(void) { return 1; }
int reader_get_chapter_count(void) { return 0; }
void reader_next_page(void) {}
void reader_prev_page(void) {}
void reader_go_to_page(int page) {}
void reader_on_chapter_loaded(int len) {}
void reader_on_chapter_blob_loaded(int handle, int size) {}
int reader_get_viewport_id(void) { return 0; }
int reader_get_viewport_width(void) { return 0; }
int reader_get_page_indicator_id(void) { return 0; }
void reader_update_page_display(void) {}
int reader_is_loading(void) { return 0; }
void reader_remeasure_all(void) {}
void reader_go_to_chapter(int chapter_index, int total_chapters) {}
void reader_show_toc(void) {}
void reader_hide_toc(void) {}
void reader_toggle_toc(void) {}
int reader_is_toc_visible(void) { return 0; }
int reader_get_toc_id(void) { return 0; }
int reader_get_progress_bar_id(void) { return 0; }
int reader_get_toc_index_for_node(int node_id) { return -1; }
void reader_on_toc_click(int node_id) {}
void reader_enter_at(int root_id, int container_hide_id, int chapter, int page) {}
int reader_get_back_btn_id(void) { return 0; }
