(* quire.dats - Quire e-reader main module
 *
 * Demonstrates type-checked DOM operations using the dom module.
 * The type system ensures:
 *   - Cannot operate on nodes that don't exist
 *   - Cannot operate on nodes that have been removed
 *   - Cannot remove the same node twice
 *)

#define ATS_DYNLOADFLAG 0

staload "quire.sats"
staload "dom.sats"

%{^
/* String literals for DOM operations */
static const char str_quire[] = "Quire";
static const char str_div[] = "div";
static const char str_span[] = "span";
static const char str_class[] = "class";
static const char str_demo_class[] = "demo-element";
static const char str_id_attr[] = "id";
static const char str_demo_id[] = "demo-child";
static const char str_hello[] = "Hello from typed DOM!";
static const char str_temp[] = "Temporary element";

extern unsigned char* get_fetch_buffer_ptr(void);

/* Helper to copy text to fetch buffer and get length */
static int copy_text_to_fetch(const char* text, int len) {
    unsigned char* buf = get_fetch_buffer_ptr();
    for (int i = 0; i < len && i < 16384; i++) {
        buf[i] = text[i];
    }
    return len;
}
%}

(* External declarations for string literals and helpers *)
extern fun get_str_quire(): ptr = "mac#"
extern fun get_str_div(): ptr = "mac#"
extern fun get_str_span(): ptr = "mac#"
extern fun get_str_class(): ptr = "mac#"
extern fun get_str_demo_class(): ptr = "mac#"
extern fun get_str_id_attr(): ptr = "mac#"
extern fun get_str_demo_id(): ptr = "mac#"
extern fun get_str_hello(): ptr = "mac#"
extern fun get_str_temp(): ptr = "mac#"
extern fun copy_text_to_fetch(text: ptr, len: int): int = "mac#"

%{
/* String getters */
void* get_str_quire(void) { return (void*)str_quire; }
void* get_str_div(void) { return (void*)str_div; }
void* get_str_span(void) { return (void*)str_span; }
void* get_str_class(void) { return (void*)str_class; }
void* get_str_demo_class(void) { return (void*)str_demo_class; }
void* get_str_id_attr(void) { return (void*)str_id_attr; }
void* get_str_demo_id(void) { return (void*)str_demo_id; }
void* get_str_hello(void) { return (void*)str_hello; }
void* get_str_temp(void) { return (void*)str_temp; }
%}

(* Initialize the application
 * Demonstrates:
 *   1. Getting root proof (node 1 from HTML)
 *   2. Setting text on root (type-safe)
 *   3. Creating child elements (returns proof)
 *   4. Setting attributes (requires proof)
 *   5. Creating and removing an element (proof consumed on remove)
 *)
implement init() = let
    (* Initialize DOM subsystem - clears diff buffer *)
    val () = dom_init()

    (* Get proof that root node (id=1) exists
     * This is the only way to bootstrap the proof system *)
    val pf_root = dom_root_proof()

    (* Copy "Quire" to fetch buffer and set as root text
     * Type-safe: requires proof that node 1 exists *)
    val _len = copy_text_to_fetch(get_str_quire(), 5)
    val pf_root = dom_set_text_offset(pf_root, 1, 0, 5)

    (* Create a child div under root (node 2)
     * Returns proof that node 2 exists under node 1 *)
    val child_id = 2
    val pf_child = dom_create_element(pf_root, 1, child_id,
                                       get_str_div(), 3)

    (* Set class attribute on the child
     * Type-safe: requires proof that node 2 exists *)
    val pf_child = dom_set_attr(pf_child, child_id,
                                 get_str_class(), 5,
                                 get_str_demo_class(), 12)

    (* Set id attribute on the child *)
    val pf_child = dom_set_attr(pf_child, child_id,
                                 get_str_id_attr(), 2,
                                 get_str_demo_id(), 10)

    (* Set text on child *)
    val _len = copy_text_to_fetch(get_str_hello(), 21)
    val pf_child = dom_set_text_offset(pf_child, child_id, 0, 21)

    (* Create a temporary element (node 3) *)
    val temp_id = 3
    val pf_temp = dom_create_element(pf_root, 1, temp_id,
                                      get_str_span(), 4)

    (* Set text on temporary element *)
    val _len = copy_text_to_fetch(get_str_temp(), 17)
    val pf_temp = dom_set_text_offset(pf_temp, temp_id, 0, 17)

    (* Remove the temporary element
     * Consumes pf_temp - cannot use pf_temp after this!
     * The function takes ownership of the proof *)
    val () = dom_remove_child(pf_temp, temp_id)

    (* COMPILE ERROR if uncommented - pf_temp was consumed by dom_remove_child:
     * val pf_temp = dom_set_text_offset(pf_temp, temp_id, 0, 5)
     *)

    (* Discard proofs at end of scope *)
    val () = dom_drop_proof(pf_root)
    val () = dom_drop_proof(pf_child)
  in
    ()
  end

(* Stub implementations for required bridge callbacks *)
implement process_event() = ()
implement on_fetch_complete(status, len) = ()
implement on_timer_complete(callback_id) = ()
implement on_file_open_complete(handle, size) = ()
implement on_decompress_complete(handle, size) = ()
implement on_kv_complete(success) = ()
implement on_kv_get_complete(len) = ()
implement on_kv_get_blob_complete(handle, size) = ()
implement on_clipboard_copy_complete(success) = ()
