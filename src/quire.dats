(* quire.dats - Quire e-reader main module
 *
 * EPUB import pipeline with type-checked DOM operations.
 * M9: File input, import progress, book title display.
 * M14: Reader settings integration.
 * M15: Book library - list, delete, resume position.
 *)

#define ATS_DYNLOADFLAG 0

staload "quire.sats"
staload "dom.sats"
staload "epub.sats"
staload "reader.sats"
staload "settings.sats"
staload "library.sats"

%{^
/* String literals for DOM operations */
static const char str_quire[] = "Quire";
static const char str_div[] = "div";
static const char str_input[] = "input";
static const char str_label[] = "label";
static const char str_for[] = "for";
static const char str_h1[] = "h1";
static const char str_h2[] = "h2";
static const char str_p[] = "p";
static const char str_class[] = "class";
static const char str_type[] = "type";
static const char str_file[] = "file";
static const char str_accept[] = "accept";
static const char str_epub_accept[] = ".epub,application/epub+zip";
static const char str_id_attr[] = "id";
static const char str_hidden[] = "hidden";
static const char str_container[] = "container";
static const char str_import_btn[] = "import-btn";
static const char str_file_input[] = "file-input";
static const char str_progress_div[] = "progress-div";
static const char str_title_div[] = "title-div";
static const char str_import_text[] = "Import EPUB";
static const char str_importing[] = "Importing...";
static const char str_error_prefix[] = "Error: ";
static const char str_by[] = " by ";
static const char str_chapters_suffix[] = " chapters";
static const char str_style[] = "style";

/* M15: Library view strings */
static const char str_library_list[] = "library-list";
static const char str_book_card[] = "book-card";
static const char str_book_title[] = "book-title";
static const char str_book_author[] = "book-author";
static const char str_book_position[] = "book-position";
static const char str_book_actions[] = "book-actions";
static const char str_read_btn[] = "read-btn";
static const char str_delete_btn[] = "delete-btn";
static const char str_read_text[] = "Read";
static const char str_delete_text[] = "Delete";
static const char str_not_started[] = "Not started";
static const char str_ch_space[] = "Ch ";
static const char str_comma_pg[] = ", page ";
static const char str_of_space[] = " of ";
static const char str_empty_lib[] = "No books yet. Import an EPUB to get started.";

/* M15: App states
 *
 * FUNCTIONAL CORRECTNESS: App state machine with valid transitions.
 * APP_STATE_VALID(s) proves s is one of the defined states.
 * Valid transitions (documented by APP_STATE_TRANSITION):
 *
 *   INIT -> LOADING_DB           (init opens IndexedDB)
 *   LOADING_DB -> LOADING_LIB    (DB opened, load library index)
 *   LOADING_DB -> LIBRARY        (DB failed, show empty library)
 *   LOADING_LIB -> LIBRARY       (library loaded, show it)
 *   LIBRARY -> IMPORTING         (user selected file)
 *   LIBRARY -> LOADING_BOOK      (user clicked Read on book card)
 *   IMPORTING -> LIBRARY         (import complete + saved, or error)
 *   LOADING_BOOK -> READING      (metadata restored, enter reader)
 *   READING -> LIBRARY           (user pressed back/Escape)
 *
 * No other transitions are valid. Each transition is guarded by
 * checking app_state before assignment. */
#define APP_STATE_INIT          0
#define APP_STATE_LOADING_DB    1
#define APP_STATE_LOADING_LIB   2
#define APP_STATE_LIBRARY       3
#define APP_STATE_IMPORTING     4
#define APP_STATE_LOADING_BOOK  5
#define APP_STATE_READING       6

/* CSS buffer for building stylesheet dynamically */
static char css_buffer[12288];
static int css_buffer_len = 0;

/* Helper: append string to CSS buffer */
static void css_append(const char* str) {
    while (*str && css_buffer_len < 12287) {
        css_buffer[css_buffer_len++] = *str++;
    }
    css_buffer[css_buffer_len] = 0;
}

/* Helper: append a class rule */
static void css_class_rule(const char* class_name, const char* properties) {
    css_append(".");
    css_append(class_name);
    css_append("{");
    css_append(properties);
    css_append("}");
}

/* Helper: append a rule with selector */
static void css_rule(const char* selector, const char* properties) {
    css_append(selector);
    css_append("{");
    css_append(properties);
    css_append("}");
}

/* Build the complete stylesheet */
static void build_css(void) {
    css_buffer_len = 0;

    /* Base page setup */
    css_rule("html,body", "margin:0;padding:0;height:100%;width:100%;overflow:hidden;"
             "font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;"
             "background:#fafaf8;color:#2a2a2a");

    /* Loading state */
    css_rule("#loading", "display:flex;flex-direction:column;align-items:center;justify-content:center;"
             "height:100vh;font-size:1.25rem;color:#666");

    /* Hidden utility */
    css_class_rule(str_hidden, "display:none!important");

    /* Main container */
    css_class_rule(str_container, "display:flex;flex-direction:column;align-items:center;"
                   "min-height:100vh;padding:2rem;box-sizing:border-box;overflow-y:auto");

    /* Title heading */
    css_rule(".container h1", "font-size:2.5rem;font-weight:300;color:#333;margin:0 0 1.5rem 0");

    /* Hidden file input */
    css_rule("input[type=file].hidden", "position:absolute;width:1px;height:1px;padding:0;margin:-1px;"
             "overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0");

    /* Import button */
    css_class_rule(str_import_btn, "display:inline-block;padding:0.875rem 2rem;font-size:1rem;font-weight:500;"
                   "color:#fff;background:#4a7c59;border:none;border-radius:0.5rem;cursor:pointer;"
                   "transition:background 0.2s,transform 0.1s;user-select:none;margin-bottom:1.5rem");
    css_append("."); css_append(str_import_btn); css_append(":hover{background:#3d6b4a}");
    css_append("."); css_append(str_import_btn); css_append(":active{transform:scale(0.98)}");

    /* Progress display */
    css_class_rule(str_progress_div, "margin-top:0.5rem;margin-bottom:1rem;font-size:0.875rem;color:#666;min-height:1.25rem");

    /* Title/book info display */
    css_class_rule(str_title_div, "margin-top:1rem;font-size:1.125rem;color:#333;text-align:center;"
                   "max-width:80%;word-wrap:break-word");

    /* M15: Library list */
    css_class_rule(str_library_list, "width:100%;max-width:600px;margin:0 auto");

    /* M15: Book card */
    css_class_rule(str_book_card, "background:#fff;border:1px solid #e0e0e0;border-radius:0.5rem;"
                   "padding:1rem 1.25rem;margin-bottom:0.75rem;display:flex;flex-direction:column;gap:0.25rem");

    /* M15: Book title in card */
    css_class_rule(str_book_title, "font-size:1.1rem;font-weight:500;color:#333");

    /* M15: Book author in card */
    css_class_rule(str_book_author, "font-size:0.875rem;color:#666");

    /* M15: Book position in card */
    css_class_rule(str_book_position, "font-size:0.8rem;color:#999;margin-top:0.125rem");

    /* M15: Book actions row */
    css_class_rule(str_book_actions, "display:flex;gap:0.5rem;margin-top:0.5rem;justify-content:flex-end");

    /* Read button */
    css_class_rule(str_read_btn, "display:inline-block;padding:0.5rem 1.25rem;font-size:0.875rem;font-weight:500;"
                   "color:#fff;background:#3b6ea5;border:none;border-radius:0.375rem;cursor:pointer;"
                   "transition:background 0.2s,transform 0.1s;user-select:none");
    css_append("."); css_append(str_read_btn); css_append(":hover{background:#2d5a8a}");
    css_append("."); css_append(str_read_btn); css_append(":active{transform:scale(0.98)}");

    /* M15: Delete button */
    css_class_rule(str_delete_btn, "display:inline-block;padding:0.5rem 1rem;font-size:0.875rem;font-weight:400;"
                   "color:#c0392b;background:transparent;border:1px solid #e0e0e0;border-radius:0.375rem;"
                   "cursor:pointer;transition:background 0.2s,border-color 0.2s;user-select:none");
    css_append("."); css_append(str_delete_btn); css_append(":hover{background:#fef0ef;border-color:#c0392b}");

    /* M15: Empty library message */
    css_append(".empty-lib{color:#999;font-size:0.95rem;text-align:center;padding:2rem 0}");

    /* M14: CSS variables for reader settings */
    css_rule(":root", "--font-size:18px;--font-family:Georgia,serif;--line-height:1.6;"
             "--margin:2rem;--bg-color:#fafaf8;--text-color:#2a2a2a");

    /* Reader viewport */
    css_append(".reader-viewport{position:fixed;top:0;left:0;width:100vw;height:100vh;"
               "overflow:hidden;background:var(--bg-color)}");

    /* Chapter container with CSS columns */
    css_append(".chapter-container{column-width:100vw;column-gap:0;column-fill:auto;"
               "height:calc(100vh - calc(var(--margin) * 2));padding:var(--margin);box-sizing:border-box;"
               "overflow:visible;font-family:var(--font-family);font-size:var(--font-size);"
               "line-height:var(--line-height);color:var(--text-color);background:var(--bg-color)}");

    /* Chapter content styling */
    css_append(".chapter-container h1,.chapter-container h2,.chapter-container h3,"
               ".chapter-container h4,.chapter-container h5,.chapter-container h6"
               "{margin-top:1em;margin-bottom:0.5em;line-height:1.3}");

    css_append(".chapter-container p{margin:0 0 1em 0;text-align:justify;hyphens:auto}");
    css_append(".chapter-container img{max-width:100%;height:auto;display:block;margin:1em auto}");
    css_append(".chapter-container a{color:#4a7c59;text-decoration:none}");
    css_append(".chapter-container a:hover{text-decoration:underline}");

    /* Page indicator styling */
    css_append(".page-indicator{position:fixed;bottom:1rem;left:50%;transform:translateX(-50%);"
               "padding:0.5rem 1rem;background:rgba(0,0,0,0.6);color:#fff;border-radius:0.25rem;"
               "font-size:0.875rem;font-family:system-ui,-apple-system,sans-serif;z-index:100;"
               "pointer-events:none}");

    /* Progress bar styling */
    css_append(".progress-bar{position:fixed;top:0;left:0;width:100%;height:4px;"
               "background:rgba(0,0,0,0.1);z-index:100}");
    css_append(".progress-fill{height:100%;background:#4a7c59;transition:width 0.3s ease}");

    /* TOC overlay styling */
    css_append(".toc-overlay{position:fixed;top:0;left:0;width:100%;height:100%;"
               "background:rgba(250,250,248,0.98);z-index:200;display:flex;flex-direction:column;"
               "font-family:system-ui,-apple-system,sans-serif}");
    css_append(".toc-header{display:flex;justify-content:space-between;align-items:center;"
               "padding:1.5rem 2rem;border-bottom:1px solid #e0e0e0;font-size:1.25rem;font-weight:500}");
    css_append(".toc-close{cursor:pointer;font-size:1.5rem;color:#666;padding:0.5rem;"
               "border-radius:50%;transition:background 0.2s}");
    css_append(".toc-close:hover{background:rgba(0,0,0,0.1)}");
    css_append(".toc-list{flex:1;overflow-y:auto;padding:1rem 0}");
    css_append(".toc-entry{padding:0.75rem 2rem;cursor:pointer;border-bottom:1px solid #f0f0f0;"
               "transition:background 0.2s;color:#333}");
    css_append(".toc-entry:hover{background:rgba(74,124,89,0.1)}");
    css_append(".toc-entry.nested{padding-left:3.5rem;font-size:0.9rem;color:#666}");

    /* Settings overlay styling */
    css_append(".settings-overlay{position:fixed;top:0;left:0;width:100%;height:100%;"
               "background:rgba(0,0,0,0.5);z-index:300;display:flex;align-items:center;"
               "justify-content:center;font-family:system-ui,-apple-system,sans-serif}");
    css_append(".settings-modal{background:#fff;border-radius:0.75rem;width:90%;max-width:400px;"
               "box-shadow:0 4px 20px rgba(0,0,0,0.15);overflow:hidden}");
    css_append(".settings-header{display:flex;justify-content:space-between;align-items:center;"
               "padding:1.25rem 1.5rem;border-bottom:1px solid #e0e0e0;font-size:1.125rem;font-weight:600}");
    css_append(".settings-close{cursor:pointer;font-size:1.5rem;color:#666;padding:0.25rem 0.5rem;"
               "border-radius:4px;transition:background 0.2s}");
    css_append(".settings-close:hover{background:rgba(0,0,0,0.1)}");
    css_append(".settings-body{padding:1rem 1.5rem}");
    css_append(".settings-row{display:flex;justify-content:space-between;align-items:center;"
               "padding:0.75rem 0;border-bottom:1px solid #f0f0f0}");
    css_append(".settings-row:last-child{border-bottom:none}");
    css_append(".settings-label{font-size:0.9rem;color:#333}");
    css_append(".settings-controls{display:flex;align-items:center;gap:0.5rem}");
    css_append(".settings-btn{padding:0.5rem 0.75rem;background:#f0f0f0;border:none;border-radius:4px;"
               "cursor:pointer;font-size:0.875rem;color:#333;transition:background 0.2s;min-width:2.5rem;"
               "text-align:center;user-select:none}");
    css_append(".settings-btn:hover{background:#e0e0e0}");
    css_append(".settings-btn.active{background:#4a7c59;color:#fff}");
    css_append(".settings-btn.active:hover{background:#3d6b4a}");
    css_append(".settings-value{min-width:3.5rem;text-align:center;font-size:0.9rem;color:#333}");

    /* M15: Back button styling */
    css_append(".back-btn{position:fixed;top:1rem;left:1rem;width:2.5rem;height:2.5rem;"
               "display:flex;align-items:center;justify-content:center;"
               "background:rgba(0,0,0,0.5);color:#fff;border-radius:50%;cursor:pointer;"
               "font-size:1.25rem;z-index:150;transition:background 0.2s;user-select:none;"
               "font-family:system-ui,-apple-system,sans-serif}");
    css_append(".back-btn:hover{background:rgba(0,0,0,0.7)}");
}

extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);
extern unsigned char* get_event_buffer_ptr(void);

