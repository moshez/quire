/* quire_runtime.c — Minimal C extensions for quire */

/* quire_ptr_add and quire_get_byte are defined as macros in quire_prelude.h.
 * No function definitions needed here. */

/* Legacy buffer support for xml.dats and epub.dats (pre-ward modules).
 * These buffers were in the old runtime.c. They'll be eliminated
 * when these modules are fully migrated to ward APIs. */
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

/* ========== Library module (moved from library.dats %{^ block) ========== */

/* External: bridge imports */
extern void js_kv_get(void* store_ptr, int store_len, void* key_ptr, int key_len);
extern void js_kv_put(void* store_ptr, int store_len, void* key_ptr, int key_len, int data_offset, int data_len);

/* External: epub module */
extern int epub_get_book_id(int buf_offset);
extern int epub_get_title(int buf_offset);
extern int epub_get_author(int buf_offset);
extern int epub_get_chapter_count(void);
extern int epub_serialize_metadata(void);
extern int epub_restore_metadata(int len);

/* Book entry structure */
#define MAX_LIBRARY_BOOKS 32
#define MAX_BOOK_TITLE 128
#define MAX_BOOK_AUTHOR 128
#define MAX_BOOK_ID 16

typedef struct {
    char book_id[MAX_BOOK_ID];
    int book_id_len;
    char title[MAX_BOOK_TITLE];
    int title_len;
    char author[MAX_BOOK_AUTHOR];
    int author_len;
    int current_chapter;
    int current_page;
    int spine_count;
} library_entry_t;

/* Library state */
static library_entry_t library_books[MAX_LIBRARY_BOOKS];
static int library_count = 0;

/* Async operation flags */
static int lib_save_pending = 0;
static int lib_load_pending = 0;
static int lib_metadata_save_pending = 0;
static int lib_metadata_load_pending = 0;
static int lib_metadata_load_index = -1;

/* String constants */
static const char str_books[] = "books";
static const char str_lib_key[] = "library-index";
static const char str_book_prefix[] = "book-";

/* Helper: write u16 LE */
static void lib_write_u16(unsigned char* buf, int offset, int value) {
    buf[offset] = value & 0xff;
    buf[offset + 1] = (value >> 8) & 0xff;
}

/* Helper: read u16 LE */
static int lib_read_u16(unsigned char* buf, int offset) {
    return buf[offset] | (buf[offset + 1] << 8);
}

void library_init(void) {
    library_count = 0;
    lib_save_pending = 0;
    lib_load_pending = 0;
    lib_metadata_save_pending = 0;
    lib_metadata_load_pending = 0;
    lib_metadata_load_index = -1;
    for (int i = 0; i < MAX_LIBRARY_BOOKS; i++) {
        library_books[i].book_id_len = 0;
        library_books[i].title_len = 0;
        library_books[i].author_len = 0;
        library_books[i].current_chapter = 0;
        library_books[i].current_page = 0;
        library_books[i].spine_count = 0;
    }
}

int library_get_count(void) {
    return library_count;
}

int library_get_title(int index, int buf_offset) {
    if (index < 0 || index >= library_count) return 0;
    unsigned char* buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[index];
    for (int i = 0; i < entry->title_len && buf_offset + i < STRING_BUFFER_SIZE; i++) {
        buf[buf_offset + i] = entry->title[i];
    }
    return entry->title_len;
}

int library_get_author(int index, int buf_offset) {
    if (index < 0 || index >= library_count) return 0;
    unsigned char* buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[index];
    for (int i = 0; i < entry->author_len && buf_offset + i < STRING_BUFFER_SIZE; i++) {
        buf[buf_offset + i] = entry->author[i];
    }
    return entry->author_len;
}

int library_get_book_id(int index, int buf_offset) {
    if (index < 0 || index >= library_count) return 0;
    unsigned char* buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[index];
    for (int i = 0; i < entry->book_id_len && buf_offset + i < STRING_BUFFER_SIZE; i++) {
        buf[buf_offset + i] = entry->book_id[i];
    }
    return entry->book_id_len;
}

int library_get_chapter(int index) {
    if (index < 0 || index >= library_count) return 0;
    return library_books[index].current_chapter;
}

int library_get_page(int index) {
    if (index < 0 || index >= library_count) return 0;
    return library_books[index].current_page;
}

int library_get_spine_count(int index) {
    if (index < 0 || index >= library_count) return 0;
    return library_books[index].spine_count;
}

int library_find_book_by_id(void) {
    unsigned char* str_buf = get_string_buffer_ptr();
    int id_len = epub_get_book_id(0);
    if (id_len <= 0) return -1;

    for (int i = 0; i < library_count; i++) {
        library_entry_t* entry = &library_books[i];
        if (entry->book_id_len == id_len) {
            int match = 1;
            for (int j = 0; j < id_len && match; j++) {
                if (entry->book_id[j] != str_buf[j]) match = 0;
            }
            if (match) return i;
        }
    }
    return -1;
}

int library_add_book(void) {
    if (library_count >= MAX_LIBRARY_BOOKS) return -1;

    unsigned char* str_buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[library_count];

    /* Get book_id */
    int id_len = epub_get_book_id(0);
    if (id_len <= 0) return -1;
    if (id_len > MAX_BOOK_ID - 1) id_len = MAX_BOOK_ID - 1;
    for (int i = 0; i < id_len; i++) entry->book_id[i] = str_buf[i];
    entry->book_id[id_len] = 0;
    entry->book_id_len = id_len;

    /* Check for duplicate */
    for (int i = 0; i < library_count; i++) {
        if (library_books[i].book_id_len == id_len) {
            int match = 1;
            for (int j = 0; j < id_len && match; j++) {
                if (library_books[i].book_id[j] != entry->book_id[j]) match = 0;
            }
            if (match) {
                library_books[i].spine_count = epub_get_chapter_count();
                return i;
            }
        }
    }

    /* Get title */
    int tlen = epub_get_title(0);
    if (tlen > MAX_BOOK_TITLE - 1) tlen = MAX_BOOK_TITLE - 1;
    for (int i = 0; i < tlen; i++) entry->title[i] = str_buf[i];
    entry->title[tlen] = 0;
    entry->title_len = tlen;

    /* Get author */
    int alen = epub_get_author(0);
    if (alen > MAX_BOOK_AUTHOR - 1) alen = MAX_BOOK_AUTHOR - 1;
    for (int i = 0; i < alen; i++) entry->author[i] = str_buf[i];
    entry->author[alen] = 0;
    entry->author_len = alen;

    entry->current_chapter = 0;
    entry->current_page = 0;
    entry->spine_count = epub_get_chapter_count();

    return library_count++;
}

void library_remove_book(int index) {
    if (index < 0 || index >= library_count) return;
    for (int i = index; i < library_count - 1; i++) {
        library_books[i] = library_books[i + 1];
    }
    library_count--;
}

void library_update_position(int index, int chapter, int page) {
    if (index < 0 || index >= library_count) return;
    library_books[index].current_chapter = chapter;
    library_books[index].current_page = page;
}

int library_serialize(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    int pos = 0;

    lib_write_u16(buf, pos, library_count); pos += 2;

    for (int i = 0; i < library_count; i++) {
        library_entry_t* entry = &library_books[i];

        /* book_id (fixed 8 bytes padded with zeros) */
        for (int j = 0; j < 8; j++) {
            buf[pos++] = (j < entry->book_id_len) ? entry->book_id[j] : 0;
        }

        /* title */
        lib_write_u16(buf, pos, entry->title_len); pos += 2;
        for (int j = 0; j < entry->title_len && pos < FETCH_BUFFER_SIZE - 4; j++) {
            buf[pos++] = entry->title[j];
        }

        /* author */
        lib_write_u16(buf, pos, entry->author_len); pos += 2;
        for (int j = 0; j < entry->author_len && pos < FETCH_BUFFER_SIZE - 4; j++) {
            buf[pos++] = entry->author[j];
        }

        /* position and spine count */
        lib_write_u16(buf, pos, entry->current_chapter); pos += 2;
        lib_write_u16(buf, pos, entry->current_page); pos += 2;
        lib_write_u16(buf, pos, entry->spine_count); pos += 2;
    }

    return pos;
}

int library_deserialize(int len) {
    if (len < 2) return 0;

    unsigned char* buf = get_fetch_buffer_ptr();
    int pos = 0;

    int count = lib_read_u16(buf, pos); pos += 2;
    if (count > MAX_LIBRARY_BOOKS) count = MAX_LIBRARY_BOOKS;

    library_count = 0;

    for (int i = 0; i < count && pos < len; i++) {
        library_entry_t* entry = &library_books[library_count];

        /* book_id (fixed 8 bytes) */
        for (int j = 0; j < 8 && pos < len; j++) {
            entry->book_id[j] = buf[pos++];
        }
        entry->book_id[8] = 0;
        entry->book_id_len = 8;
        while (entry->book_id_len > 0 && entry->book_id[entry->book_id_len - 1] == 0) {
            entry->book_id_len--;
        }

        if (pos + 2 > len) break;

        /* title */
        int tlen = lib_read_u16(buf, pos); pos += 2;
        if (tlen > MAX_BOOK_TITLE - 1) tlen = MAX_BOOK_TITLE - 1;
        for (int j = 0; j < tlen && pos < len; j++) {
            entry->title[j] = buf[pos++];
        }
        entry->title[tlen] = 0;
        entry->title_len = tlen;

        if (pos + 2 > len) break;

        /* author */
        int alen = lib_read_u16(buf, pos); pos += 2;
        if (alen > MAX_BOOK_AUTHOR - 1) alen = MAX_BOOK_AUTHOR - 1;
        for (int j = 0; j < alen && pos < len; j++) {
            entry->author[j] = buf[pos++];
        }
        entry->author[alen] = 0;
        entry->author_len = alen;

        if (pos + 6 > len) break;

        /* position and spine count */
        entry->current_chapter = lib_read_u16(buf, pos); pos += 2;
        entry->current_page = lib_read_u16(buf, pos); pos += 2;
        entry->spine_count = lib_read_u16(buf, pos); pos += 2;

        library_count++;
    }

    return 1;
}

void library_save(void) {
    unsigned char* str_buf = get_string_buffer_ptr();

    int data_len = library_serialize();

    /* Write key to string buffer */
    for (int i = 0; i < 13; i++) str_buf[i] = str_lib_key[i];

    lib_save_pending = 1;
    js_kv_put((void*)str_books, 5, str_buf, 13, 0, data_len);
}

void library_load(void) {
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Write key to string buffer */
    for (int i = 0; i < 13; i++) str_buf[i] = str_lib_key[i];

    lib_load_pending = 1;
    js_kv_get((void*)str_books, 5, str_buf, 13);
}

void library_on_load_complete(int len) {
    lib_load_pending = 0;
    if (len > 0) {
        library_deserialize(len);
    }
}

void library_on_save_complete(int success) {
    lib_save_pending = 0;
}

void library_save_book_metadata(void) {
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Serialize epub metadata to fetch buffer */
    int data_len = epub_serialize_metadata();
    if (data_len <= 0) return;

    /* Build key: "book-" + book_id */
    int key_len = 0;
    for (int i = 0; i < 5; i++) str_buf[key_len++] = str_book_prefix[i];
    int id_len = epub_get_book_id(key_len);
    key_len += id_len;

    lib_metadata_save_pending = 1;
    js_kv_put((void*)str_books, 5, str_buf, key_len, 0, data_len);
}

void library_load_book_metadata(int index) {
    if (index < 0 || index >= library_count) return;

    unsigned char* str_buf = get_string_buffer_ptr();
    library_entry_t* entry = &library_books[index];

    /* Build key: "book-" + book_id */
    int key_len = 0;
    for (int i = 0; i < 5; i++) str_buf[key_len++] = str_book_prefix[i];
    for (int i = 0; i < entry->book_id_len; i++) str_buf[key_len++] = entry->book_id[i];

    lib_metadata_load_pending = 1;
    lib_metadata_load_index = index;
    js_kv_get((void*)str_books, 5, str_buf, key_len);
}

void library_on_metadata_load_complete(int len) {
    lib_metadata_load_pending = 0;
    if (len > 0) {
        epub_restore_metadata(len);
    }
}

void library_on_metadata_save_complete(int success) {
    lib_metadata_save_pending = 0;
}

int library_is_save_pending(void) { return lib_save_pending; }
int library_is_load_pending(void) { return lib_load_pending; }
int library_is_metadata_pending(void) { return lib_metadata_save_pending || lib_metadata_load_pending; }

/* ========== Settings module (moved from settings.dats %{^ block) ========== */

/* External: old DOM functions (currently dead code — will be replaced in Phase 9) */
extern void dom_init(void);
extern void* dom_root_proof(void);
extern void* dom_create_element(void*, int, int, void*, int);
extern void* dom_set_text_offset(void*, int, int, int);
extern void* dom_set_attr(void*, int, void*, int, void*, int);
extern void dom_remove_child(void*, int);
extern int dom_next_id(void);
extern void dom_drop_proof(void*);

/* External: reader functions */
extern int reader_is_active(void);
extern void reader_remeasure_all(void);

/* Settings state */
static int setting_font_size = 18;
static int setting_font_family = 0;
static int setting_theme = 0;
static int setting_line_height_tenths = 16;
static int setting_margin = 2;

/* Settings UI state */
static int settings_visible = 0;
static int settings_overlay_id = 0;
static int settings_close_id = 0;
static int settings_root_id = 1;

/* Button IDs for click handling */
static int btn_font_minus_id = 0;
static int btn_font_plus_id = 0;
static int btn_font_family_id = 0;
static int btn_theme_light_id = 0;
static int btn_theme_dark_id = 0;
static int btn_theme_sepia_id = 0;
static int btn_lh_minus_id = 0;
static int btn_lh_plus_id = 0;
static int btn_margin_minus_id = 0;
static int btn_margin_plus_id = 0;

/* Display IDs */
static int disp_font_size_id = 0;
static int disp_font_family_id = 0;
static int disp_line_height_id = 0;
static int disp_margin_id = 0;

/* Save/load state */
static int settings_save_pending = 0;
static int settings_load_pending = 0;

/* String constants */
static const char s_div[] = "div";
static const char s_class[] = "class";
static const char s_style[] = "style";

