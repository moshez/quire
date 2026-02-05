(* reader.dats - Three-chapter sliding window implementation
 *
 * M12: Manages prev/curr/next chapter slots for seamless reading.
 * Each slot tracks: chapter index, container node ID, page count, status.
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

/* External functions from epub module */
extern int epub_get_chapter_count(void);
extern int epub_get_chapter_key(int chapter_index, int buf_offset);

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
}

/* Enter reader mode - creates viewport and three chapter containers */
void reader_enter(int root_id, int container_hide_id) {
    unsigned char* buf = get_fetch_buffer_ptr();
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
        reader_current_page = 0;
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
        reader_current_page = 0;
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

/* Update page display */
void reader_update_page_display(void) {
    if (reader_page_indicator_id == 0) return;

    unsigned char* buf = get_fetch_buffer_ptr();
    int len = 0;

    chapter_slot_t* curr_slot = &slots[SLOT_CURR];
    int chapter = curr_slot->chapter_index + 1;  /* 1-indexed display */
    int page = reader_current_page + 1;  /* 1-indexed display */
    int total = curr_slot->page_count > 0 ? curr_slot->page_count : 1;

    /* "Ch N: P / T" format */
    const char* ch = str_ch_prefix;
    while (*ch && len < 16380) buf[len++] = *ch++;

    /* Chapter number */
    if (chapter >= 100) {
        buf[len++] = '0' + (chapter / 100);
        buf[len++] = '0' + ((chapter / 10) % 10);
        buf[len++] = '0' + (chapter % 10);
    } else if (chapter >= 10) {
        buf[len++] = '0' + (chapter / 10);
        buf[len++] = '0' + (chapter % 10);
    } else {
        buf[len++] = '0' + chapter;
    }

    const char* col = str_colon_space;
    while (*col && len < 16380) buf[len++] = *col++;

    /* Page number */
    if (page >= 100) {
        buf[len++] = '0' + (page / 100);
        buf[len++] = '0' + ((page / 10) % 10);
        buf[len++] = '0' + (page % 10);
    } else if (page >= 10) {
        buf[len++] = '0' + (page / 10);
        buf[len++] = '0' + (page % 10);
    } else {
        buf[len++] = '0' + page;
    }

    const char* of = str_page_of;
    while (*of && len < 16380) buf[len++] = *of++;

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

    void* pf = dom_root_proof();
    dom_set_text_offset(pf, reader_page_indicator_id, 0, len);
    dom_drop_proof(pf);
}

/* Check if any chapter is loading */
int reader_is_loading(void) {
    return loading_slot >= 0 ? 1 : 0;
}
%}

(* All implementations are in the C block above via "mac#" linkage *)