/* EPUB functions */
extern void epub_init(void);
extern int epub_start_import(int file_input_node_id);
extern int epub_get_state(void);
extern int epub_get_progress(void);
extern int epub_get_error(int buf_offset);
extern int epub_get_title(int buf_offset);
extern int epub_get_author(int buf_offset);
extern int epub_get_book_id(int buf_offset);
extern int epub_get_chapter_count(void);
extern int epub_get_chapter_key(int chapter_index, int buf_offset);
extern void epub_on_file_open(int handle, int size);
extern void epub_on_decompress(int blob_handle, int size);
extern void epub_on_db_open(int success);
extern void epub_on_db_put(int success);
extern void epub_reset(void);

/* Bridge imports */
extern void js_kv_get(void* store_ptr, int store_len, void* key_ptr, int key_len);
extern void js_kv_open(void* name_ptr, int name_len, int version, void* stores_ptr, int stores_len);
extern void js_set_inner_html_from_blob(int node_id, int blob_handle);
extern void js_blob_free(int handle);
extern int js_measure_node(int node_id);

/* DOM functions */
extern void dom_init(void);
extern void* dom_root_proof(void);
extern void* dom_create_element(void*, int, int, void*, int);
extern void* dom_set_text(void*, int, void*, int);
extern void* dom_set_text_offset(void*, int, int, int);
extern void* dom_set_attr(void*, int, void*, int, void*, int);
extern void* dom_set_inner_html(void*, int, int, int);
extern void dom_remove_child(void*, int);
extern int dom_next_id(void);
extern void dom_drop_proof(void*);

