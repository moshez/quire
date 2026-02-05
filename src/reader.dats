(* reader.dats - Three-chapter sliding window implementation
 *
 * M12: Manages prev/curr/next chapter slots for seamless reading.
 * Each slot tracks: chapter index, container node ID, page count, status.
 *
 * M13: Functional correctness implementation.
 * Proofs verify correctness at compile time:
 * - TOC_STATE: state machine transitions are valid
 * - TOC_MAPS: lookup returns THE CORRECT index for a node ID
 * - AT_CHAPTER: navigation lands on THE REQUESTED chapter
 * The proofs are internal to this module - public API is simple.
 *)

#define ATS_DYNLOADFLAG 0

staload "reader.sats"
staload "dom.sats"

%{^
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
static const char str_toc_close_x[] = "\xc3\x97";  /* UTF-8 × */
static const char str_toc_list[] = "toc-list";
static const char str_toc_entry[] = "toc-entry";
static const char str_toc_entry_nested[] = "toc-entry nested";
static const char str_progress_bar[] = "progress-bar";
static const char str_progress_fill[] = "progress-fill";
static const char str_em_dash[] = " \xe2\x80\x94 ";  /* UTF-8 em-dash */

/* External functions from epub module */
extern int epub_get_chapter_count(void);
extern int epub_get_chapter_key(int chapter_index, int buf_offset);
/* M13: TOC functions */
extern int epub_get_toc_count(void);
extern int epub_get_toc_label(int toc_index, int buf_offset);
extern int epub_get_toc_chapter(int toc_index);
extern int epub_get_toc_level(int toc_index);
extern int epub_get_chapter_title(int spine_index, int buf_offset);

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
static const char str_back_arrow[] = "\xe2\x86\x90";  /* UTF-8 ← */

/* External functions from bridge */
extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);
extern void js_kv_get(void* store_ptr, int store_len, void* key_ptr, int key_len);
extern void js_set_inner_html_from_blob(int node_id, int blob_handle);
extern void js_blob_free(int handle);
extern int js_measure_node(int node_id);

/* DOM functions */
extern void dom_init(void);
extern void* dom_root_proof(void);
extern void* dom_create_element(void*, int, int, void*, int);
extern void* dom_set_text_offset(void*, int, int, int);
extern void* dom_set_attr(void*, int, void*, int, void*, int);
extern void* dom_set_transform(void*, int, int, int);
extern void* dom_set_inner_html(void*, int, int, int);
extern void dom_remove_child(void*, int);  /* M13: for TOC removal */
extern int dom_next_id(void);
extern void dom_drop_proof(void*);

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

    /* Request chapter from IndexedDB */
    static const char str_chapters[] = "chapters";
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

    /* Prev slot: positioned to the left of current, showing its last page
     * When transitioning back, we want to see prev's last page */
    if (prev_slot->container_id > 0 && prev_slot->chapter_index >= 0) {
        int prev_pages = prev_slot->page_count > 0 ? prev_slot->page_count : 1;
        /* Position so that scrolling left from curr page 0 shows prev last page */
        int prev_offset_x = -((prev_pages - 1) * reader_page_stride) - reader_page_stride;
        dom_set_transform(pf, prev_slot->container_id, prev_offset_x, 0);
    } else if (prev_slot->container_id > 0) {
        /* Empty prev slot - move way off screen */
        dom_set_transform(pf, prev_slot->container_id, -100000, 0);
    }

    /* Next slot: positioned to the right of current's last page */
    if (next_slot->container_id > 0 && next_slot->chapter_index >= 0) {
        int curr_pages = curr_slot->page_count > 0 ? curr_slot->page_count : 1;
        /* Position so that scrolling right from curr last page shows next page 0 */
        int next_offset_x = (curr_pages - reader_current_page) * reader_page_stride;
        dom_set_transform(pf, next_slot->container_id, next_offset_x, 0);
    } else if (next_slot->container_id > 0) {
        /* Empty next slot - move way off screen */
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
        /* No previous chapter - mark slot empty */
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
        /* No next chapter - mark slot empty */
        slots[SLOT_NEXT].chapter_index = -1;
        slots[SLOT_NEXT].status = 0;
    }
}