static const char s_settings_overlay[] = "settings-overlay";
static const char s_settings_modal[] = "settings-modal";
static const char s_settings_header[] = "settings-header";
static const char s_settings_title[] = "Reader Settings";
static const char s_settings_close[] = "settings-close";
static const char s_close_x[] = "\xc3\x97";
static const char s_settings_body[] = "settings-body";
static const char s_settings_row[] = "settings-row";
static const char s_settings_label[] = "settings-label";
static const char s_settings_controls[] = "settings-controls";
static const char s_settings_btn[] = "settings-btn";
static const char s_settings_btn_active[] = "settings-btn active";
static const char s_settings_value[] = "settings-value";

static const char s_font_size_label[] = "Font Size";
static const char s_font_family_label[] = "Font";
static const char s_theme_label[] = "Theme";
static const char s_line_height_label[] = "Line Spacing";
static const char s_margin_label[] = "Margins";

static const char s_serif[] = "Serif";
static const char s_sans[] = "Sans";
static const char s_mono[] = "Mono";
static const char s_light[] = "Light";
static const char s_dark[] = "Dark";
static const char s_sepia[] = "Sepia";
static const char s_minus[] = "\xe2\x88\x92";
static const char s_plus[] = "+";

static const char s_light_bg[] = "#fafaf8";
static const char s_light_fg[] = "#2a2a2a";
static const char s_dark_bg[] = "#1a1a1a";
static const char s_dark_fg[] = "#e0e0e0";
static const char s_sepia_bg[] = "#f4ecd8";
static const char s_sepia_fg[] = "#5b4636";

static const char s_serif_css[] = "Georgia,serif";
static const char s_sans_css[] = "system-ui,-apple-system,sans-serif";
static const char s_mono_css[] = "'Courier New',monospace";

/* Forward declarations */
static void update_display_values(void);
static void apply_theme_to_body(void);
void settings_apply(void);
void settings_save(void);

static int clamp(int val, int min, int max) {
    if (val < min) return min;
    if (val > max) return max;
    return val;
}

static int settings_append_str(unsigned char* buf, int pos, const char* str) {
    while (*str && pos < 16380) {
        buf[pos++] = *str++;
    }
    return pos;
}

static int settings_append_int(unsigned char* buf, int pos, int val) {
    if (val >= 100) {
        buf[pos++] = '0' + (val / 100);
        buf[pos++] = '0' + ((val / 10) % 10);
        buf[pos++] = '0' + (val % 10);
    } else if (val >= 10) {
        buf[pos++] = '0' + (val / 10);
        buf[pos++] = '0' + (val % 10);
    } else {
        buf[pos++] = '0' + val;
    }
    return pos;
}

void settings_init(void) {
    setting_font_size = 18;
    setting_font_family = 0;
    setting_theme = 0;
    setting_line_height_tenths = 16;
    setting_margin = 2;
    settings_visible = 0;
    settings_overlay_id = 0;
}

int settings_get_font_size(void) { return setting_font_size; }
int settings_get_font_family(void) { return setting_font_family; }
int settings_get_theme(void) { return setting_theme; }
int settings_get_line_height_tenths(void) { return setting_line_height_tenths; }
int settings_get_margin(void) { return setting_margin; }

void settings_set_font_size(int size) {
    setting_font_size = clamp(size, 14, 32);
}
void settings_set_font_family(int family) {
    setting_font_family = clamp(family, 0, 2);
}
void settings_set_theme(int theme) {
    setting_theme = clamp(theme, 0, 2);
}
void settings_set_line_height_tenths(int tenths) {
    setting_line_height_tenths = clamp(tenths, 14, 24);
}
void settings_set_margin(int margin) {
    setting_margin = clamp(margin, 1, 4);
}

void settings_increase_font_size(void) {
    settings_set_font_size(setting_font_size + 2);
    settings_apply();
    update_display_values();
    settings_save();
}
void settings_decrease_font_size(void) {
    settings_set_font_size(setting_font_size - 2);
    settings_apply();
    update_display_values();
    settings_save();
}
void settings_next_font_family(void) {
    setting_font_family = (setting_font_family + 1) % 3;
    settings_apply();
    update_display_values();
    settings_save();
}
void settings_next_theme(void) {
    setting_theme = (setting_theme + 1) % 3;
    settings_apply();
    apply_theme_to_body();
    update_display_values();
    settings_save();
}
void settings_increase_line_height(void) {
    settings_set_line_height_tenths(setting_line_height_tenths + 1);
    settings_apply();
    update_display_values();
    settings_save();
}
void settings_decrease_line_height(void) {
    settings_set_line_height_tenths(setting_line_height_tenths - 1);
    settings_apply();
    update_display_values();
    settings_save();
}
void settings_increase_margin(void) {
    settings_set_margin(setting_margin + 1);
    settings_apply();
    update_display_values();
    settings_save();
}
void settings_decrease_margin(void) {
    settings_set_margin(setting_margin - 1);
    settings_apply();
    update_display_values();
    settings_save();
}

int settings_build_css_vars(int buf_offset) {
    unsigned char* buf = get_fetch_buffer_ptr() + buf_offset;
    int len = 0;

    len = settings_append_str(buf, len, "--font-size:");
    len = settings_append_int(buf, len, setting_font_size);
    len = settings_append_str(buf, len, "px;");

    len = settings_append_str(buf, len, "--font-family:");
    switch (setting_font_family) {
        case 0: len = settings_append_str(buf, len, s_serif_css); break;
        case 1: len = settings_append_str(buf, len, s_sans_css); break;
        case 2: len = settings_append_str(buf, len, s_mono_css); break;
        default: len = settings_append_str(buf, len, s_serif_css); break;
    }
    len = settings_append_str(buf, len, ";");

    len = settings_append_str(buf, len, "--line-height:");
    len = settings_append_int(buf, len, setting_line_height_tenths / 10);
    buf[len++] = '.';
    len = settings_append_int(buf, len, setting_line_height_tenths % 10);
    len = settings_append_str(buf, len, ";");

    len = settings_append_str(buf, len, "--margin:");
    len = settings_append_int(buf, len, setting_margin);
    len = settings_append_str(buf, len, "rem;");

    const char* bg_color;
    const char* fg_color;
    switch (setting_theme) {
        case 0: bg_color = s_light_bg; fg_color = s_light_fg; break;
        case 1: bg_color = s_dark_bg; fg_color = s_dark_fg; break;
        case 2: bg_color = s_sepia_bg; fg_color = s_sepia_fg; break;
        default: bg_color = s_light_bg; fg_color = s_light_fg; break;
    }

    len = settings_append_str(buf, len, "--bg-color:");
    len = settings_append_str(buf, len, bg_color);
    len = settings_append_str(buf, len, ";");
    len = settings_append_str(buf, len, "--text-color:");
    len = settings_append_str(buf, len, fg_color);

    return len;
}

static void apply_theme_to_body(void) {
    unsigned char* str_buf = get_string_buffer_ptr();
    void* pf = dom_root_proof();

    int len = 0;
    const char* bg;
    const char* fg;

    switch (setting_theme) {
        case 0: bg = s_light_bg; fg = s_light_fg; break;
        case 1: bg = s_dark_bg; fg = s_dark_fg; break;
        case 2: bg = s_sepia_bg; fg = s_sepia_fg; break;
        default: bg = s_light_bg; fg = s_light_fg; break;
    }

    len = settings_append_str(str_buf, len, "background:");
    len = settings_append_str(str_buf, len, bg);
    len = settings_append_str(str_buf, len, ";color:");
    len = settings_append_str(str_buf, len, fg);

    dom_set_attr(pf, 1, (void*)s_style, 5, str_buf, len);
    dom_drop_proof(pf);
}

void settings_apply(void) {
    if (reader_is_active()) {
        reader_remeasure_all();
    }
}

void settings_save(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();

    buf[0] = setting_font_size & 0xff;
    buf[1] = (setting_font_size >> 8) & 0xff;
    buf[2] = setting_font_family & 0xff;
    buf[3] = (setting_font_family >> 8) & 0xff;
    buf[4] = setting_theme & 0xff;
    buf[5] = (setting_theme >> 8) & 0xff;
    buf[6] = setting_line_height_tenths & 0xff;
    buf[7] = (setting_line_height_tenths >> 8) & 0xff;
    buf[8] = setting_margin & 0xff;
    buf[9] = (setting_margin >> 8) & 0xff;

    static const char key[] = "reader-settings";
    for (int i = 0; i < 15; i++) str_buf[i] = key[i];

    static const char store[] = "settings";
    settings_save_pending = 1;
    js_kv_put((void*)store, 8, str_buf, 15, 0, 10);
}

void settings_load(void) {
    unsigned char* str_buf = get_string_buffer_ptr();

    static const char key[] = "reader-settings";
    for (int i = 0; i < 15; i++) str_buf[i] = key[i];

    static const char store[] = "settings";
    settings_load_pending = 1;
    js_kv_get((void*)store, 8, str_buf, 15);
}

void settings_on_load_complete(int len) {
    settings_load_pending = 0;
    if (len < 10) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    int fs = buf[0] | (buf[1] << 8);
    int ff = buf[2] | (buf[3] << 8);
    int th = buf[4] | (buf[5] << 8);
    int lh = buf[6] | (buf[7] << 8);
    int mg = buf[8] | (buf[9] << 8);

    settings_set_font_size(fs);
    settings_set_font_family(ff);
    settings_set_theme(th);
    settings_set_line_height_tenths(lh);
    settings_set_margin(mg);

    apply_theme_to_body();
    settings_apply();
}

void settings_on_save_complete(int success) {
    settings_save_pending = 0;
}

int settings_is_visible(void) { return settings_visible; }
int settings_get_overlay_id(void) { return settings_overlay_id; }

