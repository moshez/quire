(* reader.dats - Three-chapter sliding window implementation
 *
 * M12: Implements seamless reading across chapter boundaries.
 * Maintains three chapter containers that rotate as the user navigates.
 *)

#define ATS_DYNLOADFLAG 0

staload "reader.sats"
staload "dom.sats"
staload "epub.sats"

%{^
/* Slot and loading state constants (must match reader.sats) */
#define SLOT_PREV 0
#define SLOT_CURR 1
#define SLOT_NEXT 2
#define LOAD_EMPTY    0
#define LOAD_PENDING  1
#define LOAD_READY    2

/* String constants for reader DOM elements */
static const char str_div[] = "div";
static const char str_class[] = "class";
static const char str_reader_viewport[] = "reader-viewport";
static const char str_chapter_container[] = "chapter-container";
static const char str_page_indicator[] = "page-indicator";
static const char str_page_of[] = " / ";

/* External functions */
extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);
extern void* dom_root_proof(void);
extern void* dom_create_element(void*, int, int, void*, int);
extern void* dom_set_attr(void*, int, void*, int, void*, int);
extern void* dom_set_text_offset(void*, int, int, int);
extern void* dom_set_transform(void*, int, int, int);
extern void* dom_set_inner_html(void*, int, int, int);
extern void dom_drop_proof(void*);
extern int dom_next_id(void);
extern int js_measure_node(int);
extern void js_kv_get(void* store_ptr, int store_len, void* key_ptr, int key_len);
extern void js_set_inner_html_from_blob(int node_id, int blob_handle);
extern void js_blob_free(int handle);
extern int epub_get_chapter_key(int chapter_index, int buf_offset);
extern int epub_get_chapter_count(void);

/* Chapter store name */
static const char str_chapters_store[] = "chapters";

/* Sliding window state */
static int reader_active = 0;
static int total_chapters = 0;
static int viewport_width = 0;
static int page_stride = 0;

/* Current position */
static int current_chapter = 0;
static int current_page = 0;

/* DOM node IDs */
static int root_id = 1;
static int viewport_id = 0;
static int page_indicator_id = 0;

/* Slot state: chapter indices (-1 = no chapter assigned) */
static int slot_chapter[3] = {-1, -1, -1};

/* Slot state: loading status */
static int slot_loading[3] = {0, 0, 0};

/* Slot state: page counts (valid when loading == LOAD_READY) */
static int slot_pages[3] = {1, 1, 1};

/* Slot state: DOM container node IDs */
static int slot_node_id[3] = {0, 0, 0};

/* Which slot is currently being loaded (for callback routing) */
static int loading_slot = -1;

/* Blob handle for pending chapter injection */
static int pending_blob_handle = 0;

/* Get slot's chapter container node ID */
int reader_get_slot_node_id_impl(int slot) {
    if (slot < 0 || slot > 2) return 0;
    return slot_node_id[slot];
}

/* Check if reader is active */
int reader_is_active_impl(void) {
    return reader_active;
}

/* Get current chapter index */
int reader_get_chapter_impl(void) {
    return current_chapter;
}

/* Get current page */
int reader_get_page_impl(void) {
    return current_page;
}

/* Get total pages in current chapter */
int reader_get_total_pages_impl(void) {
    return slot_pages[SLOT_CURR];
}

/* Get loading slot for callback routing */
int reader_get_loading_slot_impl(void) {
    return loading_slot;
}

/* Get viewport width for click zones */
int reader_get_viewport_width_impl(void) {
    return viewport_width;
}

/* Measure a slot's container and get page count */
static int measure_slot(int slot) {
    int node_id = slot_node_id[slot];
    if (node_id == 0) return 1;

    if (!js_measure_node(node_id)) return 1;

    /* Read measurements from fetch buffer (float64 values) */
    unsigned char* buf = get_fetch_buffer_ptr();
    double scroll_width_d;
    double width_d;

    /* Read float64 values manually */
    unsigned char sw_bytes[8], w_bytes[8];
    for (int i = 0; i < 8; i++) {
        sw_bytes[i] = buf[32 + i];  /* scrollWidth at offset 32 */
        w_bytes[i] = buf[16 + i];   /* width at offset 16 */
    }

    scroll_width_d = *(double*)sw_bytes;
    width_d = *(double*)w_bytes;

    int scroll_width = (int)scroll_width_d;
    int width = (int)width_d;

    if (width <= 0) width = 1;

    /* Update global viewport measurements if not set */
    if (viewport_width == 0) {
        viewport_width = width;
        page_stride = width;  /* column-gap is 0 */
    }

    /* Compute page count */
    int pages = (scroll_width + width - 1) / width;
    if (pages < 1) pages = 1;

    return pages;
}