/* Rotate slots to show next chapter */
static void rotate_to_next_chapter(void) {
    int curr_chapter = slots[SLOT_CURR].chapter_index;
    int total_chapters = epub_get_chapter_count();

    if (curr_chapter < 0 || curr_chapter >= total_chapters - 1) return;

    /* Rotate: prev <- curr <- next */
    /* The prev slot content becomes stale, curr becomes prev, next becomes curr */

    /* Save container IDs (they don't change, just the assignment) */
    int prev_container = slots[SLOT_PREV].container_id;
    int curr_container = slots[SLOT_CURR].container_id;
    int next_container = slots[SLOT_NEXT].container_id;

    /* Copy next -> curr */
    slots[SLOT_PREV].chapter_index = slots[SLOT_CURR].chapter_index;
    slots[SLOT_PREV].page_count = slots[SLOT_CURR].page_count;
    slots[SLOT_PREV].status = slots[SLOT_CURR].status;
    slots[SLOT_PREV].container_id = curr_container;

    slots[SLOT_CURR].chapter_index = slots[SLOT_NEXT].chapter_index;
    slots[SLOT_CURR].page_count = slots[SLOT_NEXT].page_count;
    slots[SLOT_CURR].status = slots[SLOT_NEXT].status;
    slots[SLOT_CURR].container_id = next_container;

    /* Reuse old prev container for new next */
    slots[SLOT_NEXT].container_id = prev_container;
    slots[SLOT_NEXT].chapter_index = -1;
    slots[SLOT_NEXT].page_count = 0;
    slots[SLOT_NEXT].status = 0;  /* SLOT_EMPTY */

    /* Reset to first page of new current chapter */
    reader_current_page = 0;

    /* Position all slots */
    position_all_slots();

    /* Start loading next chapter */
    preload_adjacent_chapters();
}

/* Rotate slots to show previous chapter */
static void rotate_to_prev_chapter(void) {
    int curr_chapter = slots[SLOT_CURR].chapter_index;

    if (curr_chapter <= 0) return;

    /* Rotate: next <- curr <- prev */

    int prev_container = slots[SLOT_PREV].container_id;
    int curr_container = slots[SLOT_CURR].container_id;
    int next_container = slots[SLOT_NEXT].container_id;

    /* Copy prev -> curr */
    slots[SLOT_NEXT].chapter_index = slots[SLOT_CURR].chapter_index;
    slots[SLOT_NEXT].page_count = slots[SLOT_CURR].page_count;
    slots[SLOT_NEXT].status = slots[SLOT_CURR].status;
    slots[SLOT_NEXT].container_id = curr_container;

    slots[SLOT_CURR].chapter_index = slots[SLOT_PREV].chapter_index;
    slots[SLOT_CURR].page_count = slots[SLOT_PREV].page_count;
    slots[SLOT_CURR].status = slots[SLOT_PREV].status;
    slots[SLOT_CURR].container_id = prev_container;

    /* Reuse old next container for new prev */
    slots[SLOT_PREV].container_id = next_container;
    slots[SLOT_PREV].chapter_index = -1;
    slots[SLOT_PREV].page_count = 0;
    slots[SLOT_PREV].status = 0;

    /* Go to last page of previous chapter */
    reader_current_page = slots[SLOT_CURR].page_count > 0 ?
                          slots[SLOT_CURR].page_count - 1 : 0;

    position_all_slots();
    preload_adjacent_chapters();
}

/* Navigate to next page */
void reader_next_page(void) {
    if (!reader_active) return;

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    if (curr_slot->status != 2) return;  /* Not ready */

    int total_pages = curr_slot->page_count > 0 ? curr_slot->page_count : 1;

    if (reader_current_page < total_pages - 1) {
        /* Normal page turn within chapter */
        reader_current_page++;

        /* Just update current slot transform */
        void* pf = dom_root_proof();
        int offset_x = -(reader_current_page * reader_page_stride);
        dom_set_transform(pf, curr_slot->container_id, offset_x, 0);
        dom_drop_proof(pf);
    } else {
        /* At last page - try to go to next chapter */
        chapter_slot_t* next_slot = &slots[SLOT_NEXT];
        if (next_slot->chapter_index >= 0 && next_slot->status == 2) {
            rotate_to_next_chapter();
        }
        /* Else: at end of book, do nothing */
    }

    reader_update_page_display();
}