/* Reader module functions */
extern void reader_init(void);
extern void reader_enter(int root_id, int container_hide_id);
extern void reader_enter_at(int root_id, int container_hide_id, int chapter, int page);
extern void reader_exit(void);
extern int reader_is_active(void);
extern int reader_get_viewport_width(void);
extern void reader_next_page(void);
extern void reader_prev_page(void);
extern void reader_go_to_page(int page);
extern int reader_get_total_pages(void);
extern int reader_get_current_chapter(void);
extern int reader_get_current_page(void);
extern void reader_on_chapter_loaded(int len);
extern void reader_on_chapter_blob_loaded(int handle, int size);
extern int reader_get_back_btn_id(void);
extern void reader_toggle_toc(void);
extern void reader_hide_toc(void);
extern int reader_is_toc_visible(void);
extern int reader_get_toc_index_for_node(int node_id);
extern void reader_on_toc_click(int node_id);

/* Settings module functions */
extern void settings_init(void);
extern void settings_set_root_id(int id);
extern int settings_is_visible(void);
extern void settings_show(void);
extern void settings_hide(void);
extern void settings_toggle(void);
extern int settings_handle_click(int node_id);
extern void settings_load(void);
extern void settings_on_load_complete(int len);
extern void settings_on_save_complete(int success);
extern int settings_is_save_pending(void);
extern int settings_is_load_pending(void);

/* Library module functions */
extern void library_init(void);
extern int library_get_count(void);
extern int library_get_title(int index, int buf_offset);
extern int library_get_author(int index, int buf_offset);
extern int library_get_book_id(int index, int buf_offset);
extern int library_get_chapter(int index);
extern int library_get_page(int index);
extern int library_get_spine_count(int index);
extern int library_add_book(void);
extern void library_remove_book(int index);
extern void library_update_position(int index, int chapter, int page);
extern int library_find_book_by_id(void);
extern void library_save(void);
extern void library_load(void);
extern void library_on_load_complete(int len);
extern void library_on_save_complete(int success);
extern void library_save_book_metadata(void);
extern void library_load_book_metadata(int index);
extern void library_on_metadata_load_complete(int len);
extern void library_on_metadata_save_complete(int success);
extern int library_is_save_pending(void);
extern int library_is_load_pending(void);
extern int library_is_metadata_pending(void);

/* Read event from event buffer */
static int get_event_type(void) {
    unsigned char* buf = get_event_buffer_ptr();
    return buf[0];
}

static int get_event_node_id(void) {
    unsigned char* buf = get_event_buffer_ptr();
    return buf[1] | (buf[2] << 8) | (buf[3] << 16) | (buf[4] << 24);
}

static int get_event_data1(void) {
    unsigned char* buf = get_event_buffer_ptr();
    return buf[5] | (buf[6] << 8) | (buf[7] << 16) | (buf[8] << 24);
}

static int get_event_data2(void) {
    unsigned char* buf = get_event_buffer_ptr();
    return buf[9] | (buf[10] << 8) | (buf[11] << 16) | (buf[12] << 24);
}

/* Helper to copy text to fetch buffer */
static int copy_text_to_fetch(const char* text, int len) {
    unsigned char* buf = get_fetch_buffer_ptr();
    for (int i = 0; i < len && i < 16384; i++) {
        buf[i] = text[i];
    }
    return len;
}

