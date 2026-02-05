(* quire.dats - Quire e-reader main module
 *
 * EPUB import pipeline with type-checked DOM operations.
 * M9: File input, import progress, book title display.
 *)

#define ATS_DYNLOADFLAG 0

staload "quire.sats"
staload "dom.sats"
staload "epub.sats"

%{^
/* String literals for DOM operations */
static const char str_quire[] = "Quire";
static const char str_div[] = "div";
static const char str_input[] = "input";
static const char str_label[] = "label";
static const char str_for[] = "for";
static const char str_h1[] = "h1";
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
static const char str_done[] = "Import complete!";
static const char str_error_prefix[] = "Error: ";
static const char str_by[] = " by ";
static const char str_chapters[] = " chapters";

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
extern int epub_get_chapter_count(void);
extern void epub_on_file_open(int handle, int size);
extern void epub_on_decompress(int blob_handle, int size);
extern void epub_on_db_open(int success);
extern void epub_on_db_put(int success);

/* DOM functions */
extern void dom_init(void);
extern void* dom_root_proof(void);
extern void* dom_create_element(void*, int, int, void*, int);
extern void* dom_set_text(void*, int, void*, int);
extern void* dom_set_text_offset(void*, int, int, int);
extern void* dom_set_attr(void*, int, void*, int, void*, int);
extern int dom_next_id(void);
extern void dom_drop_proof(void*);

/* Read event type from event buffer */
static int get_event_type(void) {
    unsigned char* buf = get_event_buffer_ptr();
    return buf[0];
}

/* Read node ID from event buffer */
static int get_event_node_id(void) {
    unsigned char* buf = get_event_buffer_ptr();
    return buf[1] | (buf[2] << 8) | (buf[3] << 16) | (buf[4] << 24);
}

/* Helper to copy text to fetch buffer */
static int copy_text_to_fetch(const char* text, int len) {
    unsigned char* buf = get_fetch_buffer_ptr();
    for (int i = 0; i < len && i < 16384; i++) {
        buf[i] = text[i];
    }
    return len;
}

/* Node IDs for UI elements */
static int root_id = 1;
static int container_id = 0;
static int file_input_id = 0;
static int import_btn_id = 0;
static int progress_id = 0;
static int title_id = 0;

/* Import state tracking */
static int import_in_progress = 0;
static int last_progress = -1;
%}

(* External declarations for C functions and strings *)
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
extern fun get_str_importing(): ptr = "mac#"
extern fun get_str_done(): ptr = "mac#"
extern fun get_str_error_prefix(): ptr = "mac#"
extern fun get_str_by(): ptr = "mac#"
extern fun get_str_chapters(): ptr = "mac#"
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
extern fun show_import_complete(): void = "mac#"
extern fun show_import_error(): void = "mac#"

%{
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
void* get_str_importing(void) { return (void*)str_importing; }
void* get_str_done(void) { return (void*)str_done; }
void* get_str_error_prefix(void) { return (void*)str_error_prefix; }
void* get_str_by(void) { return (void*)str_by; }
void* get_str_chapters(void) { return (void*)str_chapters; }

/* Node ID getters/setters */
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

/* Update progress display */
void update_progress_display(void) {
    int progress = epub_get_progress();
    if (progress == last_progress) return;
    last_progress = progress;

    unsigned char* buf = get_fetch_buffer_ptr();
    int len = 0;

    /* "Importing... XX%" */
    const char* importing = str_importing;
    while (*importing && len < 16380) {
        buf[len++] = *importing++;
    }
    buf[len++] = ' ';

    /* Convert progress to string */
    if (progress >= 100) {
        buf[len++] = '1';
        buf[len++] = '0';
        buf[len++] = '0';
    } else if (progress >= 10) {
        buf[len++] = '0' + (progress / 10);
        buf[len++] = '0' + (progress % 10);
    } else {
        buf[len++] = '0' + progress;
    }
    buf[len++] = '%';

    /* Update progress text */
    void* pf = dom_root_proof();
    dom_set_text_offset(pf, progress_id, 0, len);
    dom_drop_proof(pf);
}

/* Show import complete message with book info */
void show_import_complete(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();
    int len = 0;

    /* Get title */
    int title_len = epub_get_title(0);
    for (int i = 0; i < title_len && len < 16380; i++) {
        buf[len++] = str_buf[i];
    }

    /* " by " */
    const char* by = str_by;
    while (*by && len < 16380) {
        buf[len++] = *by++;
    }

    /* Get author */
    int author_len = epub_get_author(0);
    for (int i = 0; i < author_len && len < 16380; i++) {
        buf[len++] = str_buf[i];
    }

    /* Update title display */
    void* pf = dom_root_proof();
    dom_set_text_offset(pf, title_id, 0, len);

    /* Update progress to show chapter count */
    len = 0;
    int chapter_count = epub_get_chapter_count();

    /* Convert chapter count */
    if (chapter_count >= 100) {
        buf[len++] = '0' + (chapter_count / 100);
        buf[len++] = '0' + ((chapter_count / 10) % 10);
        buf[len++] = '0' + (chapter_count % 10);
    } else if (chapter_count >= 10) {
        buf[len++] = '0' + (chapter_count / 10);
        buf[len++] = '0' + (chapter_count % 10);
    } else {
        buf[len++] = '0' + chapter_count;
    }

    const char* chapters = str_chapters;
    while (*chapters && len < 16380) {
        buf[len++] = *chapters++;
    }

    dom_set_text_offset(pf, progress_id, 0, len);
    dom_drop_proof(pf);
}

/* Show error message */
void show_import_error(void) {
    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();
    int len = 0;

    /* "Error: " prefix */
    const char* prefix = str_error_prefix;
    while (*prefix && len < 16380) {
        buf[len++] = *prefix++;
    }

    /* Get error message */
    int error_len = epub_get_error(0);
    for (int i = 0; i < error_len && len < 16380; i++) {
        buf[len++] = str_buf[i];
    }

    /* Update progress display */
    void* pf = dom_root_proof();
    dom_set_text_offset(pf, progress_id, 0, len);
    dom_drop_proof(pf);
}
%}