/* Apply transform to position a slot at a given page offset */
static void position_slot(int slot, int page_offset) {
    int node_id = slot_node_id[slot];
    if (node_id == 0) return;

    int offset_x = -(page_offset * page_stride);
    void* pf = dom_root_proof();
    dom_set_transform(pf, node_id, offset_x, 0);
    dom_drop_proof(pf);
}

/* Update page indicator text */
void reader_update_display_impl(void) {
    if (page_indicator_id == 0) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    int len = 0;

    /* Calculate total page number across all chapters */
    /* For now, just show current page / total in chapter */
    int display_page = current_page + 1;
    int total = slot_pages[SLOT_CURR];

    /* Format: "page / total (ch X)" */
    if (display_page >= 100) {
        buf[len++] = '0' + (display_page / 100);
        buf[len++] = '0' + ((display_page / 10) % 10);
        buf[len++] = '0' + (display_page % 10);
    } else if (display_page >= 10) {
        buf[len++] = '0' + (display_page / 10);
        buf[len++] = '0' + (display_page % 10);
    } else {
        buf[len++] = '0' + display_page;
    }

    /* " / " */
    buf[len++] = ' ';
    buf[len++] = '/';
    buf[len++] = ' ';

    /* Total pages */
    if (total >= 100) {
        buf[len++] = '0' + (total / 100);
        buf[len++] = '0' + ((total / 10) % 10);
        buf[len++] = '0' + (total % 10);
    } else if (total >= 10) {
        buf[len++] = '0' + (total / 10);
        buf[len++] = '0' + (total % 10);
    } else {
        buf[len++] = '0' + total;
    }

    /* Update text */
    void* pf = dom_root_proof();
    dom_set_text_offset(pf, page_indicator_id, 0, len);
    dom_drop_proof(pf);
}

/* Request a chapter to be loaded into a slot */
void reader_request_chapter_impl(int slot, int chapter_idx) {
    if (slot < 0 || slot > 2) return;
    if (chapter_idx < 0 || chapter_idx >= total_chapters) {
        /* Invalid chapter - mark slot as empty */
        slot_chapter[slot] = -1;
        slot_loading[slot] = LOAD_EMPTY;
        return;
    }

    /* Mark slot as pending load */
    slot_chapter[slot] = chapter_idx;
    slot_loading[slot] = LOAD_PENDING;
    loading_slot = slot;

    /* Get chapter key and request from IndexedDB */
    unsigned char* str_buf = get_string_buffer_ptr();
    int key_len = epub_get_chapter_key(chapter_idx, 0);
    if (key_len == 0) {
        slot_loading[slot] = LOAD_EMPTY;
        loading_slot = -1;
        return;
    }

    js_kv_get((void*)str_chapters_store, 8, str_buf, key_len);
}

/* Handle chapter loaded (small, in fetch buffer) */
void reader_on_chapter_loaded_impl(int slot, int len) {
    if (slot < 0 || slot > 2) return;

    int node_id = slot_node_id[slot];
    if (node_id == 0) {
        slot_loading[slot] = LOAD_EMPTY;
        loading_slot = -1;
        return;
    }

    if (len == 0) {
        /* Empty chapter - still mark as ready */
        slot_loading[slot] = LOAD_READY;
        slot_pages[slot] = 1;
        loading_slot = -1;
        return;
    }

    /* Inject HTML via SET_INNER_HTML */
    void* pf = dom_root_proof();
    dom_set_inner_html(pf, node_id, 0, len);
    dom_drop_proof(pf);

    /* Measure and update state */
    slot_pages[slot] = measure_slot(slot);
    slot_loading[slot] = LOAD_READY;
    loading_slot = -1;

    /* If this was the current slot, update display */
    if (slot == SLOT_CURR) {
        position_slot(SLOT_CURR, current_page);
        reader_update_display_impl();
    }
}