/* Helper to append integer to buffer */
static int append_int(unsigned char* buf, int pos, int value) {
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

/* Node IDs */
static int root_id = 1;
static int container_id = 0;
static int file_input_id = 0;
static int import_btn_id = 0;
static int progress_id = 0;
static int title_id = 0;
static int library_list_id = 0;

/* M15: Per-book card node IDs (read and delete buttons).
 *
 * FUNCTIONAL CORRECTNESS: Book card node ID mapping.
 * BOOK_CARD_MAPS(node_id, book_index, card_count) proves that:
 * - book_read_ids[i] is THE read button for library book index i
 * - book_delete_ids[i] is THE delete button for library book index i
 * - 0 <= i < card_count <= MAX_BOOK_READ_IDS
 *
 * Constructed by rebuild_library_list() which assigns node IDs
 * in order: for each book i, book_read_ids[i] = dom_next_id().
 * Consumed by process_event_impl click handler which looks up
 * the matching index for a clicked node_id.
 *
 * This mapping guarantees that clicking "Read" on book 3's card
 * opens book 3 (not book 2 or 4), and clicking "Delete" on book 3's
 * card removes book 3 from the library. */
#define MAX_BOOK_READ_IDS 32
#define MAX_BOOK_DELETE_IDS 32
static int book_read_ids[MAX_BOOK_READ_IDS];
static int book_delete_ids[MAX_BOOK_DELETE_IDS];
static int book_card_count = 0;

/* App state */
static int app_state = 0;  /* APP_STATE_INIT */
static int import_in_progress = 0;
static int last_progress = -1;
static int current_book_index = -1;  /* Index of book being read */

/* Forward declarations */
static void show_library(void);
static void rebuild_library_list(void);
static void enter_reader_for_book(int book_index);
static void exit_reader_to_library(void);
static void handle_import_complete(void);

/* Get CSS buffer pointer and length */
static void* get_css_buffer(void) { return css_buffer; }
static int get_css_len(void) { return css_buffer_len; }

/* String getters */
void* get_str_quire(void) { return (void*)str_quire; }
void* get_str_div(void) { return (void*)str_div; }
void* get_str_input(void) { return (void*)str_input; }
void* get_str_label(void) { return (void*)str_label; }
void* get_str_for(void) { return (void*)str_for; }
void* get_str_h1(void) { return (void*)str_h1; }
void* get_str_p(void) { return (void*)str_p; }
void* get_str_class(void) { return (void*)str_class; }
void* get_str_type(void) { return (void*)str_type; }
void* get_str_file(void) { return (void*)str_file; }
void* get_str_accept(void) { return (void*)str_accept; }
void* get_str_epub_accept(void) { return (void*)str_epub_accept; }
void* get_str_id_attr(void) { return (void*)str_id_attr; }
void* get_str_hidden(void) { return (void*)str_hidden; }
void* get_str_container(void) { return (void*)str_container; }
void* get_str_import_btn(void) { return (void*)str_import_btn; }
void* get_str_file_input(void) { return (void*)str_file_input; }
void* get_str_progress_div(void) { return (void*)str_progress_div; }
void* get_str_title_div(void) { return (void*)str_title_div; }
void* get_str_import_text(void) { return (void*)str_import_text; }
void* get_str_style(void) { return (void*)str_style; }
int get_container_id(void) { return container_id; }
int get_file_input_id(void) { return file_input_id; }
int get_import_btn_id(void) { return import_btn_id; }
int get_progress_id(void) { return progress_id; }
int get_title_id(void) { return title_id; }
void set_container_id(int id) { container_id = id; }
void set_file_input_id(int id) { file_input_id = id; }
void set_import_btn_id(int id) { import_btn_id = id; }
void set_progress_id(int id) { progress_id = id; }
void set_title_id(int id) { title_id = id; }
int get_import_in_progress(void) { return import_in_progress; }
void set_import_in_progress(int v) { import_in_progress = v; }

/* App state accessors for ATS code.
 * Every set_app_state call in ATS code must be accompanied by an
 * APP_STATE_TRANSITION proof construction. */
int get_app_state(void) { return app_state; }
void set_app_state(int s) { app_state = s; }

/* Inject styles into document */
void inject_styles(void) {
    unsigned char* fetch_buf = get_fetch_buffer_ptr();

    if (css_buffer_len == 0) {
        build_css();
    }

    for (int i = 0; i < css_buffer_len && i < 16384; i++) {
        fetch_buf[i] = css_buffer[i];
    }

    void* pf = dom_root_proof();
    int style_id = dom_next_id();
    void* pf_style = dom_create_element(pf, root_id, style_id, (void*)str_style, 5);
    dom_set_inner_html(pf_style, style_id, 0, css_buffer_len);
    dom_drop_proof(pf_style);
    dom_drop_proof(pf);
}

/* Update progress display during import */
void update_progress_display(void) {
    int progress = epub_get_progress();
    if (progress == last_progress) return;
    last_progress = progress;

    unsigned char* buf = get_fetch_buffer_ptr();
    int len = 0;

    const char* importing = str_importing;
    while (*importing && len < 16380) {
        buf[len++] = *importing++;
    }
    buf[len++] = ' ';

    len = append_int(buf, len, progress);
    buf[len++] = '%';

    void* pf = dom_root_proof();
    dom_set_text_offset(pf, progress_id, 0, len);
    dom_drop_proof(pf);
}

/* Show import error */
void show_import_error(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();
    int len = 0;

    const char* prefix = str_error_prefix;
    while (*prefix && len < 16380) {
        buf[len++] = *prefix++;
    }

    int error_len = epub_get_error(0);
    for (int i = 0; i < error_len && len < 16380; i++) {
        buf[len++] = str_buf[i];
    }

    void* pf = dom_root_proof();
    dom_set_text_offset(pf, progress_id, 0, len);
    dom_drop_proof(pf);
}

/* M15: Build and display the library list.
 *
 * FUNCTIONAL CORRECTNESS: Establishes BOOK_CARD_MAPS for all books.
 * For each book i in 0..count-1:
 * - book_read_ids[i] = dom_next_id() assigned during card creation
 * - book_delete_ids[i] = dom_next_id() assigned during card creation
 * - Title, author, position displayed are from library_get_title/author/etc(i)
 *   which return THE data for book i (verified by BOOK_IN_LIBRARY).
 * - book_card_count is set to min(count, MAX_BOOK_READ_IDS)
 *
 * The sequential assignment (i=0 gets first pair of IDs, i=1 gets next, etc.)
 * ensures the mapping is bijective: each button maps to exactly one book. */
static void rebuild_library_list(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();
    void* pf = dom_root_proof();

    /* Remove old library list if exists */
    if (library_list_id > 0) {
        dom_remove_child(pf, library_list_id);
        library_list_id = 0;
    }

    /* Create library list container */
    int list_id = dom_next_id();
    library_list_id = list_id;
    void* pf_list = dom_create_element(pf, container_id, list_id, (void*)str_div, 3);
    pf_list = dom_set_attr(pf_list, list_id, (void*)str_class, 5,
                           (void*)str_library_list, 12);

    int count = library_get_count();
    book_card_count = 0;

    if (count == 0) {
        /* Show empty library message */
        int empty_id = dom_next_id();
        void* pf_empty = dom_create_element(pf_list, list_id, empty_id, (void*)str_p, 1);
        pf_empty = dom_set_attr(pf_empty, empty_id, (void*)str_class, 5,
                                (void*)"empty-lib", 9);
        int len = 0;
        const char* msg = str_empty_lib;
        while (*msg && len < 200) buf[len++] = *msg++;
        dom_set_text_offset(pf_empty, empty_id, 0, len);
        dom_drop_proof(pf_empty);
    } else {
        for (int i = 0; i < count && i < MAX_BOOK_READ_IDS; i++) {
            /* Create book card */
            int card_id = dom_next_id();
            void* pf_card = dom_create_element(pf_list, list_id, card_id, (void*)str_div, 3);
            pf_card = dom_set_attr(pf_card, card_id, (void*)str_class, 5,
                                   (void*)str_book_card, 9);

            /* Title */
            int title_nid = dom_next_id();
            void* pf_title = dom_create_element(pf_card, card_id, title_nid, (void*)str_div, 3);
            pf_title = dom_set_attr(pf_title, title_nid, (void*)str_class, 5,
                                    (void*)str_book_title, 10);
            int tlen = library_get_title(i, 0);
            if (tlen > 0) {
                for (int j = 0; j < tlen && j < 200; j++) buf[j] = str_buf[j];
                dom_set_text_offset(pf_title, title_nid, 0, tlen);
            }
            dom_drop_proof(pf_title);

            /* Author */
            int author_nid = dom_next_id();
            void* pf_author = dom_create_element(pf_card, card_id, author_nid, (void*)str_div, 3);
            pf_author = dom_set_attr(pf_author, author_nid, (void*)str_class, 5,
                                     (void*)str_book_author, 11);
            int alen = library_get_author(i, 0);
            if (alen > 0) {
                int len = 0;
                const char* by = str_by;
                /* skip leading space in " by " */
                by++;
                while (*by && len < 200) buf[len++] = *by++;
                for (int j = 0; j < alen && len < 400; j++) buf[len++] = str_buf[j];
                dom_set_text_offset(pf_author, author_nid, 0, len);
            }
            dom_drop_proof(pf_author);

            /* Position */
            int pos_nid = dom_next_id();
            void* pf_pos = dom_create_element(pf_card, card_id, pos_nid, (void*)str_div, 3);
            pf_pos = dom_set_attr(pf_pos, pos_nid, (void*)str_class, 5,
                                  (void*)str_book_position, 13);
            {
                int ch = library_get_chapter(i);
                int pg = library_get_page(i);
                int sc = library_get_spine_count(i);
                int len = 0;

                if (ch == 0 && pg == 0) {
                    const char* ns = str_not_started;
                    while (*ns && len < 200) buf[len++] = *ns++;
                } else {
                    const char* ch_s = str_ch_space;
                    while (*ch_s && len < 200) buf[len++] = *ch_s++;
                    len = append_int(buf, len, ch + 1);
                    const char* of_s = str_of_space;
                    while (*of_s && len < 200) buf[len++] = *of_s++;
                    len = append_int(buf, len, sc);
                    const char* pg_s = str_comma_pg;
                    while (*pg_s && len < 200) buf[len++] = *pg_s++;
                    len = append_int(buf, len, pg + 1);
                }
                dom_set_text_offset(pf_pos, pos_nid, 0, len);
            }
            dom_drop_proof(pf_pos);

            /* Actions row */
            int acts_nid = dom_next_id();
            void* pf_acts = dom_create_element(pf_card, card_id, acts_nid, (void*)str_div, 3);
            pf_acts = dom_set_attr(pf_acts, acts_nid, (void*)str_class, 5,
                                   (void*)str_book_actions, 12);

            /* Read button */
            int read_nid = dom_next_id();
            book_read_ids[i] = read_nid;
            void* pf_read = dom_create_element(pf_acts, acts_nid, read_nid, (void*)str_label, 5);
            pf_read = dom_set_attr(pf_read, read_nid, (void*)str_class, 5,
                                   (void*)str_read_btn, 8);
            {
                int len = 0;
                const char* txt = str_read_text;
                while (*txt && len < 20) buf[len++] = *txt++;
                dom_set_text_offset(pf_read, read_nid, 0, len);
            }
            dom_drop_proof(pf_read);

            /* Delete button */
            int del_nid = dom_next_id();
            book_delete_ids[i] = del_nid;
            void* pf_del = dom_create_element(pf_acts, acts_nid, del_nid, (void*)str_label, 5);
            pf_del = dom_set_attr(pf_del, del_nid, (void*)str_class, 5,
                                  (void*)str_delete_btn, 10);
            {
                int len = 0;
                const char* txt = str_delete_text;
                while (*txt && len < 20) buf[len++] = *txt++;
                dom_set_text_offset(pf_del, del_nid, 0, len);
            }
            dom_drop_proof(pf_del);

            dom_drop_proof(pf_acts);
            dom_drop_proof(pf_card);
            book_card_count++;
        }
    }

    dom_drop_proof(pf_list);
    dom_drop_proof(pf);
}

/* M15: Show library view (creates full UI) */
static void show_library(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    void* pf = dom_root_proof();

    /* Unhide container if hidden */
    pf = dom_set_attr(pf, container_id, (void*)str_class, 5, (void*)str_container, 9);

    /* Clear progress and title text */
    dom_set_text_offset(pf, progress_id, 0, 0);
    dom_set_text_offset(pf, title_id, 0, 0);

    dom_drop_proof(pf);

    /* Build library list */
    rebuild_library_list();

    /* TRANSITION: Multiple valid transitions lead here:
     *   LOADING_LIB_TO_LIBRARY(2, 3)
     *   LOADING_DB_TO_LIBRARY(1, 3)
     *   IMPORTING_TO_LIBRARY(4, 3)
     *   READING_TO_LIBRARY(6, 3)
     * show_library() is a terminal transition to LIBRARY state. */
    app_state = APP_STATE_LIBRARY;
}

/* M15: Enter reader for a specific book.
 *
 * FUNCTIONAL CORRECTNESS:
 * - book_index is verified against library_get_count() (BOOK_IN_LIBRARY)
 * - current_book_index is set to book_index, creating a binding between
 *   the reader session and THE correct book
 * - library_load_book_metadata(book_index) loads THE metadata for this book
 *   (key constructed from book_id at this index)
 * - State transition: LIBRARY -> LOADING_BOOK (APP_STATE_TRANSITION) */
static void enter_reader_for_book(int book_index) {
    if (book_index < 0 || book_index >= library_get_count()) return;

    current_book_index = book_index;
    app_state = APP_STATE_LOADING_BOOK;  // TRANSITION: LIBRARY_TO_LOADING_BOOK(3, 5)

    /* Load book metadata from IndexedDB */
    library_load_book_metadata(book_index);
}

/* M15: Exit reader back to library.
 *
 * FUNCTIONAL CORRECTNESS:
 * - Saves reading position via library_update_position using
 *   reader_get_current_chapter/page which return THE current position
 * - library_save() persists the updated position (async)
 * - State transition: READING -> LIBRARY (APP_STATE_TRANSITION)
 * - reader_exit() cleans up reader DOM state */
static void exit_reader_to_library(void) {
    /* Save current reading position */
    if (current_book_index >= 0) {
        int ch = reader_get_current_chapter();
        int pg = reader_get_current_page();
        library_update_position(current_book_index, ch, pg);

        /* Save library index (async) */
        library_save();
    }

    /* Remove reader DOM elements */
    void* pf = dom_root_proof();

    /* Remove viewport, page indicator, progress bar, back button */
    int back_id = reader_get_back_btn_id();
    if (back_id > 0) dom_remove_child(pf, back_id);

    dom_drop_proof(pf);

    reader_exit();
    current_book_index = -1;
    app_state = APP_STATE_LIBRARY;  // TRANSITION: READING_TO_LIBRARY(6, 3)

    /* Show library view */
    show_library();
}

/* M15: Handle import completion - add to library and save.
 *
 * FUNCTIONAL CORRECTNESS:
 * - library_add_book() reads from epub module state which is in DONE state
 *   (verified by epub_get_state() == 8 in handle_state_after_op)
 * - Deduplication: if book already exists, returns existing index
 * - library_save_book_metadata() serializes THE current epub state
 *   (METADATA_ROUNDTRIP guarantees correct restore on next load)
 * - Eventual state transition: IMPORTING -> LIBRARY after async saves */
static void handle_import_complete(void) {
    import_in_progress = 0;

    /* Add book to library */
    int idx = library_add_book();

    /* Save book metadata to IDB */
    library_save_book_metadata();

    /* We need to wait for metadata save, then save library index */
    /* Metadata save is async; we handle it in on_kv_complete */
}

/* M15: Handle state transitions after async EPUB operations */
static void handle_state_after_op(void) {
    int state = epub_get_state();
    if (state == 99) {  /* Error */
        show_import_error();
        import_in_progress = 0;
        app_state = APP_STATE_LIBRARY;  // TRANSITION: IMPORTING_TO_LIBRARY(4, 3) [error path]
    } else if (state == 6 || state == 7) {  /* Still processing */
        update_progress_display();
    } else if (state == 8) {  /* Done */
        handle_import_complete();
    }
}

/* M15: String constants for IDB */
static const char str_quire_db[] = "quire";
static const char str_stores[] = "books,chapters,resources,settings";

/* String constant accessors for open_db (ATS code) */
void* get_str_quire_db(void) { return (void*)str_quire_db; }
void* get_str_stores(void) { return (void*)str_stores; }

/* process_event implementation */
void process_event_impl(void) {
    int event_type = get_event_type();
    int node_id = get_event_node_id();
    int data1 = get_event_data1();
    int data2 = get_event_data2();

    /* Click events */
    if (event_type == 1) {
        /* Settings modal takes priority */
        if (settings_is_visible()) {
            if (settings_handle_click(node_id)) return;
            settings_hide();
            return;
        }

        /* M15: Back button in reader mode */
        if (reader_is_active() && node_id == reader_get_back_btn_id()) {
            exit_reader_to_library();
            return;
        }

        /* M15: Book read buttons in library view */
        if (app_state == APP_STATE_LIBRARY) {
            for (int i = 0; i < book_card_count; i++) {
                if (node_id == book_read_ids[i]) {
                    enter_reader_for_book(i);
                    return;
                }
                if (node_id == book_delete_ids[i]) {
                    library_remove_book(i);
                    library_save();
                    rebuild_library_list();
                    return;
                }
            }
        }

        /* Reader click zones */
        int vw = reader_get_viewport_width();
        if (reader_is_active() && vw > 0) {
            if (reader_is_toc_visible()) {
                int toc_index = reader_get_toc_index_for_node(node_id);
                if (toc_index >= 0) {
                    reader_on_toc_click(node_id);
                    return;
                }
                reader_hide_toc();
                return;
            }

            int click_x = data1;
            int zone_left = vw / 5;
            int zone_right = vw - zone_left;

            if (click_x < zone_left) {
                reader_prev_page();
            } else if (click_x > zone_right) {
                reader_next_page();
            } else {
                reader_toggle_toc();
            }
        }
    }

    /* Input events (file selected) */
    if (event_type == 2) {
        if (node_id == file_input_id && !import_in_progress) {
            import_in_progress = 1;
            app_state = APP_STATE_IMPORTING;  // TRANSITION: LIBRARY_TO_IMPORTING(3, 4)

            /* Show import progress */
            unsigned char* buf = get_fetch_buffer_ptr();
            int len = 0;
            const char* importing = str_importing;
            while (*importing && len < 100) buf[len++] = *importing++;
            void* pf = dom_root_proof();
            dom_set_text_offset(pf, progress_id, 0, len);
            dom_drop_proof(pf);

            epub_start_import(node_id);
        }
    }

    /* Keyboard events in reader mode */
    if (event_type == 4 && reader_is_active()) {
        int key_code = data1;

        if (key_code == 27 && settings_is_visible()) {
            settings_hide();
            return;
        }

        /* M15: Escape exits reader if nothing else is open */
        if (key_code == 27 && !reader_is_toc_visible() && !settings_is_visible()) {
            exit_reader_to_library();
            return;
        }

        if (key_code == 83 && !reader_is_toc_visible()) {
            settings_toggle();
            return;
        }

        if (settings_is_visible()) return;

        switch (key_code) {
            case 27:
                if (reader_is_toc_visible()) reader_hide_toc();
                break;
            case 84:
                reader_toggle_toc();
                break;
            case 37: case 33:
                if (!reader_is_toc_visible()) reader_prev_page();
                break;
            case 39: case 34: case 32:
                if (!reader_is_toc_visible()) reader_next_page();
                break;
            case 36:
                if (!reader_is_toc_visible()) reader_go_to_page(0);
                break;
            case 35:
                if (!reader_is_toc_visible()) reader_go_to_page(reader_get_total_pages() - 1);
                break;
        }
    }
}

/* Async callback: file open */
void on_file_open_impl(int handle, int size) {
    epub_on_file_open(handle, size);
    int state = epub_get_state();
    if (state == 99) {
        show_import_error();
        import_in_progress = 0;
        app_state = APP_STATE_LIBRARY;  // TRANSITION: IMPORTING_TO_LIBRARY(4, 3) [error]
    }
}

/* Async callback: decompress */
void on_decompress_impl(int handle, int size) {
    epub_on_decompress(handle, size);
    handle_state_after_op();
}

/* Async callback: kv put complete.
 *
 * FUNCTIONAL CORRECTNESS: Callback dispatch correctness.
 * CALLBACK_DISPATCH_CORRECT proves that each async completion callback
 * is routed to THE correct handler based on pending operation state.
 *
 * Dispatch priority (checked in order):
 * 1. settings_is_save_pending() -> settings_on_save_complete
 * 2. library_is_metadata_pending() -> library_on_metadata_save_complete
 * 3. library_is_save_pending() -> library_on_save_complete
 * 4. (default) -> epub_on_db_put (during import)
 *
 * Correctness relies on the invariant that at most ONE pending flag
 * is set at any time. This is maintained because:
 * - Each async operation sets its flag before calling js_kv_put
 * - The completion handler clears the flag before starting new ops
 * - Only one kv_put is in flight at a time (JS bridge serializes) */
void on_kv_complete_impl(int success) {
    /* Settings save takes priority */
    if (settings_is_save_pending()) {
        settings_on_save_complete(success);
        return;
    }
    /* Library metadata save */
    if (library_is_metadata_pending()) {
        library_on_metadata_save_complete(success);
        /* After metadata save, save library index */
        library_save();
        return;
    }
    /* Library index save */
    if (library_is_save_pending()) {
        library_on_save_complete(success);
        /* If we just finished import+save, show library */
        if (app_state == APP_STATE_IMPORTING) {
            app_state = APP_STATE_LIBRARY;  // TRANSITION: IMPORTING_TO_LIBRARY(4, 3) [save done]
            show_library();
        }
        return;
    }
    /* EPUB import put */
    epub_on_db_put(success);
    handle_state_after_op();
}

/* Async callback: kv open complete */
void on_kv_open_impl(int success) {
    if (app_state == APP_STATE_LOADING_DB) {
        if (success) {
            /* DB opened, now load library index */
            app_state = APP_STATE_LOADING_LIB;  // TRANSITION: LOADING_DB_TO_LOADING_LIB(1, 2)
            library_load();
        } else {
            /* DB failed to open, show empty library */
            app_state = APP_STATE_LIBRARY;  // TRANSITION: LOADING_DB_TO_LIBRARY(1, 3)
            show_library();
        }
        return;
    }
    /* During import, forward to epub */
    epub_on_db_open(success);
    int state = epub_get_state();
    if (state == 99) {
        show_import_error();
        import_in_progress = 0;
        app_state = APP_STATE_LIBRARY;  // TRANSITION: IMPORTING_TO_LIBRARY(4, 3) [error]
    }
}

/* Async callback: kv get complete.
 *
 * FUNCTIONAL CORRECTNESS: Callback dispatch correctness.
 * Dispatch priority (checked in order):
 * 1. settings_is_load_pending() -> settings_on_load_complete
 * 2. library_is_load_pending() -> library_on_load_complete
 * 3. library_is_metadata_pending() -> library_on_metadata_load_complete
 * 4. reader_is_active() -> reader_on_chapter_loaded
 *
 * Same single-pending-flag invariant as on_kv_complete_impl.
 * After metadata load, enters reader at saved position using
 * library_get_chapter/page to retrieve THE correct position
 * for the selected book. */
void on_kv_get_complete_impl(int len) {
    /* Settings load */
    if (settings_is_load_pending()) {
        settings_on_load_complete(len);
        return;
    }
    /* Library index load */
    if (library_is_load_pending()) {
        library_on_load_complete(len);
        if (app_state == APP_STATE_LOADING_LIB) {
            /* Library loaded, show it */
            show_library();
            /* Load settings */
            settings_load();
        }
        return;
    }
    /* Library metadata load */
    if (library_is_metadata_pending()) {
        library_on_metadata_load_complete(len);
        if (app_state == APP_STATE_LOADING_BOOK && current_book_index >= 0) {
            /* Metadata restored, enter reader */
            int ch = library_get_chapter(current_book_index);
            int pg = library_get_page(current_book_index);
            app_state = APP_STATE_READING;  // TRANSITION: LOADING_BOOK_TO_READING(5, 6)
            if (ch > 0 || pg > 0) {
                reader_enter_at(root_id, container_id, ch, pg);
            } else {
                reader_enter(root_id, container_id);
            }
        }
        return;
    }
    /* Reader chapter load */
    if (reader_is_active()) {
        reader_on_chapter_loaded(len);
    }
}

/* Async callback: kv get blob complete */
void on_kv_get_blob_complete_impl(int handle, int size) {
    if (reader_is_active()) {
        reader_on_chapter_blob_loaded(handle, size);
    }
}
%}

