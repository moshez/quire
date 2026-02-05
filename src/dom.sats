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
  {parent:int} {child:int | child > 0}
  ( parent_pf: node_proof(parent, 0)
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

(* Set an attribute on a node *)
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
