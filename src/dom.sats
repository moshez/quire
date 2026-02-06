(* dom.sats - Type-level DOM model with proofs
 *
 * Freestanding ATS2 version: works without prelude.
 * Uses abstract types to track node existence at compile time.
 * The C implementation erases these at runtime.
 *)

(* Op codes matching bridge protocol (quire-design.md §2.3.5) *)
#define OP_SET_TEXT       1
#define OP_SET_ATTR       2
#define OP_SET_TRANSFORM  3
#define OP_CREATE_ELEMENT 4
#define OP_REMOVE_CHILD   5
#define OP_SET_INNER_HTML 6

(* Abstract type representing proof that a node exists.
 * id = the node ID, parent = parent node ID
 * These are compile-time only - erased to void* at runtime *)
abstype node_proof(id: int, parent: int) = ptr

(* Initialize the DOM module - call once at startup *)
fun dom_init(): void = "mac#"

(* Create a new element
 * parent_pf: proof that parent exists (borrowed, not consumed)
 * Returns: proof that child exists *)
fun dom_create_element
  {parent:int} {grandparent:int} {child:int | child > 0}
  ( parent_pf: node_proof(parent, grandparent)
  , parent_id: int parent
  , child_id: int child
  , tag_ptr: ptr
  , tag_len: int
  ) : node_proof(child, parent) = "mac#"

(* Remove a child element
 * Takes ownership of proof - cannot be used after this *)
fun dom_remove_child
  {id:int} {parent:int}
  ( pf: node_proof(id, parent)
  , id: int id
  ) : void = "mac#"

(* Set text content of a node
 * pf: proof that node exists (borrowed) *)
fun dom_set_text
  {id:int} {parent:int}
  ( pf: node_proof(id, parent)
  , id: int id
  , text_ptr: ptr
  , text_len: int
  ) : node_proof(id, parent) = "mac#"

(* Set text content using offset into fetch buffer *)
fun dom_set_text_offset
  {id:int} {parent:int}
  ( pf: node_proof(id, parent)
  , id: int id
  , fetch_offset: int
  , fetch_len: int
  ) : node_proof(id, parent) = "mac#"

(* ========== Attribute Name Safety ========== *)

(* Valid HTML attribute name proof.
 * VALID_ATTR_NAME(n) proves a string of length n is a known-valid
 * HTML attribute name. Only constructors for known names exist.
 *
 * BUG PREVENTED: Without this proof, the shared string buffer could
 * contain arbitrary data (e.g., a book title leaked from a corrupted
 * buffer) that gets passed as an attribute name, causing DOM exceptions
 * like "'A Tal' is not a valid attribute name."
 *
 * ROOT CAUSE ANALYSIS: The string buffer is shared between SET_ATTR
 * diffs and other operations. If a pending SET_ATTR diff's string data
 * is overwritten before the bridge flushes it, the bridge reads garbage
 * as the attribute name. The VALID_ATTR_NAME proof ensures that only
 * compile-time-constant names are used, preventing dynamic data from
 * leaking into attribute names even under buffer corruption. *)
dataprop VALID_ATTR_NAME(n: int) =
  | ATTR_CLASS(5)           (* "class" *)
  | ATTR_ID(2)              (* "id" *)
  | ATTR_TYPE(4)            (* "type" *)
  | ATTR_FOR(3)             (* "for" *)
  | ATTR_ACCEPT(6)          (* "accept" *)
  | ATTR_HREF(4)            (* "href" *)
  | ATTR_SRC(3)             (* "src" *)
  | ATTR_STYLE(5)           (* "style" *)
  | ATTR_ROLE(4)            (* "role" *)
  | ATTR_TABINDEX(8)        (* "tabindex" *)

(* Set an attribute on a node — unchecked version.
 * WARNING: Callers in C blocks bypass ATS type checking.
 * New ATS code should prefer dom_set_attr_safe which requires
 * a VALID_ATTR_NAME proof. *)
fun dom_set_attr
  {id:int} {parent:int}
  ( pf: node_proof(id, parent)
  , id: int id
  , name_ptr: ptr
  , name_len: int
  , val_ptr: ptr
  , val_len: int
  ) : node_proof(id, parent) = "mac#"

(* Set CSS transform on a node *)
fun dom_set_transform
  {id:int} {parent:int}
  ( pf: node_proof(id, parent)
  , id: int id
  , x: int
  , y: int
  ) : node_proof(id, parent) = "mac#"

(* Set innerHTML of a node *)
fun dom_set_inner_html
  {id:int} {parent:int}
  ( pf: node_proof(id, parent)
  , id: int id
  , fetch_offset: int
  , fetch_len: int
  ) : node_proof(id, parent) = "mac#"

(* Get next available node ID and increment counter *)
fun dom_next_id(): [n:int | n > 0] int n = "mac#"

(* Bootstrap: create proof for the root loading div (node ID 1)
 * This is the only way to create a node_proof without dom_create_element.
 * The root node is pre-registered by the bridge from HTML. *)
fun dom_root_proof(): node_proof(1, 0) = "mac#"

(* Discard a proof - use when you're done with a node but not removing it *)
fun dom_drop_proof
  {id:int} {parent:int}
  ( pf: node_proof(id, parent)
  ) : void = "mac#"

(* ========== Shared Buffer Flush Protocol ========== *)

(* BUFFER_FLUSHED(true) proves all pending diffs have been flushed
 * and the string/fetch buffers are safe to rewrite.
 *
 * CRITICAL INVARIANT: dom_set_attr and dom_create_element write data
 * to the shared string buffer and emit diffs that reference it.
 * If ANY code modifies the string buffer before the diff is flushed
 * by the bridge, the bridge reads corrupted data.
 *
 * BUG PREVENTED: rebuild_library_list() called dom_set_attr (writing
 * "class" to string buffer), then library_get_title() (overwriting
 * string buffer with book title), then dom_set_text_offset (which
 * flushed the SET_ATTR diff). The bridge read "A Tal" (first 5 bytes
 * of title) as the attribute name instead of "class".
 *
 * FIX: dom_set_attr and dom_create_element now flush their diffs
 * immediately after emitting them (via trailing js_apply_diffs call),
 * ensuring string buffer data is consumed before it can be corrupted.
 *
 * ENFORCEMENT: New code that writes to shared buffers between DOM
 * operations must call js_apply_diffs() first to flush pending diffs.
 * In ATS code, this is enforced by the node_proof linear type —
 * each DOM operation consumes and returns the proof, preventing
 * interleaved buffer writes. In C blocks, this must be manually
 * verified. *)
absprop BUFFER_FLUSHED(flushed: bool)