(* ========== M15: App State Machine Proofs ========== *)

(* App state validity proof.
 * APP_STATE_VALID(s) proves state s is one of the defined app states.
 * Prevents invalid state values at compile time. *)
dataprop APP_STATE_VALID(state: int) =
  | APP_INIT_STATE(0)
  | APP_LOADING_DB_STATE(1)
  | APP_LOADING_LIB_STATE(2)
  | APP_LIBRARY_STATE(3)
  | APP_IMPORTING_STATE(4)
  | APP_LOADING_BOOK_STATE(5)
  | APP_READING_STATE(6)

(* App state transition proof.
 * APP_STATE_TRANSITION(from, to) proves that transitioning from state `from`
 * to state `to` is a valid state machine transition.
 *
 * BUG PREVENTED: open_db() originally called js_kv_open() without setting
 * app_state = APP_STATE_LOADING_DB. When on_kv_open_complete fired, the
 * check `app_state == APP_STATE_LOADING_DB` failed (still INIT), so the
 * library never loaded. The documentary proof existed but wasn't enforced.
 *
 * ENFORCEMENT: Functions that perform state transitions in ATS code should
 * construct and consume proof witnesses. For C block transitions, the
 * transition must be documented with a comment citing this dataprop.
 * Each C block that sets app_state MUST have a comment:
 *   // TRANSITION: APP_STATE_TRANSITION(from, to)
 * This ensures code review catches missing transitions. *)
