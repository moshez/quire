(* dom.dats - Implementation of type-level DOM operations
 *
 * Freestanding ATS2 version: all implementations in embedded C.
 * The abstract node_proof type erases to ptr at runtime.
 * Type checking happens at compile time, runtime is just diff emission.
 *)

#define ATS_DYNLOADFLAG 0

staload "dom.sats"

%{^
/* C implementation of DOM diff emission
 *
 * Diff buffer layout (16-byte aligned entries, quire-design.md §2.2):
 *   Byte 0: entry count (uint8)
 *   Bytes 1-3: padding
 *   Byte 4+: entries, each 16 bytes:
 *     +0: op (uint32)
 *     +4: nodeId (uint32)
 *     +8: value1 (uint32)
 *     +12: value2 (uint32)
 */

extern unsigned char* get_diff_buffer_ptr(void);
extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);

/* Flush pending diffs to bridge before overwriting shared buffers.
 * Operations that write to the string buffer (CREATE_ELEMENT, SET_ATTR)
 * must flush first so previously queued diffs read correct string data. */
extern void js_apply_diffs(void);

/* Next available node ID (WASM owns the ID space) */
static unsigned int dom_next_node_id = 2;  /* 1 is reserved for root */

/* Write a 32-bit unsigned integer in little-endian format */
static void dom_write_u32(unsigned char* buf, unsigned int v) {
    buf[0] = v & 0xFF;
    buf[1] = (v >> 8) & 0xFF;
    buf[2] = (v >> 16) & 0xFF;
    buf[3] = (v >> 24) & 0xFF;
}

/* Add a diff entry to the buffer */
static void dom_emit_diff(unsigned int op, unsigned int node_id,
                          unsigned int value1, unsigned int value2) {
    unsigned char* diff = get_diff_buffer_ptr();
    unsigned int count = diff[0];

    /* Max 255 entries per frame (fits in byte 0) */
    if (count >= 255) return;

    /* Entry offset: header (4 bytes) + count * 16 bytes per entry */
    unsigned int offset = 4 + count * 16;

    dom_write_u32(diff + offset, op);
    dom_write_u32(diff + offset + 4, node_id);
    dom_write_u32(diff + offset + 8, value1);
    dom_write_u32(diff + offset + 12, value2);

    diff[0] = count + 1;
}

/* Copy string to string buffer, return length written */
static unsigned int dom_copy_to_string_buf(const char* src, unsigned int len,
                                           unsigned int offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (unsigned int i = 0; i < len && offset + i < 4096; i++) {
        buf[offset + i] = src[i];
    }
    return len;
}

/* Copy string to fetch buffer, return length written */
static unsigned int dom_copy_to_fetch_buf(const char* src, unsigned int len,
                                          unsigned int offset) {
    unsigned char* buf = get_fetch_buffer_ptr();
    for (unsigned int i = 0; i < len && offset + i < 16384; i++) {
        buf[offset + i] = src[i];
    }
    return len;
}

/* DOM operations - proof arguments (void*) are ignored at runtime */

void dom_init(void) {
    unsigned char* diff = get_diff_buffer_ptr();
    diff[0] = 0;  /* Clear diff count */
}

void* dom_create_element(void* parent_pf, int parent, int child,
                         void* tag_ptr, int tag_len) {
    (void)parent_pf;  /* Proof ignored at runtime */

    /* Flush pending diffs before overwriting shared buffers */
    js_apply_diffs();

    /* Copy tag name to string buffer at offset 0 */
    dom_copy_to_string_buf((const char*)tag_ptr, tag_len, 0);

    /* CREATE_ELEMENT: nodeId=child, value1=parent, value2=tag_len */
    dom_emit_diff(4, child, parent, tag_len);

    /* Flush immediately: string buffer data (tag name) must be consumed
     * before caller can overwrite shared buffers. */
    js_apply_diffs();

    return (void*)0;  /* Return dummy proof (erased at runtime) */
}

void dom_remove_child(void* pf, int id) {
    (void)pf;  /* Proof consumed - ignored at runtime */

    js_apply_diffs();

    /* REMOVE_CHILD: nodeId=id, value1/value2 unused */
    dom_emit_diff(5, id, 0, 0);
}

void* dom_set_text(void* pf, int id, void* text_ptr, int text_len) {
    (void)pf;

    js_apply_diffs();

    /* Copy text to fetch buffer at offset 0 */
    dom_copy_to_fetch_buf((const char*)text_ptr, text_len, 0);

    /* SET_TEXT: nodeId=id, value1=offset(0), value2=len */
    dom_emit_diff(1, id, 0, text_len);

    return (void*)0;  /* Return proof (borrowed - same as input) */
}

void* dom_set_text_offset(void* pf, int id, int fetch_offset, int fetch_len) {
    (void)pf;

    js_apply_diffs();

    /* SET_TEXT: nodeId=id, value1=offset, value2=len */
    dom_emit_diff(1, id, fetch_offset, fetch_len);

    return (void*)0;
}

void* dom_set_attr(void* pf, int id, void* name_ptr, int name_len,
                   void* val_ptr, int val_len) {
    (void)pf;

    js_apply_diffs();

    /* Copy name to string buffer at offset 0 */
    dom_copy_to_string_buf((const char*)name_ptr, name_len, 0);

    /* Copy value to string buffer at offset name_len */
    if (val_len > 0) {
        dom_copy_to_string_buf((const char*)val_ptr, val_len, name_len);
    }

    /* SET_ATTR: nodeId=id, value1=name_len, value2=val_len */
    dom_emit_diff(2, id, name_len, val_len);

    /* Flush immediately: string buffer data (attr name/value) must be
     * consumed before caller can overwrite shared buffers. */
    js_apply_diffs();

    return (void*)0;
}

void* dom_set_transform(void* pf, int id, int x, int y) {
    (void)pf;

    js_apply_diffs();

    /* SET_TRANSFORM: nodeId=id, value1=x, value2=y
     * x and y are int32, interpreted as signed by bridge */
    dom_emit_diff(3, id, (unsigned int)x, (unsigned int)y);

    return (void*)0;
}

void* dom_set_inner_html(void* pf, int id, int fetch_offset, int fetch_len) {
    (void)pf;

    js_apply_diffs();

    /* SET_INNER_HTML: nodeId=id, value1=offset, value2=len */
    dom_emit_diff(6, id, fetch_offset, fetch_len);

    return (void*)0;
}

int dom_next_id(void) {
    return dom_next_node_id++;
}

void* dom_root_proof(void) {
    /* Return dummy proof for root node (id=1, parent=0) */
    return (void*)0;
}

void dom_drop_proof(void* pf) {
    (void)pf;  /* Proof discarded - no runtime effect */
}
%}
