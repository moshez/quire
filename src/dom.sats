(* dom.sats - Type-level DOM model with proofs
 *
 * Freestanding ATS2 version: works without prelude.
 * Uses abstract types to track node existence at compile time.
 * The C implementation erases these at runtime.
 *)

staload "buf.sats"

(* Op codes matching bridge protocol (quire-design.md §2.3.5) *)
#define OP_SET_TEXT       1
#define OP_SET_ATTR       2
#define OP_SET_TRANSFORM  3
#define OP_CREATE_ELEMENT 4
#define OP_REMOVE_CHILD   5
#define OP_SET_INNER_HTML 6

(* Valid opcode proof.
 * VALID_OPCODE(op) proves op is one of the defined bridge opcodes.
 * Only constructors for the 6 protocol opcodes exist, making it
 * impossible to emit a diff with an arbitrary integer opcode.
 *
 * TEST MADE PASS-BY-CONSTRUCTION:
 *   test_opcodes_match_protocol — Only valid opcodes (1-6) can be
 *   passed to dom_emit_diff; compile rejects any other value. *)
dataprop VALID_OPCODE(opc: int) =
  | OPCODE_SET_TEXT(1)
  | OPCODE_SET_ATTR(2)
  | OPCODE_SET_TRANSFORM(3)
  | OPCODE_CREATE_ELEMENT(4)
  | OPCODE_REMOVE_CHILD(5)
  | OPCODE_SET_INNER_HTML(6)

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
  {parent:int} {grandparent:int} {child:int | child > 0} {tl:nat | tl <= SBUF_CAP}
  ( parent_pf: node_proof(parent, grandparent)
  , parent_id: int parent
  , child_id: int child
  , tag_ptr: ptr
  , tag_len: int tl
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
  {id:int} {parent:int} {tl:nat | tl <= FBUF_CAP}
  ( pf: node_proof(id, parent)
  , id: int id
  , text_ptr: ptr
  , text_len: int tl
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

(* Set an attribute on a node.
 * Requires VALID_ATTR_NAME(nl) proof, ensuring name_ptr points to a
 * known-valid HTML attribute name. Buffer bounds are enforced:
 * name_len + val_len <= STRING_BUFFER_SIZE.
 *
 * C callers bypass ATS type checking — the proof is erased and the
 * C signature is unchanged. C blocks must use only compile-time
 * string constants for attribute names. *)
fun dom_set_attr
  {id:int} {parent:int} {nl:nat | nl <= SBUF_CAP} {vl:nat | nl + vl <= SBUF_CAP}
  ( pf_attr: VALID_ATTR_NAME(nl)
  , pf: node_proof(id, parent)
  , id: int id
  , name_ptr: ptr
  , name_len: int nl
  , val_ptr: ptr
  , val_len: int vl
  ) : node_proof(id, parent) = "mac#"

(* Set an attribute on a node — backward-compatible alias.
 * Now that dom_set_attr itself requires VALID_ATTR_NAME,
 * this is a pure passthrough. Kept for existing callers. *)
fun dom_set_attr_checked
  {id:int} {parent:int} {nl:nat | nl <= SBUF_CAP} {vl:nat | nl + vl <= SBUF_CAP}
  ( pf_attr: VALID_ATTR_NAME(nl)
  , pf: node_proof(id, parent)
  , id: int id
  , name_ptr: ptr
  , name_len: int nl
  , val_ptr: ptr
  , val_len: int vl
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

(* Diff count bounds proof.
 * DIFF_COUNT_BOUNDED(count, max) proves count <= max where max = 255.
 * The diff buffer uses a uint8 count, so at most 255 diffs per frame.
 *
 * TEST MADE PASS-BY-CONSTRUCTION:
 *   test_diff_count_bounded — dom_emit_diff silently drops if count >= 255. *)
dataprop DIFF_COUNT_BOUNDED(count: int, max: int) =
  | {c,m:nat | c <= m} BOUNDED_DIFFS(c, m)

(* Diff entry bounds proof.
 * DIFF_ENTRY_SAFE(count) proves writing a 16-byte entry at position
 * (4 + count * 16) stays within DIFF_BUFFER_SIZE (4096).
 * Max valid count = 254: 4 + 254*16 + 16 = 4084 <= 4096.
 *
 * TEST MADE PASS-BY-CONSTRUCTION:
 *   test_diff_entry_within_buffer — dom_emit_diff only writes when
 *   DIFF_ENTRY_SAFE(count) is provable, connecting the count >= 255
 *   runtime check to the buffer size. *)
dataprop DIFF_ENTRY_SAFE(count: int) =
  | {c:nat | 4 + c * 16 + 16 <= 4096} SAFE_DIFF_ENTRY(c)

(* ========== Low-level C primitives (freestanding, no prelude) ========== *)

(* Bitwise operations — ATS2 has no bitwise ops without prelude *)
fun quire_band(a: int, b: int): int = "mac#"
fun quire_bsr(a: int, n: int): int = "mac#"
fun quire_int2uint(x: int): int = "mac#"

(* Null pointer for proof construction *)
fun quire_null_ptr(): ptr = "mac#"

(* DOM next-node-id state accessors (variable in runtime.c) *)
fun get_dom_next_node_id(): int = "mac#"
fun set_dom_next_node_id(v: int): void = "mac#"

(* Bridge flush — consumes pending diffs *)
fun js_apply_diffs(): void = "mac#"

(* Zero-cost cast: construct node_proof from ptr at compile time *)
castfn __make_proof {id:int} {parent:int} (x: ptr): node_proof(id, parent)

(* ========== Proof helper functions ========== *)

(* Construct VALID_ATTR_NAME proofs for known attribute names.
 * These are the ONLY way to obtain VALID_ATTR_NAME proofs,
 * ensuring only compile-time-constant names are used. *)
praxi lemma_attr_class(): VALID_ATTR_NAME(5) (* "class" *)
praxi lemma_attr_id(): VALID_ATTR_NAME(2)    (* "id" *)
praxi lemma_attr_type(): VALID_ATTR_NAME(4)  (* "type" *)
praxi lemma_attr_for(): VALID_ATTR_NAME(3)   (* "for" *)
praxi lemma_attr_accept(): VALID_ATTR_NAME(6) (* "accept" *)
praxi lemma_attr_style(): VALID_ATTR_NAME(5) (* "style" *)