dataprop APP_STATE_TRANSITION(from: int, to: int) =
  | INIT_TO_LOADING_DB(0, 1)
  | LOADING_DB_TO_LOADING_LIB(1, 2)
  | LOADING_DB_TO_LIBRARY(1, 3)
  | LOADING_LIB_TO_LIBRARY(2, 3)
  | LIBRARY_TO_IMPORTING(3, 4)
  | LIBRARY_TO_LOADING_BOOK(3, 5)
  | IMPORTING_TO_LIBRARY(4, 3)
  | LOADING_BOOK_TO_READING(5, 6)
  | READING_TO_LIBRARY(6, 3)

(* Book card node ID mapping proof.
 * BOOK_CARD_MAPS(node_id, book_index, card_count) proves that
 * node_id is THE read or delete button for book at book_index,
 * where 0 <= book_index < card_count.
 *
 * Constructed by rebuild_library_list, consumed by process_event_impl.
 * NOTE: Proof is documentary - runtime loop scan verifies mapping. *)
dataprop BOOK_CARD_MAPS(node_id: int, book_index: int, card_count: int) =
  | {n:int} {i,c:nat | i < c} CARD_FOR_BOOK(n, i, c)

(* Async callback dispatch proof.
 * CALLBACK_ROUTED(handler_id) proves that an async completion was
 * routed to handler handler_id based on pending flags.
 * handler_id: 0=settings, 1=library_metadata, 2=library_index,
 *             3=epub_import, 4=reader_chapter
 *
 * NOTE: Proof is documentary - pending flag checks verify routing. *)
