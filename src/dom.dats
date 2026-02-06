(* dom.dats - Implementation of type-level DOM operations
 *
 * Low-level buffer helpers (byte writes, diff emission) remain in C.
 * All public DOM operations are implemented in ATS, giving compile-time
 * type checking over proof arguments and op codes.
 *)

#define ATS_DYNLOADFLAG 0

staload "dom.sats"

%{^
/* Low-level C helpers for buffer operations.
 * These perform byte-level manipulation that ATS freestanding
 * mode cannot express without a prelude. */

extern unsigned char* get_diff_buffer_ptr(void);
extern unsigned char* get_fetch_buffer_ptr(void);
extern unsigned char* get_string_buffer_ptr(void);
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
static void dom_emit_diff_c(unsigned int op, unsigned int node_id,
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
static unsigned int dom_copy_to_strbuf_c(const char* src, unsigned int len,
                                         unsigned int offset) {
    unsigned char* buf = get_string_buffer_ptr();
    for (unsigned int i = 0; i < len && offset + i < 4096; i++) {
        buf[offset + i] = src[i];
    }
    return len;
}

/* Copy string to fetch buffer, return length written */
static unsigned int dom_copy_to_fetchbuf_c(const char* src, unsigned int len,
                                           unsigned int offset) {
    unsigned char* buf = get_fetch_buffer_ptr();
    for (unsigned int i = 0; i < len && offset + i < 16384; i++) {
        buf[offset + i] = src[i];
    }
    return len;
}

/* Clear diff buffer count */
static void dom_init_c(void) {
    unsigned char* diff = get_diff_buffer_ptr();
    diff[0] = 0;
}

/* Get and increment next node ID */
static int dom_next_id_c(void) {
    return dom_next_node_id++;
}

/* Return null pointer (erased proof at runtime) */
static void* dom_null_proof_c(void) {
    return (void*)0;
}
%}

(* ========== ATS implementations ========== *)

implement dom_init() =
  $extfcall(void, "dom_init_c")

implement dom_create_element
  {parent} {grandparent} {child}
  (parent_pf, parent_id, child_id, tag_ptr, tag_len) = let
    val () = $extfcall(void, "js_apply_diffs")
    val _ = $extfcall(int, "dom_copy_to_strbuf_c", tag_ptr, tag_len, 0)
    val () = $extfcall(void, "dom_emit_diff_c", OP_CREATE_ELEMENT, child_id, parent_id, tag_len)
    val () = $extfcall(void, "js_apply_diffs")
  in
    $extfcall(node_proof(child, parent), "dom_null_proof_c")
  end

implement dom_remove_child
  {id} {parent}
  (pf, id) = let
    val () = $extfcall(void, "js_apply_diffs")
    val () = $extfcall(void, "dom_emit_diff_c", OP_REMOVE_CHILD, id, 0, 0)
  in () end

implement dom_set_text
  {id} {parent}
  (pf, id, text_ptr, text_len) = let
    val () = $extfcall(void, "js_apply_diffs")
    val _ = $extfcall(int, "dom_copy_to_fetchbuf_c", text_ptr, text_len, 0)
    val () = $extfcall(void, "dom_emit_diff_c", OP_SET_TEXT, id, 0, text_len)
  in
    $extfcall(node_proof(id, parent), "dom_null_proof_c")
  end

implement dom_set_text_offset
  {id} {parent}
  (pf, id, fetch_offset, fetch_len) = let
    val () = $extfcall(void, "js_apply_diffs")
    val () = $extfcall(void, "dom_emit_diff_c", OP_SET_TEXT, id, fetch_offset, fetch_len)
  in
    $extfcall(node_proof(id, parent), "dom_null_proof_c")
  end

implement dom_set_attr
  {id} {parent}
  (pf, id, name_ptr, name_len, val_ptr, val_len) = let
    val () = $extfcall(void, "js_apply_diffs")
    val _ = $extfcall(int, "dom_copy_to_strbuf_c", name_ptr, name_len, 0)
    val _ = $extfcall(int, "dom_copy_to_strbuf_c", val_ptr, val_len, name_len)
    val () = $extfcall(void, "dom_emit_diff_c", OP_SET_ATTR, id, name_len, val_len)
    val () = $extfcall(void, "js_apply_diffs")
  in
    $extfcall(node_proof(id, parent), "dom_null_proof_c")
  end

implement dom_set_attr_checked
  {id} {parent} {n}
  (pf_attr, pf, id, name_ptr, name_len, val_ptr, val_len) = let
    prval _ = pf_attr  (* Consume proof — name is valid *)
  in
    dom_set_attr(pf, id, name_ptr, name_len, val_ptr, val_len)
  end

implement dom_set_transform
  {id} {parent}
  (pf, id, x, y) = let
    val () = $extfcall(void, "js_apply_diffs")
    val () = $extfcall(void, "dom_emit_diff_c", OP_SET_TRANSFORM, id, x, y)
  in
    $extfcall(node_proof(id, parent), "dom_null_proof_c")
  end

implement dom_set_inner_html
  {id} {parent}
  (pf, id, fetch_offset, fetch_len) = let
    val () = $extfcall(void, "js_apply_diffs")
    val () = $extfcall(void, "dom_emit_diff_c", OP_SET_INNER_HTML, id, fetch_offset, fetch_len)
  in
    $extfcall(node_proof(id, parent), "dom_null_proof_c")
  end

implement dom_next_id() =
  $extfcall([n:int | n > 0] int n, "dom_next_id_c")

implement dom_root_proof() =
  $extfcall(node_proof(1, 0), "dom_null_proof_c")

implement dom_drop_proof {id} {parent} (pf) = ()