static void update_display_values(void) {
    if (!settings_visible) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    void* pf = dom_root_proof();
    int len;

    if (disp_font_size_id > 0) {
        len = 0;
        len = settings_append_int(buf, len, setting_font_size);
        len = settings_append_str(buf, len, "px");
        dom_set_text_offset(pf, disp_font_size_id, 0, len);
    }

    if (disp_font_family_id > 0) {
        const char* family_name;
        int family_len;
        switch (setting_font_family) {
            case 0: family_name = s_serif; family_len = 5; break;
            case 1: family_name = s_sans; family_len = 4; break;
            case 2: family_name = s_mono; family_len = 4; break;
            default: family_name = s_serif; family_len = 5; break;
        }
        for (int i = 0; i < family_len; i++) buf[i] = family_name[i];
        dom_set_text_offset(pf, disp_font_family_id, 0, family_len);
    }

    if (disp_line_height_id > 0) {
        len = 0;
        len = settings_append_int(buf, len, setting_line_height_tenths / 10);
        buf[len++] = '.';
        len = settings_append_int(buf, len, setting_line_height_tenths % 10);
        dom_set_text_offset(pf, disp_line_height_id, 0, len);
    }

    if (disp_margin_id > 0) {
        len = 0;
        len = settings_append_int(buf, len, setting_margin);
        len = settings_append_str(buf, len, "rem");
        dom_set_text_offset(pf, disp_margin_id, 0, len);
    }

    unsigned char* str_buf = get_string_buffer_ptr();
    if (btn_theme_light_id > 0) {
        if (setting_theme == 0) dom_set_attr(pf, btn_theme_light_id, (void*)s_class, 5, (void*)s_settings_btn_active, 19);
        else dom_set_attr(pf, btn_theme_light_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    }
    if (btn_theme_dark_id > 0) {
        if (setting_theme == 1) dom_set_attr(pf, btn_theme_dark_id, (void*)s_class, 5, (void*)s_settings_btn_active, 19);
        else dom_set_attr(pf, btn_theme_dark_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    }
    if (btn_theme_sepia_id > 0) {
        if (setting_theme == 2) dom_set_attr(pf, btn_theme_sepia_id, (void*)s_class, 5, (void*)s_settings_btn_active, 19);
        else dom_set_attr(pf, btn_theme_sepia_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    }
    dom_drop_proof(pf);
}

void settings_show(void) {
    if (settings_visible) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    void* pf = dom_root_proof();
    int len;

    int overlay_id = dom_next_id();
    settings_overlay_id = overlay_id;
    void* pf_overlay = dom_create_element(pf, settings_root_id, overlay_id, (void*)s_div, 3);
    pf_overlay = dom_set_attr(pf_overlay, overlay_id, (void*)s_class, 5, (void*)s_settings_overlay, 16);

    int modal_id = dom_next_id();
    void* pf_modal = dom_create_element(pf_overlay, overlay_id, modal_id, (void*)s_div, 3);
    pf_modal = dom_set_attr(pf_modal, modal_id, (void*)s_class, 5, (void*)s_settings_modal, 14);

    int header_id = dom_next_id();
    void* pf_header = dom_create_element(pf_modal, modal_id, header_id, (void*)s_div, 3);
    pf_header = dom_set_attr(pf_header, header_id, (void*)s_class, 5, (void*)s_settings_header, 15);
    len = 0;
    len = settings_append_str(buf, len, s_settings_title);
    dom_set_text_offset(pf_header, header_id, 0, len);

    int close_id = dom_next_id();
    settings_close_id = close_id;
    void* pf_close = dom_create_element(pf_header, header_id, close_id, (void*)s_div, 3);
    pf_close = dom_set_attr(pf_close, close_id, (void*)s_class, 5, (void*)s_settings_close, 14);
    len = 0;
    len = settings_append_str(buf, len, s_close_x);
    dom_set_text_offset(pf_close, close_id, 0, len);
    dom_drop_proof(pf_close);
    dom_drop_proof(pf_header);

    int body_id = dom_next_id();
    void* pf_body = dom_create_element(pf_modal, modal_id, body_id, (void*)s_div, 3);
    pf_body = dom_set_attr(pf_body, body_id, (void*)s_class, 5, (void*)s_settings_body, 13);

    /* Font Size Row */
    int row1_id = dom_next_id();
    void* pf_row1 = dom_create_element(pf_body, body_id, row1_id, (void*)s_div, 3);
    pf_row1 = dom_set_attr(pf_row1, row1_id, (void*)s_class, 5, (void*)s_settings_row, 12);
    int lbl1_id = dom_next_id();
    void* pf_lbl1 = dom_create_element(pf_row1, row1_id, lbl1_id, (void*)s_div, 3);
    pf_lbl1 = dom_set_attr(pf_lbl1, lbl1_id, (void*)s_class, 5, (void*)s_settings_label, 14);
    len = 0; len = settings_append_str(buf, len, s_font_size_label);
    dom_set_text_offset(pf_lbl1, lbl1_id, 0, len);
    dom_drop_proof(pf_lbl1);
    int ctrl1_id = dom_next_id();
    void* pf_ctrl1 = dom_create_element(pf_row1, row1_id, ctrl1_id, (void*)s_div, 3);
    pf_ctrl1 = dom_set_attr(pf_ctrl1, ctrl1_id, (void*)s_class, 5, (void*)s_settings_controls, 17);
    btn_font_minus_id = dom_next_id();
    void* pf_btn = dom_create_element(pf_ctrl1, ctrl1_id, btn_font_minus_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_font_minus_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    len = 0; len = settings_append_str(buf, len, s_minus);
    dom_set_text_offset(pf_btn, btn_font_minus_id, 0, len);
    dom_drop_proof(pf_btn);
    disp_font_size_id = dom_next_id();
    void* pf_val = dom_create_element(pf_ctrl1, ctrl1_id, disp_font_size_id, (void*)s_div, 3);
    pf_val = dom_set_attr(pf_val, disp_font_size_id, (void*)s_class, 5, (void*)s_settings_value, 14);
    len = 0; len = settings_append_int(buf, len, setting_font_size); len = settings_append_str(buf, len, "px");
    dom_set_text_offset(pf_val, disp_font_size_id, 0, len);
    dom_drop_proof(pf_val);
    btn_font_plus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl1, ctrl1_id, btn_font_plus_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_font_plus_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    len = 0; len = settings_append_str(buf, len, s_plus);
    dom_set_text_offset(pf_btn, btn_font_plus_id, 0, len);
    dom_drop_proof(pf_btn);
    dom_drop_proof(pf_ctrl1);
    dom_drop_proof(pf_row1);

    /* Font Family Row */
    int row2_id = dom_next_id();
    void* pf_row2 = dom_create_element(pf_body, body_id, row2_id, (void*)s_div, 3);
    pf_row2 = dom_set_attr(pf_row2, row2_id, (void*)s_class, 5, (void*)s_settings_row, 12);
    int lbl2_id = dom_next_id();
    void* pf_lbl2 = dom_create_element(pf_row2, row2_id, lbl2_id, (void*)s_div, 3);
    pf_lbl2 = dom_set_attr(pf_lbl2, lbl2_id, (void*)s_class, 5, (void*)s_settings_label, 14);
    len = 0; len = settings_append_str(buf, len, s_font_family_label);
    dom_set_text_offset(pf_lbl2, lbl2_id, 0, len);
    dom_drop_proof(pf_lbl2);
    int ctrl2_id = dom_next_id();
    void* pf_ctrl2 = dom_create_element(pf_row2, row2_id, ctrl2_id, (void*)s_div, 3);
    pf_ctrl2 = dom_set_attr(pf_ctrl2, ctrl2_id, (void*)s_class, 5, (void*)s_settings_controls, 17);
    btn_font_family_id = dom_next_id();
    disp_font_family_id = btn_font_family_id;
    pf_btn = dom_create_element(pf_ctrl2, ctrl2_id, btn_font_family_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_font_family_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    const char* family_name; int family_len;
    switch (setting_font_family) {
        case 0: family_name = s_serif; family_len = 5; break;
        case 1: family_name = s_sans; family_len = 4; break;
        case 2: family_name = s_mono; family_len = 4; break;
        default: family_name = s_serif; family_len = 5; break;
    }
    for (int i = 0; i < family_len; i++) buf[i] = family_name[i];
    dom_set_text_offset(pf_btn, btn_font_family_id, 0, family_len);
    dom_drop_proof(pf_btn);
    dom_drop_proof(pf_ctrl2);
    dom_drop_proof(pf_row2);

    /* Theme Row */
    int row3_id = dom_next_id();
    void* pf_row3 = dom_create_element(pf_body, body_id, row3_id, (void*)s_div, 3);
    pf_row3 = dom_set_attr(pf_row3, row3_id, (void*)s_class, 5, (void*)s_settings_row, 12);
    int lbl3_id = dom_next_id();
    void* pf_lbl3 = dom_create_element(pf_row3, row3_id, lbl3_id, (void*)s_div, 3);
    pf_lbl3 = dom_set_attr(pf_lbl3, lbl3_id, (void*)s_class, 5, (void*)s_settings_label, 14);
    len = 0; len = settings_append_str(buf, len, s_theme_label);
    dom_set_text_offset(pf_lbl3, lbl3_id, 0, len);
    dom_drop_proof(pf_lbl3);
    int ctrl3_id = dom_next_id();
    void* pf_ctrl3 = dom_create_element(pf_row3, row3_id, ctrl3_id, (void*)s_div, 3);
    pf_ctrl3 = dom_set_attr(pf_ctrl3, ctrl3_id, (void*)s_class, 5, (void*)s_settings_controls, 17);
    btn_theme_light_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl3, ctrl3_id, btn_theme_light_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_theme_light_id, (void*)s_class, 5,
        setting_theme == 0 ? (void*)s_settings_btn_active : (void*)s_settings_btn, setting_theme == 0 ? 19 : 12);
    len = 0; len = settings_append_str(buf, len, s_light);
    dom_set_text_offset(pf_btn, btn_theme_light_id, 0, len);
    dom_drop_proof(pf_btn);
    btn_theme_dark_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl3, ctrl3_id, btn_theme_dark_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_theme_dark_id, (void*)s_class, 5,
        setting_theme == 1 ? (void*)s_settings_btn_active : (void*)s_settings_btn, setting_theme == 1 ? 19 : 12);
    len = 0; len = settings_append_str(buf, len, s_dark);
    dom_set_text_offset(pf_btn, btn_theme_dark_id, 0, len);
    dom_drop_proof(pf_btn);
    btn_theme_sepia_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl3, ctrl3_id, btn_theme_sepia_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_theme_sepia_id, (void*)s_class, 5,
        setting_theme == 2 ? (void*)s_settings_btn_active : (void*)s_settings_btn, setting_theme == 2 ? 19 : 12);
    len = 0; len = settings_append_str(buf, len, s_sepia);
    dom_set_text_offset(pf_btn, btn_theme_sepia_id, 0, len);
    dom_drop_proof(pf_btn);
    dom_drop_proof(pf_ctrl3);
    dom_drop_proof(pf_row3);

    /* Line Height Row */
    int row4_id = dom_next_id();
    void* pf_row4 = dom_create_element(pf_body, body_id, row4_id, (void*)s_div, 3);
    pf_row4 = dom_set_attr(pf_row4, row4_id, (void*)s_class, 5, (void*)s_settings_row, 12);
    int lbl4_id = dom_next_id();
    void* pf_lbl4 = dom_create_element(pf_row4, row4_id, lbl4_id, (void*)s_div, 3);
    pf_lbl4 = dom_set_attr(pf_lbl4, lbl4_id, (void*)s_class, 5, (void*)s_settings_label, 14);
    len = 0; len = settings_append_str(buf, len, s_line_height_label);
    dom_set_text_offset(pf_lbl4, lbl4_id, 0, len);
    dom_drop_proof(pf_lbl4);
    int ctrl4_id = dom_next_id();
    void* pf_ctrl4 = dom_create_element(pf_row4, row4_id, ctrl4_id, (void*)s_div, 3);
    pf_ctrl4 = dom_set_attr(pf_ctrl4, ctrl4_id, (void*)s_class, 5, (void*)s_settings_controls, 17);
    btn_lh_minus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl4, ctrl4_id, btn_lh_minus_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_lh_minus_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    len = 0; len = settings_append_str(buf, len, s_minus);
    dom_set_text_offset(pf_btn, btn_lh_minus_id, 0, len);
    dom_drop_proof(pf_btn);
    disp_line_height_id = dom_next_id();
    pf_val = dom_create_element(pf_ctrl4, ctrl4_id, disp_line_height_id, (void*)s_div, 3);
    pf_val = dom_set_attr(pf_val, disp_line_height_id, (void*)s_class, 5, (void*)s_settings_value, 14);
    len = 0; len = settings_append_int(buf, len, setting_line_height_tenths / 10);
    buf[len++] = '.'; len = settings_append_int(buf, len, setting_line_height_tenths % 10);
    dom_set_text_offset(pf_val, disp_line_height_id, 0, len);
    dom_drop_proof(pf_val);
    btn_lh_plus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl4, ctrl4_id, btn_lh_plus_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_lh_plus_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    len = 0; len = settings_append_str(buf, len, s_plus);
    dom_set_text_offset(pf_btn, btn_lh_plus_id, 0, len);
    dom_drop_proof(pf_btn);
    dom_drop_proof(pf_ctrl4);
    dom_drop_proof(pf_row4);

    /* Margin Row */
    int row5_id = dom_next_id();
    void* pf_row5 = dom_create_element(pf_body, body_id, row5_id, (void*)s_div, 3);
    pf_row5 = dom_set_attr(pf_row5, row5_id, (void*)s_class, 5, (void*)s_settings_row, 12);
    int lbl5_id = dom_next_id();
    void* pf_lbl5 = dom_create_element(pf_row5, row5_id, lbl5_id, (void*)s_div, 3);
    pf_lbl5 = dom_set_attr(pf_lbl5, lbl5_id, (void*)s_class, 5, (void*)s_settings_label, 14);
    len = 0; len = settings_append_str(buf, len, s_margin_label);
    dom_set_text_offset(pf_lbl5, lbl5_id, 0, len);
    dom_drop_proof(pf_lbl5);
    int ctrl5_id = dom_next_id();
    void* pf_ctrl5 = dom_create_element(pf_row5, row5_id, ctrl5_id, (void*)s_div, 3);
    pf_ctrl5 = dom_set_attr(pf_ctrl5, ctrl5_id, (void*)s_class, 5, (void*)s_settings_controls, 17);
    btn_margin_minus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl5, ctrl5_id, btn_margin_minus_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_margin_minus_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    len = 0; len = settings_append_str(buf, len, s_minus);
    dom_set_text_offset(pf_btn, btn_margin_minus_id, 0, len);
    dom_drop_proof(pf_btn);
    disp_margin_id = dom_next_id();
    pf_val = dom_create_element(pf_ctrl5, ctrl5_id, disp_margin_id, (void*)s_div, 3);
    pf_val = dom_set_attr(pf_val, disp_margin_id, (void*)s_class, 5, (void*)s_settings_value, 14);
    len = 0; len = settings_append_int(buf, len, setting_margin); len = settings_append_str(buf, len, "rem");
    dom_set_text_offset(pf_val, disp_margin_id, 0, len);
    dom_drop_proof(pf_val);
    btn_margin_plus_id = dom_next_id();
    pf_btn = dom_create_element(pf_ctrl5, ctrl5_id, btn_margin_plus_id, (void*)s_div, 3);
    pf_btn = dom_set_attr(pf_btn, btn_margin_plus_id, (void*)s_class, 5, (void*)s_settings_btn, 12);
    len = 0; len = settings_append_str(buf, len, s_plus);
    dom_set_text_offset(pf_btn, btn_margin_plus_id, 0, len);
    dom_drop_proof(pf_btn);
    dom_drop_proof(pf_ctrl5);
    dom_drop_proof(pf_row5);

    dom_drop_proof(pf_body);
    dom_drop_proof(pf_modal);
    dom_drop_proof(pf_overlay);
    dom_drop_proof(pf);

    settings_visible = 1;
}

void settings_hide(void) {
    if (!settings_visible || settings_overlay_id == 0) return;

    void* pf = dom_root_proof();
    dom_remove_child(pf, settings_overlay_id);
    dom_drop_proof(pf);

    settings_visible = 0;
    settings_overlay_id = 0;
    settings_close_id = 0;
    btn_font_minus_id = 0; btn_font_plus_id = 0;
    btn_font_family_id = 0;
    btn_theme_light_id = 0; btn_theme_dark_id = 0; btn_theme_sepia_id = 0;
    btn_lh_minus_id = 0; btn_lh_plus_id = 0;
    btn_margin_minus_id = 0; btn_margin_plus_id = 0;
    disp_font_size_id = 0; disp_font_family_id = 0;
    disp_line_height_id = 0; disp_margin_id = 0;
}

void settings_toggle(void) {
    if (settings_visible) settings_hide();
    else settings_show();
}

int settings_handle_click(int node_id) {
    if (!settings_visible) return 0;
    if (node_id == settings_close_id) { settings_hide(); return 1; }
    if (node_id == btn_font_minus_id) { settings_decrease_font_size(); return 1; }
    if (node_id == btn_font_plus_id) { settings_increase_font_size(); return 1; }
    if (node_id == btn_font_family_id) { settings_next_font_family(); return 1; }
    if (node_id == btn_theme_light_id) { settings_set_theme(0); settings_apply(); apply_theme_to_body(); update_display_values(); settings_save(); return 1; }
    if (node_id == btn_theme_dark_id) { settings_set_theme(1); settings_apply(); apply_theme_to_body(); update_display_values(); settings_save(); return 1; }
    if (node_id == btn_theme_sepia_id) { settings_set_theme(2); settings_apply(); apply_theme_to_body(); update_display_values(); settings_save(); return 1; }
    if (node_id == btn_lh_minus_id) { settings_decrease_line_height(); return 1; }
    if (node_id == btn_lh_plus_id) { settings_increase_line_height(); return 1; }
    if (node_id == btn_margin_minus_id) { settings_decrease_margin(); return 1; }
    if (node_id == btn_margin_plus_id) { settings_increase_margin(); return 1; }
    return 0;
}

void settings_set_root_id(int id) { settings_root_id = id; }
int settings_is_save_pending(void) { return settings_save_pending; }
int settings_is_load_pending(void) { return settings_load_pending; }

/* ========== EPUB module (moved from epub.dats %{^ block) ========== */

/* External: bridge imports (not already declared above) */
extern void js_file_open(int node_id);
extern int js_file_read_chunk(int handle, int offset, int length);
extern void js_file_close(int handle);
extern void js_decompress(int file_handle, int offset, int compressed_size, int method);
extern int js_blob_read_chunk(int handle, int offset, int length);
extern int js_blob_size(int handle);
extern void js_blob_free(int handle);
extern void js_kv_open(void* name_ptr, int name_len, int version, void* stores_ptr, int stores_len);
extern void js_kv_put_blob(void* store_ptr, int store_len, void* key_ptr, int key_len, int blob_handle);

/* External: ZIP functions (from zip.dats) */
extern void zip_init(void);
extern int zip_open(int file_handle, int file_size);
extern int zip_get_entry(int index, void* entry);
extern int zip_get_entry_name(int index, int buf_offset);
extern int zip_entry_name_ends_with(int index, void* suffix, int suffix_len);
extern int zip_entry_name_equals(int index, void* name, int name_len);
extern int zip_find_entry(void* name, int name_len);
extern int zip_get_data_offset(int index);
extern int zip_get_entry_count(void);
extern void zip_close(void);

/* External: XML tree functions (from xml.dats) */
extern void* xml_parse(int data_len);
extern void xml_free_tree(void* tree);
extern void* xml_find_element(void* tree, void* name, int name_len);
extern void* xml_first_child(void* node);
extern void* xml_next_sibling(void* cursor);
extern void* xml_node_at(void* cursor);
extern int xml_node_is_element(void* node);
extern int xml_node_name_is(void* node, void* name, int name_len);
extern int xml_node_get_attr(void* node, void* name, int name_len, int buf_offset);
extern int xml_node_get_text(void* node, int buf_offset);

/* Forward declarations */
static void process_next_entry(void);
void epub_continue(void);

/* Constants */
#define MAX_TITLE_LEN 256
#define MAX_AUTHOR_LEN 256
#define MAX_OPF_PATH_LEN 256
#define MAX_BOOK_ID_LEN 64
#define MAX_SPINE_ITEMS 256
#define MAX_MANIFEST_ITEMS 512

/* String constants (str_books already defined in library section above) */
static const char str_container_path[] = "META-INF/container.xml";
static const char str_rootfile[] = "rootfile";
static const char str_full_path[] = "full-path";
static const char str_metadata[] = "metadata";
static const char str_dc_title[] = "dc:title";
static const char str_title[] = "title";
static const char str_dc_creator[] = "dc:creator";
static const char str_creator[] = "creator";
static const char str_manifest[] = "manifest";
static const char str_item[] = "item";
static const char str_id[] = "id";
static const char str_href[] = "href";
static const char str_media_type[] = "media-type";
static const char str_spine[] = "spine";
static const char str_itemref[] = "itemref";
static const char str_idref[] = "idref";
static const char str_chapters[] = "chapters";
static const char str_resources[] = "resources";
static const char str_stores[] = "books,chapters,resources,settings";
static const char str_quire_db[] = "quire";
static const char str_xhtml[] = "application/xhtml+xml";
static const char str_html[] = "text/html";
static const char str_opf_suffix[] = ".opf";
static const char str_ncx_suffix[] = ".ncx";
static const char str_unknown[] = "Unknown";

/* M13: NCX/TOC parsing string constants */
static const char str_navMap[] = "navMap";
static const char str_navPoint[] = "navPoint";
static const char str_navLabel[] = "navLabel";
static const char str_text[] = "text";
static const char str_content[] = "content";
static const char str_src[] = "src";

/* Manifest item */
typedef struct {
    int id_offset;          /* Offset in manifest_strings */
    int id_len;
    int href_offset;
    int href_len;
    int media_type;         /* 0=other, 1=xhtml, 2=css, 3=image, 4=font */
    int zip_index;          /* Index in ZIP central directory */
} manifest_item_t;

/* M13: TOC entry */
#define MAX_TOC_ENTRIES 256
#define MAX_TOC_LABEL_LEN 128

typedef struct {
    int label_offset;       /* Offset in toc_strings */
    int label_len;
    int href_offset;        /* Offset in toc_strings */
    int href_len;
    int spine_index;        /* Index into spine (-1 if not found) */
    int nesting_level;      /* 0 = top level, 1 = nested, etc. */
} toc_entry_t;

/* EPUB import state */
static int epub_state = 0;  /* EPUB_STATE_IDLE */
static int epub_progress = 0;
static char epub_error[128] = {0};
static int epub_error_len = 0;

/* File and book info */
static int file_handle = 0;
static int file_size = 0;
static char book_title[MAX_TITLE_LEN] = {0};
static int book_title_len = 0;
static char book_author[MAX_AUTHOR_LEN] = {0};
static int book_author_len = 0;
static char book_id[MAX_BOOK_ID_LEN] = {0};
static int book_id_len = 0;
static char opf_path[MAX_OPF_PATH_LEN] = {0};
static int opf_path_len = 0;
static char opf_dir[MAX_OPF_PATH_LEN] = {0};
static int opf_dir_len = 0;

/* Manifest and spine */
static char manifest_strings[4096] = {0};
static int manifest_strings_offset = 0;
static manifest_item_t manifest_items[MAX_MANIFEST_ITEMS];
static int manifest_count = 0;
static int spine_manifest_indices[MAX_SPINE_ITEMS];
static int spine_count = 0;

/* M13: TOC storage */
static char toc_strings[8192] = {0};
static int toc_strings_offset = 0;
static toc_entry_t toc_entries[MAX_TOC_ENTRIES];
static int toc_count = 0;
static int ncx_zip_index = -1;  /* ZIP index of NCX file */

/* Processing state */
static int current_entry_index = 0;
static int total_entries = 0;
static int current_blob_handle = 0;

/* Helper: Set error message */
static void epub_set_error(const char* msg) {
    int i = 0;
    while (msg[i] && i < 127) {
        epub_error[i] = msg[i];
        i++;
    }
    epub_error[i] = 0;
    epub_error_len = i;
    epub_state = 99;  /* EPUB_STATE_ERROR */
}

/* Helper: Copy string from source to dest */
static int epub_copy_string(const unsigned char* src, int src_len, char* dest, int max_len) {
    int len = src_len < max_len ? src_len : max_len - 1;
    for (int i = 0; i < len; i++) {
        dest[i] = src[i];
    }
    dest[len] = 0;
    return len;
}

/* Helper: Simple hash for book ID */
static void generate_book_id(void) {
    unsigned int hash = 5381;
    for (int i = 0; i < book_title_len; i++) {
        hash = ((hash << 5) + hash) + (unsigned char)book_title[i];
    }
    for (int i = 0; i < book_author_len; i++) {
        hash = ((hash << 5) + hash) + (unsigned char)book_author[i];
    }

    /* Convert hash to hex string */
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 8; i++) {
        book_id[i] = hex[(hash >> (28 - i * 4)) & 0xf];
    }
    book_id[8] = 0;
    book_id_len = 8;
}

/* Helper: Find manifest item by ID */
static int find_manifest_by_id(const unsigned char* id, int id_len) {
    for (int i = 0; i < manifest_count; i++) {
        if (manifest_items[i].id_len == id_len) {
            int match = 1;
            for (int j = 0; j < id_len && match; j++) {
                if (manifest_strings[manifest_items[i].id_offset + j] != id[j]) {
                    match = 0;
                }
            }
            if (match) return i;
        }
    }
    return -1;
}

/* M13: Helper: Find spine index from href (handles fragment identifiers) */
static int find_spine_index_by_href(const unsigned char* href, int href_len) {
    /* Extract path without fragment (e.g., "chapter1.xhtml" from "chapter1.xhtml#section1") */
    int path_len = href_len;
    for (int i = 0; i < href_len; i++) {
        if (href[i] == '#') {
            path_len = i;
            break;
        }
    }

    /* Try to find matching manifest item by href */
    for (int i = 0; i < manifest_count; i++) {
        manifest_item_t* item = &manifest_items[i];
        if (item->href_len == path_len) {
            int match = 1;
            for (int j = 0; j < path_len && match; j++) {
                if (manifest_strings[item->href_offset + j] != href[j]) {
                    match = 0;
                }
            }
            if (match) {
                /* Found manifest item, now find in spine */
                for (int s = 0; s < spine_count; s++) {
                    if (spine_manifest_indices[s] == i) {
                        return s;
                    }
                }
            }
        }
    }

    return -1;
}

/* Helper: Get OPF directory path */
static void extract_opf_dir(void) {
    opf_dir_len = 0;
    /* Find last '/' in OPF path */
    int last_slash = -1;
    for (int i = 0; i < opf_path_len; i++) {
        if (opf_path[i] == '/') last_slash = i;
    }
    if (last_slash > 0) {
        for (int i = 0; i <= last_slash; i++) {
            opf_dir[i] = opf_path[i];
        }
        opf_dir_len = last_slash + 1;
    }
    opf_dir[opf_dir_len] = 0;
}

/* Parse container.xml to find OPF path */
static int parse_container(void) {
    unsigned char* buf = get_fetch_buffer_ptr();

    /* Find container.xml in ZIP */
    int entry_idx = zip_find_entry((void*)str_container_path, 22);
    if (entry_idx < 0) {
        epub_set_error("Missing container.xml");
        return 0;
    }

    /* Get entry info */
    int entry_data[7];
    if (!zip_get_entry(entry_idx, entry_data)) {
        epub_set_error("Failed to read container entry");
        return 0;
    }

    int compression = entry_data[3];
    int compressed_size = entry_data[4];
    int data_offset = zip_get_data_offset(entry_idx);

    if (compression == 0) {
        /* Stored - read directly */
        int read_len = js_file_read_chunk(file_handle, data_offset, compressed_size);
        if (read_len <= 0) {
            epub_set_error("Failed to read container.xml");
            return 0;
        }

        void* tree = xml_parse(read_len);
        if (!tree) {
            epub_set_error("XML parse failed");
            return 0;
        }

        /* Find <rootfile full-path="..."> */
        void* rf = xml_find_element(tree, (void*)str_rootfile, 8);
        if (rf) {
            int path_len = xml_node_get_attr(rf, (void*)str_full_path, 9, 0);
            if (path_len > 0) {
                unsigned char* str_buf = get_string_buffer_ptr();
                opf_path_len = epub_copy_string(str_buf, path_len, opf_path, MAX_OPF_PATH_LEN);
                extract_opf_dir();
                xml_free_tree(tree);
                return 1;
            }
        }
        xml_free_tree(tree);
        epub_set_error("No rootfile in container.xml");
        return 0;
    } else {
        /* Deflated - need async decompression */
        epub_set_error("Compressed container.xml not yet supported");
        return 0;
    }
}

/* Parse OPF file for metadata, manifest, and spine */
static int parse_opf(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Find OPF in ZIP */
    int entry_idx = zip_find_entry(opf_path, opf_path_len);
    if (entry_idx < 0) {
        epub_set_error("OPF file not found in ZIP");
        return 0;
    }

    /* Get entry info */
    int entry_data[7];
    if (!zip_get_entry(entry_idx, entry_data)) {
        epub_set_error("Failed to read OPF entry");
        return 0;
    }

    int compression = entry_data[3];
    int compressed_size = entry_data[4];
    int data_offset = zip_get_data_offset(entry_idx);

    if (compression != 0) {
        epub_set_error("Compressed OPF not yet supported");
        return 0;
    }

    /* Read OPF content */
    int read_len = js_file_read_chunk(file_handle, data_offset, compressed_size);
    if (read_len <= 0) {
        epub_set_error("Failed to read OPF content");
        return 0;
    }

    void* tree = xml_parse(read_len);
    if (!tree) {
        epub_set_error("XML parse failed for OPF");
        return 0;
    }

    /* Reset manifest and spine */
    manifest_count = 0;
    manifest_strings_offset = 0;
    spine_count = 0;

    /* Parse metadata: find <metadata> and iterate children */
    void* meta_node = xml_find_element(tree, (void*)str_metadata, 8);
    if (meta_node) {
        void* mc = xml_first_child(meta_node);
        while (mc) {
            void* child = xml_node_at(mc);
            if (child && xml_node_is_element(child)) {
                if ((xml_node_name_is(child, (void*)str_dc_title, 8) ||
                     xml_node_name_is(child, (void*)str_title, 5)) && book_title_len == 0) {
                    int len = xml_node_get_text(child, 0);
                    if (len > 0) {
                        book_title_len = epub_copy_string(str_buf, len, book_title, MAX_TITLE_LEN);
                    }
                } else if ((xml_node_name_is(child, (void*)str_dc_creator, 10) ||
                            xml_node_name_is(child, (void*)str_creator, 7)) && book_author_len == 0) {
                    int len = xml_node_get_text(child, 0);
                    if (len > 0) {
                        book_author_len = epub_copy_string(str_buf, len, book_author, MAX_AUTHOR_LEN);
                    }
                }
            }
            mc = xml_next_sibling(mc);
        }
    }

    /* Parse manifest: find <manifest> and iterate <item> children */
    void* manifest_node = xml_find_element(tree, (void*)str_manifest, 8);
    if (manifest_node) {
        void* mc = xml_first_child(manifest_node);
        while (mc) {
            void* child = xml_node_at(mc);
            if (child && xml_node_name_is(child, (void*)str_item, 4) &&
                manifest_count < MAX_MANIFEST_ITEMS) {
                manifest_item_t* item = &manifest_items[manifest_count];

                /* Get id attribute */
                int id_len = xml_node_get_attr(child, (void*)str_id, 2, 0);
                if (id_len > 0 && manifest_strings_offset + id_len < 4096) {
                    item->id_offset = manifest_strings_offset;
                    item->id_len = id_len;
                    for (int i = 0; i < id_len; i++) {
                        manifest_strings[manifest_strings_offset++] = str_buf[i];
                    }
                } else {
                    mc = xml_next_sibling(mc);
                    continue;
                }

                /* Get href attribute */
                int href_len = xml_node_get_attr(child, (void*)str_href, 4, 0);
                if (href_len > 0 && manifest_strings_offset + href_len < 4096) {
                    item->href_offset = manifest_strings_offset;
                    item->href_len = href_len;
                    for (int i = 0; i < href_len; i++) {
                        manifest_strings[manifest_strings_offset++] = str_buf[i];
                    }
                } else {
                    mc = xml_next_sibling(mc);
                    continue;
                }

                /* Get media-type */
                int mt_len = xml_node_get_attr(child, (void*)str_media_type, 10, 0);
                item->media_type = 0;
                if (mt_len > 0) {
                    /* Check for xhtml */
                    int is_xhtml = 1;
                    const char* xhtml = str_xhtml;
                    for (int i = 0; i < 20 && i < mt_len && is_xhtml; i++) {
                        if (str_buf[i] != xhtml[i]) is_xhtml = 0;
                    }
                    if (is_xhtml && mt_len >= 20) item->media_type = 1;

                    /* Check for text/html */
                    if (item->media_type == 0) {
                        int is_html = 1;
                        const char* html = str_html;
                        for (int i = 0; i < 9 && i < mt_len && is_html; i++) {
                            if (str_buf[i] != html[i]) is_html = 0;
                        }
                        if (is_html && mt_len >= 9) item->media_type = 1;
                    }
                }

                /* Find corresponding ZIP entry */
                char full_path[512];
                int full_len = 0;
                for (int i = 0; i < opf_dir_len && full_len < 511; i++) {
                    full_path[full_len++] = opf_dir[i];
                }
                for (int i = 0; i < item->href_len && full_len < 511; i++) {
                    full_path[full_len++] = manifest_strings[item->href_offset + i];
                }
                full_path[full_len] = 0;

                item->zip_index = zip_find_entry(full_path, full_len);
                manifest_count++;
            }
            mc = xml_next_sibling(mc);
        }
    }

    /* Parse spine: find <spine> and iterate <itemref> children */
    void* spine_node = xml_find_element(tree, (void*)str_spine, 5);
    if (spine_node) {
        void* mc = xml_first_child(spine_node);
        while (mc) {
            void* child = xml_node_at(mc);
            if (child && xml_node_name_is(child, (void*)str_itemref, 7) &&
                spine_count < MAX_SPINE_ITEMS) {
                int idref_len = xml_node_get_attr(child, (void*)str_idref, 5, 0);
                if (idref_len > 0) {
                    int manifest_idx = find_manifest_by_id(str_buf, idref_len);
                    if (manifest_idx >= 0) {
                        spine_manifest_indices[spine_count++] = manifest_idx;
                    }
                }
            }
            mc = xml_next_sibling(mc);
        }
    }

    xml_free_tree(tree);

    /* Set defaults if metadata missing */
    if (book_title_len == 0) {
        book_title_len = epub_copy_string((const unsigned char*)str_unknown, 7, book_title, MAX_TITLE_LEN);
    }
    if (book_author_len == 0) {
        book_author_len = epub_copy_string((const unsigned char*)str_unknown, 7, book_author, MAX_AUTHOR_LEN);
    }

    generate_book_id();

    /* Find NCX file in manifest */
    ncx_zip_index = -1;
    for (int i = 0; i < zip_get_entry_count(); i++) {
        if (zip_entry_name_ends_with(i, (void*)str_ncx_suffix, 4)) {
            ncx_zip_index = i;
            break;
        }
    }

    return 1;
}

/* M13: Helper: process navPoint children recursively */
static void parse_ncx_navpoints(void* parent, int level) {
    unsigned char* str_buf = get_string_buffer_ptr();
    void* cursor = xml_first_child(parent);
    while (cursor) {
        void* child = xml_node_at(cursor);
        if (child && xml_node_name_is(child, (void*)str_navPoint, 8)) {
            /* Found a navPoint - extract label and content src */
            int label_offset = 0;
            int label_len = 0;
            int has_label = 0;

            /* Find navLabel > text for label */
            void* label_node = xml_find_element(child, (void*)str_text, 4);
            if (label_node) {
                int len = xml_node_get_text(label_node, 0);
                if (len > 0 && toc_strings_offset + len < 8190) {
                    label_offset = toc_strings_offset;
                    label_len = len < MAX_TOC_LABEL_LEN ? len : MAX_TOC_LABEL_LEN;
                    for (int i = 0; i < label_len; i++) {
                        toc_strings[toc_strings_offset++] = str_buf[i];
                    }
                    has_label = 1;
                }
            }

            /* Find content[@src] */
            void* content_node = xml_find_element(child, (void*)str_content, 7);
            if (content_node && has_label && toc_count < MAX_TOC_ENTRIES) {
                int src_len = xml_node_get_attr(content_node, (void*)str_src, 3, 0);
                if (src_len > 0) {
                    toc_entry_t* entry = &toc_entries[toc_count];
                    entry->label_offset = label_offset;
                    entry->label_len = label_len;

                    /* Store href */
                    entry->href_offset = toc_strings_offset;
                    entry->href_len = src_len < 256 ? src_len : 255;
                    if (toc_strings_offset + entry->href_len < 8190) {
                        for (int i = 0; i < entry->href_len; i++) {
                            toc_strings[toc_strings_offset++] = str_buf[i];
                        }
                    }

                    entry->spine_index = find_spine_index_by_href(str_buf, src_len);
                    entry->nesting_level = level;
                    toc_count++;
                }
            }

            /* Recurse into nested navPoints */
            parse_ncx_navpoints(child, level + 1);
        }
        cursor = xml_next_sibling(cursor);
    }
}

/* M13: Parse NCX file for Table of Contents */
static int parse_ncx(void) {
    if (ncx_zip_index < 0) return 0;  /* No NCX file found */

    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();

    /* Get NCX entry info */
    int entry_data[7];
    if (!zip_get_entry(ncx_zip_index, entry_data)) {
        return 0;
    }

    int compression = entry_data[3];
    int compressed_size = entry_data[4];
    int data_offset = zip_get_data_offset(ncx_zip_index);

    if (compression != 0) {
        /* Compressed NCX not supported for now */
        return 0;
    }

    /* Read NCX content */
    int read_len = js_file_read_chunk(file_handle, data_offset, compressed_size);
    if (read_len <= 0) {
        return 0;
    }

    void* tree = xml_parse(read_len);
    if (!tree) {
        return 0;
    }

    /* Reset TOC state */
    toc_count = 0;
    toc_strings_offset = 0;

    /* Find <navMap> element */
    void* navMap = xml_find_element(tree, (void*)str_navMap, 6);
    if (navMap) {
        /* Process navPoints recursively via helper */
        parse_ncx_navpoints(navMap, 0);
    }

    xml_free_tree(tree);
    return toc_count > 0 ? 1 : 0;
}

/* Start storing entries in IndexedDB */
static void start_storing(void) {
    epub_state = 6;  /* EPUB_STATE_DECOMPRESSING */
    current_entry_index = 0;
    total_entries = zip_get_entry_count();
    epub_progress = 0;

    epub_continue();
}

/* Process next entry */
static void process_next_entry(void) {
    while (current_entry_index < total_entries) {
        int idx = current_entry_index;

        /* Get entry info */
        int entry_data[7];
        if (!zip_get_entry(idx, entry_data)) {
            current_entry_index++;
            continue;
        }

        int compression = entry_data[3];
        int compressed_size = entry_data[4];
        int uncompressed_size = entry_data[5];

        /* Skip directories (end with /) and empty files */
        unsigned char* str_buf = get_string_buffer_ptr();
        int name_len = zip_get_entry_name(idx, 0);
        if (name_len > 0 && str_buf[name_len - 1] == '/') {
            current_entry_index++;
            continue;
        }
        if (uncompressed_size == 0 && compressed_size == 0) {
            current_entry_index++;
            continue;
        }

        /* Skip OPF and container.xml - we don't need to store them */
        if (zip_entry_name_ends_with(idx, (void*)str_opf_suffix, 4) ||
            zip_entry_name_ends_with(idx, (void*)str_ncx_suffix, 4) ||
            zip_entry_name_equals(idx, (void*)str_container_path, 22)) {
            current_entry_index++;
            continue;
        }

        int data_offset = zip_get_data_offset(idx);
        if (data_offset < 0) {
            current_entry_index++;
            continue;
        }

        if (compression == 8) {
            /* Deflate - need async decompression */
            js_decompress(file_handle, data_offset, compressed_size, 0);
            return;  /* Wait for callback */
        } else if (compression == 0) {
            /* Stored - read and store directly */
            int read_len = js_file_read_chunk(file_handle, data_offset, uncompressed_size);
            if (read_len > 0) {
                /* Store directly from fetch buffer */
                unsigned char* str_buf2 = get_string_buffer_ptr();
                int name_len2 = zip_get_entry_name(idx, 0);

                /* Build key: book_id/path */
                char key[600];
                int key_len = 0;
                for (int i = 0; i < book_id_len && key_len < 599; i++) {
                    key[key_len++] = book_id[i];
                }
                key[key_len++] = '/';
                for (int i = 0; i < name_len2 && key_len < 599; i++) {
                    key[key_len++] = str_buf2[i];
                }

                /* Determine store based on content type */
                const char* store = str_resources;
                int store_len = 9;

                /* Check if this is a chapter (in spine) */
                for (int i = 0; i < manifest_count; i++) {
                    if (manifest_items[i].zip_index == idx && manifest_items[i].media_type == 1) {
                        /* Check if in spine */
                        for (int j = 0; j < spine_count; j++) {
                            if (spine_manifest_indices[j] == i) {
                                store = str_chapters;
                                store_len = 8;
                                break;
                            }
                        }
                        break;
                    }
                }

                js_kv_put((void*)store, store_len, key, key_len, 0, read_len);
                epub_state = 7;  /* EPUB_STATE_STORING */
                return;  /* Wait for callback */
            }
        }

        current_entry_index++;
    }

    /* All entries processed */
    epub_state = 8;  /* EPUB_STATE_DONE */
    epub_progress = 100;
}

/* Public API */

void epub_init(void) {
    epub_state = 0;
    epub_progress = 0;
    epub_error[0] = 0;
    epub_error_len = 0;
    file_handle = 0;
    file_size = 0;
    book_title[0] = 0;
    book_title_len = 0;
    book_author[0] = 0;
    book_author_len = 0;
    book_id[0] = 0;
    book_id_len = 0;
    opf_path[0] = 0;
    opf_path_len = 0;
    opf_dir[0] = 0;
    opf_dir_len = 0;
    manifest_count = 0;
    manifest_strings_offset = 0;
    spine_count = 0;
    current_entry_index = 0;
    total_entries = 0;
    current_blob_handle = 0;
    /* M13: Reset TOC state */
    toc_count = 0;
    toc_strings_offset = 0;
    ncx_zip_index = -1;
}

int epub_start_import(int file_input_node_id) {
    epub_init();
    epub_state = 1;  /* EPUB_STATE_OPENING_FILE */
    js_file_open(file_input_node_id);
    return 1;
}

int epub_get_state(void) {
    return epub_state;
}

int epub_get_progress(void) {
    return epub_progress;
}

int epub_get_error(int buf_offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (int i = 0; i < epub_error_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = epub_error[i];
    }
    return epub_error_len;
}

int epub_get_title(int buf_offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (int i = 0; i < book_title_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = book_title[i];
    }
    return book_title_len;
}

int epub_get_author(int buf_offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (int i = 0; i < book_author_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = book_author[i];
    }
    return book_author_len;
}

int epub_get_book_id(int buf_offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (int i = 0; i < book_id_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = book_id[i];
    }
    return book_id_len;
}

int epub_get_chapter_count(void) {
    return spine_count;
}

int epub_get_chapter_key(int chapter_index, int buf_offset) {
    if (chapter_index < 0 || chapter_index >= spine_count) return 0;

    unsigned char* buf = get_string_buffer_ptr();
    int key_len = 0;

    /* Add book_id prefix */
    for (int i = 0; i < book_id_len && key_len + buf_offset < 4096; i++) {
        buf[buf_offset + key_len++] = book_id[i];
    }

    /* Add separator */
    if (key_len + buf_offset < 4096) {
        buf[buf_offset + key_len++] = '/';
    }

    /* Get manifest item for this spine entry */
    int manifest_idx = spine_manifest_indices[chapter_index];
    if (manifest_idx < 0 || manifest_idx >= manifest_count) return 0;

    manifest_item_t* item = &manifest_items[manifest_idx];

    /* Add OPF directory prefix (chapters are stored with full path from ZIP root) */
    for (int i = 0; i < opf_dir_len && key_len + buf_offset < 4096; i++) {
        buf[buf_offset + key_len++] = opf_dir[i];
    }

    /* Add chapter href */
    for (int i = 0; i < item->href_len && key_len + buf_offset < 4096; i++) {
        buf[buf_offset + key_len++] = manifest_strings[item->href_offset + i];
    }

    return key_len;
}

void epub_continue(void) {
    switch (epub_state) {
        case 6:  /* EPUB_STATE_DECOMPRESSING */
        case 7:  /* EPUB_STATE_STORING */
            process_next_entry();
            break;
        default:
            break;
    }
}

void epub_on_file_open(int handle, int size) {
    if (handle == 0) {
        epub_set_error("Failed to open file");
        return;
    }

    file_handle = handle;
    file_size = size;
    epub_state = 2;  /* EPUB_STATE_PARSING_ZIP */

    /* Parse ZIP */
    zip_init();
    int entry_count = zip_open(handle, size);
    if (entry_count == 0) {
        epub_set_error("Invalid ZIP file");
        return;
    }

    epub_state = 3;  /* EPUB_STATE_READING_CONTAINER */

    /* Parse container.xml */
    if (!parse_container()) {
        return;  /* Error already set */
    }

    epub_state = 4;  /* EPUB_STATE_READING_OPF */

    /* Parse OPF */
    if (!parse_opf()) {
        return;  /* Error already set */
    }

    /* M13: Parse NCX for TOC (optional - don't fail if missing) */
    parse_ncx();

    epub_state = 5;  /* EPUB_STATE_OPENING_DB */

    /* Open IndexedDB */
    js_kv_open((void*)str_quire_db, 5, 1, (void*)str_stores, 24);
}

void epub_on_decompress(int blob_handle, int size) {
    if (blob_handle == 0) {
        /* Decompression failed - skip this entry */
        current_entry_index++;
        process_next_entry();
        return;
    }

    current_blob_handle = blob_handle;

    /* Get entry name for key */
    unsigned char* str_buf = get_string_buffer_ptr();
    int name_len = zip_get_entry_name(current_entry_index, 0);

    /* Build key: book_id/path */
    char key[600];
    int key_len = 0;
    for (int i = 0; i < book_id_len && key_len < 599; i++) {
        key[key_len++] = book_id[i];
    }
    key[key_len++] = '/';
    for (int i = 0; i < name_len && key_len < 599; i++) {
        key[key_len++] = str_buf[i];
    }

    /* Determine store */
    const char* store = str_resources;
    int store_len = 9;

    /* Check if this is a chapter */
    for (int i = 0; i < manifest_count; i++) {
        if (manifest_items[i].zip_index == current_entry_index && manifest_items[i].media_type == 1) {
            for (int j = 0; j < spine_count; j++) {
                if (spine_manifest_indices[j] == i) {
                    store = str_chapters;
                    store_len = 8;
                    break;
                }
            }
            break;
        }
    }

    epub_state = 7;  /* EPUB_STATE_STORING */
    js_kv_put_blob((void*)store, store_len, key, key_len, blob_handle);
}

void epub_on_db_open(int success) {
    if (!success) {
        epub_set_error("Failed to open database");
        return;
    }

    /* Start storing entries */
    start_storing();
}

void epub_on_db_put(int success) {
    /* Free blob handle if we have one */
    if (current_blob_handle > 0) {
        js_blob_free(current_blob_handle);
        current_blob_handle = 0;
    }

    /* Update progress */
    current_entry_index++;
    if (total_entries > 0) {
        epub_progress = (current_entry_index * 100) / total_entries;
    }

    /* Continue with next entry */
    epub_state = 6;  /* EPUB_STATE_DECOMPRESSING */
    process_next_entry();
}

void epub_cancel(void) {
    if (current_blob_handle > 0) {
        js_blob_free(current_blob_handle);
        current_blob_handle = 0;
    }
    if (file_handle > 0) {
        js_file_close(file_handle);
        file_handle = 0;
    }
    zip_close();
    epub_state = 0;
}

/* M13: TOC API functions */

int epub_get_toc_count(void) {
    return toc_count;
}

int epub_get_toc_label(int toc_index, int buf_offset) {
    if (toc_index < 0 || toc_index >= toc_count) return 0;

    unsigned char* buf = get_string_buffer_ptr();
    toc_entry_t* entry = &toc_entries[toc_index];

    for (int i = 0; i < entry->label_len && buf_offset + i < 4096; i++) {
        buf[buf_offset + i] = toc_strings[entry->label_offset + i];
    }
    return entry->label_len;
}

int epub_get_toc_chapter(int toc_index) {
    if (toc_index < 0 || toc_index >= toc_count) return -1;
    return toc_entries[toc_index].spine_index;
}

int epub_get_toc_level(int toc_index) {
    if (toc_index < 0 || toc_index >= toc_count) return 0;
    return toc_entries[toc_index].nesting_level;
}

int epub_get_chapter_title(int spine_index, int buf_offset) {
    if (spine_index < 0 || spine_index >= spine_count) return 0;

    unsigned char* buf = get_string_buffer_ptr();

    /* Find first TOC entry that matches this spine index */
    for (int i = 0; i < toc_count; i++) {
        if (toc_entries[i].spine_index == spine_index) {
            toc_entry_t* entry = &toc_entries[i];
            for (int j = 0; j < entry->label_len && buf_offset + j < 4096; j++) {
                buf[buf_offset + j] = toc_strings[entry->label_offset + j];
            }
            return entry->label_len;
        }
    }

    return 0;  /* No TOC entry found for this chapter */
}

/* M15: Helper to write uint16 LE to buffer */
static void epub_write_u16(unsigned char* buf, int offset, int value) {
    buf[offset] = value & 0xff;
    buf[offset + 1] = (value >> 8) & 0xff;
}

/* M15: Helper to read uint16 LE from buffer */
static int epub_read_u16(unsigned char* buf, int offset) {
    return buf[offset] | (buf[offset + 1] << 8);
}

/* M15: Helper to read int16 LE from buffer (signed) */
static int epub_read_i16(unsigned char* buf, int offset) {
    int v = buf[offset] | (buf[offset + 1] << 8);
    if (v >= 0x8000) v -= 0x10000;
    return v;
}

/* M15: Serialize book metadata to fetch buffer. */
int epub_serialize_metadata(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    int pos = 0;
    int max = 16384;

    /* book_id */
    epub_write_u16(buf, pos, book_id_len); pos += 2;
    for (int i = 0; i < book_id_len && pos < max; i++) buf[pos++] = book_id[i];

    /* title */
    epub_write_u16(buf, pos, book_title_len); pos += 2;
    for (int i = 0; i < book_title_len && pos < max; i++) buf[pos++] = book_title[i];

    /* author */
    epub_write_u16(buf, pos, book_author_len); pos += 2;
    for (int i = 0; i < book_author_len && pos < max; i++) buf[pos++] = book_author[i];

    /* opf_dir */
    epub_write_u16(buf, pos, opf_dir_len); pos += 2;
    for (int i = 0; i < opf_dir_len && pos < max; i++) buf[pos++] = opf_dir[i];

    /* spine */
    epub_write_u16(buf, pos, spine_count); pos += 2;
    for (int s = 0; s < spine_count; s++) {
        int mi = spine_manifest_indices[s];
        if (mi >= 0 && mi < manifest_count) {
            manifest_item_t* item = &manifest_items[mi];
            epub_write_u16(buf, pos, item->href_len); pos += 2;
            for (int i = 0; i < item->href_len && pos < max; i++) {
                buf[pos++] = manifest_strings[item->href_offset + i];
            }
        } else {
            epub_write_u16(buf, pos, 0); pos += 2;
        }
    }

    /* toc */
    epub_write_u16(buf, pos, toc_count); pos += 2;
    for (int t = 0; t < toc_count; t++) {
        toc_entry_t* entry = &toc_entries[t];
        epub_write_u16(buf, pos, entry->label_len); pos += 2;
        epub_write_u16(buf, pos, (unsigned int)(entry->spine_index) & 0xffff); pos += 2;
        epub_write_u16(buf, pos, entry->nesting_level); pos += 2;
        for (int i = 0; i < entry->label_len && pos < max; i++) {
            buf[pos++] = toc_strings[entry->label_offset + i];
        }
    }

    return pos;
}

/* M15: Restore book metadata from fetch buffer. */
int epub_restore_metadata(int len) {
    unsigned char* buf = get_fetch_buffer_ptr();
    int pos = 0;

    if (len < 12) return 0;  /* Minimum: 6 u16 headers */

    /* Reset state */
    epub_state = 8;  /* EPUB_STATE_DONE - ready to read */
    epub_progress = 100;
    manifest_count = 0;
    manifest_strings_offset = 0;
    spine_count = 0;
    toc_count = 0;
    toc_strings_offset = 0;

    /* book_id */
    int id_len = epub_read_u16(buf, pos); pos += 2;
    if (id_len > MAX_BOOK_ID_LEN - 1) id_len = MAX_BOOK_ID_LEN - 1;
    for (int i = 0; i < id_len; i++) book_id[i] = buf[pos++];
    book_id[id_len] = 0;
    book_id_len = id_len;

    /* title */
    int tlen = epub_read_u16(buf, pos); pos += 2;
    if (tlen > MAX_TITLE_LEN - 1) tlen = MAX_TITLE_LEN - 1;
    for (int i = 0; i < tlen; i++) book_title[i] = buf[pos++];
    book_title[tlen] = 0;
    book_title_len = tlen;

    /* author */
    int alen = epub_read_u16(buf, pos); pos += 2;
    if (alen > MAX_AUTHOR_LEN - 1) alen = MAX_AUTHOR_LEN - 1;
    for (int i = 0; i < alen; i++) book_author[i] = buf[pos++];
    book_author[alen] = 0;
    book_author_len = alen;

    /* opf_dir */
    int dlen = epub_read_u16(buf, pos); pos += 2;
    if (dlen > MAX_OPF_PATH_LEN - 1) dlen = MAX_OPF_PATH_LEN - 1;
    for (int i = 0; i < dlen; i++) opf_dir[i] = buf[pos++];
    opf_dir[dlen] = 0;
    opf_dir_len = dlen;

    /* spine: create one manifest item per spine entry */
    int sc = epub_read_u16(buf, pos); pos += 2;
    if (sc > MAX_SPINE_ITEMS) sc = MAX_SPINE_ITEMS;
    spine_count = sc;
    manifest_count = 0;
    manifest_strings_offset = 0;

    for (int s = 0; s < sc; s++) {
        int href_len = epub_read_u16(buf, pos); pos += 2;
        if (manifest_count < MAX_MANIFEST_ITEMS && manifest_strings_offset + href_len < 4096) {
            manifest_item_t* item = &manifest_items[manifest_count];
            item->id_offset = 0;
            item->id_len = 0;
            item->href_offset = manifest_strings_offset;
            item->href_len = href_len;
            item->media_type = 1;  /* xhtml */
            item->zip_index = -1;
            for (int i = 0; i < href_len; i++) {
                manifest_strings[manifest_strings_offset++] = buf[pos++];
            }
            spine_manifest_indices[s] = manifest_count;
            manifest_count++;
        } else {
            pos += href_len;
            spine_manifest_indices[s] = -1;
        }
    }

    /* toc */
    int tc = epub_read_u16(buf, pos); pos += 2;
    if (tc > MAX_TOC_ENTRIES) tc = MAX_TOC_ENTRIES;
    toc_count = tc;
    toc_strings_offset = 0;

    for (int t = 0; t < tc; t++) {
        int label_len = epub_read_u16(buf, pos); pos += 2;
        int spine_idx = epub_read_i16(buf, pos); pos += 2;
        int level = epub_read_u16(buf, pos); pos += 2;

        toc_entry_t* entry = &toc_entries[t];
        entry->label_offset = toc_strings_offset;
        entry->label_len = label_len;
        entry->href_offset = 0;
        entry->href_len = 0;
        entry->spine_index = spine_idx;
        entry->nesting_level = level;

        for (int i = 0; i < label_len && toc_strings_offset < 8192; i++) {
            toc_strings[toc_strings_offset++] = buf[pos++];
        }
    }

    return 1;
}

/* M15: Reset epub state to idle. */
void epub_reset(void) {
    epub_state = 0;
    epub_progress = 0;
    epub_error_len = 0;
    file_handle = 0;
    file_size = 0;
    book_title_len = 0;
    book_author_len = 0;
    book_id_len = 0;
    opf_path_len = 0;
    opf_dir_len = 0;
    manifest_count = 0;
    manifest_strings_offset = 0;
    spine_count = 0;
    toc_count = 0;
    toc_strings_offset = 0;
    ncx_zip_index = -1;
    current_entry_index = 0;
    total_entries = 0;
    current_blob_handle = 0;
}

/* ========== Reader module (moved from reader.dats %{^ block) ========== */

/* External: bridge imports (not already declared above) */
extern void js_set_inner_html_from_blob(int node_id, int blob_handle);
extern int js_measure_node(int node_id);

/* External: DOM functions (not already declared above) */
extern void* dom_set_transform(void*, int, int, int);
extern void* dom_set_inner_html(void*, int, int, int);

/* Chapter slot structure */
typedef struct {
    int chapter_index;     /* -1 if empty */
    int container_id;      /* DOM node ID for this slot's container */
    int page_count;        /* Number of pages in this chapter */
    int status;            /* SLOT_EMPTY, SLOT_LOADING, SLOT_READY */
    int blob_handle;       /* Pending blob handle during load */
} chapter_slot_t;

/* Slot constants */
#define SLOT_PREV 0
#define SLOT_CURR 1
#define SLOT_NEXT 2

/* Reader state */
static int reader_active = 0;
static int reader_viewport_id = 0;
static int reader_page_indicator_id = 0;
static int reader_viewport_width = 0;
static int reader_page_stride = 0;

/* Current reading position */
static int reader_current_page = 0;

/* Three chapter slots */
static chapter_slot_t slots[3] = {
    { -1, 0, 0, 0, 0 },
    { -1, 0, 0, 0, 0 },
    { -1, 0, 0, 0, 0 }
};

/* Which slot is currently being loaded (for async completion) */
static int loading_slot = -1;

/* String constants */
static const char str_div[] = "div";
static const char str_class[] = "class";
static const char str_hidden[] = "hidden";
static const char str_reader_viewport[] = "reader-viewport";
static const char str_chapter_container[] = "chapter-container";
static const char str_chapter_prev[] = "chapter-prev";
static const char str_chapter_curr[] = "chapter-curr";
static const char str_chapter_next[] = "chapter-next";
static const char str_page_indicator[] = "page-indicator";
static const char str_page_of[] = " / ";
static const char str_ch_prefix[] = "Ch ";
static const char str_colon_space[] = ": ";

/* M13: TOC overlay string constants */
static const char str_toc_overlay[] = "toc-overlay";
static const char str_toc_header[] = "toc-header";
static const char str_toc_title[] = "Table of Contents";
static const char str_toc_close[] = "toc-close";
static const char str_toc_close_x[] = "\xc3\x97";  /* UTF-8 x */
static const char str_toc_list[] = "toc-list";
static const char str_toc_entry[] = "toc-entry";
static const char str_toc_entry_nested[] = "toc-entry nested";
static const char str_progress_bar[] = "progress-bar";
static const char str_progress_fill[] = "progress-fill";
static const char str_em_dash[] = " \xe2\x80\x94 ";  /* UTF-8 em-dash */

/* M13: TOC overlay state */
static int toc_visible = 0;
static int toc_overlay_id = 0;
static int toc_close_id = 0;
static int toc_list_id = 0;
static int progress_bar_id = 0;
static int progress_fill_id = 0;
static int root_node_id = 1;  /* Save for TOC creation */

/* M13: TOC entry node ID to index mapping */
#define MAX_TOC_ENTRY_IDS 256
static int toc_entry_ids[MAX_TOC_ENTRY_IDS];
static int toc_entry_count = 0;

/* M15: Back button and resume state */
static int reader_back_btn_id = 0;
static int reader_resume_page = 0;  /* Page to resume at after chapter loads */
static const char str_back_btn[] = "back-btn";
static const char str_back_arrow[] = "\xe2\x86\x90";  /* UTF-8 left arrow */

/* Forward declarations */
static void load_chapter_into_slot(int slot_index, int chapter_index);
static void inject_slot_html(int slot_index);
static void measure_slot_pages(int slot_index);
static void position_all_slots(void);
static void preload_adjacent_chapters(void);
static void rotate_to_next_chapter(void);
static void rotate_to_prev_chapter(void);
void reader_update_page_display(void);

/* Initialize reader module */
void reader_init(void) {
    reader_active = 0;
    reader_viewport_id = 0;
    reader_page_indicator_id = 0;
    reader_viewport_width = 0;
    reader_page_stride = 0;
    reader_current_page = 0;
    loading_slot = -1;

    for (int i = 0; i < 3; i++) {
        slots[i].chapter_index = -1;
        slots[i].container_id = 0;
        slots[i].page_count = 0;
        slots[i].status = 0;  /* SLOT_EMPTY */
        slots[i].blob_handle = 0;
    }

    /* M13: Reset TOC state */
    toc_visible = 0;
    toc_overlay_id = 0;
    toc_close_id = 0;
    toc_list_id = 0;
    progress_bar_id = 0;
    progress_fill_id = 0;
    toc_entry_count = 0;

    /* M15: Reset back button and resume state */
    reader_back_btn_id = 0;
    reader_resume_page = 0;
}

/* Enter reader mode - creates viewport and three chapter containers */
void reader_enter(int root_id, int container_hide_id) {
    unsigned char* buf = get_fetch_buffer_ptr();
    root_node_id = root_id;  /* M13: Save for TOC creation */
    void* pf = dom_root_proof();

    /* Hide the import container */
    pf = dom_set_attr(pf, container_hide_id, (void*)str_class, 5, (void*)str_hidden, 6);

    /* Create reader viewport */
    int vid = dom_next_id();
    reader_viewport_id = vid;
    void* pf_viewport = dom_create_element(pf, root_id, vid, (void*)str_div, 3);
    pf_viewport = dom_set_attr(pf_viewport, vid, (void*)str_class, 5,
                               (void*)str_reader_viewport, 15);

    /* Create three chapter containers inside viewport */
    /* Prev chapter container */
    int prev_id = dom_next_id();
    slots[SLOT_PREV].container_id = prev_id;
    slots[SLOT_PREV].chapter_index = -1;
    slots[SLOT_PREV].status = 0;  /* SLOT_EMPTY */
    void* pf_prev = dom_create_element(pf_viewport, vid, prev_id, (void*)str_div, 3);
    pf_prev = dom_set_attr(pf_prev, prev_id, (void*)str_class, 5,
                           (void*)str_chapter_container, 17);
    dom_drop_proof(pf_prev);

    /* Current chapter container */
    int curr_id = dom_next_id();
    slots[SLOT_CURR].container_id = curr_id;
    slots[SLOT_CURR].chapter_index = -1;
    slots[SLOT_CURR].status = 0;
    void* pf_curr = dom_create_element(pf_viewport, vid, curr_id, (void*)str_div, 3);
    pf_curr = dom_set_attr(pf_curr, curr_id, (void*)str_class, 5,
                           (void*)str_chapter_container, 17);
    dom_drop_proof(pf_curr);

    /* Next chapter container */
    int next_id = dom_next_id();
    slots[SLOT_NEXT].container_id = next_id;
    slots[SLOT_NEXT].chapter_index = -1;
    slots[SLOT_NEXT].status = 0;
    void* pf_next = dom_create_element(pf_viewport, vid, next_id, (void*)str_div, 3);
    pf_next = dom_set_attr(pf_next, next_id, (void*)str_class, 5,
                           (void*)str_chapter_container, 17);
    dom_drop_proof(pf_next);

    dom_drop_proof(pf_viewport);

    /* M15: Create back button */
    int back_id = dom_next_id();
    reader_back_btn_id = back_id;
    void* pf_back = dom_create_element(pf, root_id, back_id, (void*)str_div, 3);
    pf_back = dom_set_attr(pf_back, back_id, (void*)str_class, 5,
                           (void*)str_back_btn, 8);
    {
        int blen = 0;
        const char* arrow = str_back_arrow;
        while (*arrow && blen < 10) buf[blen++] = *arrow++;
        dom_set_text_offset(pf_back, back_id, 0, blen);
    }
    dom_drop_proof(pf_back);

    /* Create page indicator */
    int pid = dom_next_id();
    reader_page_indicator_id = pid;
    void* pf_indicator = dom_create_element(pf, root_id, pid, (void*)str_div, 3);
    pf_indicator = dom_set_attr(pf_indicator, pid, (void*)str_class, 5,
                                (void*)str_page_indicator, 14);

    /* Initial page display "Ch 1: 1 / 1" */
    int len = 0;
    const char* ch = str_ch_prefix;
    while (*ch && len < 16380) buf[len++] = *ch++;
    buf[len++] = '1';
    const char* col = str_colon_space;
    while (*col && len < 16380) buf[len++] = *col++;
    buf[len++] = '1';
    const char* of = str_page_of;
    while (*of && len < 16380) buf[len++] = *of++;
    buf[len++] = '1';
    dom_set_text_offset(pf_indicator, pid, 0, len);
    dom_drop_proof(pf_indicator);

    /* M13: Create progress bar */
    int pb_id = dom_next_id();
    progress_bar_id = pb_id;
    void* pf_progress = dom_create_element(pf, root_id, pb_id, (void*)str_div, 3);
    pf_progress = dom_set_attr(pf_progress, pb_id, (void*)str_class, 5,
                               (void*)str_progress_bar, 12);

    /* Create progress fill inside progress bar */
    int pf_id = dom_next_id();
    progress_fill_id = pf_id;
    void* pf_fill = dom_create_element(pf_progress, pb_id, pf_id, (void*)str_div, 3);
    pf_fill = dom_set_attr(pf_fill, pf_id, (void*)str_class, 5,
                           (void*)str_progress_fill, 13);
    dom_drop_proof(pf_fill);
    dom_drop_proof(pf_progress);

    dom_drop_proof(pf);

    reader_active = 1;
    reader_current_page = 0;

    /* Load first chapter into current slot */
    load_chapter_into_slot(SLOT_CURR, 0);
}

/* Exit reader mode */
void reader_exit(void) {
    reader_active = 0;
    reader_init();  /* Reset all state */
}

/* Check if reader is active */
int reader_is_active(void) {
    return reader_active;
}

/* Get current chapter index */
int reader_get_current_chapter(void) {
    if (!reader_active) return -1;
    return slots[SLOT_CURR].chapter_index;
}

/* Get current page within chapter */
int reader_get_current_page(void) {
    return reader_current_page;
}

/* Get total pages in current chapter */
int reader_get_total_pages(void) {
    if (!reader_active || slots[SLOT_CURR].status != 2) return 1;
    return slots[SLOT_CURR].page_count > 0 ? slots[SLOT_CURR].page_count : 1;
}

/* Get total chapter count */
int reader_get_chapter_count(void) {
    return epub_get_chapter_count();
}

/* Load a chapter into a specific slot */
static void load_chapter_into_slot(int slot_index, int chapter_index) {
    if (slot_index < 0 || slot_index > 2) return;
    if (chapter_index < 0 || chapter_index >= epub_get_chapter_count()) {
        /* Mark slot as empty */
        slots[slot_index].chapter_index = -1;
        slots[slot_index].status = 0;  /* SLOT_EMPTY */
        slots[slot_index].page_count = 0;
        return;
    }

    /* Already loading something */
    if (loading_slot >= 0) return;

    /* Already have this chapter in this slot */
    if (slots[slot_index].chapter_index == chapter_index &&
        slots[slot_index].status == 2) {  /* SLOT_READY */
        return;
    }

    unsigned char* str_buf = get_string_buffer_ptr();

    /* Get chapter key */
    int key_len = epub_get_chapter_key(chapter_index, 0);
    if (key_len == 0) {
        slots[slot_index].chapter_index = -1;
        slots[slot_index].status = 0;
        return;
    }

    slots[slot_index].chapter_index = chapter_index;
    slots[slot_index].status = 1;  /* SLOT_LOADING */
    slots[slot_index].page_count = 0;
    loading_slot = slot_index;

    /* Request chapter from IndexedDB (str_chapters defined in epub section) */
    js_kv_get((void*)str_chapters, 8, str_buf, key_len);
}

/* Inject HTML into a slot's container */
static void inject_slot_html(int slot_index) {
    if (slot_index < 0 || slot_index > 2) return;
    chapter_slot_t* slot = &slots[slot_index];

    if (slot->blob_handle > 0) {
        js_set_inner_html_from_blob(slot->container_id, slot->blob_handle);
        js_blob_free(slot->blob_handle);
        slot->blob_handle = 0;
    }

    slot->status = 2;  /* SLOT_READY */
}

/* Measure pages in a slot's container */
static void measure_slot_pages(int slot_index) {
    if (slot_index < 0 || slot_index > 2) return;
    chapter_slot_t* slot = &slots[slot_index];

    if (slot->container_id == 0) return;
    if (!js_measure_node(slot->container_id)) return;

    unsigned char* buf = get_fetch_buffer_ptr();

    /* Read float64 values from fetch buffer */
    double scroll_width_d, width_d;
    unsigned char* sw_ptr = buf + 32;  /* scrollWidth at offset 32 */
    unsigned char* w_ptr = buf + 16;   /* width at offset 16 */

    unsigned char sw_bytes[8], w_bytes[8];
    for (int i = 0; i < 8; i++) {
        sw_bytes[i] = sw_ptr[i];
        w_bytes[i] = w_ptr[i];
    }

    scroll_width_d = *(double*)sw_bytes;
    width_d = *(double*)w_bytes;

    int scroll_width = (int)scroll_width_d;
    int width = (int)width_d;

    if (width <= 0) width = 1;

    reader_viewport_width = width;
    reader_page_stride = width;

    slot->page_count = (scroll_width + width - 1) / width;
    if (slot->page_count < 1) slot->page_count = 1;
}

/* Position all slots based on current reading position */
static void position_all_slots(void) {
    void* pf = dom_root_proof();

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    chapter_slot_t* prev_slot = &slots[SLOT_PREV];
    chapter_slot_t* next_slot = &slots[SLOT_NEXT];

    /* Current slot: positioned at -(currentPage * stride) */
    int curr_offset_x = -(reader_current_page * reader_page_stride);
    if (curr_slot->container_id > 0) {
        dom_set_transform(pf, curr_slot->container_id, curr_offset_x, 0);
    }

    /* Prev slot: positioned to the left of current, showing its last page */
    if (prev_slot->container_id > 0 && prev_slot->chapter_index >= 0) {
        int prev_pages = prev_slot->page_count > 0 ? prev_slot->page_count : 1;
        int prev_offset_x = -((prev_pages - 1) * reader_page_stride) - reader_page_stride;
        dom_set_transform(pf, prev_slot->container_id, prev_offset_x, 0);
    } else if (prev_slot->container_id > 0) {
        dom_set_transform(pf, prev_slot->container_id, -100000, 0);
    }

    /* Next slot: positioned to the right of current's last page */
    if (next_slot->container_id > 0 && next_slot->chapter_index >= 0) {
        int curr_pages = curr_slot->page_count > 0 ? curr_slot->page_count : 1;
        int next_offset_x = (curr_pages - reader_current_page) * reader_page_stride;
        dom_set_transform(pf, next_slot->container_id, next_offset_x, 0);
    } else if (next_slot->container_id > 0) {
        dom_set_transform(pf, next_slot->container_id, 100000, 0);
    }

    dom_drop_proof(pf);
}

/* Preload adjacent chapters */
static void preload_adjacent_chapters(void) {
    int curr_chapter = slots[SLOT_CURR].chapter_index;
    if (curr_chapter < 0) return;

    int total_chapters = epub_get_chapter_count();

    /* Load previous chapter if not already loaded */
    if (curr_chapter > 0) {
        int prev_chapter = curr_chapter - 1;
        if (slots[SLOT_PREV].chapter_index != prev_chapter) {
            load_chapter_into_slot(SLOT_PREV, prev_chapter);
            return;  /* One load at a time */
        }
    } else {
        slots[SLOT_PREV].chapter_index = -1;
        slots[SLOT_PREV].status = 0;
    }

    /* Load next chapter if not already loaded */
    if (curr_chapter < total_chapters - 1) {
        int next_chapter = curr_chapter + 1;
        if (slots[SLOT_NEXT].chapter_index != next_chapter) {
            load_chapter_into_slot(SLOT_NEXT, next_chapter);
            return;
        }
    } else {
        slots[SLOT_NEXT].chapter_index = -1;
        slots[SLOT_NEXT].status = 0;
    }
}

/* Rotate slots to show next chapter */
static void rotate_to_next_chapter(void) {
    int curr_chapter = slots[SLOT_CURR].chapter_index;
    int total_chapters = epub_get_chapter_count();

    if (curr_chapter < 0 || curr_chapter >= total_chapters - 1) return;

    int prev_container = slots[SLOT_PREV].container_id;
    int curr_container = slots[SLOT_CURR].container_id;
    int next_container = slots[SLOT_NEXT].container_id;

    slots[SLOT_PREV].chapter_index = slots[SLOT_CURR].chapter_index;
    slots[SLOT_PREV].page_count = slots[SLOT_CURR].page_count;
    slots[SLOT_PREV].status = slots[SLOT_CURR].status;
    slots[SLOT_PREV].container_id = curr_container;

    slots[SLOT_CURR].chapter_index = slots[SLOT_NEXT].chapter_index;
    slots[SLOT_CURR].page_count = slots[SLOT_NEXT].page_count;
    slots[SLOT_CURR].status = slots[SLOT_NEXT].status;
    slots[SLOT_CURR].container_id = next_container;

    slots[SLOT_NEXT].container_id = prev_container;
    slots[SLOT_NEXT].chapter_index = -1;
    slots[SLOT_NEXT].page_count = 0;
    slots[SLOT_NEXT].status = 0;

    reader_current_page = 0;
    position_all_slots();
    preload_adjacent_chapters();
}

/* Rotate slots to show previous chapter */
static void rotate_to_prev_chapter(void) {
    int curr_chapter = slots[SLOT_CURR].chapter_index;

    if (curr_chapter <= 0) return;

    int prev_container = slots[SLOT_PREV].container_id;
    int curr_container = slots[SLOT_CURR].container_id;
    int next_container = slots[SLOT_NEXT].container_id;

    slots[SLOT_NEXT].chapter_index = slots[SLOT_CURR].chapter_index;
    slots[SLOT_NEXT].page_count = slots[SLOT_CURR].page_count;
    slots[SLOT_NEXT].status = slots[SLOT_CURR].status;
    slots[SLOT_NEXT].container_id = curr_container;

    slots[SLOT_CURR].chapter_index = slots[SLOT_PREV].chapter_index;
    slots[SLOT_CURR].page_count = slots[SLOT_PREV].page_count;
    slots[SLOT_CURR].status = slots[SLOT_PREV].status;
    slots[SLOT_CURR].container_id = prev_container;

    slots[SLOT_PREV].container_id = next_container;
    slots[SLOT_PREV].chapter_index = -1;
    slots[SLOT_PREV].page_count = 0;
    slots[SLOT_PREV].status = 0;

    reader_current_page = slots[SLOT_CURR].page_count > 0 ?
                          slots[SLOT_CURR].page_count - 1 : 0;

    position_all_slots();
    preload_adjacent_chapters();
}

/* Navigate to next page */
void reader_next_page(void) {
    if (!reader_active) return;

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    if (curr_slot->status != 2) return;

    int total_pages = curr_slot->page_count > 0 ? curr_slot->page_count : 1;

    if (reader_current_page < total_pages - 1) {
        reader_current_page++;

        void* pf = dom_root_proof();
        int offset_x = -(reader_current_page * reader_page_stride);
        dom_set_transform(pf, curr_slot->container_id, offset_x, 0);
        dom_drop_proof(pf);
    } else {
        chapter_slot_t* next_slot = &slots[SLOT_NEXT];
        if (next_slot->chapter_index >= 0 && next_slot->status == 2) {
            rotate_to_next_chapter();
        }
    }

    reader_update_page_display();
}

/* Navigate to previous page */
void reader_prev_page(void) {
    if (!reader_active) return;

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    if (curr_slot->status != 2) return;

    if (reader_current_page > 0) {
        reader_current_page--;

        void* pf = dom_root_proof();
        int offset_x = -(reader_current_page * reader_page_stride);
        dom_set_transform(pf, curr_slot->container_id, offset_x, 0);
        dom_drop_proof(pf);
    } else {
        chapter_slot_t* prev_slot = &slots[SLOT_PREV];
        if (prev_slot->chapter_index >= 0 && prev_slot->status == 2) {
            rotate_to_prev_chapter();
        }
    }

    reader_update_page_display();
}

/* Navigate to specific page in current chapter */
void reader_go_to_page(int page) {
    if (!reader_active) return;

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    if (curr_slot->status != 2) return;

    int total_pages = curr_slot->page_count > 0 ? curr_slot->page_count : 1;

    if (page < 0) page = 0;
    if (page >= total_pages) page = total_pages - 1;
    if (page == reader_current_page) return;

    reader_current_page = page;

    void* pf = dom_root_proof();
    int offset_x = -(reader_current_page * reader_page_stride);
    dom_set_transform(pf, curr_slot->container_id, offset_x, 0);
    dom_drop_proof(pf);

    reader_update_page_display();
}

/* Handle chapter data loaded (small, in fetch buffer) */
void reader_on_chapter_loaded(int len) {
    if (!reader_active || loading_slot < 0) return;

    int slot_index = loading_slot;
    loading_slot = -1;

    if (len == 0) {
        slots[slot_index].status = 0;
        return;
    }

    /* Inject HTML via SET_INNER_HTML */
    void* pf = dom_root_proof();
    dom_set_inner_html(pf, slots[slot_index].container_id, 0, len);
    dom_drop_proof(pf);

    slots[slot_index].status = 2;  /* SLOT_READY */

    /* Measure pages */
    measure_slot_pages(slot_index);

    if (slot_index == SLOT_CURR) {
        if (reader_resume_page > 0) {
            int max_page = slots[SLOT_CURR].page_count > 0 ? slots[SLOT_CURR].page_count - 1 : 0;
            reader_current_page = reader_resume_page <= max_page ? reader_resume_page : max_page;
            reader_resume_page = 0;
        } else {
            reader_current_page = 0;
        }
        position_all_slots();
        reader_update_page_display();
        preload_adjacent_chapters();
    } else {
        position_all_slots();
        preload_adjacent_chapters();
    }
}

/* Handle chapter data loaded (large, as blob) */
void reader_on_chapter_blob_loaded(int handle, int size) {
    if (!reader_active || loading_slot < 0) return;

    int slot_index = loading_slot;
    loading_slot = -1;

    if (handle == 0 || size == 0) {
        slots[slot_index].status = 0;
        return;
    }

    slots[slot_index].blob_handle = handle;
    inject_slot_html(slot_index);

    measure_slot_pages(slot_index);

    if (slot_index == SLOT_CURR) {
        if (reader_resume_page > 0) {
            int max_page = slots[SLOT_CURR].page_count > 0 ? slots[SLOT_CURR].page_count - 1 : 0;
            reader_current_page = reader_resume_page <= max_page ? reader_resume_page : max_page;
            reader_resume_page = 0;
        } else {
            reader_current_page = 0;
        }
        position_all_slots();
        reader_update_page_display();
        preload_adjacent_chapters();
    } else {
        position_all_slots();
        preload_adjacent_chapters();
    }
}

/* Get viewport ID */
int reader_get_viewport_id(void) {
    return reader_viewport_id;
}

/* Get viewport width */
int reader_get_viewport_width(void) {
    return reader_viewport_width;
}

/* Get page indicator ID */
int reader_get_page_indicator_id(void) {
    return reader_page_indicator_id;
}

/* M13: Helper to append integer to buffer */
static int reader_append_int(unsigned char* buf, int pos, int value) {
    if (value >= 100) {
        buf[pos++] = '0' + (value / 100);
        buf[pos++] = '0' + ((value / 10) % 10);
        buf[pos++] = '0' + (value % 10);
    } else if (value >= 10) {
        buf[pos++] = '0' + (value / 10);
        buf[pos++] = '0' + (value % 10);
    } else {
        buf[pos++] = '0' + value;
    }
    return pos;
}

/* Update page display */
void reader_update_page_display(void) {
    if (reader_page_indicator_id == 0) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();
    int len = 0;

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    int chapter_idx = curr_slot->chapter_index;
    int chapter = chapter_idx + 1;  /* 1-indexed display */
    int page = reader_current_page + 1;  /* 1-indexed display */
    int total = curr_slot->page_count > 0 ? curr_slot->page_count : 1;

    /* M13: Try to get chapter title from TOC */
    int title_len = epub_get_chapter_title(chapter_idx, 0);
    if (title_len > 0 && title_len < 100) {
        for (int i = 0; i < title_len && len < 16300; i++) {
            buf[len++] = str_buf[i];
        }
    } else {
        const char* ch = str_ch_prefix;
        while (*ch && len < 16380) buf[len++] = *ch++;
        len = reader_append_int(buf, len, chapter);
    }

    /* Add em-dash separator */
    const char* dash = str_em_dash;
    while (*dash && len < 16380) buf[len++] = *dash++;

    len = reader_append_int(buf, len, page);

    const char* of = str_page_of;
    while (*of && len < 16380) buf[len++] = *of++;

    len = reader_append_int(buf, len, total);

    void* pf = dom_root_proof();
    dom_set_text_offset(pf, reader_page_indicator_id, 0, len);

    /* M13: Update progress bar */
    if (progress_fill_id > 0) {
        int total_chapters = epub_get_chapter_count();
        int progress_pct = 0;
        if (total_chapters > 0) {
            int base_progress = (chapter_idx * 100) / total_chapters;
            int page_progress = (total > 1) ? ((page - 1) * 100) / (total * total_chapters) : 0;
            progress_pct = base_progress + page_progress;
            if (progress_pct > 100) progress_pct = 100;
        }

        /* Build style string: "width:XX%" */
        static const char rdr_str_style[] = "style";
        static const char rdr_str_width_prefix[] = "width:";
        static const char rdr_str_pct[] = "%";

        int style_len = 0;
        const char* wp = rdr_str_width_prefix;
        while (*wp && style_len < 20) str_buf[style_len++] = *wp++;
        style_len = reader_append_int(str_buf, style_len, progress_pct);
        const char* pct = rdr_str_pct;
        while (*pct && style_len < 25) str_buf[style_len++] = *pct++;

        dom_set_attr(pf, progress_fill_id, (void*)rdr_str_style, 5, str_buf, style_len);
    }

    dom_drop_proof(pf);
}

/* Check if any chapter is loading */
int reader_is_loading(void) {
    return loading_slot >= 0 ? 1 : 0;
}

/* M14: Re-measure all chapter slots after settings change */
void reader_remeasure_all(void) {
    if (!reader_active) return;

    for (int i = 0; i < 3; i++) {
        if (slots[i].status == 2) {
            measure_slot_pages(i);
        }
    }

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    if (curr_slot->status == 2) {
        int max_page = curr_slot->page_count > 0 ? curr_slot->page_count - 1 : 0;
        if (reader_current_page > max_page) {
            reader_current_page = max_page;
        }
    }

    position_all_slots();
    reader_update_page_display();
}

/* M13: Go to specific chapter */
void reader_go_to_chapter(int chapter_index, int total_chapters) {
    if (!reader_active) return;

    for (int i = 0; i < 3; i++) {
        slots[i].chapter_index = -1;
        slots[i].status = 0;
        slots[i].page_count = 0;
    }

    reader_current_page = 0;
    loading_slot = -1;

    load_chapter_into_slot(SLOT_CURR, chapter_index);
}

/* M13: Show Table of Contents overlay */
void reader_show_toc(void) {
    if (!reader_active || toc_visible) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();
    void* pf = dom_root_proof();

    int overlay_id = dom_next_id();
    toc_overlay_id = overlay_id;
    void* pf_overlay = dom_create_element(pf, root_node_id, overlay_id, (void*)str_div, 3);
    pf_overlay = dom_set_attr(pf_overlay, overlay_id, (void*)str_class, 5,
                              (void*)str_toc_overlay, 11);

    int header_id = dom_next_id();
    void* pf_header = dom_create_element(pf_overlay, overlay_id, header_id, (void*)str_div, 3);
    pf_header = dom_set_attr(pf_header, header_id, (void*)str_class, 5,
                             (void*)str_toc_header, 10);

    int len = 0;
    const char* title = str_toc_title;
    while (*title && len < 100) buf[len++] = *title++;
    dom_set_text_offset(pf_header, header_id, 0, len);

    int close_id = dom_next_id();
    toc_close_id = close_id;
    void* pf_close = dom_create_element(pf_header, header_id, close_id, (void*)str_div, 3);
    pf_close = dom_set_attr(pf_close, close_id, (void*)str_class, 5,
                            (void*)str_toc_close, 9);
    len = 0;
    const char* close_x = str_toc_close_x;
    while (*close_x && len < 10) buf[len++] = *close_x++;
    dom_set_text_offset(pf_close, close_id, 0, len);
    dom_drop_proof(pf_close);
    dom_drop_proof(pf_header);

    int list_id = dom_next_id();
    toc_list_id = list_id;
    void* pf_list = dom_create_element(pf_overlay, overlay_id, list_id, (void*)str_div, 3);
    pf_list = dom_set_attr(pf_list, list_id, (void*)str_class, 5,
                           (void*)str_toc_list, 8);

    toc_entry_count = 0;
    int toc_total = epub_get_toc_count();
    for (int i = 0; i < toc_total && i < MAX_TOC_ENTRY_IDS; i++) {
        int entry_id = dom_next_id();
        void* pf_entry = dom_create_element(pf_list, list_id, entry_id, (void*)str_div, 3);

        toc_entry_ids[toc_entry_count++] = entry_id;

        int level = epub_get_toc_level(i);
        if (level > 0) {
            pf_entry = dom_set_attr(pf_entry, entry_id, (void*)str_class, 5,
                                    (void*)str_toc_entry_nested, 16);
        } else {
            pf_entry = dom_set_attr(pf_entry, entry_id, (void*)str_class, 5,
                                    (void*)str_toc_entry, 9);
        }

        int label_len = epub_get_toc_label(i, 0);
        if (label_len > 0) {
            for (int j = 0; j < label_len && j < 200; j++) {
                buf[j] = str_buf[j];
            }
            dom_set_text_offset(pf_entry, entry_id, 0, label_len);
        }
        dom_drop_proof(pf_entry);
    }

    dom_drop_proof(pf_list);
    dom_drop_proof(pf_overlay);
    dom_drop_proof(pf);

    toc_visible = 1;
}

/* M13: Hide Table of Contents overlay */
void reader_hide_toc(void) {
    if (!reader_active || !toc_visible || toc_overlay_id == 0) return;

    void* pf = dom_root_proof();
    dom_remove_child(pf, toc_overlay_id);
    dom_drop_proof(pf);

    toc_visible = 0;
    toc_overlay_id = 0;
    toc_close_id = 0;
    toc_list_id = 0;
    toc_entry_count = 0;
}

/* M13: Check if TOC is visible */
int reader_is_toc_visible(void) {
    return toc_visible;
}

/* M13: Toggle TOC visibility */
void reader_toggle_toc(void) {
    if (toc_visible) {
        reader_hide_toc();
    } else {
        reader_show_toc();
    }
}

/* M13: Get TOC overlay ID */
int reader_get_toc_id(void) {
    return toc_overlay_id;
}

/* M13: Get progress bar ID */
int reader_get_progress_bar_id(void) {
    return progress_bar_id;
}

/* M13: Look up TOC index from node ID */
int reader_get_toc_index_for_node(int node_id) {
    for (int i = 0; i < toc_entry_count; i++) {
        if (toc_entry_ids[i] == node_id) {
            return i;
        }
    }
    return -1;
}

/* M13: Handle TOC entry click by node ID */
void reader_on_toc_click(int node_id) {
    if (!reader_active) return;

    int toc_index = reader_get_toc_index_for_node(node_id);
    if (toc_index < 0) return;

    int chapter_index = epub_get_toc_chapter(toc_index);
    if (chapter_index < 0) return;

    reader_hide_toc();

    int total = epub_get_chapter_count();
    if (chapter_index < total) {
        reader_go_to_chapter(chapter_index, total);
    }
}

/* M15: Enter reader at specific chapter and page for resume */
void reader_enter_at(int root_id, int container_hide_id, int chapter, int page) {
    reader_resume_page = page;
    reader_enter(root_id, container_hide_id);

    int total = epub_get_chapter_count();
    if (chapter > 0 && chapter < total) {
        loading_slot = -1;
        for (int i = 0; i < 3; i++) {
            slots[i].chapter_index = -1;
            slots[i].status = 0;
            slots[i].page_count = 0;
        }
        load_chapter_into_slot(SLOT_CURR, chapter);
    }
}

/* M15: Get back button node ID */
int reader_get_back_btn_id(void) {
    return reader_back_btn_id;
}