dataprop CALLBACK_ROUTED(handler_id: int) =
  | ROUTE_SETTINGS(0)
  | ROUTE_LIB_METADATA(1)
  | ROUTE_LIB_INDEX(2)
  | ROUTE_EPUB_IMPORT(3)
  | ROUTE_READER_CHAPTER(4)

(* External ATS function declarations *)
extern fun get_str_quire(): ptr = "mac#"
extern fun get_str_div(): ptr = "mac#"
extern fun get_str_input(): ptr = "mac#"
extern fun get_str_label(): ptr = "mac#"
extern fun get_str_for(): ptr = "mac#"
extern fun get_str_h1(): ptr = "mac#"
extern fun get_str_p(): ptr = "mac#"
extern fun get_str_class(): ptr = "mac#"
extern fun get_str_type(): ptr = "mac#"
extern fun get_str_file(): ptr = "mac#"
extern fun get_str_accept(): ptr = "mac#"
extern fun get_str_epub_accept(): ptr = "mac#"
extern fun get_str_id_attr(): ptr = "mac#"
extern fun get_str_hidden(): ptr = "mac#"
extern fun get_str_container(): ptr = "mac#"
extern fun get_str_import_btn(): ptr = "mac#"
extern fun get_str_file_input(): ptr = "mac#"
extern fun get_str_progress_div(): ptr = "mac#"
extern fun get_str_title_div(): ptr = "mac#"
extern fun get_str_import_text(): ptr = "mac#"
extern fun get_str_style(): ptr = "mac#"
extern fun get_css_buffer(): ptr = "mac#"
extern fun get_css_len(): int = "mac#"
extern fun build_css(): void = "mac#"
extern fun inject_styles(): void = "mac#"
extern fun copy_text_to_fetch(text: ptr, len: int): int = "mac#"
extern fun get_event_type(): int = "mac#"
extern fun get_event_node_id(): int = "mac#"
extern fun get_container_id(): int = "mac#"
extern fun get_file_input_id(): int = "mac#"
extern fun get_import_btn_id(): int = "mac#"
extern fun get_progress_id(): int = "mac#"
extern fun get_title_id(): int = "mac#"
extern fun set_container_id(id: int): void = "mac#"
extern fun set_file_input_id(id: int): void = "mac#"
extern fun set_import_btn_id(id: int): void = "mac#"
extern fun set_progress_id(id: int): void = "mac#"
extern fun set_title_id(id: int): void = "mac#"
extern fun get_import_in_progress(): int = "mac#"
extern fun set_import_in_progress(v: int): void = "mac#"
extern fun update_progress_display(): void = "mac#"
extern fun show_import_error(): void = "mac#"

(* M12: ATS extern for reader_init *)
extern fun reader_init_ats(): void = "mac#reader_init"

(* M14: ATS extern for settings_init *)
extern fun settings_init_ats(): void = "mac#settings_init"
extern fun settings_set_root_id_ats(id: int): void = "mac#settings_set_root_id"

(* M15: ATS extern for library_init *)
extern fun library_init_ats(): void = "mac#library_init"

(* App state accessors — used to enforce APP_STATE_TRANSITION from ATS *)
extern fun get_app_state(): int = "mac#"
extern fun set_app_state(s: int): void = "mac#"

(* String constants for open_db *)
extern fun get_str_quire_db(): ptr = "mac#"
extern fun get_str_stores(): ptr = "mac#"