(* Initialize the application UI *)
implement init() = let
    val () = dom_init()
    val () = epub_init()

    (* Get root proof *)
    val pf_root = dom_root_proof()

    (* Clear loading text *)
    val _len = copy_text_to_fetch(get_str_quire(), 5)
    val pf_root = dom_set_text_offset(pf_root, 1, 0, 0)

    (* Create container div *)
    val cid = dom_next_id()
    val () = set_container_id(cid)
    val pf_container = dom_create_element(pf_root, 1, cid, get_str_div(), 3)
    val pf_container = dom_set_attr(pf_container, cid,
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
    val pf_file = dom_set_attr(pf_file, fid,
                                get_str_type(), 4,
                                get_str_file(), 4)
    val pf_file = dom_set_attr(pf_file, fid,
                                get_str_accept(), 6,
                                get_str_epub_accept(), 26)
    val pf_file = dom_set_attr(pf_file, fid,
                                get_str_class(), 5,
                                get_str_hidden(), 6)
    val pf_file = dom_set_attr(pf_file, fid,
                                get_str_id_attr(), 2,
                                get_str_file_input(), 10)
    val () = dom_drop_proof(pf_file)

    (* Create import button (label for file input) *)
    val bid = dom_next_id()
    val () = set_import_btn_id(bid)
    val pf_btn = dom_create_element(pf_container, cid, bid, get_str_label(), 5)
    val pf_btn = dom_set_attr(pf_btn, bid,
                               get_str_class(), 5,
                               get_str_import_btn(), 10)
    val pf_btn = dom_set_attr(pf_btn, bid,
                               get_str_for(), 3,
                               get_str_file_input(), 10)
    val _len = copy_text_to_fetch(get_str_import_text(), 11)
    val pf_btn = dom_set_text_offset(pf_btn, bid, 0, 11)
    val () = dom_drop_proof(pf_btn)

    (* Create progress display *)
    val pid = dom_next_id()
    val () = set_progress_id(pid)
    val pf_prog = dom_create_element(pf_container, cid, pid, get_str_p(), 1)
    val pf_prog = dom_set_attr(pf_prog, pid,
                                get_str_class(), 5,
                                get_str_progress_div(), 12)
    val () = dom_drop_proof(pf_prog)

    (* Create title display area *)
    val did = dom_next_id()
    val () = set_title_id(did)
    val pf_tdiv = dom_create_element(pf_container, cid, did, get_str_p(), 1)
    val pf_tdiv = dom_set_attr(pf_tdiv, did,
                                get_str_class(), 5,
                                get_str_title_div(), 9)
    val () = dom_drop_proof(pf_tdiv)

    (* Clean up proofs *)
    val () = dom_drop_proof(pf_container)
    val () = dom_drop_proof(pf_root)
  in
    ()
  end

(* C implementations for callbacks - extern declarations must come before use *)
extern fun process_event_impl(): void = "mac#"
extern fun on_file_open_impl(handle: int, size: int): void = "mac#"
extern fun on_decompress_impl(handle: int, size: int): void = "mac#"
extern fun on_kv_complete_impl(success: int): void = "mac#"
extern fun on_kv_open_impl(success: int): void = "mac#"

(* Handle events - implemented in C to avoid prelude dependency *)
implement process_event() = process_event_impl()

(* Callback handlers - implemented in C to avoid prelude dependency *)
implement on_fetch_complete(status, len) = ()
implement on_timer_complete(callback_id) = ()
implement on_file_open_complete(handle, size) = on_file_open_impl(handle, size)
implement on_decompress_complete(handle, size) = on_decompress_impl(handle, size)
implement on_kv_complete(success) = on_kv_complete_impl(success)
implement on_kv_get_complete(len) = ()
implement on_kv_get_blob_complete(handle, size) = ()
implement on_clipboard_copy_complete(success) = ()
implement on_kv_open_complete(success) = on_kv_open_impl(success)

%{
void process_event_impl(void) {
    int event_type = get_event_type();
    int node_id = get_event_node_id();

    /* Event type 2 = input (file selected) */
    if (event_type == 2) {
        if (node_id == file_input_id) {
            if (!import_in_progress) {
                import_in_progress = 1;
                epub_start_import(node_id);
            }
        }
    }
}

/* Handle state transitions after async operations */
static void handle_state_after_op(void) {
    int state = epub_get_state();
    if (state == 99) {  /* Error */
        show_import_error();
        import_in_progress = 0;
    } else if (state == 6 || state == 7) {  /* Still processing */
        update_progress_display();
    } else if (state == 8) {  /* Done */
        show_import_complete();
        import_in_progress = 0;
    }
}

void on_file_open_impl(int handle, int size) {
    epub_on_file_open(handle, size);
    int state = epub_get_state();
    if (state == 99) {
        show_import_error();
        import_in_progress = 0;
    }
}

void on_decompress_impl(int handle, int size) {
    epub_on_decompress(handle, size);
    handle_state_after_op();
}

void on_kv_complete_impl(int success) {
    epub_on_db_put(success);
    handle_state_after_op();
}

void on_kv_open_impl(int success) {
    epub_on_db_open(success);
    int state = epub_get_state();
    if (state == 99) {
        show_import_error();
        import_in_progress = 0;
    }
}
%}