/* Handle chapter loaded (large, as blob) */
void reader_on_chapter_blob_loaded_impl(int slot, int handle, int size) {
    if (slot < 0 || slot > 2) return;

    int node_id = slot_node_id[slot];
    if (node_id == 0 || handle == 0 || size == 0) {
        slot_loading[slot] = LOAD_EMPTY;
        loading_slot = -1;
        if (handle > 0) js_blob_free(handle);
        return;
    }

    /* Inject HTML from blob */
    js_set_inner_html_from_blob(node_id, handle);
    js_blob_free(handle);

    /* Measure and update state */
    slot_pages[slot] = measure_slot(slot);
    slot_loading[slot] = LOAD_READY;
    loading_slot = -1;

    /* If this was the current slot, update display */
    if (slot == SLOT_CURR) {
        position_slot(SLOT_CURR, current_page);
        reader_update_display_impl();
    }
}

/* Rotate slots forward: curr->prev, next->curr, load new next */
static void rotate_forward(void) {
    /* Save old slot states */
    int old_prev_chapter = slot_chapter[SLOT_PREV];
    int old_prev_pages = slot_pages[SLOT_PREV];
    int old_prev_node = slot_node_id[SLOT_PREV];

    /* Rotate chapter assignments */
    slot_chapter[SLOT_PREV] = slot_chapter[SLOT_CURR];
    slot_pages[SLOT_PREV] = slot_pages[SLOT_CURR];
    slot_loading[SLOT_PREV] = slot_loading[SLOT_CURR];

    slot_chapter[SLOT_CURR] = slot_chapter[SLOT_NEXT];
    slot_pages[SLOT_CURR] = slot_pages[SLOT_NEXT];
    slot_loading[SLOT_CURR] = slot_loading[SLOT_NEXT];

    /* Old prev slot becomes new next (to be loaded) */
    slot_chapter[SLOT_NEXT] = -1;
    slot_pages[SLOT_NEXT] = 1;
    slot_loading[SLOT_NEXT] = LOAD_EMPTY;

    /* Rotate DOM node IDs to match */
    slot_node_id[SLOT_PREV] = slot_node_id[SLOT_CURR];
    slot_node_id[SLOT_CURR] = slot_node_id[SLOT_NEXT];
    slot_node_id[SLOT_NEXT] = old_prev_node;

    /* Clear old prev container content (now NEXT) */
    if (slot_node_id[SLOT_NEXT] > 0) {
        void* pf = dom_root_proof();
        unsigned char* buf = get_fetch_buffer_ptr();
        buf[0] = 0;  /* Empty string */
        dom_set_inner_html(pf, slot_node_id[SLOT_NEXT], 0, 0);
        dom_drop_proof(pf);
    }

    /* Update current chapter index */
    current_chapter++;
    current_page = 0;

    /* Position current slot at page 0 */
    position_slot(SLOT_CURR, 0);

    /* Request next chapter if available */
    if (current_chapter + 1 < total_chapters) {
        reader_request_chapter_impl(SLOT_NEXT, current_chapter + 1);
    }

    reader_update_display_impl();
}