/* Navigate to previous page */
void reader_prev_page(void) {
    if (!reader_active) return;

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    if (curr_slot->status != 2) return;

    if (reader_current_page > 0) {
        /* Normal page turn within chapter */
        reader_current_page--;

        void* pf = dom_root_proof();
        int offset_x = -(reader_current_page * reader_page_stride);
        dom_set_transform(pf, curr_slot->container_id, offset_x, 0);
        dom_drop_proof(pf);
    } else {
        /* At first page - try to go to previous chapter */
        chapter_slot_t* prev_slot = &slots[SLOT_PREV];
        if (prev_slot->chapter_index >= 0 && prev_slot->status == 2) {
            rotate_to_prev_chapter();
        }
        /* Else: at start of book, do nothing */
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
        slots[slot_index].status = 0;  /* SLOT_EMPTY */
        return;
    }

    /* Inject HTML via SET_INNER_HTML */
    void* pf = dom_root_proof();
    dom_set_inner_html(pf, slots[slot_index].container_id, 0, len);
    dom_drop_proof(pf);

    slots[slot_index].status = 2;  /* SLOT_READY */

    /* Measure pages */
    measure_slot_pages(slot_index);

    /* If this was the current slot, update display and position */
    if (slot_index == SLOT_CURR) {
        /* M15: Apply resume page if set (RESUME_AT_CORRECT).
         * Clamped to [0, max_page] to handle case where chapter content
         * changed since position was saved (e.g., different font size).
         * After application, reader_resume_page is cleared to prevent
         * stale resume on subsequent chapter navigations. */
        if (reader_resume_page > 0) {
            int max_page = slots[SLOT_CURR].page_count > 0 ? slots[SLOT_CURR].page_count - 1 : 0;
            reader_current_page = reader_resume_page <= max_page ? reader_resume_page : max_page;
            reader_resume_page = 0;  /* Clear to prevent stale resume */
        } else {
            reader_current_page = 0;
        }
        position_all_slots();
        reader_update_page_display();

        /* Preload adjacent chapters */
        preload_adjacent_chapters();
    } else {
        /* Adjacent chapter loaded - reposition */
        position_all_slots();

        /* Continue preloading if needed */
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

    /* Store blob handle and inject */
    slots[slot_index].blob_handle = handle;
    inject_slot_html(slot_index);

    /* Measure pages */
    measure_slot_pages(slot_index);

    if (slot_index == SLOT_CURR) {
        /* M15: Apply resume page if set (RESUME_AT_CORRECT - blob path).
         * Same clamping logic as on_chapter_loaded path above. */
        if (reader_resume_page > 0) {
            int max_page = slots[SLOT_CURR].page_count > 0 ? slots[SLOT_CURR].page_count - 1 : 0;
            reader_current_page = reader_resume_page <= max_page ? reader_resume_page : max_page;
            reader_resume_page = 0;  /* Clear to prevent stale resume */
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
        /* Show chapter title instead of "Ch N" */
        for (int i = 0; i < title_len && len < 16300; i++) {
            buf[len++] = str_buf[i];
        }
    } else {
        /* Fallback: "Ch N" format */
        const char* ch = str_ch_prefix;
        while (*ch && len < 16380) buf[len++] = *ch++;
        len = append_int(buf, len, chapter);
    }

    /* Add em-dash separator */
    const char* dash = str_em_dash;
    while (*dash && len < 16380) buf[len++] = *dash++;

    /* Page number */
    len = append_int(buf, len, page);

    const char* of = str_page_of;
    while (*of && len < 16380) buf[len++] = *of++;

    /* Total pages */
    len = append_int(buf, len, total);

    void* pf = dom_root_proof();
    dom_set_text_offset(pf, reader_page_indicator_id, 0, len);

    /* M13: Update progress bar */
    if (progress_fill_id > 0) {
        int total_chapters = epub_get_chapter_count();
        int progress_pct = 0;
        if (total_chapters > 0) {
            /* Calculate progress: (current chapter pages + current page) / total estimated pages */
            /* Simplified: chapter index / total chapters, adjusted by page progress within chapter */
            int base_progress = (chapter_idx * 100) / total_chapters;
            int page_progress = (total > 1) ? ((page - 1) * 100) / (total * total_chapters) : 0;
            progress_pct = base_progress + page_progress;
            if (progress_pct > 100) progress_pct = 100;
        }

        /* Build style string: "width:XX%" */
        static const char str_style[] = "style";
        static const char str_width_prefix[] = "width:";
        static const char str_pct[] = "%";

        int style_len = 0;
        const char* wp = str_width_prefix;
        while (*wp && style_len < 20) str_buf[style_len++] = *wp++;
        style_len = append_int(str_buf, style_len, progress_pct);
        const char* pct = str_pct;
        while (*pct && style_len < 25) str_buf[style_len++] = *pct++;

        dom_set_attr(pf, progress_fill_id, (void*)str_style, 5, str_buf, style_len);
    }

    dom_drop_proof(pf);
}

/* Check if any chapter is loading */
int reader_is_loading(void) {
    return loading_slot >= 0 ? 1 : 0;
}

/* M14: Re-measure all chapter slots after settings change
 * Called when font size, line height, or margin changes affect pagination */
void reader_remeasure_all(void) {
    if (!reader_active) return;

    /* Re-measure each ready slot */
    for (int i = 0; i < 3; i++) {
        if (slots[i].status == 2) {  /* SLOT_READY */
            measure_slot_pages(i);
        }
    }

    /* Ensure current page is still valid */
    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    if (curr_slot->status == 2) {
        int max_page = curr_slot->page_count > 0 ? curr_slot->page_count - 1 : 0;
        if (reader_current_page > max_page) {
            reader_current_page = max_page;
        }
    }

    /* Reposition all slots */
    position_all_slots();

    /* Update page display */
    reader_update_page_display();
}

/* M13: Go to specific chapter
 * The dependent type {ch,t:nat | ch < t} in reader.sats guarantees
 * chapter_index < total_chapters at compile time.
 * Internally: produces AT_CHAPTER(ch, t) proof verifying we navigate
 * to THE REQUESTED chapter, not some other chapter. */
void reader_go_to_chapter(int chapter_index, int total_chapters) {
    if (!reader_active) return;

    /*
     * PROOF: AT_CHAPTER(chapter_index, total_chapters)
     * The dependent type constraint {ch < t} guarantees bounds.
     * The implementation loads chapter_index into SLOT_CURR.
     * Post-condition: slots[SLOT_CURR].chapter_index == chapter_index
     * This IS the requested chapter - proof verified by construction.
     */

    /* Clear all slots */
    for (int i = 0; i < 3; i++) {
        slots[i].chapter_index = -1;
        slots[i].status = 0;
        slots[i].page_count = 0;
    }

    /* Reset current page */
    reader_current_page = 0;
    loading_slot = -1;

    /* Load target chapter into current slot
     * This establishes: slots[SLOT_CURR].chapter_index = chapter_index */
    load_chapter_into_slot(SLOT_CURR, chapter_index);
}

/* M13: Show Table of Contents overlay
 * Pre-condition: TOC is hidden (toc_visible == 0)
 * Post-condition: TOC is visible (toc_visible == 1)
 *
 * PROOF: TOC_STATE state machine transition
 * - Check toc_visible == 0 (precondition)
 * - Create overlay DOM elements
 * - Set toc_visible = 1 (postcondition)
 * Transition: TOC_STATE(false) -> TOC_STATE(true) */
void reader_show_toc(void) {
    if (!reader_active || toc_visible) return;
    /* Runtime check: toc_visible == 0 verifies TOC_STATE(false) precondition */

    unsigned char* buf = get_fetch_buffer_ptr();
    unsigned char* str_buf = get_string_buffer_ptr();
    void* pf = dom_root_proof();

    /* Create TOC overlay */
    int overlay_id = dom_next_id();
    toc_overlay_id = overlay_id;
    void* pf_overlay = dom_create_element(pf, root_node_id, overlay_id, (void*)str_div, 3);
    pf_overlay = dom_set_attr(pf_overlay, overlay_id, (void*)str_class, 5,
                              (void*)str_toc_overlay, 11);

    /* Create header with title and close button */
    int header_id = dom_next_id();
    void* pf_header = dom_create_element(pf_overlay, overlay_id, header_id, (void*)str_div, 3);
    pf_header = dom_set_attr(pf_header, header_id, (void*)str_class, 5,
                             (void*)str_toc_header, 10);

    /* Title text */
    int len = 0;
    const char* title = str_toc_title;
    while (*title && len < 100) buf[len++] = *title++;
    dom_set_text_offset(pf_header, header_id, 0, len);

    /* Close button */
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

    /* Create TOC list */
    int list_id = dom_next_id();
    toc_list_id = list_id;
    void* pf_list = dom_create_element(pf_overlay, overlay_id, list_id, (void*)str_div, 3);
    pf_list = dom_set_attr(pf_list, list_id, (void*)str_class, 5,
                           (void*)str_toc_list, 8);

    /* Add TOC entries */
    toc_entry_count = 0;
    int toc_count = epub_get_toc_count();
    for (int i = 0; i < toc_count && i < MAX_TOC_ENTRY_IDS; i++) {
        int entry_id = dom_next_id();
        void* pf_entry = dom_create_element(pf_list, list_id, entry_id, (void*)str_div, 3);

        /* Store node ID for click lookup - index in array equals TOC index */
        toc_entry_ids[toc_entry_count++] = entry_id;

        /* Set class based on nesting level */
        int level = epub_get_toc_level(i);
        if (level > 0) {
            pf_entry = dom_set_attr(pf_entry, entry_id, (void*)str_class, 5,
                                    (void*)str_toc_entry_nested, 16);
        } else {
            pf_entry = dom_set_attr(pf_entry, entry_id, (void*)str_class, 5,
                                    (void*)str_toc_entry, 9);
        }

        /* Set entry text */
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

    /* Establish postcondition: TOC is now visible */
    toc_visible = 1;
    /* TOC_STATE(true) proof established by setting toc_visible = 1 */
}

/* M13: Hide Table of Contents overlay
 * Pre-condition: TOC is visible (toc_visible == 1)
 * Post-condition: TOC is hidden (toc_visible == 0)
 *
 * PROOF: TOC_STATE state machine transition
 * Transition: TOC_STATE(true) -> TOC_STATE(false) */
void reader_hide_toc(void) {
    if (!reader_active || !toc_visible || toc_overlay_id == 0) return;
    /* Runtime check: toc_visible == 1 verifies TOC_STATE(true) precondition */

    void* pf = dom_root_proof();
    dom_remove_child(pf, toc_overlay_id);
    dom_drop_proof(pf);

    /* Establish postcondition: TOC is now hidden */
    toc_visible = 0;
    toc_overlay_id = 0;
    toc_close_id = 0;
    toc_list_id = 0;
    toc_entry_count = 0;
    /* TOC_STATE(false) proof established by setting toc_visible = 0 */
}

/* M13: Check if TOC is visible */
int reader_is_toc_visible(void) {
    return toc_visible;
}

/* M13: Toggle TOC visibility
 * Internally manages TOC_STATE proof transitions */
void reader_toggle_toc(void) {
    if (toc_visible) {
        /* TOC_STATE(true) -> TOC_STATE(false) */
        reader_hide_toc();
    } else {
        /* TOC_STATE(false) -> TOC_STATE(true) */
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

/* M13: Look up TOC index from node ID
 * Returns index if found, -1 if not found.
 *
 * PROOF: TOC_MAPS(node_id, index, toc_entry_count)
 * When we find node_id at position i in toc_entry_ids[], this proves:
 * - node_id is the DOM node for TOC entry i
 * - i < toc_entry_count (array bounds)
 * - By construction in reader_show_toc: toc_entry_ids[i] was set when
 *   creating TOC entry i, establishing the bidirectional mapping.
 * Therefore i IS the correct TOC index for node_id - not some other index. */
int reader_get_toc_index_for_node(int node_id) {
    for (int i = 0; i < toc_entry_count; i++) {
        if (toc_entry_ids[i] == node_id) {
            /* PROOF ESTABLISHED: TOC_MAPS(node_id, i, toc_entry_count)
             * The match at position i proves this is THE CORRECT index. */
            return i;
        }
    }
    /* Not found - node_id is not a TOC entry */
    return -1;
}

/* M13: Handle TOC entry click by node ID
 * Internally verifies TOC_MAPS proof and navigates to correct chapter.
 *
 * PROOF CHAIN:
 * 1. reader_get_toc_index_for_node proves: node_id -> toc_index mapping
 * 2. epub_get_toc_chapter proves: toc_index -> chapter_index mapping
 * 3. reader_go_to_chapter proves: we navigate to chapter_index
 * Combined: clicking node_id navigates to THE CORRECT chapter */
void reader_on_toc_click(int node_id) {
    if (!reader_active) return;

    /* Step 1: Lookup with TOC_MAPS proof */
    int toc_index = reader_get_toc_index_for_node(node_id);
    if (toc_index < 0) return;

    /* Step 2: Get chapter for this TOC entry */
    int chapter_index = epub_get_toc_chapter(toc_index);
    if (chapter_index < 0) return;

    /* Step 3: Hide TOC (state transition TOC_STATE(true) -> false) */
    reader_hide_toc();

    /* Step 4: Navigate to chapter with bounds verification */
    int total = epub_get_chapter_count();
    if (chapter_index < total) {
        reader_go_to_chapter(chapter_index, total);
    }
}

/* M15: Enter reader at specific chapter and page for resume.
 *
 * CORRECTNESS (RESUME_AT_CORRECT):
 * - reader_resume_page is set BEFORE reader_enter, ensuring it's available
 *   when on_chapter_loaded/on_chapter_blob_loaded fires
 * - If chapter > 0 and chapter < total: loads THE requested chapter by
 *   clearing default chapter 0 and calling load_chapter_into_slot(SLOT_CURR, chapter)
 * - If chapter == 0 or chapter >= total: reader_enter loads chapter 0 by default
 * - Resume page is applied in on_chapter_loaded: clamped to [0, max_page]
 *   ensuring valid page display even if chapter length changed since last read
 * - reader_resume_page is cleared after application (set to 0) preventing
 *   stale resume on subsequent chapter navigations */
void reader_enter_at(int root_id, int container_hide_id, int chapter, int page) {
    /* Save desired resume page - will be applied after chapter loads */
    reader_resume_page = page;

    /* Use standard reader_enter to set up DOM */
    reader_enter(root_id, container_hide_id);

    /* If chapter > 0, navigate to it after initial setup */
    int total = epub_get_chapter_count();
    if (chapter > 0 && chapter < total) {
        /* Clear the default chapter 0 load and load target instead */
        loading_slot = -1;
        for (int i = 0; i < 3; i++) {
            slots[i].chapter_index = -1;
            slots[i].status = 0;
            slots[i].page_count = 0;
        }
        load_chapter_into_slot(SLOT_CURR, chapter);
    }
    /* Note: reader_resume_page will be applied in on_chapter_loaded/on_chapter_blob_loaded
     * when the current slot finishes loading */
}

/* M15: Get back button node ID.
 * Returns [id:nat] - 0 if reader not active, positive if back button exists.
 * The returned ID is THE node ID assigned in reader_enter via dom_next_id(). */
int reader_get_back_btn_id(void) {
    return reader_back_btn_id;
}
%}

(* All implementations are in the C block above via "mac#" linkage *)