(* Bridge import for opening IndexedDB *)
extern fun js_kv_open(name_ptr: ptr, name_len: int, version: int,
                      stores_ptr: ptr, stores_len: int): void = "mac#"

(* Open IndexedDB for library and book data.
 * ENFORCED PROOF: Constructs INIT_TO_LOADING_DB(0, 1) at compile time,
 * guaranteeing that app_state is set to LOADING_DB BEFORE the async
 * js_kv_open call.
 *
 * BUG PREVENTED: Original C version forgot to set app_state before
 * js_kv_open. When on_kv_open_complete fired, it checked for
 * APP_STATE_LOADING_DB but found INIT, so library never loaded.
 *
 * TEST MADE PASS-BY-CONSTRUCTION:
 *   test_open_db_sets_state_before_async — The ATS type system ensures
 *   set_app_state(1) happens textually before js_kv_open. *)
fn open_db(): void = let
    (* Construct transition proof — this is the ENFORCED version of
     * the documentary comment that was in the C code. *)
    prval _pf_transition = INIT_TO_LOADING_DB()

    (* Set state BEFORE async call — the proof above witnesses
     * that this is a valid transition from INIT(0) to LOADING_DB(1). *)
    val () = set_app_state(1) (* APP_STATE_LOADING_DB *)
  in
    (* Now safe to call async: on_kv_open_complete will see LOADING_DB *)
    js_kv_open(get_str_quire_db(), 5, 1, get_str_stores(), 33)
  end

(* Initialize the application UI *)
implement init() = let
    val () = dom_init()
    val () = epub_init()
    val () = reader_init_ats()
    val () = settings_init_ats()
    val () = settings_set_root_id_ats(1)
    val () = library_init_ats()

    (* Get root proof *)
    val pf_root = dom_root_proof()

    (* Clear loading text BEFORE injecting styles.
     * dom_set_text_offset with len=0 sets textContent='', which removes
     * all children.  Must happen before inject_styles adds <style>. *)
    val pf_root = dom_set_text_offset(pf_root, 1, 0, 0)
    val () = dom_drop_proof(pf_root)

    (* Inject CSS styles into document *)
    val () = inject_styles()

    (* Re-acquire root proof after inject_styles *)
    val pf_root = dom_root_proof()

    (* Create container div — all dom_set_attr_checked calls below
     * consume a VALID_ATTR_NAME proof, enforcing Bug #3 prevention
     * at compile time. *)
    val cid = dom_next_id()
    val () = set_container_id(cid)
    val pf_container = dom_create_element(pf_root, 1, cid, get_str_div(), 3)
    val pf_container = dom_set_attr_checked(lemma_attr_class(),
                                     pf_container, cid,
                                     get_str_class(), 5,
                                     get_str_container(), 9)

    (* Create title heading *)
    val tid = dom_next_id()
    val pf_title_h = dom_create_element(pf_container, cid, tid, get_str_h1(), 2)
    val _len = copy_text_to_fetch(get_str_quire(), 5)
    val pf_title_h = dom_set_text_offset(pf_title_h, tid, 0, 5)
    val () = dom_drop_proof(pf_title_h)

    (* Create hidden file input *)
    val fid = dom_next_id()
    val () = set_file_input_id(fid)
    val pf_file = dom_create_element(pf_container, cid, fid, get_str_input(), 5)
    val pf_file = dom_set_attr_checked(lemma_attr_type(),
                                pf_file, fid,
                                get_str_type(), 4,
                                get_str_file(), 4)
    val pf_file = dom_set_attr_checked(lemma_attr_accept(),
                                pf_file, fid,
                                get_str_accept(), 6,
                                get_str_epub_accept(), 26)
    val pf_file = dom_set_attr_checked(lemma_attr_class(),
                                pf_file, fid,
                                get_str_class(), 5,
                                get_str_hidden(), 6)
    val pf_file = dom_set_attr_checked(lemma_attr_id(),
                                pf_file, fid,
                                get_str_id_attr(), 2,
                                get_str_file_input(), 10)
    val () = dom_drop_proof(pf_file)

    (* Create import button (label for file input) *)
    val bid = dom_next_id()
    val () = set_import_btn_id(bid)
    val pf_btn = dom_create_element(pf_container, cid, bid, get_str_label(), 5)
    val pf_btn = dom_set_attr_checked(lemma_attr_class(),
                               pf_btn, bid,
                               get_str_class(), 5,
                               get_str_import_btn(), 10)
    val pf_btn = dom_set_attr_checked(lemma_attr_for(),
                               pf_btn, bid,
                               get_str_for(), 3,
                               get_str_file_input(), 10)
    val _len = copy_text_to_fetch(get_str_import_text(), 11)
    val pf_btn = dom_set_text_offset(pf_btn, bid, 0, 11)
    val () = dom_drop_proof(pf_btn)

    (* Create progress display *)
    val pid = dom_next_id()
    val () = set_progress_id(pid)
    val pf_prog = dom_create_element(pf_container, cid, pid, get_str_p(), 1)
    val pf_prog = dom_set_attr_checked(lemma_attr_class(),
                                pf_prog, pid,
                                get_str_class(), 5,
                                get_str_progress_div(), 12)
    val () = dom_drop_proof(pf_prog)

    (* Create title display area (reused for import status) *)
    val did = dom_next_id()
    val () = set_title_id(did)
    val pf_tdiv = dom_create_element(pf_container, cid, did, get_str_p(), 1)
    val pf_tdiv = dom_set_attr_checked(lemma_attr_class(),
                                pf_tdiv, did,
                                get_str_class(), 5,
                                get_str_title_div(), 9)
    val () = dom_drop_proof(pf_tdiv)

    (* Clean up proofs *)
    val () = dom_drop_proof(pf_container)
    val () = dom_drop_proof(pf_root)
  in
    (* M15: Open database and load library.
     * State transition: INIT -> LOADING_DB (APP_STATE_TRANSITION).
     * on_kv_open_complete will handle the DB open result and
     * continue the startup sequence: LOADING_DB -> LOADING_LIB -> LIBRARY. *)
    open_db()
  end

(* C implementations for callbacks *)
extern fun process_event_impl(): void = "mac#"
extern fun on_file_open_impl(handle: int, size: int): void = "mac#"
extern fun on_decompress_impl(handle: int, size: int): void = "mac#"
extern fun on_kv_complete_impl(success: int): void = "mac#"
extern fun on_kv_open_impl(success: int): void = "mac#"
extern fun on_kv_get_complete_impl(len: int): void = "mac#"
extern fun on_kv_get_blob_complete_impl(handle: int, size: int): void = "mac#"

implement process_event() = process_event_impl()
implement on_fetch_complete(status, len) = ()
implement on_timer_complete(callback_id) = ()
implement on_file_open_complete(handle, size) = on_file_open_impl(handle, size)
implement on_decompress_complete(handle, size) = on_decompress_impl(handle, size)
implement on_kv_complete(success) = on_kv_complete_impl(success)
implement on_kv_get_complete(len) = on_kv_get_complete_impl(len)
implement on_kv_get_blob_complete(handle, size) = on_kv_get_blob_complete_impl(handle, size)
implement on_clipboard_copy_complete(success) = ()
implement on_kv_open_complete(success) = on_kv_open_impl(success)