/* Rotate slots backward: curr->next, prev->curr, load new prev */
static void rotate_backward(void) {
    /* Save old slot states */
    int old_next_chapter = slot_chapter[SLOT_NEXT];
    int old_next_pages = slot_pages[SLOT_NEXT];
    int old_next_node = slot_node_id[SLOT_NEXT];

    /* Rotate chapter assignments */
    slot_chapter[SLOT_NEXT] = slot_chapter[SLOT_CURR];
    slot_pages[SLOT_NEXT] = slot_pages[SLOT_CURR];
    slot_loading[SLOT_NEXT] = slot_loading[SLOT_CURR];

    slot_chapter[SLOT_CURR] = slot_chapter[SLOT_PREV];
    slot_pages[SLOT_CURR] = slot_pages[SLOT_PREV];
    slot_loading[SLOT_CURR] = slot_loading[SLOT_PREV];

    /* Old next slot becomes new prev (to be loaded) */
    slot_chapter[SLOT_PREV] = -1;
    slot_pages[SLOT_PREV] = 1;
    slot_loading[SLOT_PREV] = LOAD_EMPTY;

    /* Rotate DOM node IDs to match */
    slot_node_id[SLOT_NEXT] = slot_node_id[SLOT_CURR];
    slot_node_id[SLOT_CURR] = slot_node_id[SLOT_PREV];
    slot_node_id[SLOT_PREV] = old_next_node;

    /* Clear old next container content (now PREV) */
    if (slot_node_id[SLOT_PREV] > 0) {
        void* pf = dom_root_proof();
        dom_set_inner_html(pf, slot_node_id[SLOT_PREV], 0, 0);
        dom_drop_proof(pf);
    }

    /* Update current chapter index */
    current_chapter--;
    current_page = slot_pages[SLOT_CURR] - 1;  /* Go to last page of prev chapter */
    if (current_page < 0) current_page = 0;

    /* Position current slot at last page */
    position_slot(SLOT_CURR, current_page);

    /* Request previous chapter if available */
    if (current_chapter > 0) {
        reader_request_chapter_impl(SLOT_PREV, current_chapter - 1);
    }

    reader_update_display_impl();
}

/* Navigate to next page */
void reader_next_page_impl(void) {
    if (!reader_active) return;

    int total = slot_pages[SLOT_CURR];

    if (current_page < total - 1) {
        /* Still pages left in current chapter */
        current_page++;
        position_slot(SLOT_CURR, current_page);
        reader_update_display_impl();
    } else if (current_chapter < total_chapters - 1) {
        /* At last page of chapter - go to next chapter */
        /* Check if next chapter is loaded */
        if (slot_loading[SLOT_NEXT] == LOAD_READY) {
            rotate_forward();
        }
        /* If not ready, do nothing - user must wait */
    }
    /* At last page of last chapter - do nothing */
}

/* Navigate to previous page */
void reader_prev_page_impl(void) {
    if (!reader_active) return;

    if (current_page > 0) {
        /* Still pages before in current chapter */
        current_page--;
        position_slot(SLOT_CURR, current_page);
        reader_update_display_impl();
    } else if (current_chapter > 0) {
        /* At first page of chapter - go to previous chapter */
        /* Check if prev chapter is loaded */
        if (slot_loading[SLOT_PREV] == LOAD_READY) {
            rotate_backward();
        }
        /* If not ready, do nothing - user must wait */
    }
    /* At first page of first chapter - do nothing */
}

/* Navigate to specific page in current chapter */
void reader_go_to_page_impl(int page) {
    if (!reader_active) return;

    int total = slot_pages[SLOT_CURR];
    if (page < 0) page = 0;
    if (page >= total) page = total - 1;

    if (page == current_page) return;

    current_page = page;
    position_slot(SLOT_CURR, current_page);
    reader_update_display_impl();
}

/* Create the three chapter containers */
static void create_containers(void* pf_viewport, int vid) {
    /* Create three chapter containers */
    for (int i = 0; i < 3; i++) {
        int cid = dom_next_id();
        slot_node_id[i] = cid;
        void* pf_container = dom_create_element(pf_viewport, vid, cid, (void*)str_div, 3);
        pf_container = dom_set_attr(pf_container, cid, (void*)str_class, 5,
                                    (void*)str_chapter_container, 17);
        dom_drop_proof(pf_container);
    }
}

/* Enter reader mode */
void reader_enter_impl(int chapters) {
    if (reader_active) return;

    reader_active = 1;
    total_chapters = chapters;
    current_chapter = 0;
    current_page = 0;
    viewport_width = 0;
    page_stride = 0;

    /* Reset slot states */
    for (int i = 0; i < 3; i++) {
        slot_chapter[i] = -1;
        slot_loading[i] = LOAD_EMPTY;
        slot_pages[i] = 1;
    }
    loading_slot = -1;

    unsigned char* buf = get_fetch_buffer_ptr();
    void* pf = dom_root_proof();

    /* Create reader viewport */
    int vid = dom_next_id();
    viewport_id = vid;
    void* pf_viewport = dom_create_element(pf, root_id, vid, (void*)str_div, 3);
    pf_viewport = dom_set_attr(pf_viewport, vid, (void*)str_class, 5,
                               (void*)str_reader_viewport, 15);

    /* Create three chapter containers */
    create_containers(pf_viewport, vid);

    dom_drop_proof(pf_viewport);

    /* Create page indicator */
    int pid = dom_next_id();
    page_indicator_id = pid;
    void* pf_indicator = dom_create_element(pf, root_id, pid, (void*)str_div, 3);
    pf_indicator = dom_set_attr(pf_indicator, pid, (void*)str_class, 5,
                                (void*)str_page_indicator, 14);

    /* Initial display "1 / 1" */
    buf[0] = '1';
    buf[1] = ' ';
    buf[2] = '/';
    buf[3] = ' ';
    buf[4] = '1';
    dom_set_text_offset(pf_indicator, pid, 0, 5);
    dom_drop_proof(pf_indicator);

    dom_drop_proof(pf);

    /* Load initial chapters:
     * SLOT_CURR = chapter 0
     * SLOT_NEXT = chapter 1 (if exists)
     * SLOT_PREV = empty (we're at first chapter)
     */
    reader_request_chapter_impl(SLOT_CURR, 0);

    /* Next chapter will be requested after current finishes loading */
}

/* Exit reader mode */
void reader_exit_impl(void) {
    reader_active = 0;
    /* DOM cleanup would go here if needed */
}

/* Initialize reader module */
void reader_init_impl(void) {
    reader_active = 0;
    total_chapters = 0;
    current_chapter = 0;
    current_page = 0;
    viewport_width = 0;
    page_stride = 0;
    viewport_id = 0;
    page_indicator_id = 0;
    loading_slot = -1;

    for (int i = 0; i < 3; i++) {
        slot_chapter[i] = -1;
        slot_loading[i] = LOAD_EMPTY;
        slot_pages[i] = 1;
        slot_node_id[i] = 0;
    }
}
%}

(* ATS wrapper functions *)
extern fun reader_init_impl(): void = "mac#"
extern fun reader_enter_impl(chapters: int): void = "mac#"
extern fun reader_exit_impl(): void = "mac#"
extern fun reader_is_active_impl(): int = "mac#"
extern fun reader_get_chapter_impl(): int = "mac#"
extern fun reader_get_page_impl(): int = "mac#"
extern fun reader_get_total_pages_impl(): int = "mac#"
extern fun reader_next_page_impl(): void = "mac#"
extern fun reader_prev_page_impl(): void = "mac#"
extern fun reader_go_to_page_impl(page: int): void = "mac#"
extern fun reader_on_chapter_loaded_impl(slot: int, len: int): void = "mac#"
extern fun reader_on_chapter_blob_loaded_impl(slot: int, handle: int, size: int): void = "mac#"
extern fun reader_get_loading_slot_impl(): int = "mac#"
extern fun reader_get_viewport_width_impl(): int = "mac#"
extern fun reader_update_display_impl(): void = "mac#"
extern fun reader_request_chapter_impl(slot: int, chapter_idx: int): void = "mac#"
extern fun reader_get_slot_node_id_impl(slot: int): int = "mac#"

implement reader_init() = reader_init_impl()
implement reader_enter(chapters) = reader_enter_impl(chapters)
implement reader_exit() = reader_exit_impl()
implement reader_is_active() = reader_is_active_impl()
implement reader_get_chapter() = reader_get_chapter_impl()
implement reader_get_page() = reader_get_page_impl()
implement reader_get_total_pages() = reader_get_total_pages_impl()
implement reader_next_page() = reader_next_page_impl()
implement reader_prev_page() = reader_prev_page_impl()
implement reader_go_to_page(page) = reader_go_to_page_impl(page)
implement reader_on_chapter_loaded(slot, len) = reader_on_chapter_loaded_impl(slot, len)
implement reader_on_chapter_blob_loaded(slot, handle, size) = reader_on_chapter_blob_loaded_impl(slot, handle, size)
implement reader_get_loading_slot() = reader_get_loading_slot_impl()
implement reader_get_viewport_width() = reader_get_viewport_width_impl()
implement reader_update_display() = reader_update_display_impl()
implement reader_request_chapter(slot, chapter_idx) = reader_request_chapter_impl(slot, chapter_idx)
implement reader_get_slot_node_id(slot) = reader_get_slot_node_id_impl(slot)
